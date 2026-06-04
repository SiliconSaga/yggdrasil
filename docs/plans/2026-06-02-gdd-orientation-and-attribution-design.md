# GDD Orientation, Capability Discoverability & Commit Model Attribution — Design

**Date:** 2026-06-02
**Status:** Design (implementation gated — see Phasing)
**Related:** `2026-05-20-hook-redirect-and-bypass-design.md`, `2026-05-17-hook-ask-tier-design.md`, the realm-tier capability-index skill in progress in the SiliconSaga/Loki workspace, and the `gdd-orientation-capability-index` arc (Thalamus, `rasmuss-mbp-2-thalamus.md`).

---

## Problem

GDD orientation is **convention-driven**, not enforced. `AGENTS.md` says "on every session start, read `.agent/skills/gdd-orientation/SKILL.md` and follow its startup sequence." When an agent honors that, things work. When it doesn't — sub-agents, post-compaction/resumed sessions, and non-Claude agents (Gemini, Codex) that never ran the convention — a cascade of misses follows:

- Raw commands instead of the `ws` wrapper (`git commit`, `pytest`, `ruff`, …).
- No active-realm lookup, so realm-specific instructions and the realm skill index go unread.
- Scattered "use `ws X` not raw `Y`" knowledge (today split across feedback memories + an `AGENTS.md` table) is never consolidated at the point of need.

**Forcing function:** a session working on the `knarr` Python component ran `pytest`/`ruff` raw and hit endless approval prompts, never discovering `ws test` / `ws lint` — despite `ting` demonstrating the exact adapter pattern in another Python component.

**Key reframe (from the 2026-06-02 reassessment):** the gap is *not* missing content. The root `AGENTS.md` already has a § Skills table and a § Workspace CLI "reflex-check" table; the PreToolUse hook (`gdd-permission-hook.sh`) already redirects `git commit`/`git push`/`gh pr create` to their `ws` equivalents with a session-scoped `ws hook-bypass` escape. The gap is **reliable delivery**: prose in `AGENTS.md` gets skimmed past, and the only always-fires mechanism (the hook) is Claude-only.

A topically-adjacent problem rides along: **commit model attribution**. `ws-commit.sh` builds the `Co-Authored-By` trailer as `Claude ${CLAUDE_MODEL:-Opus 4.7}` (a configured `identity.co_authored_by` overrides it entirely). The default was stale (4.7), and sessions worked around it by prepending `CLAUDE_MODEL="Opus 4.8"` inline — which dodges any allowlisted bare `ws commit`. It touches the same levers (orientation, sub-agent heads-up, possibly a hook), so it is folded into this design.

---

## Goals

