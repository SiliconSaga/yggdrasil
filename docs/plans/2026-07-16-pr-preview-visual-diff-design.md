# PR Preview + Visual Diff for GitHub Pages Components — Design

**Date:** 2026-07-16
**Status:** Design (Phase 1 + 2 scoped for build)
**Related:** `templates/components/gh-pages/`, `docs/gdd/roadmap.md`, `docs/tutorials/index.md`

---

## Purpose

Give any GDD GitHub Pages component two things on every pull request:

1. A **live preview URL** for the PR's build.
2. An automatic **before/after visual diff**, posted to the PR as inline images.

The goal is that a change can be *seen* before it ships — by a maintainer, or by a site owner with no technical background reviewing from a phone. The pattern is designed to graduate into `templates/components/gh-pages/` so every GDD Pages site inherits it.

This spec covers **Phase 1 (preview)** and **Phase 2 (visual diff)**. Both are plain CI. Downstream consumers — including chat-driven agents — are noted at the end but are not part of this design.

## Constraints

- **All-GitHub.** No Netlify/Vercel/Cloudflare, no SaaS account, no third-party signup.
- **Free.** GitHub Actions minutes only.
- **No LLM, no API key.** Nothing in this pipeline calls a model. It is vanilla CI.
- **Legible to a non-technical reviewer.** The output must make sense to someone who has never read a diff.

## Why roll our own

The OSS field was surveyed and is thinner than it looks:

| Project | Verdict |
|---|---|
| `lost-pixel` | **Archived** (2026-04-22) at 1.7k stars — the clearest marker that this space consolidated into paid SaaS |
| Sentry's screenshot action | Archived |
| `DiffGoblin` | Not a real project — one commit, 0 stars, an SEO/backlink pattern with a product funnel behind it |
| `SnapDrift` | An OSS front door to the author's hosted service (`apiKey`, `projectId`, dashboard link); its "no SaaS" claim traces to an article written by its own maintainer |
| `reg-viz/reg-actions` | Genuine and active (96★), but single-maintainer — and it consumes images you produce anyway |
| `rossjrw/pr-preview-action` | Genuine and active (427★); we lift its mechanism |
| `saadmk11/comment-webpage-screenshot` | Stale since 2023; useful only as a reference for image hosting |

**The structural fact that shapes everything:** the GitHub API *cannot attach an image to a comment*. Every "posts a visual diff to your PR" tool therefore reduces to one question — *where does it host the PNG?* The only answers are a git branch, an image host, or a vendor CDN. Once that's clear, most of the field falls away.

So we adopt the **mechanisms**, not the dependencies:

- Previews live on the `gh-pages` branch under `pr-preview/pr-<N>/`.
- Diff images are served from a git branch over HTTP.
- `baseurl` is injected at build time.
- Screenshots come from a **local** build, never the deployed CDN.

Rolling our own also removes three of the four glue burdens those tools impose (see *Simplifications*), and leaves the pattern GDD-owned — which matters when it ships in a template others depend on.

## Architecture

Two units. Neither contains a model or any secret beyond the workflow's built-in token; both run for **any** PR, whatever opened it.

```
push: main ──► build (baseurl=/<component>) ──► deploy to gh-pages:/   (preserving pr-preview/)

PR opened/sync
  ├─ Unit 1: build (baseurl=/<component>/pr-preview/pr-N) ─► gh-pages:/pr-preview/pr-N/
  │                                                          └─► sticky comment: preview URL
  └─ Unit 2: build main (baseurl="") ─► serve ─► Playwright ─┐
             build PR   (baseurl="") ─► serve ─► Playwright ─┴─► pixel diff
                                        └─► report + images ─► gh-pages:/pr-preview/pr-N/_diff/
                                             └─► sticky comment: inline before/after images

PR closed ──► delete gh-pages:/pr-preview/pr-N/
```

### Unit 1 — Preview Publisher

