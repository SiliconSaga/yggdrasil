---
name: crossplane-compositions
description: Use when writing or debugging Crossplane v1/v2 Compositions (Pipeline mode with function-go-templating + function-environment-configs + provider-kubernetes), validating offline with `crossplane render`/`beta validate`, debugging Synced-but-not-Ready claims, migrating Deployment strategy on a live cluster (the SSA-Recreate trap), recognizing CompositionRevision flapping (GitOps-managed Composition tell, stale-revision pinning, mutating-webhook fights), or configuring operators that need cluster-wide namespace watching.
---

# crossplane-compositions

## Overview

Crossplane Compositions in Pipeline mode have a small, stable set of integration gotchas that bite the same way every time: the readiness-via-CEL-on-`Object` pattern, the `function-environment-configs` context shape, validating without a cluster, and the live-mutation traps when you change a managed resource that Kubernetes treats as semi-immutable (`Deployment.strategy`), test by `kubectl apply`ing over a GitOps controller, or share a Composition with someone else who keeps rewriting it.

## When to Use

- Writing a Pipeline Composition (`function-go-templating` + `function-environment-configs` + `provider-kubernetes` + `function-auto-ready`).
- Claim is `Synced=True Ready=False` and you need to walk the chain.
- Changing a Deployment's `strategy.type` in a Composition and the rollout deadlocks or returns `Forbidden`.
- `CompositionRevision` counter climbs every reconcile cycle for no obvious reason.
- An operator the Composition deploys only reconciles in its own namespace and your Claim sits Ready=False.

## Quick Reference

