# Component Docs Convention — Design (SP-C)

*Design doc — 2026-05-19. Defines a graduation ladder for component documentation and the new "Shape 2 — Plainly structured /docs" convention. The first facet of the organization-stack model (see `2026-05-19-organization-stack-design.md`) where durable knowledge graduating from arcs has a defined long-term home. Nidavellir's `docs/` cleanup is the worked example.*

## Problem

Components in this ecosystem have documentation needs that scale wildly — from "the README is enough" to "this is the school district's whole public site." Today there is no convention for how a component's docs grow as those needs scale:

- `nidavellir` has a `docs/` directory with exactly two files (`platform-gitea.md`, `wildcard-tls.md`). There is no index, no README pointing into `docs/`, and the larger of the two files is a hodge-podge of distinct concepts (wildcard cert design, Traefik version-pin gotchas, GCP IAM + DNS setup, verification commands, renewal) crammed into one page. The component also has a `CLAUDE.md` filled with general developer content that has nothing Claude-specific about it.
- `schools` and `mtl-site` are site-flavored components (their purpose *is* to be a GitHub Pages site) and they each pick a different toolchain (Just-the-Docs Jekyll vs. plain Jekyll) without a shared convention guiding the choice.
- Yggdrasil's own docs (under `docs/`, served via MkDocs Material) are the model the user wants other components to feel like — clean topic-files-per-concept, searchable, well-cross-linked — but there is no rule that makes a component move in that direction over time.
- The SP-D organization-stack model says durable knowledge "graduates from arcs to component `docs/`." That seam needs a target shape, otherwise graduation lands on a poorly-organized surface.

This document defines a four-shape graduation ladder for component narrative content and pins the convention for the new middle shape (Shape 2 — Plainly structured `/docs`). It treats `nidavellir`'s cleanup as the worked example.

## The four shapes

Components pick the shape that fits their current content volume. Graduation between shapes is propose-then-confirm at convenient ceremony touch; no automation, no bureaucracy.

| Shape | Structure | When |
|---|---|---|
| **1. Loose root Markdown** | `README.md` (required) + optional companions at the repo root: `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, etc. No `docs/`. | From brand-new to small-but-focused — everything fits in a handful of root files. |
| **2. Plainly structured `/docs`** | Shape 1 + `docs/README.md` as the index + topic files at `docs/<topic>.md`. Plain CommonMark + GitHub-flavored extensions only. No site config. | Real documentation needs — multiple distinct topics warrant their own files. The new convention defined below. |
| **3. Themed docs site** | Shape 2 + a site config (`mkdocs.yml` / `_config.yml` / equivalent) + theme + nav. Deploys to GitHub Pages. | Navigation and search become useful; the audience extends beyond developers reading on GitHub. Includes site-flavored components like `schools` and `mtl-site` — the convention applies the same way at this shape. |
| **4. Custom site** *(sketched, future)* | Beyond MkDocs/Jekyll — Zensical, a hand-rolled framework, etc. | When the standard frameworks hit their limits. Named only so the ladder isn't open-ended; out of scope to specify. |

Site-flavored components (`schools`, `mtl-site`) live at Shape 3 — their entire purpose is to be the site. Documentation-flavored components (`nidavellir`, others) live anywhere on the ladder depending on content volume. The shapes are the same; the intent differs.

## Shape 2 — the new convention

This is what the document actually defines. Shape 1 needs no convention beyond "have a README." Shape 3 inherits its conventions from its chosen framework. Shape 2 is the new middle.

### Required structure

```text
<component-root>/
  README.md                       # independent intro — purpose, tech stack, top-level entry points
  ...optional root companions (AGENTS.md, CONTRIBUTING.md, etc.)
  docs/
    README.md                     # the docs index — first stop when a user browses to docs/
    <topic-1>.md
    <topic-2>.md
    ...
