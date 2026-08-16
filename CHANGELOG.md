# Changelog

All notable changes to the yggdrasil workspace and the `ws` CLI are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/) — see [docs/gdd/versioning.md](docs/gdd/versioning.md) for what is versioned (workspace + `ws` CLI together; methodology docs ride along) and how this file is maintained.

This changelog begins at the 1.0.0 GA push. The pre-1.0 history below is a curated reconstruction from the merged-PR record, grouped by theme rather than exhaustively — full detail lives in git history and the design docs under `docs/plans/`.

## [Unreleased]

### Added

- **Headless permission mode for sandboxed sessions** — a session that sets `GDD_SANDBOX=<component>` gets a different Tier 4: an ask has no answerer there, so each `[ask-commands]` match denies instead of prompting, and the new `[headless-allow]` section names the few forms that run without review. Entries are pinned to the sandbox's own component via `__SANDBOX_TARGET__` (a wildcard would also match `ws exec yggdrasil …`, the workspace repo itself) and to named verbs (`ws exec *` or `bundle exec *` would be arbitrary execution). Read from the environment rather than a workspace file, which an agent could write. Tier 2 redirects still apply, so wrapped verbs cannot be reached through it (#158).

## [1.0.0] - 2026-07-21

**Guardian Driven Development reaches General Availability.** This first release versions the reference implementation — the yggdrasil workspace, the `ws` CLI, the skills, and the methodology docs — as one coherent snapshot: Claude-first, with a [published roadmap](docs/gdd/roadmap.md) for cross-harness support and beyond. The gate it cleared is recorded in `docs/plans/2026-06-08-gdd-ga-readiness-design.md`.

### Added

