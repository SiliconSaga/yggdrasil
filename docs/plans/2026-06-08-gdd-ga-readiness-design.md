# GDD General Availability (1.0.0) Readiness — Design

**Date:** 2026-06-08
**Status:** Design (consolidation + roadmap — items tracked individually below)
**Related:** `2026-06-02-gdd-orientation-and-attribution-design.md` (the orientation/capability lineage this builds on), `2026-05-19-organization-stack-design.md`, `2026-05-07-thalamus-arc-dashboard-design.md`, `docs/gdd/index.md` (§ Calibrated Autonomy — the public-facing thesis).

---

## Purpose

This document consolidates the scattered "is GDD polished enough to go public?" threads into a single tracked punch-list. Those threads accumulated across four host Thalami (`Dionysus`, `FG4WWY622F`, `Loki`, `rasmuss-mbp-2`) — often the *same* friction recorded independently on multiple hosts. The goal is one canonical place to see what stands between today and a defensible **1.0.0**, so individual Thalami can stop re-tracking (and re-duplicating) these items and instead mark progress against the stable IDs here.

Each work item has a stable ID (`B*` blocker, `P*` polish, `R*` roadmap), a status checkbox, the evidence that motivated it (with the originating Thalamus and, where verified, a `file:line`), and a recommended approach. A Thalamus arc's `next:` can reference an ID (e.g. "GA `B1` done") rather than restating the work.

The **Source Ledger** at the end records exactly which Thalamus observations were folded into this doc and removed from their files, so the trail isn't lost.

---

## What "1.0.0" means

GDD is **Claude-first with a published roadmap.** The author runs multiple workspaces and will make parallel progress on the cross-harness "bonus" tracks (Codex is already active on the FG4 workspace; Gemini/Antigravity are on the radar), so the roadmap items must have **clear, designed paths** even though they don't gate 1.0.

The 1.0 line, stated as a promise to a stranger:

> *A newcomer can clone yggdrasil on a fresh Windows or Mac, get oriented, run the tutorial end-to-end, and the `ws` CLI behaves consistently across components, realms, and hoards — with Claude as the supported agent and multi-agent + team collaboration on a documented roadmap.*

GDD is a **methodology plus a reference implementation** (the yggdrasil workspace + the `ws` CLI + the skills). 1.0.0 versions the *reference implementation*; the methodology docs are versioned alongside it. Realm and component repos keep their own independent versioning.

What is explicitly **not** required for 1.0: multi-agent parity, the Team Thalami collaboration model, a flagship blog, or the deep-future infrastructure ideas. Those are the roadmap (`R*`).

---

## GA gate — Definition of Done

1.0.0 ships when every `B*` blocker is ✅ and the `P*` polish items have been swept (or explicitly deferred with a one-line reason in the Source Ledger). Concretely:

| Gate | Item | Why it gates GA |
|---|---|---|
| CLI consistency | `B1` | The most-repeated friction in the corpus; a public user will hit it immediately |
| Cross-platform | `B2` | The "clone and go" promise is unproven off the author's primary host |
| Clean first session | `B3` | A broken/noisy startup ceremony is the first thing a newcomer sees |
| Coherent surface | `B4` | Inconsistent `--help` and broken doc cross-refs read as "unfinished" |
| Front door | `B5` | The tutorial + adoption story is what strangers actually touch first |
| Release machinery | `B6` | "1.0.0" is meaningless without SemVer + a changelog |
| No hidden disables | `B7` | A silently-gated-off command is a bad GA surprise |

---

## GA Blockers (`B*`)

### B1 — Target-kind generalization — ✅ Done

**Status update (2026-06-11):** residual landed via `docs/plans/2026-06-10-gdd-ga-cleanups-plan.md`: `ws diagnose` routed through the shared resolver (with realm/hoard targets and a graceful path for repo-less component declarations), the miss-message is kind-neutral ("no such target … looked for a component, realm, or hoard"), the AGENTS.md/CLAUDE.md doc note is in, and the rename `ws_validate_component` → `ws_resolve_target` shipped clean (no alias) across scripts, tests, and the CLI guide.

**Status update (2026-06-09):** The core gap is closed. The original framing ("no shared resolver exists; build `ws_resolve_target`") was wrong — a shared multi-kind resolver **already exists**: `ws_validate_component()` in `scripts/ws-realm.sh:48` resolves `yggdrasil` (workspace root), realm dirs, hoard dirs, and ecosystem components, setting `COMPONENT_DIR`. It's just **misnamed** (the "component" name hides that it handles all four kinds). Most target-taking subcommands already route through it — `ws commit`, `push`, `cr`, `log`, `issue`, `exec`, `test`, `lint`, `pull`. `ws review` was the notable holdout (the one realm-siliconsaga #9 / FG4 actually hit), and **PR #92 fixed it** by swapping the hardcoded `components/$COMP` for `ws_validate_component` + a worktree-safe `git rev-parse --is-inside-work-tree` guard. So `ws review <realm>` / `<hoard>` now works (the coincidental cross-workspace fix the author noticed).

**Evidence the gap is now closed:**
- PR #92 (`fix(ws-review): resolve realm/hoard targets via ws_validate_component` + `guard non-git target dirs`) — verified diff routes `scripts/ws-review.sh` through the shared resolver.
- `scripts/ws-realm.sh:48-103` — `ws_validate_component` resolves yggdrasil/realm/hoard/component; `scripts/ws` calls it for exec/push/cr/log/issue; `scripts/ws-commit.sh`/`scripts/ws-test.sh`/`scripts/ws-lint.sh`/`scripts/ws-pull.sh` call it directly — verified 2026-06-09.

