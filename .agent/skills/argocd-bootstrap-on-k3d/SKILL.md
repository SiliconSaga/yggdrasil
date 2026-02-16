---
name: argocd-bootstrap-on-k3d
description: Use when bootstrapping ArgoCD app-of-apps on k3d/k3s, debugging CRD chicken-and-egg issues where ArgoCD fails to sync because sibling Applications provide missing CRDs, or writing portable shell scripts for macOS and Linux
---

# ArgoCD Bootstrap on k3d

## Overview

Patterns for bootstrapping an ArgoCD app-of-apps pattern on k3d/k3s, where ArgoCD manages components whose CRDs are installed by other components in the same sync. Covers the CRD chicken-and-egg problem, Helm release adoption, and portable scripting.

## When to Use

- ArgoCD sync fails with "could not find CRD" for IngressRoute, ProviderConfig, etc.
- Bootstrapping a fresh cluster where ArgoCD must manage CRD-providing charts
- Writing shell scripts that need to work on macOS and Linux
- ArgoCD stuck in retry loops with stale operationState

## Critical: CRD Chicken-and-Egg

**Problem**: ArgoCD validates that API resource types exist before creating sync tasks. If Application A installs Traefik (providing IngressRoute CRDs) and Application B uses IngressRoute resources, B fails validation even if A would install first via sync-waves.

`SkipDryRunOnMissingResource=true` only skips the dry-run phase, NOT the API validation. Sync-waves within a single Application do NOT wait for CRDs from sibling resources.

**Solution**: Pre-install CRD-providing components via Helm before ArgoCD starts:

```bash
# 1. Install Traefik (provides IngressRoute CRDs)
helm upgrade --install traefik traefik/traefik --namespace kube-system --version 38.0.1

# 2. Install Crossplane providers (provides ProviderConfig CRDs)
kubectl apply -f crossplane-providers.yaml
kubectl wait --for=condition=Healthy providers.pkg.crossplane.io --all --timeout=180s

# 3. Apply ProviderConfigs (CRDs now exist)
kubectl apply -f crossplane-configs.yaml

# 4. THEN install ArgoCD and apply root app
# ArgoCD adopts the Helm releases (same name+namespace) on first sync
```

ArgoCD adopts pre-existing Helm releases when the Application spec matches the release name and namespace. No conflict.

## Stale ArgoCD Operations

When ArgoCD is stuck retrying a failed sync:

```bash
# Check current state
kubectl get application layer4-fundamentals -n argocd \
  -o jsonpath='{.status.operationState.phase}'

# Force-terminate the stale operation
kubectl patch application layer4-fundamentals -n argocd \
  --type json -p='[{"op":"replace","path":"/status/operationState/phase","value":"Failed"}]'

# Auto-sync will start a fresh operation
```

Note: `selfHeal: true` can overwrite manual patches to the Application spec if the source (e.g., Gitea) doesn't have the same values. Always update the source of truth.

## Hydration Pattern

Nordri uses an internal Gitea as the Git source for ArgoCD:

1. bootstrap.sh installs Gitea in-cluster
2. Copies `platform/` files to a temp directory
3. Patches the app-of-apps path for the target overlay (homelab/gke)
4. Pushes to Gitea via port-forward
5. ArgoCD watches Gitea's internal URL

This keeps the Git source self-contained in the cluster.

## Portable Shell Scripts

### `sed -i` macOS vs Linux

```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|old|new|g" file.yaml
else
    sed -i "s|old|new|g" file.yaml
fi
```

### CWD-independent scripts

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Use $SCRIPT_DIR/path/to/file instead of relative paths
kubectl apply -f "$SCRIPT_DIR/manifests/providers.yaml"
```

## Quick Reference

| Problem | Cause | Fix |
|---------|-------|-----|
| "could not find IngressRoute CRD" | Traefik not installed yet | Pre-install Traefik via Helm before ArgoCD |
| "could not find ProviderConfig CRD" | Crossplane providers not healthy | Pre-install providers, wait Healthy |
| Sync stuck in retry loop | Stale operationState from earlier failure | Patch phase to "Failed", let auto-sync restart |
| `sed: invalid command code` on macOS | GNU vs BSD sed | Use OSTYPE check for portable `sed -i` |
| "file not found" when run from other dir | Relative paths in scripts | Use `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` |
| `/path` becomes `C:/Program Files/Git/path` | Git Bash MSYS path mangling | `export MSYS_NO_PATHCONV=1` before kubectl exec |
| selfHeal overwrites manual patches | Source of truth in Gitea differs | Update source via `update.sh`, not manual patches |

## Common Mistakes

- **Assuming `SkipDryRunOnMissingResource` handles everything**: It only skips dry-run, not API resource type validation. Pre-install CRD providers.
- **Not waiting for providers before applying configs**: `kubectl apply -f provider-configs.yaml` fails if the ProviderConfig CRD doesn't exist yet. Always `kubectl wait --for=condition=Healthy` first.
- **Manually patching ArgoCD Applications**: If selfHeal is enabled, ArgoCD will overwrite your patch on the next reconciliation. Update the Git source instead.
- **Using relative paths in bootstrap scripts**: Scripts may be called from any directory. Always resolve paths relative to SCRIPT_DIR.
