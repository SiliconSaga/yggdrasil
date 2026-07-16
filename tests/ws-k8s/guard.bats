#!/usr/bin/env bats
load test_helper
setup() { make_kubectl_stub "default"; }

make_kustomize_probe() {
    local rendered="$1"
    export KUSTOMIZE_PROBE="$BATS_TEST_TMPDIR/kustomize-called"
    cat > "$BATS_TEST_TMPDIR/kubectl-kustomize-probe" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "kustomize" ]]; then
  touch "$KUSTOMIZE_PROBE"
  cat "$rendered"
else
  echo default
fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/kubectl-kustomize-probe"
    export KUBECTL="$BATS_TEST_TMPDIR/kubectl-kustomize-probe"
}

@test "script resolver anchors slash-relative paths to the payload cwd" {
    mkdir -p "$BATS_TEST_TMPDIR/work/scripts"
    printf '#!/bin/bash\nkubectl get pods\n' > "$BATS_TEST_TMPDIR/work/scripts/direct-danger.sh"
    run bash -c 'source "$1"; k8s_guard_script_path "$2" "scripts/direct-danger.sh"' _ "$GUARD_LIB" "$BATS_TEST_TMPDIR/work"
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/work/scripts/direct-danger.sh" ]
}

@test "command normalization fails closed on multiline and compound forms" {
    local command
    for command in \
        $'echo safe\nkubectl delete namespace prod' \
        $'echo safe\rkubectl delete namespace prod' \
        'echo safe; kubectl delete namespace prod' \
        'echo safe && kubectl delete namespace prod' \
        'echo "$(kubectl delete namespace prod)"'; do
        run bash -c 'source "$1"; k8s_guard_normalize_command "$2"' _ "$GUARD_LIB" "$command"
        [ "$status" -eq 0 ]
        [ "$output" = "__GDD_K8S_UNSAFE_COMMAND__" ]
    done
}