**Residual (small, polish — no longer a GA-critical blocker):**
- **`ws diagnose`** (`scripts/ws:434`) is the remaining holdout — it special-cases `yggdrasil` and otherwise assumes a `components/` ecosystem entry, so `ws diagnose <realm|hoard>` doesn't resolve. Route it through `ws_validate_component` too (lower value — diagnose is push/cr token-coverage, component-centric).
- **Rename + unified error:** rename `ws_validate_component` → `ws_resolve_target` (or similar) so the name reflects what it does, and emit a single "no such component, realm, or hoard" miss-message instead of the current component-flavored branches ("not declared in ecosystem config" / "Invalid component name"). Cosmetic-but-clarifying; the FG4 note specifically wanted the clearer error.
- **Doc note:** add a line to `AGENTS.md` / `CLAUDE.md` "Workspace CLI" section that target-taking subcommands accept realm and hoard names (would have prevented the original wrong-turn).
- **`ws run`** (`R6`) reuses this same helper for hoard/realm targets.

**Effort:** Small residual. The load-bearing fix already shipped; reprioritize — `B2`/`B3` now outrank this.

### B2 — Cross-platform validation runs — ✅ Done (Mac column deferred by explicit scope call)

**Status update (2026-07-21):** the gate is met on deliberately-narrowed scope. Windows is validated three ways — the author's daily driver, the guided Nano76Win11 dogfood arc, and a one-shot newcomer run on a second clean Windows laptop (2026-07-21, findings fixed or roadmapped the same week). The live clone-fork e2e passed against BOTH real providers (GitHub from the clean laptop; GitLab from Dionysus — which also caught and fixed the git ≥ 2.31 token-injection floor, now a `ws preflight` check). The **old/minimal-Mac column is deferred post-GA by owner decision (2026-07-21)**: its known risk items (bash 3.2 `mapfile`/`set -u`, brew hints) were already found and fixed via earlier Mac usage (#119), Idunn runs the workspace daily on macOS, and a fresh-Mac newcomer run slots naturally into the roadmap's continuous onboarding re-testing.

**Status update (2026-07-09):** the Windows column has real coverage now: `Nano76Win11` (fresh Win11, no tooling) was dogfooded from bare machine through the gh-pages path — including a real production build (the "Local political site" case study in `docs/gdd/case-studies.md`) — and its findings fed straight back: `ws orient` self-diagnoses missing prereqs by running `ws preflight` for you, the onboarding docs stopped asserting PATH state and instruct making-it-so instead, auth was deliberately classified as deferred-to-first-remote-action rather than a preflight gate, and the bash-3.2 `set -u` crash fell out via #119. Residual papercuts from those runs are tracked as `P8`. **Remaining for the gate:** a one-shot newcomer run on a second clean Windows machine including the gh-pages tutorial (planned — the Nano76 runs were guided, not one-shot), which also covers the `B5` tutorial re-test; the Mac column has had no fresh-clone run recorded (`Idunn` — the host formerly named `rasmuss-mbp-2` — is the candidate).

The "git clone and go" promise is validated almost entirely on the author's primary host (`Dionysus`, Win10 Pro, all prereqs pre-installed). Real confidence requires exercising the bootstrap path on systems that mirror what a fresh user actually has.

**Evidence:**
- Dionysus "Testing checklist (multi-platform, post-PR-49)" — the detailed run plan, reproduced below as the canonical checklist.
- Loki bootstrap-drift observation (2026-05-20): three independent `bootstrap.sh` bugs surfaced on one fresh-cluster rebuild because "rare path" code only gets re-validated on a ground-up run. The generalized lesson — rare-path code rots silently — applies directly to the newcomer bootstrap path.
- The author has "a couple untouched systems I could set up as a trial."

**The two target environments:**

**Clean Windows** (no yggdrasil tooling yet, possibly locked-down corp profile):
- [ ] Bootstrap: install Git for Windows (accept "add Git to PATH"), open Git Bash, confirm `bash --version` / `git --version`.
- [ ] `git clone … && cd yggdrasil`.
- [ ] `bash scripts/ws preflight` — confirm winget hints are correct on current Windows, and the chocolatey-elevated-shell fallback is accurate for older/locked-down SKUs (Win10 LTSC / no-winget is the right edge case).
- [ ] Install missing tools per hints, re-run preflight to clean.
- [ ] Add `scripts/` to PATH per `dev-setup.md`, reload, `ws help`.
- [ ] `ws hoard init` — scaffolding on Windows FS (esp. dot-prefixed `.ws-cadence.yaml`).
- [ ] `ws hoard thalamus-path` / `ws hoard cadence` — path contains sanitized hostname (no spaces/colons), cadence reports `clean` immediately after init.
- [ ] `ws component init gh-pages my-page` — full tutorial Ch 1; placeholder cleanup, `gh repo create`, Pages enable via `gh api` on Git Bash (MSYS path conversion).
- [ ] Ch 2: install CodeRabbit, push a follow-up PR, `ws review`.

