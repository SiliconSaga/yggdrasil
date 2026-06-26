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
