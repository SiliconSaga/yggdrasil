#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"; mkdir -p "$ROOT_DIR/.tmp"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
    export GDD_SESSION_ID="k8s-test"
    cat > "$ROOT_DIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "KUBECTL_ARGS: $*" >> "$ROOT_DIR/kubectl.log"
case "$*" in
    *"get namespace prod"*) exit 1 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$ROOT_DIR/kubectl"
    export KUBECTL="$ROOT_DIR/kubectl"
}
run_ws() { run env WS_FOOTER_DISABLE=1 ROOT_DIR="$ROOT_DIR" KUBECTL="$KUBECTL" bash "$WS_BIN" "$@"; }

@test "scope set then show round-trips" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    [ "$status" -eq 0 ]
    run_ws k8s scope show
    [[ "$output" == *"kind-practice"* ]]
    [[ "$output" == *"alice-sandbox"* ]]
}
@test "no scope set: passthrough to kubectl" {
    run_ws k8s get pods
    [ "$status" -eq 0 ]
}
@test "in-scope read is allowed and forces --context" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    run_ws k8s get pods -n kube-system
    [ "$status" -eq 0 ]
    grep -q -- '--context kind-practice' "$ROOT_DIR/kubectl.log"
}
@test "out-of-scope write is rejected, kubectl not called" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete pod foo -n prod
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside practice scope"* || "$output" == *"blocked"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "scope set rejects a nonexistent namespace" {
    run_ws k8s scope set --context kind-practice --namespace prod
    [ "$status" -ne 0 ]
}
@test "scope clear removes the scope" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    run_ws k8s scope clear
    run_ws k8s scope show
    [[ "$output" == *"none"* ]]
}
