# Forgejo Day-2 — Design

**Status:** Draft, ready for plan
**Date:** 2026-05-15
**Owner:** Rasmus Praestholm
**Related:** [Workspace Restructure (TODO: Gitea vs GitHub Day-2)](2026-03-06-workspace-restructure.md), [Platform Gitea Notes](../../components/nidavellir/docs/platform-gitea.md), [Mimir Data Resiliency Plan](../../components/mimir/docs/plans/data-resiliency-plan.md), [Nordri Bootstrap](../../components/nordri/docs/bootstrap.md)

## Overview

Today's bootstrap installs a **Seed Gitea** (Layer 2 in `nordri/bootstrap.sh`) that is intentionally ephemeral — `persistence.enabled=false`, bundled Postgres sub-chart, no backups. Its only job is to break the GitOps chicken-and-egg: ArgoCD needs a repo to install itself. Once the platform is stable, Seed Gitea is meant to die.

This design replaces the long-pending "Platform Gitea" target state from `nidavellir/docs/platform-gitea.md` with a cleaner approach: stand up a **completely independent Forgejo instance** as a first-class Nidavellir app, leave Seed Gitea untouched until cutover, then decommission it. No PV migration, no naming collision between two Gitea instances, and a clean opportunity to adopt Forgejo (the community fork of Gitea) instead of perpetuating the Gitea brand.

GitHub becomes a public *convenience* mirror, not a critical link in the chain. Forgejo's native pull-mirror feature pulls from public GitHub repos on a schedule (no PAT needed since SiliconSaga repos are public), and an on-demand sync trigger (`ws forgejo-sync`) covers the "fetch latest now" need.

## Goals

