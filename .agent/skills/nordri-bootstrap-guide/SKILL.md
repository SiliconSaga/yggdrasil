---
name: nordri-bootstrap-guide
description: Use when bootstrapping Nordri (refr-k8s) on k3d or Rancher Desktop, integrating Mimir data services, troubleshooting ArgoCD sync issues, or running the full Nordri+Mimir stack end-to-end
---

# Nordri Bootstrap Guide

## Overview

Operational guide for the Nordri+Mimir integrated stack on k3d/k3s. Nordri provides base infrastructure (ArgoCD, Traefik, Crossplane, Garage S3) while Mimir adds data services (Kafka, Valkey, PostgreSQL, MySQL, MongoDB) via Crossplane Compositions.

## When to Use

- Setting up Nordri from scratch on k3d or Rancher Desktop
- Running Mimir data services on top of Nordri
- Debugging ArgoCD apps stuck in "Synced but not Ready"
- Understanding the bootstrap layer ordering
- Verifying the full stack end-to-end with kuttl tests

## Bootstrap Sequence

### 1. Create k3d Cluster

```bash
k3d cluster create refr-k8s \
  --port "8080:80@loadbalancer" --port "8443:443@loadbalancer" \
  --agents 2 --k3s-arg "--disable=traefik@server:*"
```

`--disable=traefik` is critical — Nordri installs its own Traefik via Helm.

### 2. Run Nordri Bootstrap

```bash
cd /path/to/refr-k8s
./bootstrap.sh homelab
```

bootstrap.sh executes these layers in order:

| Layer | Component | Purpose |
|-------|-----------|---------|
| 2 | Gitea | Internal Git source for ArgoCD |
| 2.5 | Gateway API CRDs + Crossplane Core | Foundation CRDs |
| 2.6 | Traefik (Helm) | Registers IngressRoute CRDs before ArgoCD |
| 2.7 | Crossplane Providers + Functions | Registers ProviderConfig CRDs, waits Healthy |
| 2.8 | ProviderConfigs + RBAC | Requires CRDs from Layer 2.7 |
| 3 | ArgoCD | Adopts all pre-installed Helm releases |
| 4 | Root Application | Triggers ArgoCD sync of app-of-apps |
| 5 | Garage init + Velero credentials | Layout, API key, bucket, K8s Secret (homelab only) |

Layers 2.6-2.8 exist to solve the CRD chicken-and-egg problem. See skill `argocd-bootstrap-on-k3d` for details.

### 3. Run Mimir Setup

```bash
cd /path/to/mimir
bash setup.sh --skip-crossplane
```

`--skip-crossplane` skips Crossplane core/providers/configs (Nordri owns those). Mimir installs: operators (Strimzi, redis-operator, Percona PG/PSMDB/PXC), XRDs, Compositions, operator RBAC.

### 4. Run kuttl Tests

```bash
cd /path/to/mimir
kubectl kuttl test --config kuttl-test.yaml
```

**MUST** use `--config kuttl-test.yaml` (not `kuttl test tests/e2e/`). The config sets `timeout: 600` and `parallel: 1`. Without it, tests use the 30s default and fail.

Expected timing (~662s total): Kafka 126s, Valkey 37s, PG 178s, MySQL 187s, MongoDB 133s.

## Storage Strategy

| Environment | Storage | Longhorn? |
|-------------|---------|-----------|
| k3d (Docker) | `local-path` (built-in) | No — Docker containers lack `iscsid` |
| Rancher Desktop | Longhorn | Yes — real VM, bootstrap auto-installs `open-iscsi` |
| Multi-node homelab | Longhorn or Rook-Ceph | Required for cross-node replication |
| GKE | GCE Persistent Disk (CSI) | Not needed |

For production/multi-node, `local-path` is insufficient — data doesn't survive node loss.

## Pinned Versions (2026-02-10)

| Component | Version |
|-----------|---------|
| Crossplane | 2.1.4 |
| provider-kubernetes | v1.2.0 |
| provider-helm | v1.0.0 |
| function-go-templating | v0.4.0 |
| function-auto-ready | v0.2.1 |
| Strimzi | chart 0.50.0 |
| redis-operator | chart 0.23.0 |
| pg-operator | chart 2.8.2 |
| psmdb-operator | chart 1.21.3 (image 1.21.2) |
| pxc-operator | chart 1.19.0 |
| Traefik | chart 38.0.1 |

## Operator Namespaces

| Namespace | Operators | Watch Config |
|-----------|-----------|-------------|
| `percona` | PG, PSMDB, PXC | `watchAllNamespaces=true` |
| `kafka` | Strimzi | `watchAnyNamespace=true` |
| `valkey` | redis-operator (OT-Container-Kit) | Default |

## Quick Reference

| Problem | Cause | Fix |
|---------|-------|-----|
| ArgoCD can't sync IngressRoute resources | Traefik CRDs missing | bootstrap.sh Layer 2.6 pre-installs Traefik |
| Claim Synced but never Ready, no pods | Operator not watching namespace | `watchAllNamespaces=true` (not `watchNamespace=""`) |
| kuttl tests fail at 30s | Missing `--config kuttl-test.yaml` | Always use `kubectl kuttl test --config kuttl-test.yaml` |
| Percona PG Init:ImagePullBackOff | `crVersion` mismatch with operator image | `crVersion` must match operator IMAGE tag, not chart version |
| MongoDB Init:ImagePullBackOff | `crVersion` doesn't match operator image | Use `crVersion: 1.21.2` with chart `1.21.3` |
| PG "postgres: command not found" | Using `percona-distribution-postgresql` image | Use `percona-postgresql-operator:2.7.0-ppg15-postgres` |
| Garage not initializing | Layout not assigned | bootstrap.sh Layer 5 handles this (homelab only) |
| Garage layout apply fails | replicationFactor > node count | Reduced to 1/1 for dev in values.yaml |
| Velero backup location unavailable | Missing credentials Secret | bootstrap.sh Layer 5 creates `velero-credentials` |
| `/garage` becomes `C:/Program Files/Git/garage` | Git Bash MSYS path mangling | `export MSYS_NO_PATHCONV=1` before kubectl exec |

## Common Mistakes

- **Running `kuttl test tests/e2e/` directly**: Ignores kuttl-test.yaml config. Always use `--config`.
- **Using `--set watchNamespace=""`**: Helm silently ignores empty strings. Use `watchAllNamespaces=true`.
- **Skipping `--skip-crossplane` with Mimir on Nordri**: Mimir tries to reinstall Crossplane, causing conflicts. Always pass `--skip-crossplane` when Nordri owns Crossplane.
- **Assuming Percona chart version = image version**: PSMDB chart 1.21.3 bundles image 1.21.2. The `crVersion` must match the IMAGE version.
- **Using Percona 2.8.x ppg15 images**: Percona dropped non-GIS ppg15 bundled images from 2.8.x onwards. Use 2.7.0-ppg15-postgres images (backwards compatible with 2.8.2 operator).
- **Running kubectl exec with `/path` in Git Bash**: MSYS2 converts `/garage` to a Windows path. Use `MSYS_NO_PATHCONV=1` or run from PowerShell instead.