@test "non-kubectl command is NOT_K8S" {
    run_guard "kind-practice" "alice-sandbox" ls -la
    [ "$output" = "NOT_K8S" ]
}
@test "read is classified even when no scope is armed" {
    run_guard "" "" kubectl get pods
    [ "$output" = "READ_NO_SCOPE" ]
}
@test "write is classified even when no scope is armed" {
    run_guard "" "" kubectl apply -k overlays/plain
    [ "$output" = "WRITE_NO_SCOPE" ]
}
@test "kubectl run is classified as a write without relying on manifest flags" {
    run_guard "" "" kubectl run script-test --image=pause --restart=Never -n gdd-practice
    [ "$output" = "WRITE_NO_SCOPE" ]
}
@test "kubectl run is scope-checked like every other write" {
    run_guard "kind-practice" "gdd-practice" kubectl run script-test --image=pause --restart=Never -n other
    [[ "$output" == BLOCK:scope:* ]]
}
@test "standalone kustomize render is a read" {
    run_guard "" "" kubectl kustomize overlays/plain
    [ "$output" = "READ_NO_SCOPE" ]
}
@test "read anywhere on matching context is READ_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl get pods -n kube-system
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "value-taking global flag cannot shift a delete into a read" {
    run_guard "kind-practice" "alice-sandbox" kubectl --cache-dir get delete pods --all -n kube-system
    [[ "$output" == BLOCK:scope:* ]]
}
@test "post-verb cache-dir value cannot hide a cluster-scoped resource" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete --cache-dir /tmp/cache nodes worker1
    [[ "$output" == BLOCK:unbounded:* ]]
}
@test "write to in-scope namespace is WRITE_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "write to out-of-scope namespace BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n prod
    [[ "$output" == BLOCK:* ]]
}
@test "write with a separate --raw API path is unbounded" {
    run_guard "kind-practice" "alice-sandbox" kubectl create --raw /apis/rbac.authorization.k8s.io/v1/clusterrolebindings -n alice-sandbox
    [[ "$output" == BLOCK:unbounded:* ]]
    [[ "$output" == *"--raw"* ]]
}
@test "write with an attached --raw API path is unbounded" {
    run_guard "kind-practice" "alice-sandbox" kubectl create --raw=/apis/rbac.authorization.k8s.io/v1/clusterrolebindings -n alice-sandbox
    [[ "$output" == BLOCK:unbounded:* ]]
    [[ "$output" == *"--raw"* ]]
}
@test "read with --raw remains a read" {
    run_guard "kind-practice" "alice-sandbox" kubectl get --raw=/apis
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "conflicting --context BLOCKs absolutely" {
    run_guard "kind-practice" "alice-sandbox" kubectl get pods --context other-cluster
    [[ "$output" == BLOCK:* ]]
}
@test "write with no -n uses the context default namespace" {
    make_kubectl_stub "alice-sandbox"
    run_guard "kind-practice" "alice-sandbox" kubectl scale deploy/foo --replicas=2
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "write with default namespace out of scope BLOCKs" {
    make_kubectl_stub "default"
    run_guard "kind-practice" "alice-sandbox" kubectl scale deploy/foo --replicas=2
    [[ "$output" == BLOCK:* ]]
}
@test "--all-namespaces on a write BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pods --all-namespaces
    [[ "$output" == BLOCK:* ]]
}
@test "unknown verb is treated as write (fail-safe)" {
    run_guard "kind-practice" "alice-sandbox" kubectl frobnicate -n prod
    [[ "$output" == BLOCK:* ]]
}
@test "apply -f with in-scope manifest namespace is WRITE_IN_SCOPE" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/m.yaml"
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "apply -f with out-of-scope manifest namespace BLOCKs" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n  namespace: prod\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/m.yaml"
    [[ "$output" == BLOCK:* ]]
}
@test "apply -k inspects rendered resources and allows an in-scope namespace" {
    mkdir -p "$BATS_TEST_TMPDIR/overlay"
    printf 'resources: []\n' > "$BATS_TEST_TMPDIR/overlay/kustomization.yaml"
    cat > "$BATS_TEST_TMPDIR/rendered.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: in-scope
  namespace: alice-sandbox
EOF
    cat > "$BATS_TEST_TMPDIR/kubectl-kustomize" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "kustomize" ]]; then cat "$BATS_TEST_TMPDIR/rendered.yaml"; else echo default; fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/kubectl-kustomize"
    export KUBECTL="$BATS_TEST_TMPDIR/kubectl-kustomize"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$BATS_TEST_TMPDIR/overlay"
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "apply --kustomize blocks a rendered out-of-scope namespace" {
    mkdir -p "$BATS_TEST_TMPDIR/overlay"
    printf 'resources: []\n' > "$BATS_TEST_TMPDIR/overlay/kustomization.yaml"
    cat > "$BATS_TEST_TMPDIR/rendered.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: out-of-scope
  namespace: prod
EOF
    cat > "$BATS_TEST_TMPDIR/kubectl-kustomize" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "kustomize" ]]; then cat "$BATS_TEST_TMPDIR/rendered.yaml"; else echo default; fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/kubectl-kustomize"
    export KUBECTL="$BATS_TEST_TMPDIR/kubectl-kustomize"
    run_guard "kind-practice" "alice-sandbox" kubectl --context kind-practice apply --kustomize "$BATS_TEST_TMPDIR/overlay" -n alice-sandbox
    [[ "$output" == BLOCK:scope:* ]]
}
@test "apply -k blocks a rendered cluster-scoped resource" {
    mkdir -p "$BATS_TEST_TMPDIR/overlay"
    printf 'resources: []\n' > "$BATS_TEST_TMPDIR/overlay/kustomization.yaml"
    cat > "$BATS_TEST_TMPDIR/rendered.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: unsafe
EOF
    cat > "$BATS_TEST_TMPDIR/kubectl-kustomize" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "kustomize" ]]; then cat "$BATS_TEST_TMPDIR/rendered.yaml"; else echo default; fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/kubectl-kustomize"
    export KUBECTL="$BATS_TEST_TMPDIR/kubectl-kustomize"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$BATS_TEST_TMPDIR/overlay" -n alice-sandbox
    [[ "$output" == BLOCK:unbounded:* ]]
}
@test "apply -k fails closed when the local kustomization path is missing" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$BATS_TEST_TMPDIR/missing-overlay"
    [[ "$output" == BLOCK:precondition:* ]]
}

@test "apply -k rejects an HTTPS resource before invoking kubectl kustomize" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay"
    cat > "$overlay/kustomization.yaml" <<'YAML'
resources:
  - https://attacker.example/base.yaml
YAML
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]
}

@test "apply -k rejects a Git-style remote resource before rendering" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay"
    cat > "$overlay/kustomization.yaml" <<'YAML'
resources:
  - github.com/example/repo//base?ref=main
YAML
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]
}

