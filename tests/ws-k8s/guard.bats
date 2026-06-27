#!/usr/bin/env bats
load test_helper
setup() { make_kubectl_stub "default"; }

@test "non-kubectl command is NOT_K8S" {
    run_guard "kind-practice" "alice-sandbox" ls -la
    [ "$output" = "NOT_K8S" ]
}
@test "no scope set is NO_SCOPE" {
    run_guard "" "" kubectl get pods
    [ "$output" = "NO_SCOPE" ]
}
@test "read anywhere on matching context is READ_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl get pods -n kube-system
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "write to in-scope namespace is WRITE_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}
@test "write to out-of-scope namespace BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n prod
    [[ "$output" == BLOCK:* ]]
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
@test "reading a cluster-scoped resource is still allowed (reads are free)" {
    run_guard "kind-practice" "alice-sandbox" kubectl get namespace prod
    [ "$output" = "READ_IN_SCOPE" ]
}
@test "scope show is NOT_K8S (wrapper management, not a kubectl command)" {
    run_guard "kind-practice" "alice-sandbox" ws k8s scope show
    [ "$output" = "NOT_K8S" ]
}
@test "scope set is NOT_K8S (wrapper management, not a kubectl command)" {
    run_guard "kind-practice" "alice-sandbox" ws k8s scope set --context kind-practice --namespace alice-sandbox
    [ "$output" = "NOT_K8S" ]
}
