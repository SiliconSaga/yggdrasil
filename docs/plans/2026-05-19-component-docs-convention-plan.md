# Component Docs Convention — Implementation Plan (SP-C)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the SP-C "Component documentation convention" (the four shapes + Shape 2 detail) into the `writing-yggdrasil-docs` workspace skill as the permanent home, then apply Shape 2 to `nidavellir` as the worked example — split `docs/wildcard-tls.md` into three focused topic files, distribute the misfiled `CLAUDE.md` content, add a `docs/README.md` index, polish the root `README.md`.

**Architecture:** Markdown only. Two-repo work: one commit on the existing `docs/component-docs-convention` branch in yggdrasil (skill update); four commits on a new branch in the nidavellir repo (the cleanup). No automation, no tests beyond `ws test yggdrasil` for the skill change (markdown edits don't affect the bats suite).

**Tech Stack:** Markdown. Workspace conventions: `ws commit` with `.commits/` bodyfiles, `ws push`, `ws cr`. The PreToolUse hook denies compound bash — each shell command is a separate tool call. New prose follows the no-hard-wrap rule (single-line paragraphs, single-line bullets) per `writing-yggdrasil-docs`.

**Branches:**
- Yggdrasil: existing `docs/component-docs-convention` (already carries the SP-C spec commit `8a5fb53`).
- Nidavellir: new `docs/sp-c-cleanup` off `main`.

---

## File Structure

| Repo | File | Action | Responsibility |
|------|------|--------|----------------|
| yggdrasil | `.agent/skills/writing-yggdrasil-docs/SKILL.md` | Modify | Add a "Component Documentation Convention" section codifying the four shapes + Shape 2 rules |
| nidavellir | `docs/tls-and-certificates.md` | Create | Core wildcard-cert story (from `wildcard-tls.md` sections) + cert-manager / Gateway API gotchas (from `CLAUDE.md`) |
| nidavellir | `docs/traefik-version-pins.md` | Create | The 3.6.x / 3.7.x version-constraint story (from `wildcard-tls.md`) |
| nidavellir | `docs/cloud-iam-and-dns.md` | Create | Workload Identity + Cloud DNS + the test domain note (from `wildcard-tls.md` + `CLAUDE.md`) |
| nidavellir | `docs/testing.md` | Create | The kuttl invocations (from `CLAUDE.md` Key Commands) |
| nidavellir | `docs/README.md` | Create | The docs index — topic-file table + orientation |
| nidavellir | `README.md` | Modify | Light polish — add Documentation section + For contributors / agents footer |
| nidavellir | `docs/wildcard-tls.md` | Delete | Replaced by the three topic files |
| nidavellir | `CLAUDE.md` | Delete | Content distributed; the one agent-flavored line lives in the root README footer now |

---

## Task 1: Skill update — add the Component Documentation Convention (yggdrasil)

**Files:**
- Modify: `.agent/skills/writing-yggdrasil-docs/SKILL.md` (append a new top-level section before the existing `## Terminology` section)

Branch: already on `docs/component-docs-convention`. No branch action needed.

- [ ] **Step 1: Insert the new section**

Open `.agent/skills/writing-yggdrasil-docs/SKILL.md`. Find the line `## Terminology` (an existing top-level section). Insert the following new section immediately *before* it (exactly as shown between the >>>> markers, markers not included; the new section ends with a blank line followed by the existing `## Terminology` heading):

>>>>
## Component Documentation Convention

Component narrative content scales through four shapes. A component picks the shape that fits its current content volume; graduation is propose-then-confirm during ceremony, never automated.

| Shape | Structure | When |
|---|---|---|
| **1. Loose root Markdown** | `README.md` (required) + optional root companions: `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, etc. No `docs/`. | Brand new through small-but-focused — everything fits in a handful of root files. |
| **2. Plainly structured `/docs`** | Shape 1 + `docs/README.md` as the index + topic files at `docs/<topic>.md`. Plain CommonMark + GitHub-flavored extensions. No site config. | Real documentation needs — multiple distinct topics warrant their own files. |
| **3. Themed docs site** | Shape 2 + a site config (`mkdocs.yml` / `_config.yml` / equivalent) + theme + nav. Deploys to GitHub Pages. | Navigation and search become useful; audience extends beyond developers reading on GitHub. Includes site-flavored components whose purpose is the site itself. |
| **4. Custom site** *(sketched, future)* | Beyond MkDocs/Jekyll — Zensical or a hand-rolled framework. | When the standard frameworks hit their limits. Named only so the ladder is finite. |

### Shape 2 — the convention

Shape 2 is the new middle that this skill defines. Shape 1 needs no convention beyond "have a README"; Shape 3 inherits its conventions from its chosen framework.

Required structure:

```text
<component-root>/
  README.md                       # independent intro — purpose, tech stack, entry points
  ...optional root companions (AGENTS.md, CONTRIBUTING.md, etc.)
  docs/
    README.md                     # the docs index — first stop when browsing docs/
    <topic-1>.md
    <topic-2>.md
```

**Root `README.md` once `/docs` exists** is the *independent intro*, not the doc site's front door. It carries the component's purpose, a tech-stack overview, top-level entry points (install, run, contribute), a one-line pointer into `docs/README.md`, and optionally a "For contributors / agents" footer with links to higher-level workspace docs.

**`docs/README.md` (the index)** is the first stop on GitHub (GitHub auto-renders `README.md` at directory level). Contains a short orientation paragraph + a list of topic files with one-line descriptions + an optional "where to start" recommendation.

**Topic files (`docs/<topic>.md`)** — one focused concept per file. First heading is `# Topic Title` matching the slugified filename. Cross-reference other topic files with relative links; cross-reference ecosystem docs by absolute URL. Plain CommonMark + GitHub-flavored extensions only (no mkdocs/Jekyll-specific syntax). If a topic file grows to cover multiple distinct concepts, that is the signal to split it.

### Graduation triggers

Driven by content needs, propose-then-confirm during ceremony:

- Shape 1 → 2: a single root file holds multiple distinct concepts, *or* arc-graduated knowledge would otherwise pile into the root README.
- Shape 2 → 3: roughly ~10+ topic files, or the audience extends beyond developers reading on GitHub.
- Shape 3 → 4: MkDocs/Jekyll hit a wall on layout, theming, or build behavior. Most components will not reach this.

### Anti-patterns to avoid in Shape 2

- A single file holding multiple distinct concepts that should each have their own page.
- No index — a user landing in `docs/` sees a flat directory listing of filenames with no orientation.
- Hard-wrapped prose — the no-hard-wrap rule above applies to component docs the same as everywhere; component docs render in two distinct contexts (directly on GitHub and via Shape 3+ site renderers) where hard wraps render inconsistently.

### What this convention does NOT dictate

- Shape 3 toolchain choice (mkdocs vs. Jekyll vs. Just-the-Docs — per-component decision).
- The presence or content of root-level agent-context files (`AGENTS.md`, `CLAUDE.md`). Those are separate workspace conventions — but they must not hold general developer content that belongs in `/docs`.

>>>>

- [ ] **Step 2: Verify placement and tests**

Read the surrounding lines to confirm the new section sits between the existing Mermaid rules block and the `## Terminology` section, with a blank line separating each.

Run: `bash scripts/ws test yggdrasil`
Expected: PASS (140/140) — the bats suite is unaffected by skill prose edits.

- [ ] **Step 3: Commit**

Create `.commits/sp-c-skill-update.md`:

```markdown
---
message: "docs(skills): add Component Documentation Convention to writing-yggdrasil-docs"
add:
  - .agent/skills/writing-yggdrasil-docs/SKILL.md
---

Promotes the SP-C convention into the permanent home (the skill rather than the design doc). Documents the four-shape graduation ladder and pins the new Shape 2 (Plainly structured /docs) convention — required structure, root-README role once /docs exists, docs/README.md as the GitHub-renderable index, topic-file conventions, graduation triggers, anti-patterns, and what the convention deliberately does not dictate (Shape 3 toolchain, agent-context-file presence).

Pairs with the SP-C design doc (docs/plans/2026-05-19-component-docs-convention-design.md) committed earlier on this branch. The design doc carries the rationale; the skill carries the rule.
```

Run: `bash scripts/ws commit yggdrasil .commits/sp-c-skill-update.md`
Expected: commit created on `docs/component-docs-convention`.

---

## Task 2: Create the four new nidavellir topic files

**Files:**
- Create: `components/nidavellir/docs/tls-and-certificates.md`
- Create: `components/nidavellir/docs/traefik-version-pins.md`
- Create: `components/nidavellir/docs/cloud-iam-and-dns.md`
- Create: `components/nidavellir/docs/testing.md`

This task creates the four new topic files that together cover the content currently in `docs/wildcard-tls.md` plus the developer content currently misfiled in `CLAUDE.md`. The old files are deleted in Task 5, so during Tasks 2–4 both old and new exist briefly — this is intentional so each task produces a self-contained, working commit.

- [ ] **Step 1: Create the nidavellir topic branch**

Run: `git -C components/nidavellir checkout main`
Run: `git -C components/nidavellir pull`
Run: `git -C components/nidavellir checkout -b docs/sp-c-cleanup`
Expected: switched to a new branch `docs/sp-c-cleanup` based on the latest main.

- [ ] **Step 2: Create `components/nidavellir/docs/tls-and-certificates.md`**

Use the Write tool to create the file with this exact content:

````markdown
# TLS and Certificates

How the platform terminates HTTPS for `*.cmdbee.org`, and why it's built this way.

## TL;DR

A single wildcard certificate (`*.cmdbee.org` + apex) is issued by cert-manager via a DNS-01 ACME challenge through Google Cloud DNS, stored as one Secret in `kube-system`, and served by the Traefik Gateway's `websecure` listener as its **only** `certificateRef`. Every host — current and future — is covered at once. New apps get working HTTPS with zero per-app certificate action.

## Why not per-host certificates

The earlier design gave each app its own cert-manager `Certificate` + `ReferenceGrant`, with the Traefik Gateway listener carrying one `certificateRef` per host. **This does not work.** Traefik's Gateway API provider does not reliably SNI-iterate across multiple `certificateRefs` on a single listener — it uses the first and serves the self-signed default cert for every other host ([Traefik #11972](https://github.com/traefik/traefik/issues/11972), open and unfixed). The Gateway API spec only *mandates* single-`certificateRef` support per listener; multiple is "implementation-specific," and Traefik's implementation is the broken one.

A wildcard cert sidesteps this entirely: with exactly **one** cert on the listener, Traefik never reaches its broken cert-selection path.

A *separate* defect required pinning Traefik to 3.6.x — see [Traefik Version Pins](traefik-version-pins.md).

## Components

| File | Role |
|---|---|
| `vegvisir/manifests/letsencrypt-dns01.yaml` | ClusterIssuer — ACME prod, DNS-01 solver via Cloud DNS |
| `vegvisir/manifests/wildcard-cert.yaml` | `Certificate` for `*.cmdbee.org` + `cmdbee.org` → Secret `wildcard-cmdbee-tls` in `kube-system` |
| `vegvisir/manifests/traefik-gateway.yaml` | `websecure` listener references `wildcard-cmdbee-tls` as its single `certificateRef` |
| `vegvisir/manifests/cert-manager-app.yaml` | cert-manager Helm app; its SA is annotated for Workload Identity |

The authentication, Cloud DNS, and IAM details that make this work — including the gcloud reproduction commands for a fresh cluster — live in [Cloud IAM and DNS](cloud-iam-and-dns.md).

## Verifying

```bash
# Certificate issued?
kubectl -n kube-system get certificate wildcard-cmdbee
# Expect READY=True within ~2-5 min of first sync.

# Served cert for any host (should be Let's Encrypt, not TRAEFIK DEFAULT CERT):
echo | openssl s_client -servername gitea.cmdbee.org \
  -connect gitea.cmdbee.org:443 2>/dev/null | openssl x509 -noout -subject -issuer
```

## Renewal

cert-manager auto-renews the wildcard well before its 90-day expiry, re-running the DNS-01 challenge each time. No operator action required.

## Gotchas

- **cert-manager Certificate conditions** differ by state. While issuing: `[Ready=False, Issuing=True]`. After issued: `[Ready=True]` only — `Issuing` disappears entirely. Assertions that look for `Issuing=False` after issuance will fail.
- **Gateway API condition assertions** must include ALL conditions present (e.g. both `Programmed` and `Accepted`), not just the one being checked. Partial assertions match in unexpected ways.
- **cert-manager Gateway API integration** is enabled via the `ControllerConfiguration` resource, not via `--feature-gates` flags. The `ControllerConfiguration` path is the supported one going forward.

## Related

- [Platform Gitea](platform-gitea.md) — the Forgejo day-2 plan; its earlier per-host cert assumptions are superseded by this wildcard approach.
- [yggdrasil#65](https://github.com/SiliconSaga/yggdrasil/issues/65) — the long-term three-tier (public / LAN / mesh) access architecture this fits into.
````

- [ ] **Step 3: Create `components/nidavellir/docs/traefik-version-pins.md`**

Use the Write tool to create the file with this exact content:

````markdown
# Traefik Version Pins

The Traefik chart in `nordri` is pinned to the **3.6.x** line (chart 38.x) for one specific reason: **Traefik 3.7.x regressed the Gateway provider's certificate loading entirely.** On 3.7.1, even a single valid, same-namespace `certificateRef` is never loaded into the TLS store — every host serves Traefik's self-signed default certificate.

On 3.6.5, the wildcard certificate serves correctly across all hosts. Stay on 3.6.x.

Do not bump to chart 40.x / Traefik 3.7.x without re-testing TLS end to end.

## Related background

This is a *separate* defect from the Gateway API multi-`certificateRef` limitation that originally motivated the wildcard cert design — see [TLS and Certificates](tls-and-certificates.md) for that story. The version pin protects against a different bug at a different layer.

## References

- [Traefik #11972](https://github.com/traefik/traefik/issues/11972) — Gateway API SNI iteration across multiple `certificateRefs` (open, unfixed). The bug that motivates the wildcard design.
- [yggdrasil#65](https://github.com/SiliconSaga/yggdrasil/issues/65) — the long-term three-tier (public / LAN / mesh) access architecture this fits into.

## What to re-test before bumping Traefik

1. `kubectl kuttl test --config kuttl-test.yaml` — base platform tests.
2. `WHOAMI_DOMAIN=test.cmdbee.org kubectl kuttl test --config kuttl-test-e2e.yaml` — end-to-end TLS.
3. Manually verify a non-default host serves the Let's Encrypt cert, not Traefik's default:

```bash
echo | openssl s_client -servername gitea.cmdbee.org \
  -connect gitea.cmdbee.org:443 2>/dev/null | openssl x509 -noout -subject -issuer
```

Both kuttl suites must pass and the manual check must show the issuer as Let's Encrypt.
````

- [ ] **Step 4: Create `components/nidavellir/docs/cloud-iam-and-dns.md`**

Use the Write tool to create the file with this exact content:

````markdown
# Cloud IAM and DNS

The GCP-side setup that makes the platform's wildcard certificate possible: a Workload Identity binding (no service-account keys stored anywhere) and a Cloud DNS managed zone for the test domain.

## Test domain

`cmdbee.org` is the platform's test domain. Domain **registration** is at NameCheap; DNS **resolution** is on Google Cloud DNS (managed zone `cmdbee-org` in project `teralivekubernetes`). Co-locating DNS resolution in the same GCP project as the cluster is what makes the keyless Workload Identity path below possible.

Apex and wildcard `A` records point at the Traefik LoadBalancer.

## Workload Identity — no keys

Wildcard certificates require DNS-01 (HTTP-01 cannot satisfy a wildcard). cert-manager must write a temporary `_acme-challenge.cmdbee.org` TXT record into the Cloud DNS zone to satisfy the ACME challenge. It authenticates via **Workload Identity** — no service-account key is stored anywhere:

- GCP SA `cert-manager-dns01@teralivekubernetes.iam.gserviceaccount.com` holds `roles/dns.admin`.
- The cert-manager controller's Kubernetes SA (`cert-manager/cert-manager`) is annotated `iam.gke.io/gcp-service-account: <that SA>` (set in `cert-manager-app.yaml` Helm values), and a `roles/iam.workloadIdentityUser` binding lets it impersonate the GCP SA.
- The ClusterIssuer's `cloudDNS` solver has no `serviceAccountSecretRef` — it uses the ambient WI credentials.

## Reproducing the GCP-side setup

One-time, idempotent. Requires the GKE cluster to have Workload Identity enabled (`workloadPool` set; `default-pool` running `GKE_METADATA`).

```bash
PROJECT=teralivekubernetes
SA=cert-manager-dns01
SA_EMAIL="${SA}@${PROJECT}.iam.gserviceaccount.com"

# 1. Service account
gcloud iam service-accounts create "$SA" --project "$PROJECT" \
  --display-name "cert-manager DNS-01 solver (Cloud DNS)"

# 2. DNS admin on the project
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member "serviceAccount:${SA_EMAIL}" --role roles/dns.admin --condition=None

# 3. Workload Identity binding (KSA -> GSA impersonation)
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" --project "$PROJECT" \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT}.svc.id.goog[cert-manager/cert-manager]"
```

This is out-of-GitOps (it's cloud IAM, not cluster state) — the same category as the Gitea admin credentials created by `nordri/bootstrap.sh`. A fresh cluster needs these three commands run once before the wildcard cert can issue.

## Related

- [TLS and Certificates](tls-and-certificates.md) — what this IAM and DNS setup is in service of.
````

- [ ] **Step 5: Create `components/nidavellir/docs/testing.md`**

Use the Write tool to create the file with this exact content:

````markdown
# Testing

Two kuttl test suites are available for nidavellir.

## Platform tests (fast, no DNS needed)

```bash
kubectl kuttl test --config kuttl-test.yaml
```

Covers: vegvisir, cert-manager, ClusterIssuers, default certificate.

## End-to-end tests (require live DNS for cmdbee.org)

```bash
WHOAMI_DOMAIN=test.cmdbee.org kubectl kuttl test --config kuttl-test-e2e.yaml
```

Covers: whoami Gateway attachment + HTTP routing. TLS comes from the platform wildcard certificate (see [TLS and Certificates](tls-and-certificates.md)); the demo has no per-host cert of its own.
````

- [ ] **Step 6: Commit**

Create `.commits/sp-c-nidavellir-topic-files.md`:

```markdown
---
message: "docs: split wildcard-tls.md + distribute CLAUDE.md into four topic files"
add:
  - docs/tls-and-certificates.md
  - docs/traefik-version-pins.md
  - docs/cloud-iam-and-dns.md
  - docs/testing.md
---

Splits the wildcard-tls.md hodge-podge into three focused topic files, and creates testing.md from the kuttl invocations currently in CLAUDE.md.

- tls-and-certificates.md — core wildcard-cert design (why-not-per-host, manifests, verification, renewal) plus the cert-manager / Gateway API gotchas from CLAUDE.md.
- traefik-version-pins.md — the 3.6.x must-pin / 3.7.x regressed story, with the upstream bug references and the re-test checklist before bumping.
- cloud-iam-and-dns.md — Workload Identity binding, Cloud DNS zone (registration at NameCheap, resolution at GCP Cloud DNS), and the gcloud reproduction commands. Folds in the test-domain note from CLAUDE.md.
- testing.md — the platform and end-to-end kuttl invocations from CLAUDE.md Key Commands.

The original wildcard-tls.md and CLAUDE.md still exist at this point — they get deleted in the dedicated cleanup commit later in this PR. Doing the splits first means each commit produces a working tree.

Part of the SP-C component docs convention rollout — see yggdrasil docs/plans/2026-05-19-component-docs-convention-design.md.
```

Run: `bash scripts/ws commit nidavellir .commits/sp-c-nidavellir-topic-files.md`
Expected: commit created on `docs/sp-c-cleanup` in nidavellir's repo.

---

## Task 3: Create `docs/README.md` — the index

**Files:**
- Create: `components/nidavellir/docs/README.md`

- [ ] **Step 1: Create the index file**

Use the Write tool to create `components/nidavellir/docs/README.md` with this exact content:

````markdown
# Nidavellir Docs

Operational and design documentation for the Nidavellir platform layer (Vegvísir, Mimir, Keycloak, Heimdall, Vörðu, OpenBAO). For Nidavellir's purpose and tech-stack overview, see the [repo README](../README.md).

## Topics

| File | Covers |
|---|---|
| [TLS and Certificates](tls-and-certificates.md) | The platform's wildcard-cert HTTPS termination — design, manifests, verification, renewal, cert-manager / Gateway API gotchas |
| [Traefik Version Pins](traefik-version-pins.md) | Why Traefik stays on 3.6.x — what 3.7.x broke, what to re-test before bumping |
| [Cloud IAM and DNS](cloud-iam-and-dns.md) | Workload Identity + Cloud DNS — the GCP-side setup that makes the wildcard cert possible, plus the test domain (`cmdbee.org`) |
| [Testing](testing.md) | Running the platform and end-to-end kuttl suites |
| [Platform Gitea](platform-gitea.md) | Day-2 plan for moving from the bootstrap Seed Gitea to a proper platform Gitea (Mimir-backed, TLS, durable storage) |

## Where to start

New to the platform's HTTPS story? Read [TLS and Certificates](tls-and-certificates.md) first; [Traefik Version Pins](traefik-version-pins.md) and [Cloud IAM and DNS](cloud-iam-and-dns.md) are its companions covering specific corners.
````

- [ ] **Step 2: Verify relative links resolve**

Confirm every `[text](file.md)` link in the new file points at an existing file in `components/nidavellir/docs/`:

- `tls-and-certificates.md` — exists (Task 2 Step 2)
- `traefik-version-pins.md` — exists (Task 2 Step 3)
- `cloud-iam-and-dns.md` — exists (Task 2 Step 4)
- `testing.md` — exists (Task 2 Step 5)
- `platform-gitea.md` — exists (pre-existing, unchanged)
- `../README.md` — exists (pre-existing root README, polished in Task 4 but file present)

All five topic-file links and the `../README.md` upward link must resolve.

- [ ] **Step 3: Commit**

Create `.commits/sp-c-nidavellir-docs-index.md`:

```markdown
---
message: "docs: add docs/README.md as the index for nidavellir docs"
add:
  - docs/README.md
---

Adds the docs/ index per the SP-C component documentation convention (Shape 2). GitHub auto-renders this README.md when a user browses to docs/, so it serves as the de facto landing without any site config. Contains a brief orientation paragraph, a topic-file table with one-line descriptions, and a "where to start" recommendation for the HTTPS story (the densest cluster of new topic files).

Part of the SP-C component docs convention rollout.
```

Run: `bash scripts/ws commit nidavellir .commits/sp-c-nidavellir-docs-index.md`
Expected: commit created.

---

## Task 4: Polish the root `README.md`

**Files:**
- Modify: `components/nidavellir/README.md` (append two new sections at the end)

- [ ] **Step 1: Append the Documentation and For contributors / agents sections**

Use the Edit tool. Find the last line of the existing `README.md`:

```
* OpenBAO: Secrets Storage
```

That is the last bullet in the Tech Stack section. Replace it with the same line plus two new sections appended, exactly as shown between the >>>> markers (markers not included):

>>>>
* OpenBAO: Secrets Storage

## Documentation

Operational and design documentation lives in [`docs/`](docs/README.md) — TLS and certificates, Traefik version pins, Cloud IAM and DNS, testing, and the platform Gitea day-2 plan.

## For contributors / agents

This component is part of the [SiliconSaga](https://github.com/SiliconSaga) ecosystem managed via the [yggdrasil workspace](https://github.com/SiliconSaga/yggdrasil). Workspace-level conventions, the `ws` CLI, and the Guardian Driven Development methodology are documented in [`yggdrasil/AGENTS.md`](https://github.com/SiliconSaga/yggdrasil/blob/main/AGENTS.md) and [`yggdrasil/docs/ecosystem-architecture.md`](https://siliconsaga.github.io/yggdrasil/ecosystem-architecture/).
>>>>

- [ ] **Step 2: Verify the file structure**

Read the modified `README.md` and confirm it has, in order: the existing `# Nidavellir` heading, the existing italic byline, the existing Norse quote blockquote, the existing intro paragraph, the existing `## Tech Stack` section (unchanged), the new `## Documentation` section, the new `## For contributors / agents` section. No section was deleted, no pre-existing prose was reflowed.

- [ ] **Step 3: Commit**

Create `.commits/sp-c-nidavellir-readme.md`:

```markdown
---
message: "docs: add Documentation and contributor/agents sections to root README"
add:
  - README.md
---

Polishes the root README per the SP-C component documentation convention (Shape 2). The root README becomes an independent intro once docs/ exists — it gains a Documentation section pointing into docs/README.md, and a For contributors / agents footer that consolidates the workspace pointers (yggdrasil AGENTS.md, ecosystem-architecture). The footer relocates the one genuinely agent-flavored line from the about-to-be-deleted CLAUDE.md.

Part of the SP-C component docs convention rollout.
```

Run: `bash scripts/ws commit nidavellir .commits/sp-c-nidavellir-readme.md`
Expected: commit created.

---

## Task 5: Delete the old `wildcard-tls.md` and `CLAUDE.md`

**Files:**
- Delete: `components/nidavellir/docs/wildcard-tls.md`
- Delete: `components/nidavellir/CLAUDE.md`

- [ ] **Step 1: Remove the files from disk**

Run: `rm components/nidavellir/docs/wildcard-tls.md`
Run: `rm components/nidavellir/CLAUDE.md`
Expected: both files gone from the working tree.

- [ ] **Step 2: Verify the splits and distribution are complete**

The deletion is safe only if everything from the deleted files exists in the new files. Spot-check:

- The TL;DR + why-not-per-host + components table + verification + renewal sections of `wildcard-tls.md` are now in `docs/tls-and-certificates.md`.
- The Traefik version-constraint section is now in `docs/traefik-version-pins.md`.
- The Workload Identity + GCP-side setup + DNS sections are now in `docs/cloud-iam-and-dns.md`.
- The Key Commands from `CLAUDE.md` are now in `docs/testing.md`.
- The Key Gotchas from `CLAUDE.md` are folded into `docs/tls-and-certificates.md` (cert-manager and Gateway API gotchas) and `docs/cloud-iam-and-dns.md` (test domain note).
- The Heimdall gotcha is intentionally dropped — the truth lives in `apps/kustomization.yaml`.
- The "Full agent context" line is in the root `README.md` "For contributors / agents" footer.

Run: `git -C components/nidavellir status --short`
Expected: shows the two deletions (`D docs/wildcard-tls.md`, `D CLAUDE.md`) and nothing else.

- [ ] **Step 3: Commit**

Create `.commits/sp-c-nidavellir-delete-old.md`:

```markdown
---
message: "docs: delete wildcard-tls.md and CLAUDE.md (content distributed)"
add:
  - docs/wildcard-tls.md
  - CLAUDE.md
---

Removes the two files whose content has been redistributed earlier in this PR.

- docs/wildcard-tls.md — split into docs/tls-and-certificates.md, docs/traefik-version-pins.md, and docs/cloud-iam-and-dns.md. The original was a hodge-podge of five distinct concepts; each now has its own focused topic file.
- CLAUDE.md — barely Claude-specific. Content distributed: Key Commands → docs/testing.md; cert-manager / Gateway API gotchas → docs/tls-and-certificates.md (Gotchas section); test-domain note → docs/cloud-iam-and-dns.md; "Full agent context" pointer → root README.md (For contributors / agents footer). The Heimdall app-state note is intentionally dropped — the truth is in apps/kustomization.yaml; a docs reference would be duplication.

Git history preserves both files. Part of the SP-C component docs convention rollout.
```

Run: `bash scripts/ws commit nidavellir .commits/sp-c-nidavellir-delete-old.md`
Expected: commit created. The `add:` list contains the two deleted files — `ws commit` passes them to `git add`, which stages tracked-file deletions correctly (per the commit-template guidance: "already-deleted-from-disk-but-tracked file → regular path").

---

## After the plan

All commits land on:
- Yggdrasil: existing branch `docs/component-docs-convention` (already carries `8a5fb53` spec, gains the Task 1 skill-update commit).
- Nidavellir: new branch `docs/sp-c-cleanup`, four commits (Tasks 2–5).

When ready to open CRs:

**Yggdrasil:**

- `bash scripts/ws diagnose yggdrasil` (first push of the session sanity check)
- `bash scripts/ws push yggdrasil`
- `cp templates/change.md .crs/sp-c-component-docs.md` and fill in Summary / Test plan / Related
- `bash scripts/ws cr yggdrasil "docs: SP-C component docs convention" .crs/sp-c-component-docs.md`

**Nidavellir:**

- `bash scripts/ws diagnose nidavellir`
- `bash scripts/ws push nidavellir`
- `cp templates/change.md .crs/sp-c-nidavellir-cleanup.md` and fill in
- `bash scripts/ws cr nidavellir "docs: SP-C cleanup — split wildcard-tls + distribute CLAUDE.md" .crs/sp-c-nidavellir-cleanup.md`

Both CR bodies should cross-reference each other so reviewers can navigate between the convention (yggdrasil) and the worked example (nidavellir).

## Verification summary

This plan only touches markdown — no code, no tests beyond confirming the workspace bats suite still passes after the skill change. Verification per task is: cross-reference validity (relative links between topic files, the upward link from `docs/README.md` to `../README.md`, the absolute links to yggdrasil URLs); correct placement of inserted sections in modified files (Task 1 in the skill, Task 4 in the root README); and `ws test yggdrasil` green after Task 1. The functional proof is browsing the nidavellir repo on GitHub post-merge: root README renders as a clean intro pointing into `docs/`; `docs/README.md` renders as the index when the user browses to `docs/`; topic files cross-link without dead links.