@test "apply -k rejects absolute and parent-traversal resources before rendering" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay"
    printf 'resources:\n  - ../outside.yaml\n' > "$overlay/kustomization.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\n' > "$BATS_TEST_TMPDIR/outside.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]

    printf 'resources:\n  - /etc/hosts\n' > "$overlay/kustomization.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"
    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]
}

@test "apply -k recursively rejects a remote reference in a local child" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay/child"
    printf 'resources:\n  - child\n' > "$overlay/kustomization.yaml"
    cat > "$overlay/child/kustomization.yaml" <<'YAML'
resources:
  - https://attacker.example/nested.yaml
YAML
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]
}

@test "apply -k rejects a remote legacy JSON patch before rendering" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay"
    cat > "$overlay/kustomization.yaml" <<'YAML'
patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: example
    path: https://attacker.example/patch.json
YAML
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]
}

@test "apply -k rejects a symlinked kustomization file before rendering" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay"
    printf 'resources: []\n' > "$BATS_TEST_TMPDIR/outside-kustomization.yaml"
    ln -s "$BATS_TEST_TMPDIR/outside-kustomization.yaml" "$overlay/kustomization.yaml" 2>/dev/null || true
    [[ -L "$overlay/kustomization.yaml" ]] || skip "real symlinks not supported on this platform"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [[ "$output" == BLOCK:precondition:* ]]
    [ ! -e "$KUSTOMIZE_PROBE" ]
}