| Goal | Pattern | Gotcha |
|------|---------|--------|
| Offline-validate a Composition | `crossplane render <xr>.yaml <composition>.yaml <functions>.yaml --extra-resources=<envconfig>.yaml --include-function-results --include-context` | No cluster needed — fastest feedback loop. Pair with `crossplane beta validate <xrd>.yaml -` for schema. |
| Read EnvironmentConfig in template | `{{- $env := index .context "apiextensions.crossplane.io/environment" -}}` then `$env.data.<key>` | `function-environment-configs` writes the merged map under exactly that context key. |
| Readiness from live status | `Object.spec.readiness: { policy: DeriveFromCelQuery, celQuery: status.availableReplicas >= 1 }` | provider-kubernetes evaluates the CEL against the **observed** object. Requires `kubernetes.crossplane.io/v1alpha2` (v1alpha1 doesn't support it). |
| Single-replica RWO Deployment | `strategy: { type: Recreate }` | Default RollingUpdate deadlocks on Multi-Attach. See `kube-prometheus-stack` → "Single-Replica RWO Workloads" and `alertmanager-config` for the same pattern. |
| Provider setup order | Install providers → `kubectl wait --for=condition=Healthy providers.pkg.crossplane.io --all --timeout=120s` → THEN apply `ProviderConfig`s | Otherwise `no matches for kind ProviderConfig` (CRDs don't exist yet). |
| Operator that watches all namespaces | Use the operator's boolean (e.g. `--set watchAllNamespaces=true`), NOT `--set watchNamespace=""` | Helm `--set` silently ignores empty strings → operator only watches its own namespace → Claim stuck Synced=True Ready=False forever. |
| CRD field shape | `kubectl explain <kind>.spec.<path>` | Don't guess `spec.instances.containers` vs `spec.instances.initContainer`; the API server has the truth. |
| Testing | kuttl for end-to-end (Claim→Ready) verification | See root `kuttl-testing` skill — `--config kuttl-test.yaml` matters. |

## CEL Readiness Failure Modes

`object.status.<field>` throws `no such key: status` if the operator hasn't written **any** status yet — transient at first, **permanent** if the operator isn't watching the claim's namespace.

**Diagnosis rule:** if CEL readiness fails AND no pods are being created in the claim's namespace, the operator isn't watching. See the `watchAllNamespaces` row above.

## Debugging `Synced=True Ready=False`

Walk top-down. The contradiction is the clue — at every level ask "what does this say about the level above and below?"

```bash
# 1. XR's view + which composed resources report not-Ready.
kubectl get <xr-kind> <claim-name> -o yaml | yq '.status'
kubectl describe <xr-kind> <claim-name>

# 2. Each composed Object — Synced = "Apply succeeded"; Ready = readinessPolicy result.
kubectl get objects.kubernetes.crossplane.io -l crossplane.io/composite=<xr-name>
kubectl describe object <xr-name>-<resource-name>

# 3. The live K8s resource the Object manages.
kubectl -n <ns> get deploy <name> -o yaml | yq '.status'
kubectl -n <ns> describe pod -l <selector>
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -30

# 4. Provider-kubernetes — does it actually see the live resource?
kubectl -n crossplane-system logs deploy/provider-kubernetes-... | grep <xr-name>
```

Most-common root causes: PVC `Pending` (wrong/missing `storageClass`), `ImagePullBackOff`, the operator-not-watching pattern.

## Deployment Strategy Migration on a Live Cluster

When you change a Composition from `strategy.type: RollingUpdate` → `Recreate`, the apply fails with:

```
Deployment "X" is invalid: spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy.type is 'Recreate'
```

The old defaulted `rollingUpdate: { maxSurge, maxUnavailable }` block is still in the live spec, and the API forbids it under `type: Recreate`. The Object goes `Synced=False`; the Deployment keeps running with the old strategy — the migration silently doesn't happen.

**Two fixes — pick by blast radius:**

```bash
# Surgical: strip the orphan rollingUpdate block in place. Pod keeps running; Crossplane reconciles cleanly into Recreate on next pass.
kubectl -n <ns> patch deployment <name> --type=json \
  -p='[{"op":"remove","path":"/spec/strategy/rollingUpdate"}]'

# Nuclear: delete the live Deployment; provider-kubernetes recreates it from the manifest cleanly with type: Recreate.
kubectl -n <ns> delete deployment <name>
```

The nuclear option is what we used on GKE during the ntfy rollout — works every time but causes a brief outage. The surgical patch keeps the pod up.

## "Test Through GitOps" — Don't `kubectl apply` Over a Managed Composition

If a Composition (or any Crossplane resource) is managed by ArgoCD/Flux, a `kubectl apply` to test changes triggers a **flapping war**: your apply → GitOps self-heal reverts → next reconcile re-applies → CompositionRevision counter increments every cycle, composed resources oscillate. Test through the git source (push to the seed-gitea, hard-refresh the app); source of truth wins.

`managedFields` names the writers — diagnostic for who's fighting whom:

```bash
kubectl get composition <name> -o yaml | yq '.metadata.managedFields[].manager'
# Both `argocd-controller` AND `crossplane` writing the Composition = your flap.
```

(The SiliconSaga re-hydrate workflow — push to in-cluster seed-gitea via `update-embedded-git.sh <env>` — will live in the planned `siliconsaga-stack` skill.)

## CompositionRevision Flapping — Three Causes

1. **GitOps controller fighting Crossplane** (above — the usual case).
2. **Mutating admission webhook** (Istio/Linkerd sidecar injector, Kyverno policy, PSA defaulter) adds fields to the composed resource that aren't in your manifest. Crossplane patches them out → webhook re-injects on next admission → composed object flaps; Object's `Synced` flips. `kubectl get mutatingwebhookconfigurations` + the live resource's `managedFields`.
3. **Stale `compositionUpdatePolicy: Automatic` adopting the wrong revision.** Automatic picks the revision with the highest `spec.revision` number. If a stale higher-numbered revision lingers (e.g. messy bootstrap history where the Composition was overwritten back and forth), the XR stays pinned to old content even after you apply new. We hit this on a homelab bootstrap.

   ```bash
   # If numbers don't match creation-time ordering, delete the stale higher one.
   kubectl get compositionrevision -l crossplane.io/composition-name=<name>
   kubectl delete compositionrevision <stale-name>
   ```

## Common Mistakes

- **`kubectl apply` over a GitOps-managed Composition** → flapping war. Test through the git source instead.
- **Changing `strategy.type` to Recreate via Composition update without clearing `rollingUpdate`** → `Forbidden` API error, Object Synced=False, live Deployment unchanged. Patch or delete.
- **`--set watchNamespace=""`** on a Helm-installed operator → silently no-ops, operator only watches own namespace, Claim never goes Ready.
- **CEL query on `status.<field>` before the operator writes status** → transient `no such key: status`. If permanent: operator isn't watching the claim's namespace.
- **v1alpha1 `Object` with `readiness: { policy: DeriveFromCelQuery }`** → not supported. Use `kubernetes.crossplane.io/v1alpha2`.
- **Applying `ProviderConfig` before the Provider is `Healthy`** → `no matches for kind`. `kubectl wait --for=condition=Healthy providers.pkg.crossplane.io --all --timeout=120s` first.
- **Default operator security context clashes** (Rancher Desktop, strict PSA) — `runAsNonRoot` errors. Override in the Composition manifest (e.g. `initContainer.containerSecurityContext.runAsNonRoot: false`).
- **XRD v1 deprecation warning** — cosmetic; migrate to v2 when ready, v1 still works.

## Implementation Sketch

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: <name>-default
spec:
  compositeTypeRef: { apiVersion: ..., kind: X... }
  mode: Pipeline
  pipeline:
    - step: load-environment
      functionRef: { name: function-environment-configs }
      input:
        apiVersion: environmentconfigs.fn.crossplane.io/v1beta1
        kind: Input
        spec:
          environmentConfigs:
            - { type: Reference, ref: { name: cluster-identity } }

    - step: render-resources
      functionRef: { name: function-go-templating }
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            {{- $env := index .context "apiextensions.crossplane.io/environment" -}}
            ---
            apiVersion: kubernetes.crossplane.io/v1alpha2
            kind: Object
            metadata:
              annotations:
                gotemplating.fn.crossplane.io/composition-resource-name: my-deployment
              name: {{ .observed.composite.resource.metadata.name }}-deployment
            spec:
              readiness:
                policy: DeriveFromCelQuery
                celQuery: status.availableReplicas >= 1
              forProvider:
                manifest:
                  apiVersion: apps/v1
                  kind: Deployment
                  spec:
                    strategy:
                      type: Recreate   # if mounting a single-replica RWO PVC
                    # ...

    - step: auto-ready
      functionRef: { name: function-auto-ready }
```

## Sources

- [Crossplane Compositions](https://docs.crossplane.io/latest/concepts/compositions/)
- [`crossplane render`](https://docs.crossplane.io/latest/cli/command-reference/#render) + [`crossplane beta validate`](https://docs.crossplane.io/latest/cli/command-reference/#beta-validate)
- [function-go-templating](https://github.com/crossplane-contrib/function-go-templating) + [function-environment-configs](https://github.com/crossplane-contrib/function-environment-configs)
- [provider-kubernetes `Object`](https://github.com/crossplane-contrib/provider-kubernetes) — v1alpha2 for `DeriveFromCelQuery`
- See `kube-prometheus-stack` (RWO+Recreate, SSA migration applied to a real workload), `alertmanager-config` (same pattern), `kuttl-testing` (end-to-end Claim→Ready testing), and the planned `siliconsaga-stack` (re-hydrate-to-test workflow).
