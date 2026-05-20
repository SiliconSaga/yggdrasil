# Heimdall Phase 2 Monitoring — Design

**Status:** Draft, ready for plan
**Date:** 2026-05-19
**Owner:** Rasmus Praestholm
**Related:** [Heimdall Architecture](../../components/heimdall/docs/architecture.md), [Forgejo Day-2 Design](2026-05-15-forgejo-day2-design.md) (consumes the monitoring gates this design produces), [Heimdall PR #3 — Prometheus storage bump](https://github.com/SiliconSaga/heimdall/pull/3) (the incident that motivated this arc)

## Overview

On 2026-05-15, both Prometheus pods on GKE crashlooped for 4d18h with `no space left on device` on the WAL — 1328 + 275 restarts each — before anyone noticed. The immediate fix landed (10Gi → 20Gi PVC bump, in-place expansion + claim sync via PR #3). The deeper lesson is that Heimdall has no alerting on its own health, and no out-of-cluster watcher to flag when the in-cluster watcher is itself the casualty.

This design covers the three follow-ups that close that gap as a single arc, scoped narrowly enough to land before the Forgejo day-2 cutover (whose Phase 5 validation gates depend on them):

1. **Self-health PrometheusRules** — PVC-fill, restart-storm, and TSDB-corruption alerts that would have caught the May-15 incident inside the Prometheus's normal alert flow.
2. **Retention tune-down to ~7d** — Loki/Tempo/Prometheus retention shrinks from 15d → 7d as a stopgap until the Phase 2 S3/Garage backend makes hot-storage size a non-issue.
3. **Uptime Kuma** — sibling under `components/heimdall/`, declaratively seeded from git, with each cluster's Kuma probing both itself and the other cluster's endpoints. Out-of-cluster watcher complements Prometheus's in-cluster view.

## Goals

1. **Catch the May-15 failure class before users notice it** — PrometheusRules fire on PVC fill rate, on Prometheus restart storms, on TSDB corruption.
2. **Buy headroom against the next storage surprise** — 7-day retention as a stopgap; no claim that this is the right long-term answer.
3. **Watcher independent from the watched** — Uptime Kuma in each cluster cross-probes the other, so a wedged Heimdall in one cluster doesn't blind the operator.
4. **All Kuma config in git, reproducible from scratch** — no UI-driven snowflake state. Seed-via-API on every install.
5. **Stay inside the Heimdall brand** — Kuma lives in the heimdall repo under the heimdall ArgoCD app, even though it's not part of the `HeimdallStack` Crossplane composition.

## Non-goals

- **AlertManager notification routing** (Slack/email/webhook). Alerts in v1 are visible only via Grafana's AlertManager UI panel — visible signal, not pager-grade. Separate arc.
- **Tailscale (or equivalent) link for GKE → homelab probing.** v1 ships homelab → GKE only (public endpoints, no plumbing); GKE → homelab follows once the network link decision is made.
- **S3/Garage object-store backend.** This design's retention tune-down is the stopgap *until* that arc lands; the backend itself is its own design.
- **Cross-cluster alert federation** (Thanos / Prometheus remote-write between clusters). Out of scope; each cluster's Prometheus stays standalone, Kuma provides the cross-view.
- **Kuma status-page hardening** (custom branding, public URL with auth). The bare default status page is sufficient for v1.

## Architecture

### Component layout (post-arc)

```text
components/heimdall/
  crossplane/                 # HeimdallStack composition (existing)
    xrd.yaml                  # + PrometheusRule pipeline step (§1)
    composition.yaml          # + retention parameter wired into Loki/Tempo (§2)
    claim.yaml                # retentionDays: 7 (§2)
  kuma/                       # NEW — sibling, not in composition
    helm-release.yaml         # Provider-Helm Release (Uptime Kuma chart)
    config/
      homelab-monitors.yaml   # what homelab Kuma probes
      gke-monitors.yaml       # what GKE Kuma probes
    seed-job.yaml             # post-install Job: reads ConfigMap, POSTs to Kuma API
    secret.yaml               # kuma-admin-credentials pattern
```

One Nidavellir ArgoCD Application (`heimdall-app.yaml`) keeps syncing the whole `components/heimdall/` directory; ArgoCD applies the Crossplane Claim and the sibling Kuma manifests in the same pass.

### Cross-watch shape

```text
       Homelab Cluster                          GKE Cluster
  ┌───────────────────────┐             ┌───────────────────────┐
  │  Heimdall (LGTM)      │             │  Heimdall (LGTM)      │
  │    ↓ scrapes          │             │    ↓ scrapes          │
  │  Local workloads      │             │  Local workloads      │
  │                       │             │                       │
  │  Uptime Kuma          │             │  Uptime Kuma          │
  │   ├─ probes self      │             │   ├─ probes self      │
  │   └─ probes GKE ───── HTTPS ──────► │   (publicly reachable │
  │      via cmdbee.org   │             │    *.cmdbee.org)      │
  │                       │             │                       │
  │  (probed by GKE Kuma  │             │   └─ probes homelab ──── (future:
  │   when Tailscale link │ ◄────────── │       Tailscale link  │   GKE → homelab)
  │   is in place)        │             │       — not in v1)    │
  └───────────────────────┘             └───────────────────────┘
```

Asymmetric by design: homelab endpoints aren't publicly reachable, so the GKE → homelab direction needs network plumbing (Tailscale subnet router, or equivalent). That decision is a separate arc; v1 ships the homelab → GKE direction, which works immediately.

## Component decisions

| Concern | Decision | Why |
|---|---|---|
| PrometheusRules surface | New composition step rendering a `PrometheusRule` CR (Provider-Kubernetes Object) | Keeps rules versioned in heimdall repo, not buried in Helm values; future rules add as siblings without touching kube-prometheus-stack values |
| Rule set scope (v1) | PVC fill (Prometheus, Loki, Tempo), Prometheus restart-storm, TSDB corruption | Covers the May-15 class; broader app/runtime alerting deferred |
| Retention default | `retentionDays: 7` (was 15) | Stopgap until S3 backend; matches typical homelab observability window |
| Retention scope | Single `retentionDays` parameter drives Loki + Tempo; Prometheus retention is its own Helm value, set to match | One knob in the claim; composition fans out to the three stacks |
| Kuma deployment | Provider-Helm Release of the community `uptime-kuma` chart (`oci://registry-1.docker.io/bitnamicharts/uptime-kuma` or `https://dirsigler.github.io/uptime-kuma-helm`) | Avoids reinventing a Deployment+Service+PVC; matches the Provider-Helm pattern already used for LGTM |
| Kuma placement in composition | **Outside** the `HeimdallStack` XR | Composition wedge ≠ Kuma wedge; Kuma's lifecycle (UI-driven config, single-replica) is unlike the LGTM stack; sibling Helm Release keeps them independent |
| Kuma config flow | Per-env `monitors.yaml` in git → ConfigMap → post-install Job → Kuma REST API | "Build/rebuild from scratch from pure config in git" requirement; no UI-driven snowflake state |
| Kuma API client | [`uptime-kuma-api`](https://github.com/lucasheld/uptime-kuma-api) Python library in the Job container | Kuma's native API is socket.io, not REST; this library is the de facto declarative client |
| Reconcile trigger | ConfigMap hash annotation on the Job pod template | ArgoCD re-applies Job when config changes → Job re-seeds; no operator, no controller |
| Kuma admin creds | Plain k8s Secret (`kuma-admin-credentials`), generated at first install if absent | Same pattern as `gitea-admin-credentials`/`forgejo-admin-credentials`; OpenBAO can sync into it later |
| Kuma storage | Small PVC for SQLite (cluster default StorageClass) | State continuity across restarts; config recoverable from git regardless |
| Kuma ingress | Per-route Certificate via cert-manager (`kuma.cmdbee.org` on GKE, `kuma.localhost` on homelab) | Matches existing patterns; wildcard cert will fold in when that arc lands |
| Cross-watch v1 scope | Homelab Kuma probes GKE public endpoints; GKE Kuma probes itself only | No new network plumbing; GKE → homelab direction lands in a follow-up arc |

## Phase plan

| Phase | Scope |
|---|---|
| 0 | This design doc |
| 1 | PrometheusRules composition step + retention tune-down — single small heimdall PR; validates against current GKE deployment |
| 2 | Uptime Kuma sibling — Helm Release, Secret, PVC, ingress, admin creds bootstrap; deploy without monitor config |
| 3 | Kuma seed Job — `uptime-kuma-api`-based, ConfigMap-driven, idempotent; verify monitors appear after install on a fresh cluster |
| 4 | Per-env monitor configs in git — homelab and GKE `monitors.yaml`; homelab → GKE cross-probe is live |
| 5 | Validation gates green: PrometheusRules visible in Prometheus `/rules`, simulated PVC-fill fires the alert, Kuma status page shows expected probes, fresh-cluster rebuild reproduces the same Kuma state |

GKE → homelab cross-probe direction is **deferred** to a follow-up arc that picks the network-link mechanism (Tailscale subnet router, ZeroTier, WireGuard-on-Crossplane, ngrok tunnel, etc.).

## Validation gates

Acceptance criteria for closing the arc:

- **PrometheusRules:**
  - `kubectl get prometheusrule -n heimdall heimdall-self-health` exists
  - Each rule shows up under Prometheus's `/rules` endpoint with `state: inactive` (none firing in a healthy cluster)
  - Simulated PVC fill (e.g., `dd if=/dev/zero of=/prometheus/test.bin bs=1M count=18000` in a Prometheus pod) flips `PrometheusPVCFillingUp` to `firing` within the rule's `for:` window
- **Retention:**
  - Loki config in the running pod shows `limits_config.retention_period: 168h`
  - Tempo config shows matching retention
  - Prometheus pod's `--storage.tsdb.retention.time=7d` flag confirmed
  - No regression in dashboard queries that look back ≤7d
- **Uptime Kuma:**
  - `kuma.cmdbee.org` reachable from outside the cluster (GKE) and `kuma.localhost` from homelab
  - Login with the bootstrapped admin credentials works
  - Monitor list matches the git config exactly — same names, types, intervals, URLs
  - On a from-scratch cluster (k3d destroy + recreate), Kuma comes up with identical monitor config without manual intervention
- **Cross-watch:**
  - Homelab Kuma status page shows GKE endpoints (`grafana.cmdbee.org`, `prometheus.cmdbee.org`, `argocd.cmdbee.org`, etc.) as green when GKE is healthy
  - Stopping a GKE service flips the corresponding monitor red within the configured interval

## Open questions

These are not blockers for the design — they get resolved during plan/implementation.

1. **Helm chart choice for Kuma.** Two viable charts: `dirsigler/uptime-kuma` (long-running community chart) vs `bitnamicharts/uptime-kuma` (newer Bitnami inclusion). Decide in plan doc based on freshness, security-patch cadence, and configurability of the values surface.
2. **Seed Job retry semantics.** If Kuma's API isn't ready when the Job runs, does it retry-with-backoff inside the Job, or rely on Job `backoffLimit` + ArgoCD retry? Lean: inside-Job retry with a 5-minute ceiling.
3. **One Kuma per env or shared with env-flavored config?** Each cluster gets its own Kuma instance; the per-env config is which `monitors.yaml` gets baked into its ConfigMap. The Composition (Phase 1) reads `environment` from `cluster-identity` and selects the right monitor config — already a precedent in the existing composition.
4. **Should the seed Job clean up monitors removed from git?** Yes for the "rebuild from scratch" goal, but it means a buggy commit can delete prod monitors. Mitigation: dry-run / diff mode toggle on the Job, default to apply-only-additions on first version, opt into deletion-on-removal once trust is built.
5. **PrometheusRule wave assignment.** The rule needs Prometheus operator CRDs available (kube-prometheus-stack already provides them as part of its install). Confirm the pipeline ordering puts the PrometheusRule step after the kube-prometheus-stack Release reports Ready.
6. **What does `kuma-admin-credentials` look like before first login?** Kuma's first-run flow prompts the human to set the admin via the UI. Workaround: the seed Job's first action is to POST to `/api/setup` with credentials from the Secret if the install is fresh. The `uptime-kuma-api` library covers this.

## Future work

- **GKE → homelab cross-probe direction.** Pick a network-link mechanism (Tailscale subnet router is the leading candidate — already present elsewhere in the Cervator workspace), deploy a sidecar or operator, point GKE Kuma's monitor config at homelab endpoints. Separate arc.
- **AlertManager notification routing.** Slack webhook, email, or PagerDuty-equivalent. Required before alerts in v1 become pager-grade. Separate arc.
- **S3/Garage backend for Loki/Tempo.** The proper answer to "we keep running out of disk." This design's retention tune-down is the explicit stopgap; once that backend lands, retention can rise back to 30+ days.
- **Kuma status page on a public URL.** With basic auth or a per-route Certificate, the cross-env status pages could be linked from a top-level "is anything down?" landing page — useful both for self-monitoring and for the SiliconSaga community visibility story.
- **Additional self-health rules as patterns emerge.** Loki ingester memory pressure, Tempo block-flush failures, AlertManager-Prometheus disconnects, kube-state-metrics scrape failures.
- **OpenBAO sync for `kuma-admin-credentials`.** Same pattern as `forgejo-admin-credentials` — when OpenBAO lands, the Secret name stays the same and ESO syncs from upstream.