**The one prerequisite change.** GitHub Pages serves **one site per repo**, so previews must live *inside* the production site's tree. A component serving `main`/root (letting GitHub build the Jekyll) must move to:

- Pages source: **`gh-pages` branch, root** — still "Deploy from branch". The "GitHub Actions" source is incompatible with this pattern.
- `main` becomes **source-only**; a workflow builds it and publishes to `gh-pages`.
- Production lands at `gh-pages:/`; previews at `gh-pages:/pr-preview/pr-<N>/`.

The production deploy **must not wipe previews** — it publishes with `pr-preview/` excluded from cleaning.

| | |
|---|---|
| Trigger | `pull_request` (opened, synchronize, reopened) and (closed → cleanup) |
| Build | Jekyll, with `baseurl: /<component>/pr-preview/pr-<N>` injected at build time |
| Publish | commit `_site/` to `gh-pages` under `pr-preview/pr-<N>/` |
| Comment | sticky (create-or-update): the preview URL as a plain link |
| Cleanup | on close, remove the directory and update the comment |
| Auth | the built-in `GITHUB_TOKEN` — same repo, so **no PAT** |

**A plain link, deliberately — not a QR code.** Some preview actions render a QR into the comment, and it is tempting to reach for one "because the reviewer is on a phone." That reasoning is backwards: a reviewer already reading the PR *on* their phone simply taps the link, and an agent relaying the URL into a chat channel can only use a link. A QR is a **cross-device** tool — it earns its place when someone reviewing on a *desktop* wants to open the preview on a real handset to check mobile rendering. That is a genuine but secondary need, and generating a QR ourselves would mean adding a library or calling a third-party QR service from a site's CI. Not worth it now; revisit only if desktop→handset checking becomes routine.

**`baseurl` injection only works if the site uses `relative_url`/`absolute_url` throughout.** Any hardcoded `/assets/...` yields an unstyled preview. This is a real precondition for adopting the pattern, and worth auditing per component — the same discipline that makes a custom-domain cutover a one-line change is what makes previews possible.

### Unit 2 — Visual Differ

**Screenshot a locally-served build, never the preview URL.** Two decisive reasons:

1. The preview URL goes through Pages' CDN with publish + propagation delay. Screenshotting it races a stale cache and manufactures phantom diffs.
2. The preview is served from a subpath while `main` serves from root. Diffing those would light up **every asset path on every page**. Building both locally with `baseurl: ""` makes the comparison apples-to-apples by construction.

Unit 2 therefore never touches Unit 1's output. The preview URL is for the **human**; the diff is computed independently.

| | |
|---|---|
| Baseline | build `main` **in the same job** (see *Simplifications*) |
| Candidate | build the PR head |
| Serve | a local static server per build, behind a wait-for-ready gate |
| Screenshot | Playwright — `reducedMotion: 'reduce'`, await `document.fonts.ready` |
| Routes | **derived from the built `sitemap.xml`** (see *Simplifications*) |
| Diff | per-route pixel comparison; emit `before`/`after`/`diff` PNGs for changed routes only |
| Publish | into the preview tree at `pr-preview/pr-<N>/_diff/`, plus a generated `_diff/index.html` report |
| Comment | sticky: changed routes, inline images, links to the report and preview |

**New routes** (in the PR, absent from `main`) render as a full screenshot labelled "new page" rather than a diff. **Removed routes** are listed by name. Two viewports — mobile and desktop — one browser.

### Determinism — and the calm toggle