```

### Root `README.md` once `/docs` exists

Once a component adopts Shape 2, the root `README.md` becomes an **independent intro**, not the doc site's front door. It carries:

- The component's purpose, in a paragraph or two
- A "Tech stack" or equivalent overview section
- Top-level entry points: how to install or run, where to find the deeper docs, how to contribute
- A *"Detailed docs in [docs/README.md](docs/README.md)"* pointer
- Optionally a *"For contributors / agents"* footer with links to higher-level workspace docs (e.g. `yggdrasil/AGENTS.md`, `yggdrasil/docs/ecosystem-architecture.md`) — this is where a thin agent-context pointer belongs once `CLAUDE.md`-style files are deleted

The root `README.md` is not part of the docs site. A reader landing on the component's GitHub repo page sees this; clicking into `docs/` is the explicit move to the deeper material. For Shape 3 components, the separation becomes even cleaner — the root `README.md` stays a repo landing, while the site's home page is `docs/index.md`.

### `docs/README.md` — the index

The first stop when a user browses to `docs/` on GitHub. GitHub auto-renders `README.md` at directory level, so this is the de facto landing page without any site config. Contains:

- A short orientation paragraph: what this component's docs cover, who they're for
- A list of the topic files with a one-line description of each (so a reader can scan and pick)
- Optional: a brief "where to start" recommendation (e.g. *"new here? read X first"*)

### Topic files (`docs/<topic>.md`)

One focused concept per file. Conventions:

- The first heading is `# Topic Title` matching the filename (slugified — e.g. `tls-and-certificates.md` → `# TLS and Certificates`)
- Cross-reference other topic files with relative links: `[Cloud IAM and DNS](cloud-iam-and-dns.md)`
- Cross-reference yggdrasil or other ecosystem docs by absolute URL: `[the organization-stack](https://siliconsaga.github.io/yggdrasil/gdd/organization-stack/)`
- Plain CommonMark + GitHub-flavored extensions (tables, fenced code, task lists, alerts) — no mkdocs/Jekyll-specific syntax
- Cover one concept well; if a topic file is growing to cover multiple distinct concepts, that's the signal to split it (the anti-pattern that gave rise to this convention)

### Anti-patterns to avoid

The things `wildcard-tls.md` is currently guilty of:

- A single file holding multiple distinct concepts that should each have their own page (wildcard cert design + Traefik version-pin gotchas + GCP setup + verification + renewal all in one document)
- No index — a user landing in `docs/` sees a flat directory listing of filenames with no orientation
- Implicit knowledge — a topic file that assumes the reader has read the rest of the component's README without saying so

### Prose conventions

The workspace-wide rule applies to component docs too: **do not hard-wrap prose**. Write each paragraph as a single line; let the renderer wrap. The convention is enforced in the `gdd-doc-writing` skill — same rule, same reasons (some renderers respect hard-wraps as visible line breaks; reflowing after every edit is friction; editors handle wrap natively).

This is called out explicitly here because component docs render in two distinct contexts — directly on GitHub when browsing a repo, and (for Shape 3+) via a themed site renderer — and hard-wrapped lines render reliably in neither.

## Graduation triggers

Driven by content needs, propose-then-confirm during ceremony. No auto-detection.

- **Shape 1 → 2** — a single root file holds multiple distinct concepts, *or* arc-graduated knowledge from the SP-D model would otherwise pile into the root README.
- **Shape 2 → 3** — rough signal: ~10+ topic files, *or* the audience extends beyond developers reading on GitHub (navigation and search make a real difference).
- **Shape 3 → 4** — MkDocs/Jekyll hit a wall on layout, theming, or build behavior. Most components will not reach this; Shape 4 is named only to keep the ladder finite.

Transitions surface during scribe or gdd-housekeeping ceremonies — the agent notices the signal (a root file growing topic-fragmented, a `docs/` accumulating files past the readable-on-GitHub point) and proposes the move. The human confirms.

## SP-D arc-knowledge interaction

When an arc closes and the GDD ceremony graduates durable knowledge to a component (per the SP-D model), the agent proposes a destination tied to the component's current shape:

- **Component at Shape 1** — graduate to the root `README.md`, *or* propose a Shape 1 → 2 transition if the knowledge is substantial enough to warrant a new `docs/` dir.
- **Component at Shape 2+** — graduate to a new or updated `docs/<topic>.md` file. New topic gets a new file; existing topic gets the update folded in.

The graduation destination is propose-then-confirm — the same drift-tolerant posture as the rest of the organization stack. The SP-D model creates the gravity for SP-C's shapes to fill in over time.

## Cross-linking from the ecosystem

- Yggdrasil docs link to component docs by GitHub URL — the rendered repo page for Shape 1 or 2 components, the Pages URL for Shape 3+. URLs are stable across the convention and require no coordination.
- Component docs do not get embedded into yggdrasil's MkDocs site. Different repos, different toolchains, sync friction outweighs the integration benefit at this scale.
- A future enhancement worth naming but not specifying here: a "Components" nav section in yggdrasil's `mkdocs.yml` listing each component with a one-line description + link-out to its repo or docs URL. Defer to a separate round.

## Nidavellir worked example

Current state:

- `README.md` at the root — short, tech-stack-only (one paragraph + a six-item bullet list)
- `CLAUDE.md` at the root — *misfiled*. Contains general developer content (kuttl test invocations, cert-manager gotchas, Traefik conditions, Heimdall app-state note, test-domain mention). One line is genuinely Claude-flavored ("Full agent context: yggdrasil/CLAUDE.md and yggdrasil/docs/ecosystem-architecture.md"). The rest is just useful developer notes that belong in `docs/`.
- `docs/platform-gitea.md` — focused, already topic-shaped. Keep.
- `docs/wildcard-tls.md` — the hodge-podge. Covers wildcard cert design, why-not-per-host rationale, Traefik 3.6.x/3.7.x version constraints, the four manifests, Workload Identity authentication, GCP-side setup commands, verification, DNS, renewal, and links to other docs. Five-ish distinct concepts.

