---
name: argocd-gitops
description: Use when writing or debugging vanilla open-source ArgoCD — bootstrapping with the CRD chicken-and-egg problem (sync waves + `SkipDryRunOnMissingResource=true` + `ServerSideApply=true`), app-of-apps patterns and their parent-prune footgun, applying changes to `selfHeal: true` Applications (test through Git, NOT `kubectl apply`/edit), patching Helm chart values via Kustomize `helmCharts`, `ServerSideApply` for >262KB CRDs (and why `Replace=true` is the wrong escape hatch), stale-operation recovery, and hard-refreshing a Git-cache miss. NOT Grafana-managed alerting or Argo Rollouts.
---

# argocd-gitops

## Overview

ArgoCD's mental model is "Git is the source of truth, the controller reconciles the cluster to match." Almost every operational pain comes from **fighting that model** — editing the live cluster while `selfHeal: true` is on, packing too-large CRDs through client-side apply, racing sync waves against asynchronous readiness (provider CRDs), or pruning a parent Application's directory without realizing it cascades. The skill is mostly: how the model expects you to act, and where the model bites you.

## When to Use

- Bootstrapping a fresh ArgoCD on k3d/k3s/cloud K8s.
- Application stuck `OutOfSync` / `Degraded` / `Progressing` longer than expected.
- Applying a config change to a `selfHeal: true` Application.
- Apps whose CRDs come from sibling Apps in the same app-of-apps (CRD chicken-and-egg).
- Operator CRDs failing to apply with `metadata.annotations: Too long`.
- ArgoCD shows `Synced` but the live cluster doesn't reflect your last Git push.

NOT for Grafana-managed alerting (`alerting-irm` in grafana/skills), Argo Rollouts (separate project), or per-Crossplane gotchas (see `crossplane-compositions`).

## Quick Reference

| Goal | Pattern | Gotcha |
|------|---------|--------|
| Change a live Application's config | Edit Git → push → `argocd app sync <name>` (or wait for poll) | **NEVER** `kubectl apply`/edit on live resources of a `selfHeal: true` Application — the controller reverts within minutes. |
| App references a CRD that a sibling App installs | `syncOptions: [ServerSideApply=true, SkipDryRunOnMissingResource=true]` + `retry.backoff` + sync waves | Sync waves order *sync start*, not "wait until Healthy." Retry is the actual safety net. |
| CRDs exceed 262 KB annotation limit | `syncOptions: [ServerSideApply=true]` | `Replace=true` is the WRONG escape hatch — it bypasses SSA field ownership and breaks everything downstream that relies on it. |
| Patch a Helm chart value that isn't in `values.yaml` | Kustomize `helmCharts` + JSON6902 `patches:`; ArgoCD needs `kustomize.buildOptions: --enable-helm` in `argocd-cm` | Helm-native overrides survive chart upgrades; structural patches break when the manifest tree shifts — prefer values if exposed. |
| Force ArgoCD to re-read Git (webhook missed) | `kubectl annotate application <name> argocd.argoproj.io/refresh=hard --overwrite` | Plain `refresh` recomputes diff against cached manifests; `hard-refresh` re-clones. For "webhook missed" → `hard`. |
| Per-resource sync option override | `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` annotation on the resource manifest | Fine-grained when only some resources in an App need a tweak. |

## "Test Through Git" — the One Rule

**With `selfHeal: true`, editing the live cluster does NOT change the cluster.** It changes it for ~3 minutes, then the controller reconciles back to Git. Examples that bite:

- `kubectl scale deployment/traefik --replicas=3` → 3min later you're back at 2 (often during the exact incident you scaled for).
- `kubectl edit` on an `Application`'s spec → controller overwrites from Git source on next poll.
- "Edit Live Manifest" in the ArgoCD UI → same fate.

**Right way (always):** change Git → push → optionally `argocd app sync` to skip the wait. If you genuinely need an imperative override during an incident:

```bash
# Disable selfHeal, scale, commit Git, re-enable selfHeal.
kubectl -n argocd patch application <app> --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false,"prune":true}}}}'
kubectl -n <ns> scale deployment/<name> --replicas=N
# ... commit + push the change to Git ...
kubectl -n argocd patch application <app> --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}'
```

Commit the Git change **within the incident window** or your next post-mortem will surface the drift.

(For Crossplane Compositions specifically — `kubectl apply` over a GitOps-managed Composition triggers a flapping war. See `crossplane-compositions` → "Test Through GitOps".)

## CRD Chicken-and-Egg (Bootstrap)

App B uses an `IngressRoute`; App A (Traefik) installs the CRD. They're in the same app-of-apps. App B's plan-time dry-run fails because the CRD doesn't exist yet on the API server.

**Three-part fix** (use all three on consumer Apps):

```yaml
syncPolicy:
  syncOptions:
    - ServerSideApply=true              # SSA tolerates unknown fields better than client-side
    - SkipDryRunOnMissingResource=true  # the actual fix — skip dry-run for unknown kinds
    - CreateNamespace=true
  retry:
    limit: 10
    backoff: { duration: 10s, factor: 2, maxDuration: 5m }
```

Plus **sync waves** to start the CRD-provider Apps first:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-5"   # Traefik, Crossplane core, Percona operator CRDs
    # later waves: 0 (Crossplane Providers), 5 (ProviderConfigs), 10 (workload consumers)