1. **Eliminate the May-2 failure mode** — ArgoCD no longer depends on an ephemeral Git source. The Seed-Gitea-as-source-of-truth model is replaced with a durable, PVC-backed Forgejo instance.
2. **Clean break, no migration** — Seed Gitea stays exactly as it is until the cutover ceremony, then is uninstalled. There is never a window where two Git instances both pretend to be the source of truth.
3. **GitHub stays for convenience** — public mirror that humans push to and Forgejo pulls from, never the platform's load-bearing dependency. Air-gap viability is preserved.
4. **No new prerequisites on the critical path** — OpenBAO is *not* required for v1; standard k8s Secret pattern suffices for Forgejo admin creds and any later mirror Secrets. OpenBAO can be adopted later as a sync-target for the same Secret without touching Forgejo's chart values.
5. **Rename the brand once** — drop the `nordri-admin/<repo>` namespace and `gitea-*` plumbing in favor of `siliconsaga/<repo>` and `forgejo-*` while we're already touching every URL for the cutover.
6. **Fold the parked `gitea-github-sync` arc** — the new design subsumes it as Phase 4 (Forgejo's native pull-mirror).

## Non-goals

The following are explicitly out of scope for this day-2 cutover:

- **OpenBAO standup.** Deferred to a separate arc. Forgejo admin password lives in a plain k8s Secret on day-2; ESO/OpenBAO can sync into the same Secret name later without Forgejo needing reconfiguration.
- **Vegvísir wildcard cert.** Forgejo gets a per-route cert at first (the same workaround `ting/k8s/overlays/frontstate/certificate-patch.yaml` uses today). Wildcard cert is its own arc.
- **Bidirectional sync.** Forgejo → GitHub is explicitly not configured. Cluster-internal Git writes flow back through the human's local GDD workspace and standard `git push` to GitHub; Forgejo is a downstream mirror only.
- **Tier-3 repos in Forgejo.** Cutover scope is the *minimum* set ArgoCD currently consumes (`nordri`, `nidavellir`, `mimir`, `heimdall`). Nidavellir's app-of-apps pulls in others as configured — that becomes the workflow for adding new repos to the in-cluster mirror set going forward, not a one-time decision baked into this design.
- **Seed Gitea preservation.** After ~2 weeks of green monitoring, Seed Gitea Helm release is uninstalled. No backup mirror, no zombie-mode fallback — GitHub is the better recovery source than a stale Seed.
- **Conflict-resolution tooling for divergent Forgejo writes.** Rare scenario; agent-driven manual resolution is acceptable per existing operating principle.

## Architecture

### Target state (post-cutover)

```text
                      ┌────────────────────┐
                      │    GitHub (public)  │
                      └──────────┬─────────┘
                                 │ scheduled pull-mirror
                                 │ (Forgejo native, anon, ~1h interval)
                                 ▼
   ┌──────────────────────────────────────────────────┐
   │  Cluster (homelab or GKE)                        │
   │                                                   │
   │  ┌────────────────────┐   ArgoCD Applications    │
   │  │  Forgejo           │◄──── repoURL: forgejo... │
   │  │  - PVC for repos   │                          │
   │  │  - Postgres claim  │                          │
   │  │    (Mimir-vended)  │                          │
   │  │  - HTTPRoute + cert│                          │
   │  └────────────────────┘                          │
   │                                                   │
   │  ┌────────────────────┐                          │
   │  │  Seed Gitea         │  ❌ uninstalled after    │
   │  │  (was here)         │     ~2-week soak        │
   │  └────────────────────┘                          │
   └──────────────────────────────────────────────────┘
```

### Sync direction (unidirectional)

```text
human local GDD workspace
  │
  │ git push (normal)
  ▼
GitHub (public)
  │
  │ scheduled pull-mirror (Forgejo native, ~1h)
  │ + on-demand: ws forgejo-sync <component>
  ▼
Forgejo (in-cluster)
  │
  │ ArgoCD pull (every ~3min default)
  ▼
Cluster apps reconcile
```

Cluster-internal Git writes (rare — primarily future agent-driven cluster-side commits) flow back through the human's local checkout: `<cluster Git stuff>` → human GDD workspace → GitHub → next overnight mirror cycle. Forgejo never writes upstream.

## Component decisions

| Concern | Decision | Why |
|---|---|---|
| Git platform | **Forgejo** (community fork of Gitea) | Long-pending desire; no operational difference (API/data-model compatible); fresh deploy avoids "two Giteas" naming confusion |
| Helm chart | Native Forgejo OCI chart at `oci://code.forgejo.org/forgejo/forgejo` | First-class support for Forgejo-specific values (federation, Forgejo Actions) without fighting upstream Gitea defaults |
| Postgres | Mimir-vended via Crossplane `PostgresCluster` claim | Aligns with Mimir's purpose; exercises the claim path end-to-end |
| Repo storage | PVC (cluster default StorageClass: `standard-rwo` on GKE, Longhorn on homelab, local-path on Rancher Desktop) | Matches the Mimir data-services convention (no hardcoded storage class) |
| Admin creds | Plain k8s Secret (`forgejo-admin-credentials`), generated at first install if absent | Same pattern as today's `gitea-admin-credentials`; OpenBAO can sync into it later |
| TLS | Per-route Certificate via cert-manager (workaround) | Matches the `ting/frontstate` pattern; wildcard cert is a separate arc |
| Subdomain | `forgejo.cmdbee.org` (GKE), `forgejo.localhost` or homelab equivalent | Consistent with existing `gitea.cmdbee.org` naming |
| Repo namespace | `siliconsaga/<repo>` (was `nordri-admin/<repo>`) | We're touching every URL anyway during cutover; rename is one-cost-not-two |
| Mirror auth | None (anonymous pull from public GitHub) | All SiliconSaga repos are public; PAT only enters when private repos appear |
| Mirror cadence | ~1h Forgejo native pull-mirror + on-demand `ws forgejo-sync <component>` | Native feature, no CronJob needed; on-demand handled via Forgejo's `mirror-sync` API |
| Sync wave (Nidavellir) | After Mimir operators (postgres claim must resolve), before any app that depends on Forgejo | Concrete wave assignment in plan doc |

## Cutover ceremony (Phase 3 detail)

The single high-stakes step. Variant A from earlier discussion, refined.

**Pre-condition:** Forgejo is up, healthy, has all four repos (`nordri`, `nidavellir`, `mimir`, `heimdall`) populated under `siliconsaga/<repo>` via initial seed mirror.

1. **Push the desired final state to Forgejo first.** This includes the manifest changes that point ArgoCD `repoURL`s at Forgejo. Forgejo now holds what ArgoCD will look for *after* the swap, but ArgoCD is not yet looking there.
2. **Push the swap commit to Seed Gitea last.** This single commit updates the ArgoCD Application manifests (in `nordri` repo's `platform/argocd/`) to change `repoURL` from `http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/<repo>.git` to `http://forgejo-http.forgejo.svc.cluster.local:3000/siliconsaga/<repo>.git`.
3. **ArgoCD reads the swap from Seed Gitea**, re-registers each Application against Forgejo, fetches from Forgejo, finds the desired state present, sync continues.
4. **Verify** all Applications report `Synced` + `Healthy` against Forgejo `repoURL`s.

After the ceremony, Seed Gitea is no longer referenced. It runs idle until the soak period passes and Phase 6 uninstalls it.

The ceremony is reversible at any point before step 2 by simply not pushing the swap commit. After step 2, reversing requires pushing a counter-commit to Seed Gitea (which is still running and writable).

## Validation gates (Phase 5, depends on task #3 monitoring buildout)

Before Phase 6 (Seed uninstall), the following must be green for the soak duration:

- **Uptime Kuma probe** of `forgejo.cmdbee.org/api/healthz` (and homelab equivalent if applicable) reporting >99% over 14 days.
- **ArgoCD app-sync-health alert** silent — no Application has been `OutOfSync` or `Degraded` for >5 minutes.
- **Mirror-job-health** — Forgejo's mirror-sync API for each of the four repos returns success on its scheduled cadence.
- **Postgres claim health** — Mimir's `PostgresCluster` for Forgejo reports `Ready`.
- **PVC capacity** — Forgejo repo PVC at <50% utilization (i.e., `du` of the repos is well within claim size).

These checks are concrete deliverables for task #3 and become part of the standing dashboard.

## Roadmap

Detail moves to the plan doc (`2026-05-15-forgejo-day2-plan.md`). Phase summary:

| Phase | Scope |
|---|---|
| 0 | This design doc |
| 1 | Forgejo as new Nidavellir app — Postgres claim, PVC, admin creds Secret, HTTPRoute + per-route cert |
| 2 | Initial GitHub → Forgejo seed mirror (one-time, scripted, four repos) |
| 3 | Cutover ceremony (Variant A above) |
| 4 | Forgejo native pull-mirror + `ws forgejo-sync` on-demand wrapper |
| 5 | Validation gates wired into monitoring (depends on task #3) |
| 6 | Soak period (~2 weeks), then Seed Gitea uninstall |

## Open questions

These are not blockers for the design — they get resolved during plan/implementation.

1. **Sync wave numbers.** Concrete wave assignments for Postgres-claim → Forgejo deploy → mirror-config-job. Settled in plan doc against Vegvísir's existing wave layout.
2. **Forgejo admin credential rotation flow.** Today Seed Gitea has a documented rotation flow (`bootstrap.md` § Rotating). Forgejo gets the same shape; document during Phase 1.
3. **Mirror-config bootstrap.** First-time Forgejo install: how do the four repos get their mirror configuration? Options: (a) Forgejo API call from a one-shot Job in the Helm chart values, (b) a hook in the cutover script, (c) manual UI step. Lean toward (a) for repeatability.
4. **What replaces `update-embedded-git.sh`?** The current script's purpose (push local checkouts into Seed Gitea) goes away — the new model is "push to GitHub, Forgejo mirrors." The script can be deleted or repurposed as `ws forgejo-sync` (on-demand mirror trigger). Decision in plan doc.
5. **`ecosystem.yaml` `gitea.internalUrl` field.** Becomes `forgejo.internalUrl`. Whether to keep `gitea.*` as a deprecation alias or hard-cut depends on how many call sites read it. Likely hard-cut since both will move at once.
6. **Existing Seed Gitea data.** Anything written to Seed Gitea that was never pushed back to GitHub is at risk. As of writing, the only writes to Seed Gitea come from `bootstrap.sh` and `update-embedded-git.sh` — both push local-checkout content, so GitHub is the durable source. Confirm before cutover that no human or agent has been writing directly into Seed Gitea.

## Future work

- **OpenBAO adoption** — sync the `forgejo-admin-credentials` Secret from OpenBAO via External Secrets Operator. No Forgejo-side changes needed.
- **Vegvísir wildcard cert** — replace per-route cert with `*.cmdbee.org` wildcard from cert-manager DNS-01 solver (NameCheap webhook). Tracked separately.
- **Forgejo Actions** — Forgejo includes a CI runner subsystem; not in scope for day-2 but a natural future capability for in-cluster CI without leaving the platform.
- **Federation.** Forgejo supports ActivityPub-style federation. Out of scope; mentioned only because it's the kind of capability that makes the Forgejo-not-Gitea decision pay rent later.
- **Bidirectional GitHub ⇄ Forgejo sync.** If a future workflow needs Forgejo → GitHub (e.g., agent makes a fix in-cluster and we want it surfaced on GitHub immediately rather than waiting for a human round-trip), revisit. Today's read: not needed.
- **Tier-3 repo additions.** As individual Tier-3 repos become GitOps-managed via Nidavellir's app-of-apps, they'd be added to Forgejo's mirror list. No design change required — just add the mirror config.
