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
@test "ws k8s --help shows the guard/scope wrapper help, not a kubectl passthrough" {
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"scope"* ]]
    [[ "$output" == *"guard"* ]]
    [[ "$output" == *"sustained cluster-wide"* ]]
    [[ "$output" == *"unscoped write safety floor"* ]]
    [[ "$output" == *"unattended raw-"* ]]
    [[ "$output" == *"explicit confirmation"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "no scope set: passthrough to kubectl" {
    run_ws k8s get pods
    [ "$status" -eq 0 ]
}
@test "in-scope read is allowed and forces --context" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    : > "$ROOT_DIR/kubectl.log"  # drop the scope-set lines so the grep proves the read forced --context
    run_ws k8s get pods -n kube-system
    [ "$status" -eq 0 ]
    grep -q -- '--context kind-practice' "$ROOT_DIR/kubectl.log"
}
@test "out-of-scope write is rejected, kubectl not called" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete pod foo -n prod
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside the guard scope"* || "$output" == *"REJECTED"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "cluster-scoped write rejection renders 'unbounded' remediation (no widen advice, no class tag leak)" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    : > "$ROOT_DIR/kubectl.log"
    # clusterrole is always unbounded; a namespace would now be scope-classed by name.
    run_ws k8s delete clusterrole foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"REJECTED by the k8s scope guard"* ]]
    [[ "$output" != *"unbounded:"* ]]
    [[ "$output" != *"widen the scope"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "scope set on a not-yet-existing namespace warns but arms (pre-create workflow)" {
    # The stub reports 'prod' as not found (get namespace prod → exit 1).
    run_ws k8s scope set --context kind-practice --namespace prod
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
    run_ws k8s scope show
    [[ "$output" == *"prod"* ]]
}
@test "scope set with a mix of existing and not-yet-existing namespaces arms all, warns on the missing" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox,prod
    [ "$status" -eq 0 ]
    [[ "$output" == *"prod"* ]]
    run_ws k8s scope show
    [[ "$output" == *"alice-sandbox,prod"* ]]
}
@test "context-only: scope set with no --namespace arms and show reports all-namespaces" {
    run_ws k8s scope set --context kind-practice
    [ "$status" -eq 0 ]
    [[ "$output" == *"context-only"* ]]
    run_ws k8s scope show
    [[ "$output" == *"kind-practice"* ]]
    [[ "$output" == *"(all — context-only)"* ]]
}
@test "context-only: --namespace '*' also arms context-only" {
    run_ws k8s scope set --context kind-practice --namespace '*'
    [ "$status" -eq 0 ]
    run_ws k8s scope show
    [[ "$output" == *"(all — context-only)"* ]]
}
@test "context-only: a mixed namespace list containing '*' normalizes to context-only" {
    run_ws k8s scope set --context kind-practice --namespace 'alice-sandbox,*'
    [ "$status" -eq 0 ]
    [[ "$output" == *"(all — context-only)"* ]]
    run_ws k8s scope show
    [[ "$output" == *"(all — context-only)"* ]]
}
@test "namespace named all remains a literal namespace scope" {
    run_ws k8s scope set --context kind-practice --namespace all
    [ "$status" -eq 0 ]
    run_ws k8s scope show
    [[ "$output" == *"namespaces: all"* ]]
    [[ "$output" != *"context-only"* ]]
}
@test "context-only: write to an arbitrary namespace is ALLOWED and forces --context" {
    run_ws k8s scope set --context kind-practice
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete pod foo -n gitea
    [ "$status" -eq 0 ]
    grep -q -- '--context kind-practice' "$ROOT_DIR/kubectl.log"
    run_ws k8s run probe --image=pause -n crossplane
    [ "$status" -eq 0 ]
}
@test "context-only: named namespace create and delete operations are allowed" {
    run_ws k8s scope set --context kind-practice
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s create namespace ephemeral
    [ "$status" -eq 0 ]
    run_ws k8s delete ns/ephemeral
    [ "$status" -eq 0 ]
    grep -q -- '--context kind-practice create namespace ephemeral' "$ROOT_DIR/kubectl.log"
    grep -q -- '--context kind-practice delete ns/ephemeral' "$ROOT_DIR/kubectl.log"
}
@test "context-only: reads are still free cluster-wide" {
    run_ws k8s scope set --context kind-practice
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s get pods -n kube-system
    [ "$status" -eq 0 ]
    grep -q -- '--context kind-practice' "$ROOT_DIR/kubectl.log"
}
@test "context-only: an explicit different --context is still REJECTED" {
    run_ws k8s scope set --context kind-practice
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete pod foo --context other-cluster -n gitea
    [ "$status" -ne 0 ]
    [[ "$output" == *"REJECTED"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "context-only: a cluster-scoped write is still REJECTED (context-pin protections intact)" {
    run_ws k8s scope set --context kind-practice
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete clusterrole foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"REJECTED"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "scope clear removes the scope" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    run_ws k8s scope clear
    run_ws k8s scope show
    [[ "$output" == *"none"* ]]
}
@test "ambient: no session id falls back to active-session guard scope" {
    unset GDD_SESSION_ID
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_K8S_CONTEXT=kind-practice\nGDD_K8S_NAMESPACES=alice-sandbox\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/s1.env"
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete pod foo -n prod
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside the guard scope"* || "$output" == *"REJECTED"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}
@test "ambient: same-context scopes union their namespaces" {
    unset GDD_SESSION_ID
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_K8S_CONTEXT=kind-practice\nGDD_K8S_NAMESPACES=alice-sandbox\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/s1.env"
    printf 'GDD_K8S_CONTEXT=kind-practice\nGDD_K8S_NAMESPACES=bob-sandbox\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/s2.env"
    run_ws k8s delete pod y -n bob-sandbox
    [ "$status" -eq 0 ]
    run_ws k8s delete pod x -n carol
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside the guard scope"* || "$output" == *"REJECTED"* ]]
}
@test "ambient: different contexts refuse to guard" {
    unset GDD_SESSION_ID
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_K8S_CONTEXT=ctx-a\nGDD_K8S_NAMESPACES=alice\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/s1.env"
    printf 'GDD_K8S_CONTEXT=ctx-b\nGDD_K8S_NAMESPACES=bob\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/s2.env"
    run_ws k8s get pods
    [ "$status" -ne 0 ]
    [[ "$output" == *"different contexts"* ]]
}