Target shape: Shape 2 — Plainly structured `/docs`.

### Actions

1. **Polish the root `README.md`** lightly — keep the existing purpose paragraph and the tech-stack list. Add a *Documentation* section pointing into `docs/README.md`. Add a brief *For contributors / agents* footer with a pointer to `yggdrasil/AGENTS.md` and `yggdrasil/docs/ecosystem-architecture.md` (relocating the one genuinely agent-flavored line from `CLAUDE.md`).
2. **Create `docs/README.md`** — orientation paragraph + a table of topic files with one-line descriptions.
3. **Split `docs/wildcard-tls.md`** into three focused topic files:
   - **`tls-and-certificates.md`** — wildcard cert design, the why-not-per-host rationale, the manifests overview (four files), verification commands, renewal. The core HTTPS story for the platform.
   - **`traefik-version-pins.md`** — the 3.6.x must-pin / 3.7.x regressed-the-cert-loading story, the upstream bug references, what to re-test before bumping. Standalone because it's a maintenance gotcha that someone bumping Traefik needs to find without reading the TLS doc.
   - **`cloud-iam-and-dns.md`** — Workload Identity binding (GCP SA `cert-manager-dns01`, KSA → GSA impersonation), Cloud DNS zone (`cmdbee-org` in project `teralivekubernetes`, registration at NameCheap, DNS resolution at GCP Cloud DNS), the gcloud reproduction commands for a fresh cluster, the keyless / co-located rationale. The test domain (`cmdbee.org`, test-only) folds in here.
4. **Distribute `CLAUDE.md` content** and delete the file:
   - "Full agent context" pointer → into the root `README.md` footer (handled in step 1).
   - "Key Commands" (the two kuttl invocations) → new `docs/testing.md` topic file.
   - "Key Gotchas":
     - cert-manager condition states (Ready/Issuing) + Gateway API condition assertion gotcha + cert-manager Gateway API config (`ControllerConfiguration` vs `--feature-gates`) → fold into `tls-and-certificates.md` as a *Gotchas* sub-section. All three sit in the TLS/cert-manager neighborhood.
     - Heimdall (`apps/heimdall-app.yaml` commented out in `kustomization.yaml`) → drop. The truth is in `kustomization.yaml`; a docs reference would be duplication.
     - Test domain note → into `cloud-iam-and-dns.md` (handled in step 3).
   - Delete `CLAUDE.md`.
5. **Keep `docs/platform-gitea.md`** unchanged — already focused.
6. **Delete the old `docs/wildcard-tls.md`** after the split. Git history preserves the original; the three new files cover its content.
7. **Cross-link** the topic files among themselves (relative links) and from `docs/README.md` (the index).

### Resulting structure

```text
components/nidavellir/
  README.md                       # independent intro + For contributors / agents footer
  docs/
    README.md                     # the index
    tls-and-certificates.md       # core wildcard cert + cert-manager gotchas
    traefik-version-pins.md       # 3.6.x/3.7.x version constraints
    cloud-iam-and-dns.md          # Workload Identity, Cloud DNS, test domain
    testing.md                    # kuttl invocations
    platform-gitea.md             # kept, unchanged
```

Five topic files plus the index, one deletion (`CLAUDE.md`), one light polish (root `README.md`).

## What this does NOT do

- Specify Shape 3 toolchain choice (mkdocs vs. Jekyll vs. Just-the-Docs). Per-component decision; the convention applies to the `docs/` layout, not the build framework.
- Specify Shape 4 in any detail. Named only so the ladder isn't open-ended.
- Build automation. No `ws docs check`, no shape-detection tool, no link validator. Future work if friction accrues.
- Dictate the presence or content of root-level agent-context files (`AGENTS.md`, `CLAUDE.md`). That is a separate workspace convention. SP-C only says those files must not hold general developer content that belongs in `/docs` — `nidavellir`'s `CLAUDE.md` was a clean example of misfiling.
- Add a "Components" nav section to yggdrasil's `mkdocs.yml`. A worthy future enhancement; out of scope here.
- Generalize the wildcard-tls split into a reusable "split a hodge-podge file" tool. Other components will hand-split when they graduate to Shape 2.

## Open questions

- **Existing Shape 3 components** (`schools`, `mtl-site`) currently use Jekyll-based stacks with different conventions. Whether to retrofit them to Shape 3 of this ladder (or just let them coexist and apply the convention forward) is a separate decision and not part of this round.
- **The `docs/README.md` vs `docs/index.md` filename** is locked to `README.md` for Shape 2 (GitHub auto-renders it on directory browse). At Shape 3, the framework's expectation may force `docs/index.md` instead — MkDocs uses `index.md` by default. Components moving from 2 → 3 will rename. This is mentioned but not deeply specified.