- **The `ws` CLI** — unified workspace verbs (`commit`, `push`, `cr`, `issue`, `review`, `test`, `lint`, `log`, `clone`, `clone-fork`, `pull`, `status`, `exec`, `clean`, `diagnose`, `preflight`, `orient`, and friends) with bodyfile-driven commit/CR/issue flows, Co-Authored-By attribution, fork-aware remote selection, and multi-kind target resolution (components, realms, hoards, the workspace itself) via `ws_resolve_target` (#40, #44, #62, #92, #94).
- **Session-scoped identity and configuration** — commit attribution resolves per session (`ws whoami --set` at orientation, `--co-author-file` for sub-agents, `--human` for humans, hard error over silent mis-attribution), and stance/role/mentoring are established per session via `ws session` instead of Thalamus frontmatter (#100, #103, #107, #111).
- **The `ws k8s` guard** — a kubectl safety scope: arm a context + namespaces and out-of-scope writes are rejected before kubectl runs, with class-aware messages (scope / unbounded / precondition); the hook extends the guard to raw agent `kubectl`, and ambient aggregation covers plain human terminals (#111, #112).
- **Token-injected remote git auth** — `ws push` / `clone` / `clone-fork` / `pull` inject the matching `.env` token per process so HTTPS operations never fall through to OS credential managers; `ws push` pushes tags; `ws gh` / `ws glab` run one-off provider commands with the right token loaded (#100, #106, #112, #116). Requires git ≥ 2.31, now enforced by `ws preflight` — older git silently ignores the env-config injection mechanism and falls through to the OS credential manager after all (caught live on a git 2.28 host during the GA clone-fork e2e).
- **Realms and hoards** — community config layer (`realms/`, three-layer ecosystem merge, per-component adapters) and personal containers (`hoards/`, thalami + Obsidian-vault flavors, `ws hoard init/list/scan/cadence/upgrade`) with provenance-tracked, plan/apply/rollback template upgrades (#43, #59, #63, #74–#76).
- **The PreToolUse permission hook** — tiered Bash governance: shell-composition deny, raw-command redirect-to-`ws` with session-scoped human-gated bypass, adapter-aware test/lint redirect, guarded-kubectl tier, destructive-command ask-tier, settings-allow and per-machine allow-extras; PowerShell matcher coverage (#47, #61, #64, #71, #91, #95, #111, #114).
- **`ws audit-permissions`** — startup allowlist breadth audit with watchlist severities, ws-wrapper normalization scoped to in-repo paths, and per-machine `[audit-acknowledged]` allowances (#94, #96).
- **Orientation and discovery** — `ws orient` (subcommand survey, active realm, adapter wiring, skill index), the gdd-orientation startup skill, post-dispatch discoverability footer, and the `ws:use-when` marker convention (#84, #88–#91).
- **Skills catalog** — workspace skills under `.agent/skills/` (orientation, permissions, scribe, housekeeping, review-triage, mentoring, BDD, zen/quick/flow modes, and more) with the skill→script extraction principle codified (#48, #85).
- **Thalamus system** — per-machine shared thinking files in a thalami hoard, arcs with cross-host stitching, ArcDashboard with filter/sort controls, commit-cadence nudges (#49, #60, #76).
- **Component templates and tutorial** — `ws component init` flavors including the flagship gh-pages scaffold-to-live tutorial and getting-started docs (#45, plus the gh-pages tutorial lineage).
- **Tutorials section + Guarded Kubernetes walkthrough** — chaptered hands-on tutorials under `docs/tutorials/`, opening with the `ws k8s` guard (#113, #115, #119).
- **Docs site** — `docs/gdd/` methodology pages (features tour, trust and safety, permissions, agent training, organization stack, samples, vendor component role) and the ecosystem/CLI/setup reference docs (#53, #55–#57, #66, #70, #86, #93, #99).
- **Versioning machinery** — SemVer policy for the workspace + `ws` CLI, this changelog, and the change-note tooling decision record (#97).
- **Onboarding hardening** — scope-preselected PAT creation links in `ws diagnose` token misses, `ws realm init` fork-and-rename guidance for newcomers, `.env` token-setup docs (#119).
- **Codex harness hooks** — Codex gets focused PreToolUse counterparts to the Claude hook: a Kubernetes-guard hook (#118) and a workflow-redirect hook that reads the same committed `[redirect-commands]` rules — redirect policy is shared platform-neutral data, so adding a rule affects both agents without editing either hook; raw `gh`/`glab` provider commands gained redirect rows in the same pass (#126).
- **`ws k8s` context-only scope mode** — arm just a context with all namespaces in scope, for deep work on a local throwaway cluster where per-namespace scoping is friction without safety (#126).
- **Realm activation trust gate** — `ws realm use` shows a trust summary of what the realm brings (repository hosts, adapter commands, credential-mapping requests, MCP endpoints — with URL credentials redacted and terminal control sequences stripped so the summary can't be spoofed) and requires confirmation; `--trust` covers non-interactive runs and is itself hook ask-gated for agents (#129).
- **Shared Git remote validation** — clone/realm/hoard URL sinks reject option injection, executable remote-helper syntax (`ext::`), control characters, unsupported schemes, and filesystem paths (including Windows drive-letter forms) outside explicit local flows; provider-API-returned clone URLs are pinned to the configured source host (#129).
- **Kustomize local-only preflight** — the k8s guard validates a `-k` target's whole reference graph (resources, bases, patches incl. legacy JSON6902, generators) as local, non-symlinked, and root-contained before rendering (#129).
- MCP endpoint validation at `ws mcp-setup` time: absolute HTTP(S) shape required, plain-HTTP-on-nonlocal-host and embedded-credential warnings (#129).
- **`ws docker` wrapper** — a scoped passthrough that sets `MSYS_NO_PATHCONV=1` for a single docker invocation on Git Bash, replacing the global env toggle that broke every `yq`/`gh` path; `ws` file-path arguments to native CLIs route through `cygpath`, so ws commands survive either MSYS conversion state (#131).
- `ws cr` accepts an explicitly selected non-HEAD source branch — a pushed branch from a linked worktree can open a CR without disturbing the canonical checkout. The local and selected remote-tracking tips must match before any provider call, so a stale same-named remote branch cannot open a review of code other than what the operator selected.
- The published post-1.0 roadmap grew dedicated tracks for assisted access and support (PR previews + visual diffs, chat-channel agents, sanitized release/support records, `ws share` handoffs, guided onboarding) and sandboxed workspaces (containerized, trust-scaled execution).
- Optional shellcheck linting for the workspace's own scripts (#98).

### Changed

- Permission allowlist collapsed from per-arg-count ladders to Claude Code's `:*` prefix form (~200 → ~95 entries), with deliberate pins kept for subcommands whose tightness is intentional (#96).
- `ws review` side-effect forms (`reply`, `threads … --resolve*`) moved behind the hook's ask-tier — outward-facing review actions now always prompt, while read-only triage stays frictionless (#96).
- Resolver renamed `ws_validate_component` → `ws_resolve_target` with a kind-neutral miss-message; `ws diagnose` accepts realm/hoard targets (#94).
- Help handling unified: `--help`/`-h` works at every level for every target-taking subcommand (#94).
- `ws exec` is ask-gated — every invocation requires human approval, with the trust model documented (#110).
- `git mv` redirects to the plain-`mv` + bodyfile pattern, which keeps `ws commit`'s declared staging intact (#114).
- `docs/dev-setup.md` renamed to `docs/workspace-setup.md` with an onboarding front-door polish pass (#109).
- Hard-wrapped prose de-wrapped workspace-wide per the single-line-paragraph convention (#104).
- Methodology docs consistency pass — the "good-enough" posture named as a first-class design statement, hook-doc altitude dedup, skills-reference taxonomy fix, link-shape cleanups (#120).
- `ws realm use` without `--trust` now presents the review as step one of the designed two-step activation flow — summary shown, nothing activated, exact re-run command named — instead of a bare error.
- Newcomer-language pass from fresh-laptop GA testing: the canonical Guardian Driven Development expansion + mutual-guardianship framing at agent eye-level (AGENTS.md, docs index, orientation greeting), Newcomer language rules in the orientation skill (primer before plumbing, "we" not "you", realms introduced as the augment layer, narrow diagrams, roles equip the session), the adapter-in-realm rationale, and a sharpened Thalamus pitch; six further findings recorded as roadmap entries.
- **Realm auto-detection removed** — with no `realm:` selector in `ecosystem.local.yaml`, no realm is active, including the upstream `realm-template`. Existing workspaces that relied on an implicitly selected realm should run `ws realm use <name>` once (#129, #130).
- The permission hook anchors all policy (rules files, allowlists, scratch and sensitive paths) to the workspace root instead of walking up from the command cwd; `Edit`/`Write` route through the hook, and security-sensitive state (`.claude/`, `.env`, `ecosystem.local.yaml`, hook-bypass markers, agent session files) asks instead of inheriting the scratch auto-allow (#129).
- Hoard templates require an immutable full-SHA `pin` (checked out detached), and hoard-upgrade manifests are validated against traversal and symlink escapes before any file operation (#129).
- `ws session set` accepts only the public stance/role/mentoring keys — guard and identity keys route through `ws k8s scope` and `ws whoami` (#129).
- `ws realm use` labels component repository routes and indents adapter verbs more clearly; explicit `(none declared)` rows stay visible as evidence on the trust surface (#131).
- `ws clone --add-to-ecosystem` is the canonical adoption spelling (`--add-eco` remains a compatibility alias), and adopted local source paths record in a pinned native form rather than whatever MSYS environment conversion produced (#131, #133).
- The hook's backslash fail-closed ask normalizes fully quoted drive-letter path tokens (`"D:\dir\file"`) to forward slashes before classification, so valid Windows path-bearing commands reach the allowlist instead of always asking; bare and otherwise ambiguous escape shapes still ask (#133).
- Session env files under `.tmp/gdd-agent-sessions/`: a full-file `Write` creating a new `<name>.env` identity file, or replacing the current session's own `<sid>.env`, rides the scratch auto-allow when no guard-scope key is introduced; partial edits and overwrites of another session's existing file still ask (#133).

### Removed

- The unused `ws resolve` ArgoCD manifest generator — deploy trees belong to stacks/realms, not the GDD framework (#105).
- The initial-commit `roadmap-schema.yaml` fossil at the workspace root — a pre-ecosystem phase sketch nothing referenced; the real roadmap is `docs/gdd/roadmap.md`.

### Fixed

- `ws audit-permissions` no longer floods a clean config with false positives (~120 → 0); the genuinely-broad `Bash(ws:*)` catch-all is now detected (#94).
- Audit normalization rejects foreign and traversal paths masquerading as in-repo wrappers (#96).
- GitLab MR creation pins the source project explicitly instead of relying on `glab` inference (#102).
- Provider auth checks are per-host, so an unrelated stale host in `glab`'s config no longer blocks every GitLab operation (#116).
- Empty auth-env arrays no longer crash `ws` under macOS's bash 3.2 with `set -u` (#119).
- `ws review --since prev-push` paginates the push-events lookup and recovers a missing previous push event, so the since-filter resolves on busy repos (#121).
- `ws clone-fork` works against GitHub sources: provider-aware fork lookup/creation (`gh repo fork`, org-vs-user aware) and a GitHub fork-helper URL instead of the GitLab-only API/UI path; token resolution falls back to the provider default (`GH_TOKEN`/`GITLAB_TOKEN`) on the canonical hosts like `ws push` does; provider-token names gain `GITHUB_*`/`GH_*` namespacing to match `GITLAB_*` (#122).
- `ws gitlab-auth --help` prints help even when `GITLAB_HOST` is unset (#122).
- `ws status` / `ws pull` / `ws vscode` no longer surface a yq `cannot get keys of !!null` error on a workspace with no components declared — the first-run papercut from the fresh-Win11 dogfood runs.
- Hoard rollback selects the newest pre-upgrade snapshot by timestamp across mixed legacy/sequenced backup formats — a same-second legacy suffix no longer shadows a newer sequenced snapshot on the restore path (#131).
- `ws k8s` distinguishes a failed live namespace verification from a verified-absent namespace when arming a scope (#131).
- The full bats suite passes on Windows Git Bash — dropped a ripgrep test dependency and pinned platform-dependent path forms; first fully-green Windows run (#133).
- The Kubernetes write floor no longer asks on `bash -n` syntax checks of kubectl-bearing scripts — parse-only invocations are not script runs (#133).
- Bare `ws <subcommand> --help` / `-h` invocations no longer trip the hook's ask-list — help-only forms print and exit before any subcommand logic, so they allow; a `--help` passed through to a wrapped command keeps its ask.
- The gh-pages template's title placeholder no longer disappears in rendered HTML — browsers swallowed the angle-bracket form as an unknown tag, leaving a bare `'s page` in the tab; the scaffold now ships a visible `Your Name's page`.
- GitLab default-branch lookups during CR creation surface API failures as errors instead of continuing with a `null` or guessed target branch.

### Security

- MCP configuration writes (`ws mcp-setup`) are human-gated instead of auto-approvable (#121).
- Workspace credentials load as literal data rather than shell-evaluated content, and small `ws` input-validation edges were tightened (#121).
- Credential routing reads only the committed workspace config plus `ecosystem.local.yaml` — a realm's `defaults.gitTokens` entries can no longer attach the operator's tokens (#129).
- `.env` loading refuses Git execution and configuration variables (`GIT_CONFIG*`, `GIT_SSH*`, askpass/editor/pager vars, the `GIT_DIR` family) plus `HOME`/`CDPATH` (#129).
- Git execution modifiers (`-c`, `--ext-diff`, `--upload-pack`, remote-helper transports) deny ahead of permission matching, and `ws audit-permissions` flags allowlist entries that would cover them as high severity (#129).
- Hook path comparisons normalize Windows path forms (via `cygpath` on Git Bash) before matching — previously an anchored prefix check could silently never match payload paths on Windows, failing open to passthrough (#129).
- Realm approval binds to a semantic fingerprint of the realm's executable surfaces (ecosystem routing + adapter commands) and fails closed when approved semantics change — reapproval prompts show what changed; adding a clone to the trusted ecosystem is human-gated (#130).
- Provider credentials stay scoped to their matching authority; explicit credential rejection is distinguished from transport and indeterminate failures, with redacted diagnostics (#130).
- `.env` parsing hardened — inline comments read literally, reserved-variable protection extended to the workspace-path globals — and hoard-upgrade state and review-history timestamps are validated against malformed or attacker-controlled input (#130).
- Escape sequences are excluded from allow-pattern matching so a transformed command cannot reach the wrong permission tier; sensitive-path, scratch-state, and multiline/compound matching tightened, and unsafe cross-host fork PR creation is blocked (#131).

## Pre-1.0 archaeology

The workspace evolved through roughly five waves, each anchored by design docs in `docs/plans/`: (1) the `ws` CLI extraction and provider abstraction (PRs ≤ #42); (2) realms, hoards, and component templates (#43–#46); (3) permissions, hook tiers, and skill hygiene (#47–#52, #61, #64, #71–#72); (4) the scribe role, vaults, organization stack, and hoard-upgrade machinery (#53–#76); (5) orientation, attribution, and the GA-readiness push (#83–#96).

[Unreleased]: https://github.com/SiliconSaga/yggdrasil/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/SiliconSaga/yggdrasil/releases/tag/v1.0.0
