#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CODEX_HOOK_BIN="$REPO_ROOT/.codex/hooks/gdd-k8s-hook.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/scripts"
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    mkdir -p "$WORK/_home/.codex"
    cp "$REPO_ROOT/scripts/ws-session.sh" "$WORK/scripts/ws-session.sh"
    cp "$REPO_ROOT/scripts/ws-k8s-guard.sh" "$WORK/scripts/ws-k8s-guard.sh"
    export HOME="$WORK/_home"
}

seed_scope() {
    local session_id="$1"
    local context="$2"
    local namespaces="$3"
    printf 'GDD_K8S_CONTEXT=%s\nGDD_K8S_NAMESPACES=%s\n' \
        "$context" "$namespaces" \
        > "$WORK/.tmp/gdd-agent-sessions/$session_id.env"
}

write_bypass_marker() {
    local marker_session_id="$1"
    mkdir -p "$WORK/.tmp/hook-bypass"
    printf 'session_id: %s\nslug: k8s\ncreated_at: 2026-06-29T12:00:00Z\nreason: practice\n' \
        "$marker_session_id" \
        > "$WORK/.tmp/hook-bypass/k8s.bypass"
}

run_codex_hook() {
    local command="$1"
    local session_id="${2:-codex-test}"
    local tool_name="${3:-Bash}"
    local payload
    payload="$(jq -nc \
        --arg sid "$session_id" \
        --arg tool "$tool_name" \
        --arg command "$command" \
        --arg cwd "$WORK" \
        '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:$tool,tool_input:{command:$command},cwd:$cwd}')"
    run env GDD_PROJECT_ROOT="$WORK" bash "$CODEX_HOOK_BIN" <<< "$payload"
}

assert_denied() {
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.hookEventName' <<< "$output")" = "PreToolUse" ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
}

@test "unrelated Bash command defers to normal Codex routing" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'ws status'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "non-Bash tool defers to normal Codex routing" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl delete pod foo -n prod' codex-test apply_patch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "raw kubectl defers when no scope is active" {
    run_codex_hook 'kubectl delete pod foo -n prod' no-scope
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "raw kubectl read defers under an active scope" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl get pods -n kube-system'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "guarded ws k8s read defers under an active scope" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'ws k8s get pods -n kube-system'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "verbose guarded ws k8s write defers under an active scope" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'bash scripts/ws k8s delete pod foo -n alice-sandbox'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "raw in-scope kubectl write redirects through ws k8s" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl delete pod foo -n alice-sandbox'
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"ws k8s"* ]]
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"armed context"* ]]
}

@test "raw out-of-scope kubectl write uses the shared guard message" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl delete pod foo -n prod'
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"REJECTED by the k8s scope guard"* ]]
}

@test "guarded out-of-scope ws k8s write uses the shared guard message" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'ws k8s delete pod foo -n prod'
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"REJECTED by the k8s scope guard"* ]]
}

@test "cluster-scoped write hides the internal verdict class" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'ws k8s delete namespace prod'
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"REJECTED by the k8s scope guard"* ]]
    [[ "$output" != *"unbounded:"* ]]
}

@test "scope management commands defer while the scope is armed" {
    seed_scope codex-test kind-practice alice-sandbox
    local command
    for command in \
        'ws k8s scope show' \
        'ws k8s scope clear' \
        'ws k8s scope set --context kind-practice --namespace alice-sandbox'; do
        run_codex_hook "$command"
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    done
}

@test "direct script containing raw kubectl is denied" {
    seed_scope codex-test kind-practice alice-sandbox
    printf '#!/usr/bin/env bash\nkubectl delete namespace prod\n' > "$WORK/danger.sh"
    run_codex_hook "bash $WORK/danger.sh"
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"calls raw kubectl"* ]]
}

@test "matching k8s bypass marker defers and audits the bypass" {
    seed_scope codex-test kind-practice alice-sandbox
    write_bypass_marker codex-test
    run_codex_hook 'kubectl delete pod foo -n prod'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.codex/hook-audit.log"
}

@test "matching k8s bypass marker does not audit an unrelated command" {
    seed_scope codex-test kind-practice alice-sandbox
    write_bypass_marker codex-test
    run_codex_hook 'ws status'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    if [[ -f "$HOME/.codex/hook-audit.log" ]]; then
        ! grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.codex/hook-audit.log"
    fi
}

@test "stale k8s bypass marker does not lift the guard" {
    seed_scope codex-test kind-practice alice-sandbox
    write_bypass_marker another-session
    run_codex_hook 'kubectl delete pod foo -n prod'
    assert_denied
}

@test "malformed hook payload fails open" {
    run env GDD_PROJECT_ROOT="$WORK" bash "$CODEX_HOOK_BIN" <<< 'not-json'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "missing jq fails open" {
    local payload
    payload='{"session_id":"codex-test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"kubectl delete pod foo -n prod"}}'
    run env GDD_PROJECT_ROOT="$WORK" JQ=jq-command-that-does-not-exist bash "$CODEX_HOOK_BIN" <<< "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "missing shared guard fails open and records one infrastructure warning" {
    local missing_root="$BATS_TEST_TMPDIR/missing-root"
    mkdir -p "$missing_root/scripts"
    run env GDD_PROJECT_ROOT="$missing_root" bash "$CODEX_HOOK_BIN" <<< '{"session_id":"codex-test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"kubectl delete pod foo -n prod"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'PASSTHROUGH.*shared Kubernetes guard unavailable' "$HOME/.codex/hook-audit.log"
}

@test "Codex registration contains only the focused Bash PreToolUse bridge" {
    run jq -e \
        '.hooks.PreToolUse | (length == 1 and .[0].matcher == "^Bash$" and (.[0].hooks | length == 1) and (.[0].hooks[0].command | contains(".codex/hooks/gdd-k8s-hook.sh")))' \
        "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
    run jq -e '.hooks | has("PermissionRequest") | not' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
}
