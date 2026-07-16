#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CODEX_HOOK_BIN="${GDD_CODEX_K8S_HOOK_BIN:-$REPO_ROOT/.codex/hooks/gdd-k8s-hook.sh}"
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

@test "unsafe multiline Kubernetes command is denied instead of reading only line one" {
    seed_scope codex-test kind-practice alice-sandbox

    run_codex_hook $'echo safe\nkubectl delete namespace prod'

    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"compound or multiline"* ]]
}

@test "unsafe compound Kubernetes command is denied before partial evaluation" {
    seed_scope codex-test kind-practice alice-sandbox

    run_codex_hook 'echo safe; kubectl delete namespace prod'

    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"compound or multiline"* ]]
}

@test "unrelated multiline command still defers to normal Codex routing" {
    seed_scope codex-test kind-practice alice-sandbox

    run_codex_hook $'printf first\nprintf second'

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "non-Bash tool defers to normal Codex routing" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl delete pod foo -n prod' codex-test apply_patch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "raw kubectl write is denied when no scope is active" {
    run_codex_hook 'kubectl delete pod foo -n prod' no-scope
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"No Kubernetes guard scope is active"* ]]
}

@test "quoted escaped and exe kubectl command words still reach the deny floor" {
    local command
    for command in \
        '"kubectl" delete pod foo -n prod' \
        '\kubectl delete pod foo -n prod' \
        'kubectl.exe delete pod foo -n prod'; do
        run_codex_hook "$command" no-scope
        assert_denied
        [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"No Kubernetes guard scope is active"* ]]
    done
}

@test "guarded ws k8s write is denied when no scope is active" {
    run_codex_hook 'ws k8s apply -k overlays/plain' no-scope
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"scope set"* ]]
}

@test "raw kubectl read defers when no scope is active" {
    run_codex_hook 'kubectl get pods -n prod' no-scope
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "direct script containing kubectl is denied when no scope is active" {
    printf '#!/usr/bin/env bash\nkubectl apply -k overlays/plain\n' > "$WORK/danger.sh"
    run_codex_hook "bash $WORK/danger.sh" no-scope
    assert_denied
    local reason
    reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")"
    [[ "${reason,,}" == *"no kubernetes guard scope is active"* ]]
    [[ "$reason" == *"calls raw kubectl"* ]]
}

@test "slash-relative script containing kubectl is denied when no scope is active" {
    printf '#!/usr/bin/env bash\nkubectl run script-test --image=pause -n gdd-practice\n' > "$WORK/scripts/direct-danger.sh"
    run_codex_hook 'scripts/direct-danger.sh' no-scope
    assert_denied
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"calls raw kubectl"* ]]
}

@test "env-wrapped kubectl run is denied when no scope is active" {
    run_codex_hook 'env KUBECONFIG=/tmp/test kubectl run script-test --image=pause -n gdd-practice' no-scope
    assert_denied
}

@test "absolute kubectl path is denied when no scope is active" {
    run_codex_hook '/usr/bin/kubectl run script-test --image=pause -n gdd-practice' no-scope
    assert_denied
}

@test "leading assignment before kubectl run is denied when no scope is active" {
    run_codex_hook 'KUBECONFIG=/tmp/test kubectl run script-test --image=pause -n gdd-practice' no-scope
    assert_denied
}

@test "bash options do not hide an unscoped kubectl-run script" {
    printf '#!/usr/bin/env bash\nkubectl run script-test --image=pause --restart=Never -n gdd-practice\n' > "$WORK/chapter4-script-test.sh"
    run_codex_hook 'bash -x ./chapter4-script-test.sh' no-scope
    assert_denied
}

@test "bash -c containing kubectl is denied when no scope is active" {
    run_codex_hook "bash -c 'kubectl run script-test --image=pause -n gdd-practice'" no-scope
    assert_denied
}

@test "matching k8s bypass marker permits an unscoped write and audits it" {
    write_bypass_marker no-scope
    run_codex_hook 'kubectl apply -k overlays/plain' no-scope
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.codex/hook-audit.log"
}

@test "matching k8s bypass marker permits an unscoped kubectl script" {
    printf '#!/usr/bin/env bash\nkubectl apply -k overlays/plain\n' > "$WORK/danger.sh"
    write_bypass_marker no-scope
    run_codex_hook "bash $WORK/danger.sh" no-scope
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.codex/hook-audit.log"
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

@test "Codex registration contains both focused Bash PreToolUse bridges" {
    run jq -e '
        .hooks.PreToolUse
        | length == 1
          and .[0].matcher == "^Bash$"
          and (.[0].hooks | length == 2)
          and any(.[0].hooks[]; .command | contains(".codex/hooks/gdd-k8s-hook.sh"))
          and any(.[0].hooks[]; .command | contains(".codex/hooks/gdd-redirect-hook.sh"))
    ' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
    run jq -e '.hooks | has("PermissionRequest") | not' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
}
