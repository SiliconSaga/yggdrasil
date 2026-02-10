---
name: kuttl-testing
description: Use when writing or debugging kuttl e2e tests for Kubernetes, especially tests involving Crossplane claims, operator-managed resources, one-shot client pods, or secret-dependent connectivity checks
---

# Kuttl Testing for Kubernetes

## Overview

Patterns for writing reliable kuttl (KUbernetes Test TooL) e2e tests. Covers the one-shot pod gotcha, retry patterns for connectivity tests, and assertion strategies for Crossplane claims.

## When to Use

- Writing kuttl test steps for Kubernetes resources
- Testing Crossplane claim provisioning end-to-end
- Debugging kuttl tests that timeout on `kubectl wait`
- Testing database/service connectivity with client pods
- BDD-style infrastructure testing

## Critical Gotcha: One-Shot Pods

**`kubectl run --restart=Never` pods become `Succeeded`/`Failed`, never `Ready`.**

```bash
# BROKEN - will timeout forever
kubectl run client --restart=Never --image=postgres:15 --command -- psql ...
kubectl wait --for=condition=Ready pod/client --timeout=120s

# CORRECT - wait for phase instead
kubectl run client --restart=Never --image=postgres:15 --command -- psql ...
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/client --timeout=120s
```

Why: One-shot pods (`restartPolicy: Never`) transition through `Pending` → `Running` → `Succeeded`/`Failed`. The `Ready` condition is only meaningful for long-running pods with readiness probes.

## Test Structure

```
tests/e2e/
  service-provisioning/
    00-apply.yaml       # Create claim
    01-assert.yaml      # Assert Synced + Ready
    02-connection.yaml   # (optional) Test actual connectivity
```

### Step 0: Apply Claim

```yaml
apiVersion: kuttl.dev/v1beta1
kind: TestStep
# Inline resource to create - kuttl applies it automatically
---
apiVersion: database.example.org/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: pg-e2e-test
spec:
  parameters:
    storageSize: 1Gi
    version: "15"
  compositionSelector:
    matchLabels:
      provider: percona
      service: postgresql
```

Or use a separate resource file referenced by the step.

### Step 1: Assert Ready

```yaml
apiVersion: database.example.org/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: pg-e2e-test
status:
  conditions:
    - type: Synced
      status: "True"
    - type: Ready
      status: "True"
```

kuttl polls this assertion until it matches or times out (configured in `kuttl-test.yaml`).

### Step 2: Connection Test (Script Pattern)

```yaml
apiVersion: kuttl.dev/v1beta1
kind: TestStep
commands:
  - script: |
      set -e -o pipefail
      sleep 5

      # Wait for secret to exist (operator creates it async)
      echo "Waiting for secret..."
      for i in $(seq 1 30); do
        if kubectl get secret my-secret -n $NAMESPACE >/dev/null 2>&1; then
          echo "Secret found."
          break
        fi
        echo "Secret not found yet, waiting..."
        sleep 2
      done

      # Extract credentials
      PASSWORD=$(kubectl get secret my-secret -n $NAMESPACE \
        -o jsonpath='{.data.password}' | base64 -d)

      # Run client with RETRY LOOP inside the container
      kubectl run client --namespace $NAMESPACE \
        --image=postgres:15 --restart=Never \
        --env="PGPASSWORD=$PASSWORD" \
        --command -- sh -c '
          for i in $(seq 1 12); do
            psql -h my-service -U myuser -d mydb -c "SELECT 1;" && exit 0
            echo "Retry $i..."
            sleep 5
          done
          exit 1'

      # Wait for completion (NOT --for=condition=Ready!)
      kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
        pod/client -n $NAMESPACE --timeout=120s
      kubectl logs client -n $NAMESPACE
```

Key elements:
- `$NAMESPACE` is set by kuttl automatically (the ephemeral test namespace)
- **Secret wait loop**: Operators create secrets asynchronously after the CR is ready
- **Retry loop inside container**: The service endpoint may not be routable immediately
- **`jsonpath phase=Succeeded`**: Correct wait for one-shot pods

## Quick Reference

| Pattern | Use |
|---------|-----|
| `--for=jsonpath='{.status.phase}'=Succeeded` | Wait for one-shot pods |
| `--for=condition=Ready` | Wait for long-running pods/deployments |
| `$NAMESPACE` | kuttl-provided test namespace variable |
| `sleep 5` before secret check | Give operator time to start reconciling |
| Retry loop in container command | Handle transient connectivity after provisioning |
| `set -e -o pipefail` | Fail script on any error |

## kuttl-test.yaml Configuration

```yaml
apiVersion: kuttl.dev/v1beta1
kind: TestSuite
testDirs:
  - tests/e2e/
timeout: 600        # Per-step timeout in seconds
parallel: 1         # Sequential execution (important for shared cluster resources)
skipDelete: false    # Clean up test namespaces after each test
```

`parallel: 1` is important when tests share cluster-level resources (operators, CRDs). Higher parallelism risks resource contention on small clusters.

## Common Mistakes

- **Using `--for=condition=Ready` on one-shot pods**: Will timeout forever. Use `jsonpath phase=Succeeded`.
- **No retry loop in client commands**: The service may not be reachable the instant the CR reports Ready. Always retry.
- **Not waiting for secrets**: Operators create connection secrets async. Poll for the secret before extracting credentials.
- **Forgetting `--restart=Never`**: Without it, `kubectl run` creates a Deployment, not a one-shot pod. The pod restarts on failure instead of transitioning to `Failed`.
- **Missing `set -e`**: Without strict error handling, earlier failures are silently ignored and the test may pass incorrectly.

## Client Image Reference

| Database | Client Image | Connection Command |
|----------|-------------|-------------------|
| PostgreSQL | `postgres:15` | `psql -h HOST -U USER -d DB -c "SELECT 1;"` |
| MySQL | `mysql:8.0` | `mysql -h HOST -u USER -e "SELECT 1;"` (use `MYSQL_PWD` env) |
| MongoDB | `percona/percona-server-mongodb:6.0` | `mongosh "mongodb://USER:PASS@HOST:27017/admin" --eval "db.runCommand({ping:1})"` |
| Valkey/Redis | `valkey/valkey:8.0` | `valkey-cli -h HOST ping` |
| Kafka | (use kuttl assertion on CR status) | N/A - assert KafkaNodePool Ready |