@test "apply -k renders after a recursively local reference graph passes" {
    local overlay="$BATS_TEST_TMPDIR/overlay"
    mkdir -p "$overlay/child"
    printf 'resources:\n  - child\n  - configmap.yaml\n' > "$overlay/kustomization.yaml"
    printf 'resources:\n  - child-configmap.yaml\n' > "$overlay/child/kustomization.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: root\n' > "$overlay/configmap.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: child\n' > "$overlay/child/child-configmap.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: rendered\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/rendered.yaml"
    make_kustomize_probe "$BATS_TEST_TMPDIR/rendered.yaml"

    run_guard "kind-practice" "alice-sandbox" kubectl apply -k "$overlay"

    [ "$output" = "WRITE_IN_SCOPE" ]
    [ -e "$KUSTOMIZE_PROBE" ]
}
@test "apply -f a remote URL BLOCKs (cannot resolve)" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f https://example.com/x.yaml
    [[ "$output" == BLOCK:* ]]
}
@test "apply -f - (stdin) BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f -
    [[ "$output" == BLOCK:* ]]
}
@test "config use-context is blocked (mutates kubeconfig, not a free read)" {
    run_guard "kind-practice" "alice-sandbox" kubectl config use-context other
    [[ "$output" == BLOCK:* ]]
}
@test "config delete-context is blocked (fail closed)" {
    run_guard "kind-practice" "alice-sandbox" kubectl config delete-context other
    [[ "$output" == BLOCK:* ]]
}
@test "config view is READ_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl config view
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "auth reconcile is blocked (mutating auth, fail closed)" {
    run_guard "kind-practice" "alice-sandbox" kubectl auth reconcile -f /dev/null
    [[ "$output" == BLOCK:* ]]
}
@test "auth can-i is READ_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl auth can-i create pods
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "attached -n short form (-nprod) is parsed: out-of-scope write BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -nprod
    [[ "$output" == BLOCK:* ]]
}
@test "attached -n short form (-nalice-sandbox) is parsed: in-scope write OK" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -nalice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "attached -f short form (-f<file>) is parsed for the manifest namespace" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n  namespace: prod\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f"$BATS_TEST_TMPDIR/m.yaml"
    [[ "$output" == BLOCK:* ]]
}
@test "apply -f manifest with no namespace falls back to in-scope -n" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/m.yaml" -n alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "apply -f manifest with no namespace and no -n BLOCKs" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/m.yaml"
    [[ "$output" == BLOCK:* ]]
}
@test "delete namespace is blocked even with an in-scope -n (cluster-scoped)" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace prod -n alice-sandbox
    [[ "$output" == BLOCK:* ]]
}
@test "delete ns short alias is blocked (cluster-scoped)" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete ns prod
    [[ "$output" == BLOCK:* ]]
}
@test "create clusterrole is blocked (cluster-scoped)" {
    run_guard "kind-practice" "alice-sandbox" kubectl create clusterrole foo --verb=get --resource=pods
    [[ "$output" == BLOCK:* ]]
}
@test "cordon node is blocked (node-level verb)" {
    run_guard "kind-practice" "alice-sandbox" kubectl cordon node1
    [[ "$output" == BLOCK:* ]]
}
@test "apply -f a cluster-scoped Kind is blocked even with in-scope -n" {
    printf 'apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRole\nmetadata:\n  name: x\n' > "$BATS_TEST_TMPDIR/cr.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/cr.yaml" -n alice-sandbox
    [[ "$output" == BLOCK:* ]]
}
@test "create namespace whose name is IN scope is allowed (WRITE_IN_SCOPE)" {
    run_guard "kind-practice" "alice-sandbox" kubectl create namespace alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "delete namespace whose name is IN scope is allowed (delete+recreate workflow)" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "delete ns alias whose name is IN scope is allowed" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete ns alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "create namespace whose name is OUT of scope is classed 'scope'" {
    run_guard "kind-practice" "alice-sandbox" kubectl create namespace prod
    [[ "$output" == BLOCK:scope:* ]]
}
@test "delete namespace with mixed in/out-of-scope names BLOCKs on the out-of-scope one" {
    run_guard "kind-practice" "alice-sandbox,bob-sandbox" kubectl delete namespace alice-sandbox prod
    [[ "$output" == BLOCK:scope:* ]]
}
@test "create namespace IN scope with a value-flag does not misread the flag value as a name" {
    run_guard "kind-practice" "alice-sandbox" kubectl create namespace alice-sandbox -o yaml
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "delete namespace IN scope with --timeout does not misread the value as a name" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace alice-sandbox --timeout 5s
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "delete ns/<name> slash form IN scope is allowed" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete ns/alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "delete namespace/<name> slash form OUT of scope is classed 'scope'" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace/prod
    [[ "$output" == BLOCK:scope:* ]]
}
@test "space-form --dry-run does NOT consume the mode (kubectl NoOptDefVal); out-of-scope name blocks" {
    # kubectl's --dry-run has a NoOptDefVal, so `--dry-run client` does NOT consume
    # 'client' — kubectl itself reads it as a second namespace target. The guard
    # must NOT treat --dry-run as value-consuming, or it would fail OPEN on the
    # out-of-scope 'client'. (The correct mode form is --dry-run=client.)
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace alice-sandbox --dry-run client
    [[ "$output" == BLOCK:scope:* ]]
}
@test "equals-form --dry-run=client is a single token and does not affect name parsing" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace alice-sandbox --dry-run=client
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "delete namespace with no name (e.g. --all) stays cluster-scoped unbounded" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete namespace --all
    [[ "$output" == BLOCK:unbounded:* ]]
}
@test "reading a cluster-scoped resource is still allowed (reads are free)" {
    run_guard "kind-practice" "alice-sandbox" kubectl get namespace prod
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "apply -f a kind:List blocks when an embedded item is out of scope" {
    printf 'apiVersion: v1\nkind: List\nitems:\n  - {apiVersion: v1, kind: Pod, metadata: {name: a, namespace: alice-sandbox}}\n  - {apiVersion: v1, kind: Pod, metadata: {name: b, namespace: prod}}\n' > "$BATS_TEST_TMPDIR/l.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/l.yaml"
    [[ "$output" == BLOCK:* ]]
}
@test "apply -f a kind:List with all items in scope is WRITE_IN_SCOPE" {
    printf 'apiVersion: v1\nkind: List\nitems:\n  - {apiVersion: v1, kind: Pod, metadata: {name: a, namespace: alice-sandbox}}\n  - {apiVersion: v1, kind: ConfigMap, metadata: {name: c, namespace: alice-sandbox}}\n' > "$BATS_TEST_TMPDIR/l.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/l.yaml"
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "apply -f a kind:List with a cluster-scoped item BLOCKs" {
    printf 'apiVersion: v1\nkind: List\nitems:\n  - {apiVersion: v1, kind: Pod, metadata: {name: a, namespace: alice-sandbox}}\n  - {apiVersion: rbac.authorization.k8s.io/v1, kind: ClusterRole, metadata: {name: c}}\n' > "$BATS_TEST_TMPDIR/l.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/l.yaml"
    [[ "$output" == BLOCK:* ]]
}
@test "out-of-scope namespace write is classed 'scope'" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n prod
    [[ "$output" == BLOCK:scope:* ]]
}
@test "cluster-scoped resource write is classed 'unbounded'" {
    # Use a clusterrole (always unbounded). A namespace is now scope-checked by
    # NAME — an out-of-scope namespace is classed 'scope', not 'unbounded'.
    run_guard "kind-practice" "alice-sandbox" kubectl delete clusterrole foo
    [[ "$output" == BLOCK:unbounded:* ]]
}
@test "config use-context is classed 'unbounded' (not namespace-bounded)" {
    run_guard "kind-practice" "alice-sandbox" kubectl config use-context other
    [[ "$output" == BLOCK:unbounded:* ]]
}
@test "conflicting --context is classed 'context'" {
    run_guard "kind-practice" "alice-sandbox" kubectl get pods --context other-cluster
    [[ "$output" == BLOCK:context:* ]]
}
@test "missing -f file is classed 'precondition'" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/does-not-exist.yaml"
    [[ "$output" == BLOCK:precondition:* ]]
}
@test "apply -f a remote URL is classed 'precondition'" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f https://example.com/x.yaml
    [[ "$output" == BLOCK:precondition:* ]]
}
@test "apply -f a backslash path resolves (Windows Git Bash native path)" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/m.yaml"
    # Claude Code passes native Windows paths (C:\...\m.yaml); the guard must
    # normalize backslashes before the on-disk check instead of failing closed.
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR\\m.yaml"
    [ "$output" = "WRITE_IN_SCOPE" ]
}