**Old / minimal Mac** (older macOS, bash 3.2, maybe no brew):
- [ ] Prereq audit: `bash --version` (likely 3.2 — check whether bash-4 features trip; `rasmuss-mbp-2` hit `mapfile` in `git-push.sh`/`git-cr.sh`, fixed by `brew install bash`).
- [ ] `bash scripts/ws preflight` — the high-value test; surfaces missing yq/jq/gh and possibly bash-4. Confirm brew hints and the `realpath` `$(brew --prefix coreutils)` hint resolve.
- [ ] `brew install bash yq jq gh`, retry preflight.
- [ ] Add `scripts/` to PATH; confirm bare `ws`.
- [ ] Hoards setup + tutorial Ch 1 + Ch 2.
- [ ] Multi-machine sync: clone the thalami hoard from its remote, confirm per-machine file detection picks the right hostname, `ws hoard cadence` reports fresh (not another machine's dirty), then exercise the edit→commit→push→pull rebase flow.

**Cross-cutting checks (either OS):**
- [ ] Hostname sanitization for non-trivial hostnames (spaces/colons/weird chars) → well-formed per-machine thalamus filename.
- [ ] `ws hoard thalamus-path` without yq (rename yq temporarily) — confirm the PR #49 exemption holds empirically.
- [ ] `ws preflight --notarealflag` exits nonzero with a clear error, not silent defaults.
- [ ] Help system: `ws help <cmd>`, `ws <cmd> --help`, `ws <cmd> <comp> --help` all work uniformly across 5–6 subcommands (see `B4` — at least `ws issue --help` is currently broken).
- [ ] Permission prompts during orientation and the tutorial — capture the exact command shape of any unexpected prompt (see `B3`, `P2`).
- [ ] gh-pages tutorial auth wrinkle: if `.env` uses an agent-account PAT, confirm the Ch 1 "use a personal PAT" recovery path and that Ch 2 doesn't trap the user on an agent-namespace repo.

**Approach:** Treat each trial system as a one-shot newcomer simulation; file findings as issues, fix, re-run. This is as much a GA *gate* as a feature — the promise is unproven until it runs green on a non-author machine.

### B3 — `ws audit-permissions` de-noise — ✅ Done

**Status update (2026-06-11):** landed via the GA-cleanups batch, TDD'd. The matcher now normalizes the ws-wrapper form (`bash [<path>/]scripts/ws …` → `ws …`) before watchlist comparison — mirroring the PreToolUse hook — so narrow per-subcommand allows no longer trip `Bash(bash *)`; a new high-severity `Bash(ws:*)` entry catches the genuinely-broad subcommand-less catch-all in both bare and wrapper forms. A clean config went from ~120 findings to 0–1. Follow-on: the vendored bats runner (`bash tests/vendor/bats-core/bin/bats tests/…`) is now allowlisted scoped to `tests/`, with matching normalization so the entries don't self-flag (a non-`tests/` target still flags). This unblocks `P3`/`P4` as predicted.

`ws audit-permissions` runs at orientation (the startup ceremony) and currently floods a *clean* config with ~120 false-positive "high — wildcards out the hook" findings, exiting nonzero. This is the first thing a newcomer's first session surfaces.

**Evidence:**
- Reproduced live 2026-06-08: exit 134, ~120 findings, every one a narrow literal like `Bash(bash scripts/ws help)` flagged because it glob-matches a broad `Bash(bash *)` watchlist entry.
- Dionysus observation ("ws audit-permissions over-matches narrow allows"): the matcher tests "does the allow string glob-match a broad watchlist pattern," which flags narrow exact allows; it should instead flag allows whose *own* wildcard placement makes them broad (e.g. `*` immediately after `bash `/`ws exec `).
- FG4 "Non-agent-specific workspace observations from Codex orientation": the hook normalizes `bash scripts/ws` → `ws`; the audit needs the same normalization/exception before it's useful at orientation time.

**Approach:** Rewrite the matcher to flag broad *wildcard placement* in the allow itself, not glob-coincidence with a broad watchlist entry; apply the same `bash scripts/ws` → `ws` normalization the hook uses. Security-sensitive matcher logic → TDD (RED first: a clean settings.json must yield zero findings). This also unblocks the `P3` auto-approve narrowings and the `P4` ladder collapse, which the current over-matcher would otherwise flag.

### B4 — Help-system uniformity + doc anchor/reference sweep — ✅ Done

**Status update (2026-06-11):** `ws issue`, `ws cr`, `ws exec`, and `ws diagnose` gained the `--help`/`-h` detection their siblings had (`ws exec` checks position 1 only so wrapped-command flags pass through); smoke tests pin all of them. The anchor sweep checked every "see X above/below" reference under `.agent/skills/` + `docs/` against its file's actual headings — exactly one was stale (gdd-scribe's "PARA Structure" → "PARA Conventions"), now fixed.

Two coherence gaps that read as "unfinished" to a public reader.

**Evidence (help):**
- `ws issue --help` exits 1 with a terse `Usage:` line instead of the rich `--help` other subcommands emit — verified 2026-06-08. The Dionysus "Random" note flagged exactly this ("Does `ws issue --help` not work? I thought we caught `ws command help` and `ws command --help` everywhere").

**Evidence (docs):**
- Dionysus "Random": `.agent/skills/scribe/SKILL.md` says "see PARA Structure above" but the section is "PARA Conventions" — section headers were hand-edited without updating pointers. Needs an anchor-vs-reference consistency pass across docs + skills.

**Approach:** Sweep every `ws` verb for uniform `--help` handling (treat `--help`/`-h` as a help request at every level, never as a malformed invocation). Separately, grep docs + skills for "see <X> above/below" style internal references and reconcile each against its actual current heading.

### B5 — Tutorial + newcomer front door + adoption section — 🟡 Mostly done

**Status update (2026-07-09):** the doc-side gaps below closed via #109 (workspace-setup front-door polish), #119 (onboarding hardening: PAT-creation links, realm fork-and-rename guidance, `.env` token docs), and #120 (consistency pass): `docs/getting-started/index.md` now uses the full `bash scripts/ws` form deliberately in the pre-PATH steps and says so; the "Bringing GDD to Your Own Community" / "How adoption works" section describes the three-layer bootstrap as implemented (the *"details will evolve"* caveat is gone); and the gh-pages production path has published proof (`docs/gdd/case-studies.md`, "Local political site for a non-technical owner"). **Remaining:** the end-to-end fresh-clone tutorial re-test validating the ~15-min scaffold-to-live claim — this rides the `B2` second-Windows-machine run. Mermaid diagrams and additional template flavors stay roadmap.

The tutorial is the literal front door for a public launch, and the `tutorial-next-pass` arc (Dionysus, active) is untouched. Known gaps already captured:

**Evidence (Dionysus "Tutorial next pass"):**
- End-to-end fresh-clone re-run of the gh-pages tutorial to validate the ~15-min scaffold-to-live claim and catch stale steps (overlaps `B2`).
- `docs/getting-started/index.md` still uses `bash scripts/ws` in steps 1 + 5 even though step 4 puts `ws` on PATH; clone/PATH ordering reads awkwardly.
- "Bringing GDD to Your Own Community" / "How adoption works" is still marked *"Initial design — details will evolve!"* — but the realm + three-layer bootstrap is implemented now, so it can become concrete. **This is the bridge from "it works for the author" to "others can adopt it" and is the most GA-load-bearing piece of the front door.**
- "Template" vs "tutorial" vocabulary made explicit (a *template* is a forkable scaffold; a *tutorial* is an instantiated component to play with).
- Mentoring-mode refresh so the tutorial path is its natural entry point (partially addressed by yggdrasil #91; double-check in this pass).
- Mermaid diagrams for `ecosystem-architecture.md` / `getting-started/`.
- **Additional template flavors** beyond gh-pages (lets testers flip between flavors across sessions, exercising the hoard-thalami sync): local frontend (vanilla JS), local backend (Java-Gradle / Python / Go / Node where adapters exist), full-stack mini (frontend + backend + sqlite), template MCP server (leverages realm-level `mcp.servers`). Roadmap-adjacent — a richer tutorial benefits from ≥2 flavors, but gh-pages alone clears the GA bar.
- **Scaffolding-system integration** (far-future, `R6`-adjacent): Backstage software-templates / CookieCutter back `ws component init` more richly than `cp -R`; ties to the Backstage-visualization thread and the `ws hoard upgrade` "extend beyond contiguous managed-regions" work (yggdrasil issue #77). Not GA.

**Approach:** Run the tutorial pass as its own arc (it already is). Prioritize the adoption section (concrete realm bootstrap walkthrough) and the getting-started `ws`-vs-`bash scripts/ws` consistency, since those are what a public reader trips on first.

### B6 — SemVer + CHANGELOG + release notes — ✅ Machinery in place (tag pending the gate)

**Status update (2026-06-11):** versioning unit decided per the recommendation below — workspace + `ws` CLI version together under SemVer, methodology docs ride along, realm/component/hoard-template versioning stays independent. Root `CHANGELOG.md` seeded (Keep a Changelog; `[Unreleased]` becomes `1.0.0` at tag time; curated pre-1.0 archaeology grouped by wave). `docs/gdd/versioning.md` carries the policy, the release ceremony, and the change-note tooling decision record: conventional-commit subjects (already the `ws commit` convention) as the input, git-cliff as the optional no-Node drafting tool, GitHub auto-generated release notes as a per-repo complement, semantic-release/release-please explicitly not adopted. The Terasology-style aggregation problem (engine + modules → one release note; here, the SiliconSaga stack) is parked as a future ecosystem-manifest-driven `ws changelog` verb — recorded in the doc and `R6`. Remaining: the `ws version` subcommand stays optional; cut the `1.0.0` tag when all B* are ✅.

"1.0.0" requires the machinery to make a version mean something. None exists today.

**Evidence:** No `CHANGELOG`/`VERSION`/`CHANGES` at the workspace root — verified 2026-06-08 (only vendored `node_modules` changelogs inside components). The author flagged this as a known GA TODO.

**Approach:** Decide the versioning unit (recommendation: version the yggdrasil workspace + `ws` CLI together under SemVer; methodology docs ride along; realm/component repos keep their own). Add a root `CHANGELOG.md` (Keep-a-Changelog format), seed it with a curated history reconstructed from the merged-PR record, and tag `1.0.0` when the gate is met. Add a short "Versioning & Releases" doc (or section in `docs/gdd/`) stating the policy. Optionally a `ws version` subcommand surfacing the workspace version + active realm.

### B7 — Confirm `ws hoard upgrade` is re-enabled — ✅ Done

**Status update (2026-06-11):** confirmed — no `WS_HOARD_UPGRADE_ENABLED` reference remains anywhere under `scripts/`, and `ws hoard upgrade --help` prints the full `--plan`/`--apply`/`--rollback` usage with exit 0. The gate was lifted by the hoard-upgrade-v2 work (PRs #74-76) as expected; the disable observation was stale. No code change needed.

A command that's secretly gated off is a bad GA surprise.

**Evidence:** Dionysus observation (2026-05-22): `ws hoard upgrade` was disabled behind `WS_HOARD_UPGRADE_ENABLED=1` (default off) pending a provenance fix. The `hoard-upgrade-v2` arc (PRs #74-76) shipped provenance (`.hoard.yaml`) *after* that note, and was meant to lift the gate — so the disable observation is likely stale.

**Approach:** 30-second confirm that the public `ws hoard upgrade` path is enabled (gate lifted) post-v2; if still gated, lift it. Trivial verify; included so it isn't forgotten.

---

## GA Polish (`P*`)

Smaller papercuts to sweep before (or alongside) the blockers. None individually gates GA, but collectively they're the difference between "rough" and "polished."

### P1 — `ws resolve` ↔ `ws review --resolve` naming collision — ✅ (resolved by removal)
Loki observation (2026-03-23): `ws resolve` (ArgoCD manifest generation) collides conceptually with `ws review … --resolve` (review-thread resolution). Resolved not by renaming but by **removing** `ws resolve` entirely — it was early-design, unused (real stacks deploy from their own hand-authored app-of-apps), and infra-specific rather than GDD-core. The generator theory + a future-redo vision moved to a realm/stack issue (SiliconSaga/realm-siliconsaga#17). The collision is gone because only `--resolve` remains.

### P2 — Absolute-path / `git -C` allowlist escapes — ⬜
Recorded on two hosts (`rasmuss-mbp-2` small observations; Loki Permissions/Hooks). Commands invoked via absolute paths or `git -C <path>` narrowly escape the `settings.json` allowlist and prompt unexpectedly (e.g. `git -C hoards/thalami-Cervator status -s`; `bash /abs/path/scripts/ws list`). Suggested fix (Loki): a hook that pushes back on absolute paths for known/common commands, nudging toward the workspace-relative form. Reduces random mid-session prompt noise — a real "feels flaky" signal for testers.

### P3 — Build-tool permission-prompt noise / curated default allowlist — ⬜
Loki phone-RC observation: following Bifrost work, *every* vanilla Gradle/build invocation prompted — pure noise when build commands are the core of the task and the blast radius is minimal. A curated default allowlist for common build/test tooling (Gradle lookups, etc.) would cut the noise; pairs with the `fewer-permission-prompts` Claude-native tooling. Weigh against the "don't auto-approve a build system that can run arbitrary commands" caution.

### P4 — Collapse redundant permission ladders to `:*` — ✅ Done
`rasmuss-mbp-2` observation (from PR #84): Claude Code's colon form `Bash(<cmd>:*)` matches command + all trailing args in one entry, making the older per-arg-count `Bash(ws test *)` / `* *` / `* * *` ladders redundant. Collapse the always-trusted `ws` subcommand ladders to a single `:*` each, guarded by `tests/ws-audit-permissions` and a scan that nothing relies on the tighter single-token binding (a subcommand with a mutating flag-form you *don't* want unbounded is the counter-case). Gated behind `B3` (the audit matcher must stop over-flagging first).

**Status update (2026-06-11):** landed post-B3. ~200 entries → ~95; help/status/pull/diagnose/actions/hoard-init/component-init/test/lint/review/log collapsed in both dispatch forms; preflight, cadence/thalamus-path, realm, clone, and the exact-form git entries stay pinned on purpose. The counter-case scan found one real instance: `ws review`'s side-effect forms (`reply`, `threads … --resolve*`) — and the old ladder's protection there was illusory anyway (the hook's glob matching let them auto-approve). They're now on the committed `[ask-commands]` list, which runs before the allow tier, so the collapse net-tightened. Empirical-table rows updated per the cross-reference rule.

### P5 — Co-Authored-By model attribution — ✅ Addressed (verify-only)
**Status update (2026-07-15):** session-scoped identity superseded the interim `.env` / `CLAUDE_MODEL` approach. A main agent establishes its identity during orientation with `ws whoami --set <name> <email>`, which writes the active session file consumed by `ws commit`. A sub-agent writes its own named co-author file under `.tmp/gdd-agent-sessions/` and commits with `ws commit --co-author-file <name> …`, avoiding shared-state races. The session identity tests cover precedence, missing-state failures, shell-significant data, and main/sub-agent resolution. Treat as done; no GA work remains.

### P6 — `ws issue` bodyfile frontmatter + identity enforcement — ⬜
Dionysus "Onboarding and identity": `ws issue` should accept a bodyfile with YAML frontmatter carrying title/label/component (mirroring commit bodyfiles); declare expected labels per component in ecosystem config and validate; enforce `identity.human_account` in provider-facing commands. Ties into `B4` (the `ws issue --help` gap) and the onboarding story. The broader "setup wizard during orientation / `ws overlay init`" piece is roadmap (`R6`). Tracked as issue #124 (post-GA).

### P7 — Bulk-resolve review threads (`ws review … --reply-from`) — ⬜
Dionysus + FG4: the `ws review <comp> reply <thread-id> "<msg>" --resolve` pattern recurs enough to script. Add `.reviews/` as the conventional drafts dir + a `--bodyfile`/`--reply-from` flag taking a YAML map of thread-id → reply → resolve (keep the positional one-liner form). FG4 hit this needing multi-paragraph markdown replies; Loki worked around it with a one-off script. Quality-of-life, not a gate. Tracked as issue #125 (post-GA).

### P8 — Fresh-machine first-run papercuts (Nano76Win11 dogfood) — ✅ Done
Residual findings from the `B2` fresh-Win11 dogfood runs (2026-06-21 → 2026-07-03):
1. ✅ **`ws status` errors on a components-less workspace** — with no components cloned it printed the yggdrasil + hoard lines but also emitted `Error: cannot get keys of !!null, keys only works for maps and arrays` from an unguarded `yq '.components | keys'` walk. Fixed (2026-07-10, TDD'd) with a `// {}` guard — the same unguarded pattern turned out to live in `ws pull` and `ws vscode`, fixed alike; `ws list` / `ws clone --all` were already safe behind a `length` pre-check, now pinned by a test.
2. ✅ **IDE holds stale PATH** — after a winget/brew tool install, a terminal restart isn't always enough; editors capture PATH at launch and need a full IDE restart. Documented in `docs/workspace-setup.md` (this pass).
3. ✅ **gh-pages local-preview prereqs undocumented** — local Jekyll preview needs Ruby + Bundler + Jekyll, which `ws preflight` deliberately doesn't check (it's a per-template need, not a workspace prereq). Documented in the gh-pages template README, including the `wdm`-gem-won't-compile-on-Ruby-3.3+ gotcha (this pass).

Two open *decisions* from the same runs were dispositioned 2026-07-09 rather than left pending: the canonical-allowlist-location question (`.claude/settings.json` vs an agent-agnostic `.agent/` source) is **deferred post-GA as issue #127** — GA ships `.claude/settings.json` as the committed Claude allowlist; and Codex onboarding guidance gets a **`CODEX.md` sibling to `CLAUDE.md`** when written (AGENTS.md stays agent-agnostic) — recorded in `docs/gdd/roadmap.md`.

---

## Roadmap (`R*`) — post-1.0, paths kept clear

These do **not** gate 1.0 but must have designed paths, since the author makes parallel progress on them across workspaces. Each is a pointer to where the real design lives plus the GA-relevant summary.

### R1 — Cross-harness compatibility (Codex / Gemini / Antigravity) — 🟡 In progress (mainline + FG4)

**Status update (2026-07-09):** this track jumped ahead of its own plan, on mainline: #118 shipped a focused Codex PreToolUse hook for the `ws k8s` guard, and #126 shipped a focused Codex redirect hook that reads the committed `[redirect-commands]` rules directly — so the "hook platform-split" piece below has its first live slice (redirect policy is platform-neutral data; both agents consume it without either hook being edited). The hook-v3 extensions bullet graduated to issue #123. Two placement decisions landed 2026-07-09: Codex onboarding guidance goes in a `CODEX.md` sibling to `CLAUDE.md` when written (AGENTS.md stays agent-agnostic), and the agent-agnostic *allowlist* source question is deferred post-GA as issue #127.

The biggest "bonus" track. Codex compatibility is actively in progress on the FG4 workspace. The designed path (FG4 "Codex compatibility plan"):
- Keep shrinking root `AGENTS.md`; add per-agent skill symlinks/mirrors so Codex discovers repo skills under its native path while Claude/GDD keep the canonical `.agent/skills/` layout (see `R3`).
- `.codex/config.toml` project layer once the repo is trusted: `sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`, network off by default.
- Port MCP setup to Codex: teach `ws mcp-setup` (or a sibling mode) to emit `[mcp_servers.*]` TOML; update MCP-usage docs to distinguish Claude `/mcp` auth from Codex `codex mcp login`.
- Treat Obra Superpowers as cross-agent: it now ships `.codex-plugin/plugin.json` and installs via the Codex plugin marketplace; document that path, keep manual install as fallback.
- **Hook platform-split** (the load-bearing piece): split GDD hook policy into platform-neutral *data* (scratch dirs, raw-command redirects, destructive-ask patterns, known-safe `ws` forms, corrective-message text) + platform *adapters* (Claude and Codex need separate hook scripts — different config locations, input payloads, decision-output formats). Use Codex `.rules` for prefix-shaped outside-sandbox decisions; keep a Codex `PreToolUse` hook for shell-composition training and inside-workspace destructive asks that rules/sandboxing won't catch.
- **The parked `hook-v3-extensions` arc** (Dionysus) — four hook ideas beyond the shipped v2 redirect/bypass pair:
  - *Non-Bash composition coverage* (the meatiest — its own tier + tests): composition routed through any non-Bash shell-bearing tool (PowerShell, Monitor, …) evades the Bash-matcher hook. Confirmed *not* an escape: `sh -c "...&&..."` on a Bash call is still denied. The gap is specifically non-Bash tools / unhooked hosts — a PowerShell-syntax tier or a blunt "use Bash" hook for bash-first workspaces, plus a decision on inspecting Monitor and friends. Same cross-harness problem as the hook platform-split, so it folds here.
  - *Hard-wrap rejection in docs* — catch hard line breaks in new prose and push back toward single-line paragraphs (the `gdd-doc-writing` rule, enforced at the hook layer). Likely a Tier 2 ask, not a Tier 1 deny — false-positive surface (code blocks, tables) needs careful matching.
  - *Auto-approve narrow forms like `ws exec <comp> ls *`* — `ws exec` is a high-broad watchlist pattern; a `ws exec <comp> <safe-cmd> *` narrowing would be auto-approve-safe. Gated on the `B3` audit matcher refinement (today the `Bash(ws exec *)` watchlist would flag the narrowing).
  - *`--ff-only` nudge on more git commands* (`git pull`, `git merge`) to avoid accidental merge commits.

Gemini/Antigravity: the cross-harness symlink registration (`R3`) and the hook data/adapter split (above) are the two primitives that make adding a third or fourth agent mechanical rather than bespoke.

### R2 — Team Thalami + publish-vs-collaborate + scribe multi-repo ceremony — ⬜ Not started

The hard distinction (author's own framing): **publishing for visibility** (a read-only mirror of a personal Thalamus, easy) is *not* the same as **moving a project solo → team collaboration** (the team needs its own note-taking home, and keeping a read-only team view in sync with a personal Thalamus is tricky). FG4 is exploring a "Team Thalami" repo you publish to from your personal Thalamus.

**Design instinct to carry forward:** the **realm repo** is the natural team note home — it already plays "shared config + identity + skills + components catalog," and FG4's repo-warden work proves realm-as-shared-config in practice. A team Thalamus likely lives in (or beside) the realm rather than being a synced mirror of any one person's personal Thalamus.

This links to the **scribe ceremony's multi-repo shuffle** — content moving between a personal Obsidian vault, a work Obsidian vault, the personal thalami hoard, the proposed team Thalami repo, a generated site, and the realm during active collaboration. That's the `organization-stack` model's natural extension (Vault → Thalami → Docs → GitHub, the scribe + GDD ceremonies, the Intake bridge) but it's a genuine brainstorm → design, not a 1.0 item. **Flagship 1.x feature.**

### R3 — Skill discovery: proactive cross-harness registration — 🟡 Mostly done; one layer remains

The Loki "Skill discovery + enhancement" mini-design. **Status update (2026-06-09):** two of the three layers are done.

- ✅ **Reactive hook-nudge layer** — shipped via the orientation lineage (PR #91); the adapter-aware Tier 3 hook redirects raw commands toward `ws` wrappers / relevant skills.
- ✅ **Per-skill body enhancements** — landed via the (closed) `skill-taxonomy-2` arc, which reorganized and slimmed the k3d-named skills into component skills. Verified 2026-06-09: the specific lessons are all present — `crossplane render` offline validation + CompositionRevision-flapping/self-heal gotcha in `components/nordri/.agent/skills/crossplane-compositions/`; ArgoCD self-heal + `refresh=hard` + test-through-GitOps in `argocd-gitops/`; the `update-embedded-git.sh` re-hydrate-to-test staging workflow cross-referenced from the realm's `siliconsaga-stack` skill. (Original design note named `crossplane-on-k3d`/`argocd-bootstrap-on-k3d`; those were renamed/folded into the component skills.)
- ⬜ **Proactive cross-harness registration ("register, don't walk") — STILL OPEN, and the load-bearing remaining piece.** Keep skills as canonical agent-neutral markdown in `.agent/skills/`; a `ws` step (idempotent, on `ws realm use` + component clone) registers them into each installed agent's discovery path — Claude → `.claude/skills/<name>/`; Codex → its mechanism; Cursor → `.cursor/rules/`; Antigravity → TBD. Must handle stale-link cleanup on realm switch + a per-tool target table. **This is the "symlinks to agent-specific homes" idea the author flagged**, it's the cheapest most-visible first step toward multi-agent, and `R1` depends on it. Confirmed 2026-06-09 that no such registration mechanism exists in `scripts/` yet.
- ⬜ **Skill-summary frontmatter field + `yq`-on-SKILL.md-body fix** (surfaced during PR #90) — small residual; confirmed absent (skill frontmatter is still `name` + `description` only).

### R4 — Flagship public writeup(s) — ⬜ Not started

Latent material already captured, unwritten: Dionysus "Wild new GDD showcase" (11.5k LOC across 3 GDD workspaces in two days); Loki parked blog arcs — BSA DI overhaul + GDD review process, **"Age of Personalized Software"** (the thesis statement — personalized software, GDD as the responsible-AI contribution, the cyborg/centaur framing that `docs/gdd/index.md` § Calibrated Autonomy already articulates), and the Bifrost after-action report. One flagship piece materially helps a public launch; the raw material exists.

### R5 — MCP "blind firehose → surgical menu" thread — ⬜ Not started

FG4 "Jeremy Friese's MCP thing" + the locally-checked-out `friese-mcp-docs/`. The goal — take MCP from a token-heavy firehose to a menu the agent samples surgically — is philosophically adjacent to GDD's whole `ws`-wrapper + local-skill-selection thesis. Not a GA item, but latent public-narrative material about *why* GDD wraps tools. Endpoints/notes live in the FG4 Thalamus section.

### R6 — Deferred `ws` CLI / infrastructure ideas — ⬜ Not started

Designed-but-deferred, "defer until evidence of need":
- **`ws rebase`** utility (Dionysus): script the repeatable rebase ceremony (status → fetch → backup branch → conflict preview → rebase or exit-to-agent if conflicts likely → verify no markers → report + offer backup cleanup).
- **`ws run <comp> <action>`** dispatcher (Loki): `ws actions` shows per-component adapter commands but doesn't execute them; `ws run` would. Needs the `B1` `ws_resolve_target` helper to accept hoard/realm targets (the `sweethome3d` auto-approve dependency).
- **`git-issue.sh` querying** (Dionysus): handle *reading* issues, not just creating them (agents currently drop to raw `gh` for this).
- **`ws changelog <target>|--stack`** (B6 follow-on, 2026-06-11): stack-level change-note aggregation — walk the declared ecosystem components, collect each repo's conventional commits (or CHANGELOG section) since its last tag, emit one grouped draft. The Terasology engine+modules aggregation lesson, solved by the manifest GDD already has. Detail in `docs/gdd/versioning.md` § Stack-level aggregation.
- **Setup wizard** during orientation / `ws overlay init` (Dionysus onboarding): walk token creation, identity config, remote setup. Companion to `P6`.
- **`ws realm new` wizard** (Dionysus): interactive realm scaffolding mirroring `ws hoard init` (today realm creation is fork-and-edit on GitHub).
- **Workspace-wide `ws diagnose`** (Dionysus): aggregate one-shot view (no comp arg) + identity/tools check; the per-repo form already exists.
- **Local lint tooling + shared config** (Dionysus): ship `.markdownlint.yaml`/`.shellcheckrc`/`.yamllint`/`.editorconfig` in-repo so local tools and CodeRabbit read the same config; invoke via pre-commit or `ws lint`.
- **Three remote homes** (`homes.{fork,internal,external}`) + the "automate detection + URL crafting for human-only steps" pattern (FG4 `cross-org-homes-design`): deprecate `forkOrg` + `forkConvention` in favor of an absolute `homes.fork` namespace path; any GDD tool hitting a "human must auth this step" gate should follow the same shape (precise detection → max-prefilled URL → clear fallback → known exit code). FG4-owned; surfaced here because it's a reusable GDD convention worth an `AGENTS.md` mention.

---

## Cross-cutting principles (carry into every item above)

- **Skill → script extraction** (Dionysus, codified PR #48/#49): skills carry decision-making; scripts carry execution; docs carry reference. Any skill walking an agent through `git … && compute && compare` is a candidate to become a `ws <subcommand>`. `B1` and `R6` are direct applications.
- **Deterministic where possible** (orientation lineage): factual state belongs in a command that can't drift (`ws orient`); judgment belongs in a skill. New GA work should keep that split.
- **Automate detection + craft the URL; the human does only the click only they can** (FG4): the right shape for any human-authority gate.

---

## Source Ledger — what moved here and from where

This records the Thalamus observations folded into this doc and removed from their files, so nothing is lost and the same item isn't re-tracked. Each Thalamus retains an Audit Log entry pointing here. Items **not** listed (cluster ops, NVIDIA/CFR day-job work, school-advocacy, knarr/ting/sweethome3d internals, GKE log exclusions) were deliberately left in place — they are operational/project-specific, not GA-readiness.

> **Note on the host-specific files referenced below** (`Dionysus-thalamus.md`, `FG4WWY622F-thalamus.md`, `Loki-thalamus.md`, `rasmuss-mbp-2-thalamus.md` — the latter host has since been renamed `Idunn`, so its file is now `Idunn-thalamus.md`): these are **external to this repository.** They live in the per-developer thalami hoard (a separate git repo cloned under `hoards/<thalami-hoard>/`, gitignored at the workspace root — this repo's `hoards/` holds only a `.gitkeep`). The names are recorded here for the author's audit trail across machines, not as paths a reader of this repo can open. See `docs/gdd/hoards.md` and `docs/gdd/thalamus.md` for the hoard model.

**Dionysus-thalamus.md** → moved: multi-platform testing checklist (`B2`); `ws audit-permissions` over-matching (`B3`); `ws issue --help` + anchor-vs-reference doc drift (`B4`); `tutorial-next-pass` forward gaps (`B5`); `ws hoard upgrade` disable (`B7`); `ws rebase` idea, local-lint-tooling, bulk-resolve review threads, `git-issue.sh` querying, onboarding/identity + setup wizard (`P6`/`P7`/`R6`); `component/<comp>` target-kind + "review realms/hoards?" (`B1`); review-workflow enhancements (`P*`); Co-Authored-By sub-agent residual (`P5`); `hook-v3-extensions` non-Bash composition coverage (`R1`). Left in place: Nidavellir DNS IAM, blog refresh, school-board items, PKM/Outbox/nonclaudesidian, schools-site stale images, Nordri rdctl note, Backstage/upgradeable-templates far-future, DI-migration items, MTL-site analytics.

**FG4WWY622F-thalamus.md** → moved: target-kind generalization Backlog item (`B1`); Codex compatibility plan + non-agent-specific Codex-orientation observations (`R1`/`B3`); Jeremy Friese MCP thread (`R5`); the reusable three-homes/URL-helper *convention* (`R6` — the NVIDIA-specific `cross-org-homes-design` + `repo-warden-evolution` arc detail stays in FG4). Left in place: all CIS/CFR, repo-warden, gitlab-audit, obsidimark, token, and rename-arc operational content.

**Loki-thalamus.md** → moved: `ws resolve` rename (`P1`); absolute-path/`git -C` allowlist escape (`P2`); build-tool prompt noise (`P3`); allow-ladder `:*` collapse (`P4`); Skill discovery proactive-registration + per-skill enhancement design note + Backlog (`R3`); Co-Authored-By/model-attribution open idea (`P5`); adapter-trust reminder (shipped via #91 — prunable). Left in place: all Heimdall/Nidavellir/Nordri/GKE/Artifactory/storage ops, the older-ArgoCD concern, GKE log-exclusion deep-dives.

**rasmuss-mbp-2-thalamus.md** → moved: allow-ladder cleanup (`P4`); bash-3.2 `mapfile` cross-platform note (folded into `B2`); model-attribution sub-agent residual (`P5`); `ws run`/`ws_classify_target` dependency note (`B1`/`R6`). Left in place: all knarr operational state, ting design, sweethome3d/Langr, the vouching/who-watches-the-watchers material.

---

## Suggested tracking

Open a `gdd-ga-1.0` arc (shared `id` across hosts) whose `next:` references this doc. Mark each `B*`/`P*` item ✅ here as it lands; the arc closes when all `B*` are ✅ and `1.0.0` is tagged (`B6`). The `R*` items graduate to their own arcs when picked up — they are roadmap pointers, not arc-tracked here.

**Sequencing note (2026-06-11):** the B1/B3/B4/B7 batch landed via `docs/plans/2026-06-10-gdd-ga-cleanups-plan.md`. The remaining GA blockers are **B2** (cross-platform runs — execute the checklist above on the two trial machines; it's a run-and-fix exercise, no plan needed) and **B6** (SemVer + CHANGELOG — needs the versioning-unit decision first, then the rest is mechanical), plus the **B5** tutorial/front-door pass tracked by its own arc. The **P\*** items are independent papercuts that can ride along with either; each **R\*** roadmap item needs its own brainstorm before any plan.

**Sequencing note (2026-07-09, updated 2026-07-10):** what's actually between here and the tag: (1) **issue #122** — clone-fork GitHub provider path + default-token fallback + `gitlab-auth --help` — re-verified still valid on 2026-07-09, then **fixed 2026-07-10** (TDD'd, full suite 684/684); the issue's last acceptance box — live end-to-end clone-fork against real GitHub AND GitLab sources — deliberately rides the clean-machine runs, so close #122 after those; (2) the **P8.1** `ws status` null-components guard — **fixed 2026-07-10** alongside; (3) the **B2/B5** one-shot newcomer runs on the planned clean systems, gh-pages tutorial included; then (4) the **B6** release ceremony per `docs/gdd/versioning.md` (curate `[Unreleased]` → `1.0.0`, annotated tag, push). P6/P7 are filed as post-GA issues #124/#125; the R1 allowlist question is #127; session-liveness was resolved by decision (no liveness marker by design — staleness never gates; `ws clean --sessions-all` is the stale-scope remedy, per the rationale comment in `scripts/ws-k8s.sh`).

**Sequencing note (2026-07-21) — the gate is met.** Every `B*` is ✅: B2 closed with the explicit Mac-deferral scope note above, B5's tutorial re-test rode the clean-laptop run (`tutorial-next-pass` arc closed), and B6's machinery has been in place since 2026-06-11 with the CHANGELOG `[Unreleased]` fully curated. The preserved editorial/branding pass **slides post-GA** (owner-leaning call, recommended 2026-07-21: three doc passes landed in the final six weeks — #120, the #128 freshness pass, and the GA-notes newcomer polish — so a dedicated wording sweep is 1.0.x material, paired with the SlopCop idea). What remains is pure ceremony on the release branch's merge: curate `[Unreleased]` → `1.0.0`, first-ever annotated tag, GitHub Release with the curated section + auto-notes appendix, then closeout (this doc marked shipped, arcs closed cross-host).

**Sequencing note (2026-07-16):** the security/hardening wave is merged — #128 (clone-fork provider parity + first-run papercuts), #129 (Argus trust boundaries), #130 (trust/auth boundaries), #131 (cross-platform workflow hardening: `ws docker`, hoard rollback correctness, realm trust output, canonical `--add-to-ecosystem`) — and the full suite is green on Windows for the first time (873 tests, Dionysus Win10/Git Bash; previously validated Mac-only). #133 (hook backslash always-ask on Windows paths) plus a session-env-file carve-out for the #129 sub-agent prompt friction are fixed on `fix/hook-backslash-path-tokens`. `[Unreleased]` in the CHANGELOG is caught up through this wave. Note: #122 was auto-closed by #128's merge, so its live clone-fork e2e acceptance (real GitHub AND GitLab sources) must survive on the B2 clean-machine run checklist rather than in the issue. Remaining unchanged: the B2/B5 clean-machine runs, then the B6 release ceremony. One open decision: the preserved pre-release editorial/branding pass (2026-07-15 disposition) — gate the tag on it or slide it post-GA.
