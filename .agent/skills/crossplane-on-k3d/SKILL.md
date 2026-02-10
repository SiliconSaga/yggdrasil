---
name: crossplane-on-k3d
description: Use when provisioning infrastructure with Crossplane on k3d/k3s, writing Compositions, debugging claims stuck in Synced-but-not-Ready, or configuring operators to watch all namespaces
---

# Crossplane on k3d

## Overview

Patterns and gotchas for running Crossplane with provider-kubernetes and provider-helm on k3d/k3s clusters. Covers composition pipelines, CEL readiness, operator namespace watching, and provider setup ordering.

## When to Use

- Setting up Crossplane on a k3d/k3s cluster
- Writing or debugging Crossplane Compositions (Pipeline mode)
- Claims stuck in "Synced but not Ready"
- CEL readiness errors like `no such key: status`
- Configuring Kubernetes operators to work with Crossplane-managed namespaces

## Critical Gotchas

### 1. Provider-configs must be applied AFTER providers are healthy

```bash
# WRONG: applying immediately after installing providers
kubectl apply -f platform.yaml  # installs provider-kubernetes
kubectl apply -f provider-configs.yaml  # FAILS - Helm CRDs don't exist yet

# RIGHT: wait first
kubectl wait --for=condition=Healthy providers.pkg.crossplane.io --all --timeout=120s
kubectl apply -f provider-configs.yaml
```

### 2. Percona PG operator: `--set watchNamespace=""` is BROKEN

Helm's `--set` silently ignores empty strings. The operator defaults to watching only its own namespace.

```bash
# BROKEN - operator only watches percona-system
helm install pg-operator percona/pg-operator --set watchNamespace=""

# CORRECT - operator watches all namespaces
helm install pg-operator percona/pg-operator --set watchAllNamespaces=true
```

This affects ANY Helm chart where `--set someVar=""` is intended to mean "all namespaces". Always check the chart for an explicit boolean flag like `watchAllNamespaces`.

### 3. CEL readiness queries crash on missing status

A CEL query like `object.status.state == 'ready'` throws `no such key: status` if the operator hasn't written any status yet. This is transient — it resolves once the operator starts reconciling. But if the operator isn't watching the namespace, it persists forever.

**Diagnosis pattern**: If CEL readiness fails AND no pods are being created in the claim's namespace, the operator isn't watching that namespace.

### 4. XRD v1 is deprecated

`CompositeResourceDefinition v1` shows deprecation warnings. Migrate to v2 when ready, but v1 still works.

## Composition Pipeline Pattern

Mimir uses the Pipeline mode with `function-go-templating` + `function-auto-ready`:

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
spec:
  mode: Pipeline
  pipeline:
    - step: deploy-resource
      functionRef:
        name: function-go-templating
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            apiVersion: kubernetes.crossplane.io/v1alpha2
            kind: Object
            spec:
              readinessPolicy: DeriveFromCelQuery
              celQuery: "object.status.state == 'ready'"
              forProvider:
                manifest:
                  # ... templated resource
    - step: automatically-detect-ready-composed-resources
      functionRef:
        name: function-auto-ready
```

Key elements:
- `DeriveFromCelQuery` + `celQuery` for readiness from operator-managed CR status
- `function-auto-ready` as final pipeline step to propagate readiness to the XR
- Go templates access claim parameters via `{{ .observed.composite.resource.spec.parameters.fieldName }}`

## Setup Ordering (validated sequence)

1. Crossplane core (Helm)
2. `platform.yaml` (provider-kubernetes + ServiceAccount + RBAC)
3. provider-helm + functions (auto-ready, go-templating)
4. **Wait for all providers/functions Healthy**
5. `provider-configs.yaml` (ProviderConfig for kubernetes + helm)
6. Namespace RBAC (crossplane-rbac.yaml)
7. Operators (Strimzi, OT-Container-Kit, Percona)
8. Operator-specific RBAC (percona/rbac.yaml)
9. XRDs and Compositions
10. Claims / tests

## Quick Reference

| Problem | Cause | Fix |
|---------|-------|-----|
| Claim Synced but never Ready | Operator not watching namespace | Use `--set watchAllNamespaces=true` |
| CEL error "no such key: status" | Operator not reconciling CR | Check operator namespace watch config |
| ProviderConfig apply fails | Provider CRDs not registered yet | Wait for `condition=Healthy` first |
| Orphaned Object resources | Parent XR deleted, Object lingers | `kubectl delete object <name>` manually |
| XRD deprecation warning | Using v1 API | Cosmetic; migrate to v2 when ready |

## Common Mistakes

- **Assuming `--set key=""` clears a value**: Helm ignores empty strings in `--set`. Use `--set-string key=""` or find a boolean alternative.
- **Applying everything at once**: Crossplane resources have dependencies. Providers must be Healthy before ProviderConfigs can be created.
- **Not giving operators cluster-wide RBAC**: Crossplane's provider-kubernetes needs `cluster-admin` to create resources in arbitrary namespaces. Operators need their own RBAC too (e.g., `percona/rbac.yaml`).