Screenshot flake is the recurring tax in every visual-diff setup. Static sites generate it in three predictable ways: **motion** (rotating banners, carousels, animations), **web fonts** (FOUT), and **third-party embeds** (iframes whose content we don't control). Motion is the worst — a banner that cycles on a timer produces a different capture on every page, every run, forever.

Rather than bolt a CI-only hack onto the site, fix it at the source with a standard web feature:

- **The site honors `prefers-reduced-motion: reduce`** — timed rotation never starts (the first item renders statically) and CSS transitions are disabled.
- **Playwright sets `reducedMotion: 'reduce'`**, which emulates that media query — screenshots become deterministic *for free*, with no test-only code path in the site.
- **Fonts:** await `document.fonts.ready` before capture.
- **Third-party embeds:** block external requests at the Playwright route level, so an embed can't inject nondeterminism. The host page still renders its own chrome.

This is the design's best trade. The mechanism that stabilizes CI is also a **genuine accessibility feature**: motion sensitivity is a real need, and timed motion is exactly what triggers it. Users who set "reduce motion" at the OS level get a calmer site. We ship an a11y improvement and get determinism as a side effect, instead of paying a flake tax forever.

Honoring `prefers-reduced-motion` therefore becomes a **stated precondition** of the pattern, alongside `relative_url`. Both are things a well-built site should do anyway; the pipeline just gives them teeth. A visible in-page "calm" toggle is a possible later addition — the media query is sufficient now.

### Simplifications over the surveyed stack

Rolling our own deletes three of the four glue burdens the OSS route imposes:

| Their glue | Our answer |
|---|---|
| A hand-maintained route list, updated as pages are added | **Derive routes from `sitemap.xml`** (`jekyll-sitemap` ships in the `github-pages` gem; verify it is actually enabled for the local build, and fail the job loudly if the sitemap is absent rather than silently screenshotting nothing). Routes then track the site automatically. |
| A `push: main` job to seed baseline images to a branch — plus drift when it's missed, and spurious diffs on the first PR after a gap | **Build `main` in the same job.** Jekyll builds in seconds; two builds per PR is nothing. No baseline state, no seeding job, no drift. |
| A second branch to host diff images | **Diff images ride inside the preview** at `pr-preview/pr-<N>/_diff/`. One publish, one cleanup, and they already have a public URL. |
| Flake suppression | Unavoidable — but `prefers-reduced-motion` collapses most of it (above). |

## Out of scope

- **Fork PRs.** A fork's token cannot write to `gh-pages`, so neither the surveyed actions nor this design supports them. Acceptable where every author is a collaborator — but it must be stated rather than discovered.
- Cross-browser matrices, and any visual testing beyond whole-page screenshots of a deployed static site.

## Downstream consumers

The pipeline's contract is deliberately narrow: **a PR gains a preview URL and a comment carrying before/after images.** Anything can consume that.

The obvious consumer is a human on a phone. A less obvious one is a **chat-driven agent** that opens a PR on a user's behalf, waits for this pipeline, and relays the preview link and diff image into a chat channel for approval. That agent is a separate design; it depends on this pipeline, not the reverse. If it never ships, the previews and diffs still stand on their own for anyone editing through the GitHub web UI.

## Risks

| Risk | Mitigation |
|---|---|
| **Pages source migration** (`main`/root → `gh-pages`) touches a live site | Do it as its own change and verify production before wiring previews; reversible via one settings toggle |
| Screenshot flake despite reduced-motion | Made an acceptance gate, not an aspiration — see criterion 3 |
| `gh-pages` branch churn (every PR commits build output) | The branch is disposable build output; history noise there is harmless |
| We now own this code | Accepted deliberately — the alternative was a single-maintainer dependency or a SaaS funnel |
| The two preconditions (`relative_url`, `prefers-reduced-motion`) aren't universal | Audit per component before adoption; both are good practice regardless |

## Success criteria

1. A PR yields a preview URL and a before/after comment within ~2 minutes.
2. The comment's images are legible on a phone, and the preview link opens correctly from a phone.
3. **Two consecutive runs of an unchanged PR produce zero diffs.**
4. A PR touching one page reports exactly that page as changed.
5. Closing the PR removes the preview.
6. The whole pipeline runs with no secrets beyond `GITHUB_TOKEN`.
7. The pattern ports into `templates/components/gh-pages/` with only `baseurl` differing.
