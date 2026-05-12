#!/usr/bin/env bats

# Tests for the PreToolUse hook at .claude/hooks/gdd-allowlist-bridge.sh.
#
# Coverage:
#   - Tier 1: deny shell composition (each operator) with specific reason
#   - Tier 2: allow via project .claude/settings.json
#       - bare command vs verbose pattern (symmetric normalization)
#       - verbose command vs bare pattern (symmetric normalization)
#       - CRLF line endings in settings.json don't break matching
#   - Tier 3: allow via project-level safe-bash-extras
#   - Tier 3: allow via user-level safe-bash-extras
#   - Tier 3: project-level takes precedence (or coexists) with user-level
#   - Passthrough: no match → exit 0 with no JSON
#   - WS_HOOK_DISABLE bypass
#   - Timeout safety: no infinite loops on Windows-style absolute paths
#
# `run_hook` wraps the hook in `timeout 10` so a future regression
# that hangs the upward-walk loop fails the test instead of stalling
# the suite.

load test_helper

setup() {
    init_hook_env
}

# ─── Tier 1: shell composition deny ─────────────────────────────────

@test "deny: && triggers shell-composition message" {
    run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "deny: || triggers shell-composition message" {
    run_hook "ls || pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "deny: ; triggers shell-composition message" {
    run_hook "ls ; pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "deny: | triggers pipes message" {
    run_hook "ls -la | head"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Pipes"* ]]
}

@test "deny: grep with | redirects to Grep tool (specific message)" {
    # Common false-positive case: regex alternation contains a literal
    # | inside the quoted pattern. The hook can't distinguish that
    # from a shell pipe, but it CAN recognize that the right answer
    # for any grep-with-| invocation is to use the Grep tool.
    run_hook 'grep -E "a|b" file.txt'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Grep tool"* ]]
    [[ "$output" != *"Pipes"* ]]
}

@test "deny: cmd | grep also redirects to Grep tool when cmd starts with grep" {
    # This case is grep ... | something — still starts with `grep `,
    # so the redirect arm fires (correctly, since the user should use
    # the Grep tool here too).
    run_hook "grep foo file | head"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Grep tool"* ]]
}

@test "deny: non-grep cmd | grep falls through to generic pipes message" {
    # `cat file | grep pattern` starts with `cat`, not `grep`, so the
    # grep-specific arm doesn't fire. Generic pipes deny still applies.
    run_hook "cat file | grep pattern"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Pipes"* ]]
}

@test "deny: backticks trigger command-substitution message" {
    run_hook 'echo `date`'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Command substitution"* ]]
}

@test "deny: \$() triggers command-substitution message" {
    run_hook 'echo $(date)'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Command substitution"* ]]
}

@test "deny: > triggers redirection message" {
    run_hook "echo hi > /tmp/file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"redirection"* ]]
}

@test "deny: < triggers redirection message" {
    run_hook "cat < /tmp/file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"redirection"* ]]
}

@test "deny: 2>&1 FD merge gets specific 'not needed' message" {
    # The Bash tool captures both stdout and stderr natively, so
    # `2>&1` is cargo-cult shell jargon. Deny with a message that
    # explains the redundancy — saves newbies from learning FD-merge
    # syntax just to follow transcripts.
    run_hook "ls 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"File-descriptor merges"* ]]
    [[ "$output" != *"Output / input redirection"* ]]
}

@test "deny: 1>&2 FD merge gets the same message" {
    run_hook "echo error 1>&2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"File-descriptor merges"* ]]
}

@test "deny: combined real redirect + FD merge hits FD message first" {
    # The FD-merge arm comes before the general redirect arm in the
    # case statement. A command containing both (`cmd 2>&1 > file`)
    # matches the FD-merge arm first. Either deny is fine — both
    # are correct — but pin the order so the user always sees the
    # more specific corrective message when both apply.
    run_hook "cmd 2>&1 > output.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"File-descriptor merges"* ]]
}

# ─── Tier 2: symmetric normalization against settings.json ──────────

@test "allow via settings: bare command matches verbose pattern" {
    write_project_settings 'Bash(bash scripts/ws status)'
    run_hook "ws status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via settings: verbose command matches bare pattern" {
    write_project_settings 'Bash(ws status)'
    run_hook "bash scripts/ws status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via settings: wildcard pattern matches args" {
    write_project_settings 'Bash(ws hoard upgrade *)'
    run_hook "ws hoard upgrade borgr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via settings: CRLF line endings don't break matching" {
    # Write the settings file with explicit CRLF endings to simulate
    # autocrlf=true on Windows. The hook must strip the trailing \r
    # before pattern comparison or the `)` close-paren strip silently
    # fails, leaving `)` in the pattern and breaking every match.
    {
        printf '{\r\n'
        printf '  "permissions": {\r\n'
        printf '    "allow": [\r\n'
        printf '      "Bash(ws status)"\r\n'
        printf '    ]\r\n'
        printf '  }\r\n'
        printf '}\r\n'
    } > "$WORK/.claude/settings.json"

    run_hook "ws status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Tier 3: project-level safe-bash-extras ─────────────────────────

@test "allow via project extras: pattern from project file matches" {
    write_project_extras 'figlet *'
    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via project extras: walks up from a nested cwd" {
    # Put extras at the project root, run with cwd nested inside.
    write_project_extras 'figlet *'
    mkdir -p "$WORK/subdir/deeper"
    run_hook "figlet hello" "$WORK/subdir/deeper"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Tier 3: user-level safe-bash-extras ────────────────────────────

@test "allow via user extras: pattern from \$HOME file matches" {
    write_user_extras 'cowsay *'
    run_hook "cowsay moo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via user extras: works without a project extras file" {
    # Only user-level extras exists. Project tree has no .claude/hooks/.
    write_user_extras 'figlet *'
    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Tier 3: project + user coexist ─────────────────────────────────

@test "both extras files contribute: pattern in either allows" {
    write_project_extras 'figlet *'
    write_user_extras 'cowsay *'

    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]

    run_hook "cowsay moo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Passthrough ────────────────────────────────────────────────────

@test "passthrough: unmatched command yields no decision" {
    run_hook "npm install some-package"
    [ "$status" -eq 0 ]
    # No JSON output → harness's normal flow takes over
    [[ "$output" != *"permissionDecision"* ]]
}

# ─── WS_HOOK_DISABLE bypass ─────────────────────────────────────────

@test "WS_HOOK_DISABLE: skips all checks, including Tier 1 deny" {
    # Even a compound command should pass through when the env var
    # is set. The bypass is the user's escape hatch for sessions
    # where they don't want the hook active at all.
    WS_HOOK_DISABLE=1 run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

# ─── Timeout-safe upward walk ───────────────────────────────────────

@test "timeout safety: Windows-style cwd doesn't hang the upward walk" {
    # The original bug: dirname of "D:/foo/bar" eventually returns "."
    # and `dirname .` returns "." forever. The hook's prev-equals-dir
    # guard exits the loop. This test confirms the guard works: a
    # Windows-style cwd completes within the 10s timeout in run_hook.
    write_project_settings 'Bash(ws status)'
    run_hook "ws status" "D:/Dev/GitWS/yggdrasil"
    [ "$status" -eq 0 ]
    # Exit status 124 would mean timeout — anything else means the
    # walk terminated. The output may or may not be "allow" depending
    # on whether the Windows path actually exists as a project root.
    # The key assertion is that we DIDN'T hit the timeout.
    [ "$status" -ne 124 ]
}
