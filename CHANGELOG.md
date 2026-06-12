# Changelog

All notable changes to the yggdrasil workspace and the `ws` CLI are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/) — see [docs/gdd/versioning.md](docs/gdd/versioning.md) for what is versioned (workspace + `ws` CLI together; methodology docs ride along) and how this file is maintained.

This changelog begins at the 1.0.0 GA push. The pre-1.0 history below is a curated reconstruction from the merged-PR record, grouped by theme rather than exhaustively — full detail lives in git history and the design docs under `docs/plans/`.

## [Unreleased]

This section becomes `1.0.0` when every GA blocker in `docs/plans/2026-06-08-gdd-ga-readiness-design.md` is ✅ and the tag is cut.

### Added

- **The `ws` CLI** — unified workspace verbs (`commit`, `push`, `cr`, `issue`, `review`, `test`, `lint`, `log`, `clone`, `clone-fork`, `pull`, `status`, `exec`, `clean`, `diagnose`, `preflight`, `orient`, and friends) with bodyfile-driven commit/CR/issue flows, Co-Authored-By attribution, fork-aware remote selection, and multi-kind target resolution (components, realms, hoards, the workspace itself) via `ws_resolve_target` (#40, #44, #62, #92, #94).
- **Realms and hoards** — community config layer (`realms/`, three-layer ecosystem merge, per-component adapters) and personal containers (`hoards/`, thalami + Obsidian-vault flavors, `ws hoard init/list/scan/cadence/upgrade`) with provenance-tracked, plan/apply/rollback template upgrades (#43, #59, #63, #74–#76).
- **The PreToolUse permission hook** — tiered Bash governance: shell-composition deny, raw-command redirect-to-`ws` with session-scoped human-gated bypass, adapter-aware test/lint redirect, destructive-command ask-tier, settings-allow and per-machine allow-extras; PowerShell matcher coverage (#47, #61, #64, #71, #91, #95).
- **`ws audit-permissions`** — startup allowlist breadth audit with watchlist severities, ws-wrapper normalization scoped to in-repo paths, and per-machine `[audit-acknowledged]` allowances (#94, #96).
- **Orientation and discovery** — `ws orient` (subcommand survey, active realm, adapter wiring, skill index), the gdd-orientation startup skill, post-dispatch discoverability footer, and the `ws:use-when` marker convention (#84, #88–#91).
- **Skills catalog** — workspace skills under `.agent/skills/` (orientation, permissions, scribe, housekeeping, review-triage, mentoring, BDD, zen/quick/flow modes, and more) with the skill→script extraction principle codified (#48, #85).
- **Thalamus system** — per-machine shared thinking files in a thalami hoard, arcs with cross-host stitching, ArcDashboard with filter/sort controls, commit-cadence nudges (#49, #60, #76).
- **Component templates and tutorial** — `ws component init` flavors including the flagship gh-pages scaffold-to-live tutorial and getting-started docs (#45, plus the gh-pages tutorial lineage).
- **Docs site** — `docs/gdd/` methodology pages (features tour, trust and safety, permissions, agent training, organization stack, samples) and the ecosystem/CLI/setup reference docs (#53, #55–#57, #66, #70, #86, #93).

### Changed

- Permission allowlist collapsed from per-arg-count ladders to Claude Code's `:*` prefix form (~200 → ~95 entries), with deliberate pins kept for subcommands whose tightness is intentional (#96).
- `ws review` side-effect forms (`reply`, `threads … --resolve*`) moved behind the hook's ask-tier — outward-facing review actions now always prompt, while read-only triage stays frictionless (#96).
- Resolver renamed `ws_validate_component` → `ws_resolve_target` with a kind-neutral miss-message; `ws diagnose` accepts realm/hoard targets (#94).
- Help handling unified: `--help`/`-h` works at every level for every target-taking subcommand (#94).

### Fixed

- `ws audit-permissions` no longer floods a clean config with false positives (~120 → 0); the genuinely-broad `Bash(ws:*)` catch-all is now detected (#94).
- Audit normalization rejects foreign and traversal paths masquerading as in-repo wrappers (#96).

## Pre-1.0 archaeology

The workspace evolved through roughly five waves, each anchored by design docs in `docs/plans/`: (1) the `ws` CLI extraction and provider abstraction (PRs ≤ #42); (2) realms, hoards, and component templates (#43–#46); (3) permissions, hook tiers, and skill hygiene (#47–#52, #61, #64, #71–#72); (4) the scribe role, vaults, organization stack, and hoard-upgrade machinery (#53–#76); (5) orientation, attribution, and the GA-readiness push (#83–#96).

[Unreleased]: https://github.com/SiliconSaga/yggdrasil/commits/main