# ─── _k8s_normalize_path: Windows backslash → forward slash ─────────
@test "_k8s_normalize_path converts a Windows drive path to forward slashes" {
    run bash -c "source '$GUARD_LIB'; _k8s_normalize_path 'C:\\Users\\me\\list.yaml'"
    [ "$output" = "C:/Users/me/list.yaml" ]
}
@test "_k8s_normalize_path leaves a POSIX path unchanged" {
    run bash -c "source '$GUARD_LIB'; _k8s_normalize_path '/home/me/list.yaml'"
    [ "$output" = "/home/me/list.yaml" ]
}

# ─── k8s_render_block: class-appropriate remediation ────────────────
render_block() { run bash -c "source '$GUARD_LIB'; k8s_render_block \"\$1\" \"\$2\" \"\$3\"" _ "$@"; }

@test "render 'scope' block points at adding the namespace to the scope (not generic 'widen', no bypass)" {
    render_block "BLOCK:scope:write target namespace prod outside the guard scope (alice-sandbox)" kind-practice k8s
    [[ "$output" == *"REJECTED"* ]]
    [[ "$output" == *"Add that namespace to the scope"* ]]
    [[ "$output" != *"hook-bypass"* ]]
}
@test "render 'scope' block with empty context uses a <ctx> placeholder, not a blank --context" {
    render_block "BLOCK:scope:write target namespace prod outside the guard scope (alice-sandbox)" "" k8s
    [[ "$output" == *"--context <ctx>"* ]]
    [[ "$output" != *"--context  --namespace"* ]]
}
@test "render 'unbounded' block: no bypass, no scope-set suggestion; points at plain kubectl / scope clear" {
    render_block "BLOCK:unbounded:namespace is a cluster-scoped resource" kind-practice k8s
    [[ "$output" == *"REJECTED"* ]]
    [[ "$output" != *"hook-bypass"* ]]
    [[ "$output" != *"scope set"* ]]   # widening is not offered as a fix here
    [[ "$output" == *"scope clear"* ]]
    [[ "$output" == *"plain"* ]]
}
@test "render 'precondition' block frames an input problem, not a scope rejection" {
    render_block "BLOCK:precondition:-f /x.yaml not found on disk" kind-practice k8s
    [[ "$output" == *"REJECTED"* ]]
    [[ "$output" != *"widen the scope"* ]]
    [[ "$output" == *"input"* ]]
}
@test "render 'context' block points at re-arming the scope" {
    render_block "BLOCK:context:explicit --context other != the guard-scope context kind-practice" kind-practice k8s
    [[ "$output" != *"widen the scope"* ]]
    [[ "$output" == *"context"* ]]
}
@test "render a classless BLOCK (back-compat) still produces a REJECTED message" {
    render_block "BLOCK:some bare legacy reason" kind-practice k8s
    [[ "$output" == *"REJECTED"* ]]
    [[ "$output" == *"some bare legacy reason"* ]]
}

@test "scope show is NOT_K8S (wrapper management, not a kubectl command)" {
    run_guard "kind-practice" "alice-sandbox" ws k8s scope show
    [ "$output" = "NOT_K8S" ]
}
@test "scope set is NOT_K8S (wrapper management, not a kubectl command)" {
    run_guard "kind-practice" "alice-sandbox" ws k8s scope set --context kind-practice --namespace alice-sandbox
    [ "$output" = "NOT_K8S" ]
}
