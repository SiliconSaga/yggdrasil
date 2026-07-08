#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK_BIN="$REPO_ROOT/.codex/hooks/gdd-redirect-hook.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    export HOME="$WORK/home"
    mkdir -p "$WORK/.claude/hooks" "$WORK/.tmp/hook-bypass" "$HOME/.codex"
    cp "$REPO_ROOT/.claude/hooks/hook-rules" "$WORK/.claude/hooks/hook-rules"
}

run_hook() {
    local command="$1"
    local session_id="${2:-codex-redirect-test}"
    local tool_name="${3:-Bash}"
    local payload
    payload="$(jq -nc \
        --arg sid "$session_id" \
        --arg tool "$tool_name" \
        --arg command "$command" \
        --arg cwd "$WORK" \
        '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:$tool,tool_input:{command:$command},cwd:$cwd}')"
    run env HOME="$HOME" GDD_PROJECT_ROOT="$WORK" bash "$HOOK_BIN" <<< "$payload"
}

@test "unrelated Bash command defers to normal Codex routing" {
    run_hook 'git status'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "non-Bash tool defers" {
    run_hook 'git push' codex-redirect-test apply_patch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "malformed payload defers" {
    run env HOME="$HOME" GDD_PROJECT_ROOT="$WORK" bash "$HOOK_BIN" <<< 'not-json'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git push is denied with the configured ws guidance" {
    run_hook 'git push origin topic'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *'Use `ws push <comp> [branch]`'* ]]
}

@test "each shipped redirect denies a representative raw command" {
    local command slug
    while IFS='|' read -r command slug; do
        run_hook "$command"
        [ "$status" -eq 0 ]
        [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
        grep -q "DENY-REDIRECT \[$slug\]" "$HOME/.codex/hook-audit.log"
    done <<'CASES'
git commit -m test|git-commit
git push|git-push
gh pr create --title test|gh-pr-create
git mv old new|git-mv
CASES
}

@test "WS_HOOK_DISABLE bypasses redirect evaluation" {
    local payload
    payload='{"session_id":"codex-redirect-test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}'
    run env HOME="$HOME" GDD_PROJECT_ROOT="$WORK" WS_HOOK_DISABLE=1 bash "$HOOK_BIN" <<< "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "suggestion text may contain additional pipes" {
    cat > "$WORK/.claude/hooks/hook-rules" <<'RULES'
[redirect-commands]
custom | custom raw* | Use `ws custom` | keep this suffix.
RULES
    run_hook 'custom raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" = 'Use `ws custom` | keep this suffix.' ]
}

@test "malformed redirect rows are audited and later valid rows still work" {
    cat > "$WORK/.claude/hooks/hook-rules" <<'RULES'
[redirect-commands]
missing separators
bad_slug | bad* | invalid slug
valid | valid raw* | Use `ws valid`.
RULES
    run_hook 'valid raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
    grep -q 'malformed \[redirect-commands\]' "$HOME/.codex/hook-audit.log"
}

@test "missing baseline rules defer and audit the infrastructure gap" {
    rm "$WORK/.claude/hooks/hook-rules"
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'redirect rules unavailable' "$HOME/.codex/hook-audit.log"
}

@test "command and pattern normalization match wrapper-path forms" {
    cat > "$WORK/.claude/hooks/hook-rules" <<'RULES'
[redirect-commands]
custom | scripts/custom raw* | Use `ws custom`.
RULES
    run_hook 'bash scripts/custom raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" = 'Use `ws custom`.' ]
}

@test "hook-rules.local adds a redirect" {
    cat > "$WORK/.claude/hooks/hook-rules.local" <<'RULES'
[redirect-commands]
local-tool | local-tool raw* | Use `ws local-tool`.
RULES
    run_hook 'local-tool raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" = 'Use `ws local-tool`.' ]
}

@test "matching-session bypass defers without emitting allow" {
    cat > "$WORK/.tmp/hook-bypass/git-push.bypass" <<'MARKER'
session_id: codex-redirect-test
reason: provider debugging
MARKER
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'BYPASS-REDIRECT \[git-push\]' "$HOME/.codex/hook-audit.log"
}

@test "mismatched-session bypass still denies" {
    cat > "$WORK/.tmp/hook-bypass/git-push.bypass" <<'MARKER'
session_id: another-session
reason: wrong owner
MARKER
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
}

@test "malformed bypass marker still denies" {
    printf '%s\n' 'reason: missing session' > "$WORK/.tmp/hook-bypass/git-push.bypass"
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
}
