#!/usr/bin/env bats

# Tests for the PreToolUse hook at .claude/hooks/gdd-permission-hook.sh.
#
# Coverage:
#   - Tier 1: deny shell composition (each operator) with specific reason
#   - Tier 2: ask-tier — destructive commands matching [ask-commands]
#   - Tier 3: allow via project .claude/settings.json
#       - bare command vs verbose pattern (symmetric normalization)
#       - verbose command vs bare pattern (symmetric normalization)
#       - CRLF line endings in settings.json don't break matching
#   - Tier 3: allow via settings.json `permissions.allow` (unchanged logic)
#   - Tier 4: allow via [allow-extras] section of hook-rules.local
#   - Tier 4: legacy safe-bash-extras file is ignored (no longer consulted)
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

# ─── Tier 3: symmetric normalization against settings.json ──────────

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

# ─── Tier 4: [allow-extras] from hook-rules.local ───────────────────

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

# ─── Tier 2: ask-list ───────────────────────────────────────────────

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

# ─── Tier 4 vs legacy safe-bash-extras ──────────────────────────────

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

@test "redirect: command outside [redirect-commands] passes through Tier 2" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_project_settings "Bash(ls *)"
    run_hook "ls -la"
    [ "$status" -eq 0 ]
    # Settings.json allow at Tier 4 should still match
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

@test "bypass: marker does NOT override Tier 3 ask-list" {
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
    # Each known slug invocation should hit Tier 3 ask, NOT Tier 2 deny.
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

@test "allow: CLAUDE_MODEL prefix on ws commit is allowlisted" {
    seed_real_project_config
    run_hook 'CLAUDE_MODEL="Opus 4.8" ws commit yggdrasil .commits/x.md'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: CLAUDE_MODEL prefix on bash scripts/ws commit is allowlisted" {
    seed_real_project_config
    run_hook 'CLAUDE_MODEL="Opus 4.8" bash scripts/ws commit yggdrasil .commits/x.md'
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

# SECURITY: a general env-prefix strip must NOT exist — an arbitrary env
# assignment on an allowlisted command must not silently auto-approve.
@test "security: LD_PRELOAD prefix on an allowlisted command does NOT auto-allow" {
    seed_real_project_config
    run_hook 'LD_PRELOAD=/tmp/evil.so ws status'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: an env prefix must not bypass a redirect deny.
@test "security: env prefix does NOT let a redirect-denied command through" {
    seed_real_project_config
    run_hook 'CLAUDE_MODEL="x" git commit -m y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws commit"* ]]
}