```

**Caveats:**
- Sync waves order *sync starts*, not "wait until Healthy." For "wait until Provider is Healthy then apply ProviderConfig" use a `PreSync` Hook + a Job that polls `kubectl wait --for=condition=Healthy`. The simpler pattern is to let retry-with-backoff converge.
- `ApplyOutOfSyncOnly=true` is fine for steady-state but can mask first-sync ordering bugs. Leave it off during initial bootstrap.

## ServerSideApply for Large CRDs

Operator CRDs (Percona, Strimzi, valkey-operator, etc.) often exceed the 262144-byte annotation limit:

```text
metadata.annotations: Too long: must have at most 262144 bytes
```

`kubectl apply` packs the full manifest into `metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]`. SSA stores field ownership in `metadata.managedFields` (no annotation-size limit). Set `ServerSideApply=true` on every Application that installs operator CRDs.

**Why `Replace=true` is the wrong fix:** it bypasses SSA's field ownership entirely. It works *once*, but every subsequent reconcile (yours OR anyone else's that touches the resource) breaks field ownership, and Kustomize/Helm-rendered patches will fight provider-kubernetes or other controllers. Always prefer `ServerSideApply=true` over `Replace=true`.

## Patching Helm Chart Values That Aren't Exposed

When a chart hardcodes a value (e.g. Percona PG operator's `runAsNonRoot: true` which breaks Rancher Desktop / strict PSA), use Kustomize `helmCharts` to render the chart and JSON6902 to patch the rendered manifest:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <ns>
helmCharts:
  - name: pg-operator
    repo: https://percona.github.io/percona-helm-charts/
    version: 2.4.1
    releaseName: percona-pg
    namespace: <ns>
    includeCRDs: true              # REQUIRED — Kustomize skips Helm CRDs by default
    valuesInline:
      watchAllNamespaces: true
patches:
  - target: { kind: Deployment, name: percona-pg-operator }
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/securityContext/runAsNonRoot
        value: false
```

Then in `argocd-cm`:

```yaml
data:
  kustomize.buildOptions: "--enable-helm"
```

The ArgoCD Application points at the directory containing `kustomization.yaml` (Kustomize source, not Helm).

## App-of-Apps Footguns

- **Parent prune cascades.** A parent Application with `prune: true` and a `path:` directory of child Application manifests: **deleting a child's manifest from Git → next sync prunes the child Application → child's `resources-finalizer` cascades to all live resources it owned**. A "small cleanup PR" can take out a production workload. Mitigate: use `prune: false` on the parent OR move children to explicit `resources` lists OR add `argocd.argoproj.io/sync-options: Prune=false` annotations on individual child resources.
- **Recursive directory mode.** `source.directory: { recurse: true }` is convenient but means *any* YAML in the tree becomes managed. Stray `*.yaml` notes or backup files become Applications.
- **Resource hook ordering** (`PreSync`, `Sync`, `PostSync`, `SyncFail`) runs within each Application's sync — they don't cross Application boundaries. Use sync waves for cross-Application ordering.

## Recovery Cookbook

### Stuck sync (`operationState.phase: Running` for ages)

```bash
# Preferred — clean terminate via CLI.
argocd app terminate-op <app>

# Without the CLI:
kubectl -n argocd patch application <app> --type merge -p '{"operation": null}'

# Last resort — controller is wedged; patch the status subresource:
kubectl -n argocd patch application <app> --type merge --subresource=status \
  -p '{"status":{"operationState":{"phase":"Failed","message":"manually cleared"}}}'

# Then re-sync
argocd app sync <app> --prune
```

Never `kubectl delete application` to "reset" — the `resources-finalizer` cascades to your live workloads.

### Webhook missed / cache stale

```bash
kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite
argocd app sync <app>          # if it's OutOfSync after refresh
```

If the entire repo cache is suspect (e.g. someone force-pushed `main`):

```bash
kubectl -n argocd rollout restart deployment/argocd-repo-server
```

## Common Mistakes

- **`kubectl edit` / `kubectl apply` over a `selfHeal: true` Application's resources** → reverts within minutes. Change Git instead.
- **`kubectl delete application` to "start over"** → `resources-finalizer` cascades, deletes live workloads.
- **Removing a child Application's YAML from a parent's directory while `prune: true`** → child + all its live resources deleted on next sync.
- **`Replace=true` to bypass the 262KB annotation limit** → wrong fix; breaks SSA field ownership. Use `ServerSideApply=true`.
- **Forgetting `includeCRDs: true`** in Kustomize `helmCharts` → operator pods crash looking for their own CRDs.
- **Forgetting `kustomize.buildOptions: --enable-helm`** in `argocd-cm` → Kustomize-with-Helm sources silently render without the chart.
- **Treating sync waves as readiness gates** → waves order sync *starts*, not "wait until Healthy." Use retry + backoff, or `PreSync` Hooks polling `kubectl wait`.

## Portable Shell Scripts (Bootstrap-Adjacent)

```bash
# Anchor every path to the script's own dir, regardless of cwd or sourcing.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Portable in-place sed (works on GNU + BSD). Or just use yq for YAML.
sed -i.bak 's/old/new/g' file && rm -f file.bak
# Or:
yq -i '.replicas = 3' values.yaml
```

`BASH_SOURCE[0]` over `$0` matters: when sourced, `$0` is the shell name.

## Sources

- [ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/)
- [Sync options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/) — `ServerSideApply`, `SkipDryRunOnMissingResource`, etc.
- [Sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Resource hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/) — `PreSync`/`PostSync`/`SyncFail`
- See `crossplane-compositions` (test-through-GitOps applied to Crossplane), `kube-prometheus-stack` (large CRD pattern in practice), `kuttl-testing` (end-to-end Application convergence testing), and the planned `siliconsaga-stack` for the in-cluster seed-Gitea + re-hydrate workflow specific to this realm.