1. Make "what can I do here / what must I read" reliably reach agents who skip convention-driven orientation — including non-Claude agents and sub-agents.
2. Replace ignorable prose with **progressive disclosure**: a slim always-present menu, deeper detail pulled on demand, never loading everything at once.
3. Keep the deterministic/factual parts in a **command** (can't drift); keep judgment in the **skill**.
4. Provide a portable "reassess on topic change" trigger, backstopped — not replaced — by the hook.
5. Keep commit model attribution current automatically and credit the right model for sub-agent commits.

## Non-Goals

- Building per-tool hook equivalents for Gemini/Codex (noted future work; portability here is carried by the non-hook layers).
- A central skill-registry subcommand or `.claude/skills/` symlink farm (the "register, don't walk" proactive-registration layer lives in the Loki `Skill discovery + enhancement` mini-design; this design is its workspace-root content/discoverability counterpart).
- Re-litigating the existing redirect/bypass hook tiers (we extend, not redesign).

---

## Design Overview — the "buffet" disclosure hierarchy

Four layers, lazy-loaded. You never eat all the cakes at once; you take a bite when you reach for one.

| Layer | What | Emitted by | Loaded when |
|---|---|---|---|
| **L0** | `AGENTS.md` slim menu: top `ws` utilities (one-liners), "an active realm is present — load its skills only when the work needs them," and the **reflex contract**. Ends with the single hard pointer to the orientation skill. | static markdown (heavily cut) | always in context |
| **L1** | **`ws orient`** — a deterministic menu generated from live state: `ws` subcommand survey + "use when," detected active realm + its skill index, per-component adapters (which `ws test`/`ws lint` are wired). | new script | agent orients or reassesses |
| **L2** | `ws <cmd> --help` — the recipe for one cake (e.g. `ws commit --help` = bodyfile templates + **attribution**). | existing `--help`, extended | agent reaches for that command |
| **L3** | deeper sub-topic help, only for genuinely complex commands. | optional | rarely |

### Why `ws orient` is a real command, not an enhanced `ws help`

It reads actual state — adapter files, the active realm, skills directories — so it **cannot drift** from reality. The `knarr` failure becomes structurally impossible: `ws orient` enumerates `knarr → ws test [pytest adapter]` because it inspects the adapter. The `gdd-orientation` **skill becomes a thin judgment wrapper** that calls `ws orient` for the factual parts and adds the non-deterministic bits (trust verification, mode/role, tone, stale-audit warnings). This matches the standing steer that GDD skills should pair with deterministic `ws` scripts rather than hand-wave data-gathering in prose.

`AGENTS.md` is cut hard: from a fat table that gets skimmed to L0 — labels + the reflex contract + "read the orientation skill at session start / after compaction / when dispatched fresh."

---

## The "reassess on topic change" trigger (A + B footer)

The hard question: what makes an agent *reassess* the menu on a topic shift instead of instinctively grabbing a raw command? Three coordinated layers — portable primary, point-of-use reinforcement, Claude backstop.

### A. Reflex contract (portable primary)

A compact block in `AGENTS.md` L0 — small enough to survive in context across topic changes, unlike a fat table. It lists **only the unconditional redirects** (always have a `ws` path, no adapter dependency):

```
Before doing any of these RAW, use the ws path (run `ws <verb> --help` first if unsure):
  commit → ws commit     push → ws push      PR → ws cr      issue → ws issue
  clone → ws clone       run a cmd inside a component → ws exec (never cd)
Before a raw dev tool (test/lint/build) OR a task-type switch: run `ws orient` — it lists
what's wired for THIS component/realm.
```

The **tripwire verb is the reassess signal**: reaching for "commit" or "test" *is* the topic change, and the contract routes the agent to the menu/help first. No abstract topic-shift detection needed. Adapter-dependent verbs (test/lint) are deliberately **not** enumerated as a static list — they grow per component and depend on wiring, so `ws orient` surfaces them dynamically instead.

### B. Command-output footer (point-of-use reinforcement)

Every `ws` command ends with one dim line:

```
↪ switching tasks? `ws orient` lists the toolset for what's here.
```

Fully agent-agnostic; reinforces exactly where the agent is already working. Cost is negligible (tiny, and prompt-cached as part of the growing prefix); the recency/salience of the latest footer near the end of context is a genuine, free benefit. It does not catch a *cold* raw reach on its own — that is what the reflex contract and the hook are for.

### Hook backstop (Claude-only, adapter-aware)

Extend `hook-rules` `[redirect-commands]`. Two behaviors by category:

- **Unconditional verbs** (`git commit`/`git push`/`gh pr create` — already wired): keep today's hard **deny-with-bypass**. Deny messages point at `ws <verb> --help` so the backstop also teaches progressive disclosure.
- **Adapter-dependent verbs** (`pytest`/`python -m pytest`/`gradle test` → `ws test`; `ruff`/`black`/`mypy` → `ws lint`): **adapter-aware**. Deny-with-bypass **only when an adapter is wired** for the resolved component (best case: "use the wired `ws test`"). When no adapter exists, **allow** the raw command and emit a one-time nudge to wire one. This avoids the spin-out where a hard deny leaves the agent with no `ws` path and no way forward — the exact impatience risk raised in review.

Non-Claude agents have no hook; they degrade gracefully to the reflex contract + footer (best-effort). This is why A+B (portable layers carry the load) was chosen over a hook-centric approach.

---

## Active-realm discovery

A commonly-missed step today: agents that skip orientation never look for the active realm, so realm-specific instructions and the realm skill index go unread. `ws orient` surfaces this deterministically — it detects the active realm (from `ecosystem.local.yaml` `realm:` selector or a single `realm-*/` directory) and prints the realm name + its skill index (names + descriptions only, bodies on demand), with a pointer "in this realm? see its `AGENTS.md` / realm index skill." This ties into the realm-tier capability-index skill being built in the Loki workspace: when that lands, `ws orient` points down to it as the realm-level continuation of the same buffet.

---

## Commit model attribution

Three pieces, ordered by how unblocked they are.

### 1. `.env` self-updating default

Current state (Phase 0, done): `.env` now has `export CLAUDE_MODEL="${CLAUDE_MODEL:-Opus 4.8}"` — the `:-` form keeps an inline override working while supplying a default. `.env.example` (checked in, last touched Apr 22 — stale) gets the same line + a comment, plus a freshness pass.

Phase 1: the orientation skill — which *knows its own model* — rewrites only the default token in `.env` if it is stale, so the workspace default tracks the current main-agent model automatically instead of being hand-maintained. The `:-` form is preserved so inline overrides still win.

### 2. Sub-agent heads-up (guidance)

When dispatching a sub-agent — especially on a different model (Sonnet vs Opus) — the dispatch instruction says: *if you commit and you are not on the workspace default model, prepend* `CLAUDE_MODEL="<your model>" ws commit …`. Inline is correct here precisely because a shared `.env` rewrite from parallel sub-agents would race. This is also documented in `ws commit --help` (the L2 bite), so an agent that reaches for commit reads it at the point of need.

### 3. Allowlist `ws commit` + the attribution prepend (Phase 0)

`ws commit` is **not** allowlisted today, so sessions hand-add it at user level and the inline attribution prepend dodges the bare allowlisted form. Fix:

- Add a `ws commit` allow pattern to project `.claude/settings.json` `permissions.allow` (normalized, so bare `ws commit` and `bash scripts/ws commit` both match).
- Add **explicit, bounded** allow patterns for the attribution prepend — `CLAUDE_MODEL=* ws commit` and `CLAUDE_MODEL=* bash scripts/ws commit` (both dispatch forms, since normalization does not reach past a leading env assignment). **No change to `normalize_for_match`.**

**Rejected — a general "strip leading `VAR=value`" in `normalize_for_match`.** It would be a privilege escalation, not a convenience: the stripped assignment is removed only for *matching* but stays on the *executed* command, so `LD_PRELOAD=…/evil.so ws status`, `PATH=/tmp/evil ws status`, or `GIT_SSH_COMMAND="…" ws push` would auto-approve without a prompt and then run with an attacker-controlled environment. Code-injection through any allowlisted command, with the catching prompt suppressed. The explicit-pattern approach is bounded to `CLAUDE_MODEL`, which is code-execution-inert — it only feeds the `Co-Authored-By` trailer string (newline-sanitized at `ws-commit.sh:135`). Two security regression tests lock this: a prepended `LD_PRELOAD`/arbitrary var on an allowlisted command must **not** auto-allow, and an env prefix must **not** bypass a redirect deny (`CLAUDE_MODEL=x git commit` still denies).

### Considered and declined

A PreToolUse trigger on `ws commit` to enforce/refresh attribution: it cannot know the acting model and would fire noisily on every commit. The `--help` doc + self-updating default + sub-agent guidance cover it without the noise. Recorded as "considered, not worth it."

---

## Cross-agent portability

- The portable layers — L0 menu + reflex contract (in `AGENTS.md`, the shared convention; `CLAUDE.md` already defers to it, and `GEMINI.md` is pointed there), `ws orient`, footers, `--help` — carry the load for non-Claude agents.
- The hook is explicitly the **Claude-only backstop**; its absence elsewhere degrades to best-effort.
- Per-tool hook equivalents (Gemini/Codex) are noted future work, out of scope here.

---

## Adapter trust & the executable-config surface

`ws test`/`ws lint` read **command strings** out of realm adapter files (`realms/<realm>/adapters/<component>.yaml`) and execute them. That is config-indirected code execution — the same shape as npm `scripts`, a Makefile target, or `.vscode/tasks.json` — and this design *leans into it*: the Phase-1 hook actively routes a visible raw `pytest` into the adapter-wrapped `ws test`, and the wrapper removes the real command from the visible command line.

**Decision: `ws test`/`ws lint` ARE blanket-allowlisted** (like `ws commit`), accepting that they run adapter-defined commands. **Rationale — the realm trust model:** a realm is an extension of your own hoards (which you wrote, hence trusted); adopting a *team's* realm and making it active locally is a deliberate act of trusting that team. Withholding the allowlist was considered and rejected — it just pushes humans to hand-allow `ws test`/`ws lint` in every workspace anyway, defeating the design while adding friction, and it does nothing the trust model doesn't already cover for the common case.

**Residual risk (bounded, accepted, mitigated):** adopting a "wild" realm off the internet, and a destructive typo slipping into an adapter command. Defended — not by withholding the allowlist — by:

1. **`ws orient` surfaces the resolved command** per component (`knarr → ws test [runs: python3 -m pytest tests/]`), so execution stays auditable despite the wrapper.
2. **Trust-verification at realm scan/activation covers AGENTS.md + realm skills + *adapter commands***. The orientation skill already watches for "evil" instructions in components/skills and notes them in Thalamus; adapter command strings are a newer executable surface that this step must explicitly read — flagging `curl|sh`, base64 blobs, out-of-repo writes, or network calls in a "test"/"lint" command.
3. **Provenance-scaled rigor:** your own / your team's realm gets a light pass; a wild/internet realm gets heavy scrutiny before activation.
4. **Adapters deserve a focused read even though they look trivial.** A realm skill is usually a script that's seen testing; a plaintext adapter command is short and a last-minute typo can slip in at the end — so the small surface is exactly where a careless/destructive change hides.

---

## Documentation impact (`/docs` GDD prose)

The mechanism changes above must be reflected in the human-facing GDD docs, or the docs drift from behavior. Each doc updated alongside the phase that changes it (Phase-0 docs ship with Phase 0). Verification: `mkdocs build --strict` (CI `.github/workflows/docs.yml`) — only existing pages change, so no `mkdocs.yml` nav edits.

**Phase 0:**
- `docs/gdd/permissions.md` — `ws commit`/`ws test`/`ws lint` allowlisted by default; the bounded `CLAUDE_MODEL=*` prepend pattern; and the **security rationale for rejecting a general env-prefix strip** (the `LD_PRELOAD`/`PATH`/`GIT_*` escalation).
- `docs/ws-cli-guide.md` — `ws commit` attribution behavior (`CLAUDE_MODEL`, the `.env` default, the sub-agent inline rule), mirroring the expanded `--help`.

**Phase 1:**
- `docs/gdd/agent-training.md` — **the largest update**: the progressive-disclosure "buffet" (L0/L1/L2), the reflex contract + tripwire verbs, `ws orient`, the command footer, and the hook as Claude-only backstop. This is the doc that explains how agents are oriented/trained.
- `docs/gdd/trust-and-safety.md` — trust verification now covers **adapter commands** (not just AGENTS.md + realm skills); provenance-scaled rigor (own/team realm vs. wild realm).
- `docs/gdd/adapters.md` — the adapter trust model + executable-config-surface framing; `ws orient` surfaces the resolved command.
- `docs/gdd/realms.md` — the "a realm is an extension of your own hoards / the team you joined" trust framing (or a pointer to `trust-and-safety.md` as the canonical home).
- `docs/gdd/features.md` — add `ws orient` and the reflex/footer discoverability layer as features.
- `docs/gdd/skills-reference.md` — `gdd-orientation` now calls `ws orient` + auto-refreshes the `.env` default + scans adapter commands.
- `docs/ws-cli-guide.md` — add the `ws orient` subcommand.
- `docs/gdd/permissions.md` — the adapter-aware test/lint hook redirects (allow-with-nudge when no adapter; deny-with-bypass when wired).

---

## Phasing (respects the arc's sequencing gate)

**Phase 0 — unblocked now** (no dependency on the in-flight PRs):
- `.env` default (done) + add `CLAUDE_MODEL` to `.env.example` + freshness pass.
- Document attribution + the sub-agent inline rule in `ws commit --help`.
- Allowlist `ws commit` + bounded `CLAUDE_MODEL=*` prepend patterns (no general env-prefix strip — see the attribution section's rejected alternative).
- Allowlist `ws test`/`ws lint` (trusted-realm model — see Adapter trust).
- Doc sweep: `permissions.md` + `ws-cli-guide.md` (see Documentation impact).

**Phase 1 — gated** behind: (a) the 4 in-flight PRs landing (realm-siliconsaga #6/#7, heimdall #7, nordri #16 — the realm-tier index pattern is the model), and (b) knarr's `ws test`/`ws lint` shipping (so `ws orient` reflects real adapters):
- Build `ws orient` (subcommand survey + active realm + per-component adapters + **resolved adapter command surfacing** + skill index).
- Cut `AGENTS.md` to L0 + reflex contract.
- Add the command-output footer.
- Extend hook redirects (adapter-aware test/lint).
- Wire active-realm + realm-index pointer (ties into the Loki realm-tier skill).
- Make the orientation skill call `ws orient`, auto-refresh the `.env` default, and **extend its risk-scan to adapter commands** (alongside AGENTS.md + realm skills).
- Doc sweep: `agent-training.md`, `trust-and-safety.md`, `adapters.md`, `realms.md`, `features.md`, `skills-reference.md`, `ws-cli-guide.md`, `permissions.md` (see Documentation impact).

---

## Testing — RED test

Dispatch a fresh sub-agent with the knarr scenario verbatim: "you're working on this Python component, run the pytest suite + lint." Pre-change: confirm it reaches for raw `pytest`/`ruff`. Post-change: confirm it pivots to `ws test`/`ws lint` and finds the adapter wiring via `ws orient`. Re-run against a component with **no** adapter wired to confirm the hook allows-with-nudge rather than spinning on a deny.

Validation contributors: the paused Knarr session (this workspace) and the Heimdall session (Loki workspace) can exercise the changes from independent starting contexts.

---

## Open questions for review

1. `ws orient` naming — pairs with the orientation skill; alternatives `ws guide` / `ws menu`.
2. Adapter-aware test/lint hook: allow-with-nudge when unwired (this design's choice) vs. always deny-with-bypass and let the agent/human wire the adapter as the forcing function. The former avoids spin-outs; the latter is stricter. Revisit if the nudge proves too soft in practice.
3. Exact tripwire-verb set in the reflex contract (current: commit/push/cr/issue/clone/exec + the `ws orient` meta-rule for test/lint/build).
