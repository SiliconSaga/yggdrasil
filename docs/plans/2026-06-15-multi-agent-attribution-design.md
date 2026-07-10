# Multi-Agent Commit Attribution — Session-Scoped Identity (Phase 1) — Design

**Date:** 2026-06-15
**Status:** Implemented (Phase 1) — see the **Revision** note below for the as-built `--co-author-file` design.
**Arc:** `multi-agent-attribution` (cross-workspace: Dionysus + FG4WWY622F)
**Builds on:** PR #100 (introduced `GDD_CO_AUTHOR` as an agent-neutral trailer identity + `ws push` tags)
**Related:** `docs/plans/2026-06-08-gdd-ga-readiness-design.md` (`R1` hook platform-split — the natural pair), `scripts/ws-hook-bypass.sh` (the `<session-id>` marker precedent this mirrors). (The `strip_claude_model_prefix` hook strip cited at design time as the prefix precedent was *removed* by this work — see the Revision note.)

---

## Purpose

Make `ws commit` attribute the *right agent* when more than one primary agent session runs against the same workspace — e.g. Claude in one terminal and Codex in another, sometimes concurrently. PR #100 shipped `GDD_CO_AUTHOR` as a single agent-neutral identity sourced from `.env`, which solves single-agent attribution but **races** when two concurrent sessions want different identities from one shared `.env` value, and **drifts** when that value goes stale (lived this session: a commit attributed `Claude Fable 5` because the `.env` default never updated after the running model silently became Opus 4.8).

Phase 1 replaces the single shared value with a **per-session identity**, re-established fresh at every `ws orient`, so concurrent sessions never collide and a new session can never inherit a stale identity. This is the first concrete instance of a larger **session-config layer** (see Phase 2+ roadmap); Phase 1 deliberately ships only the identity slice on an extensible file format.

### Goals

- Concurrent Claude + Codex sessions in one workspace each attribute commits correctly, with no manual per-commit ceremony.
- A new session always re-determines its identity (no stale-value drift).
- Single-agent workspaces are unaffected in practice (no new prompts, no required setup beyond what orientation already does).
- A wiped identity file (e.g. `ws clean`) produces a clean, actionable error — never a silent mis-attribution.

### Non-goals (Phase 1)

- Session-scoped **mode/role/allowlist-flavor** — that is Phase 2+ (see roadmap). Phase 1 only carries identity, on a format that can grow.
- Gemini / Antigravity session detection — deferred to the future issue (their session-id surfaces need direct testing).
- Perfect model-*version* certainty. The agent reports its best self-knowledge; "Claude vs Codex" is reliable, the exact version is best-effort, and the human can always correct it.

---

> **Revision (2026-06-16, during implementation):** The original chain made an inline `GDD_CO_AUTHOR="Name <email>" ws commit` env prefix the sub-agent escape hatch. That cannot work through the Claude Code permission hook: the hook's **Tier 1 redirect deny** rejects the `<`/`>` in the required `<email>` *before* any prefix-strip runs (the `CLAUDE_MODEL=` precedent never hit this because model strings have no angle brackets). Rather than restructure the security hook to strip a prefix before Tier 1, sub-agents now write their identity to a small file and point `ws commit` at it by name via a new `--co-author-file <name>` flag — a bare name with no angle brackets, which passes Tier 1 untouched and matches the existing `Bash(ws commit:*)` allow with **no hook or allowlist changes**. The hook's attribution-prefix strip is **removed entirely** (dead once no env-prefix mechanism exists). Two further refinements during implementation: the inline `GDD_CO_AUTHOR="…"` env rung is **dropped** (unused once `--co-author-file` exists; blocked by Tier 1 for agents anyway), and the no-session case is a **hard error guiding the caller to `--human`** rather than a silent no-trailer commit — so an agent (which always has a session id) can never quietly skip attribution, and a manual human commit is an explicit choice. The sections below reflect this revised design.

## The resolution chain (the heart)

`ws commit` resolves the `Co-Authored-By` identity as follows (first match wins):

1. **`--human` flag** → commit with **no `Co-Authored-By` trailer** (and skip the identity requirement entirely). This is the explicit marker a human uses when committing manually — including inside a context where a session id happens to resolve (e.g. `!ws commit` inside a Claude Code session, or a retry with an edited bodyfile). It suppresses any agent attribution.
2. **`--co-author-file <name>` flag** → read `GDD_CO_AUTHOR` from `.tmp/gdd-agent-sessions/<name>.env` (a bare name; the dir is the convention, no path is passed). This is the **sub-agent escape hatch**: a sub-agent shares its parent's session id and would otherwise resolve to the parent's session file, so it writes its own identity file (a scratch dir → Write auto-allowed) and names it here. Missing/empty file → error (you named a file that isn't there).
3. **Session file** — if a session id resolves (an agent session), `.tmp/gdd-agent-sessions/<session-id>.env`. If it is missing → **hard error** (the resilience path; an agent whose identity was cleared must re-establish, never silently mis-attribute).
4. **Nothing resolves** (no `--human`, no `--co-author-file`, no session id) → **hard error** with guidance: an agent must establish its identity (`ws orient` / `ws whoami --set`); a human committing manually must pass `--human`.

There is deliberately **no silent no-trailer fallback**. Two reasons, both raised during implementation: (a) an *agent* always has a session id, so it always lands on rung 3 — it can never quietly skip attribution by "looking like a human"; and (b) a no-session caller can't be reliably distinguished from a misconfigured agent, so rather than guess we require the human to mark themselves with `--human`. Every "loud" outcome (rungs 3–4 errors) is actionable and tells the caller exactly what to do.

What is **removed** from the chain that existed before:

- `identity.co_authored_by` (ecosystem-config pinned override) — **deleted**. Identity must never live above the session level; a stale pinned value can only cause the drift this design exists to prevent.
- The legacy `Claude $CLAUDE_MODEL <…>` fallback — **removed** (see Legacy cleanup).
- `.env`-sourced **and** inline-env `GDD_CO_AUTHOR` — **removed.** Neither an environment value nor an inline `GDD_CO_AUTHOR="…" ws commit` prefix is consulted: the inline form is blocked by the hook's Tier 1 redirect deny for agents anyway (the `<email>` angle brackets), and keeping it only for a human's terminal would be an awkward, rarely-used path. A human commits with `--human`; an agent uses its session file or `--co-author-file`. An agent session never consults `.env`, so a stale value cannot drift agent attribution — the original goal.

The email-shaped validation from PR #100 (`<…@…>` required) is retained and applied to whatever identity the chain resolves (rungs 2–3); the `--human` path (no trailer) skips it.

---

## Session id resolution

The session id keys the session file. It resolves, first match wins:

1. `GDD_SESSION_ID` — optional explicit override. **Not set in normal operation.** Two narrow uses: (a) tests, which must simulate a session without a real harness id; (b) a future harness that injects no usable session var (deferred — see Non-goals).
2. `CLAUDE_CODE_SESSION_ID` — injected by Claude Code into every Bash call's environment. Proven: `ws hook-bypass` already keys its markers on it.
3. `CODEX_THREAD_ID` — Codex's per-thread id, observed present in the environment. Flagged as undocumented; treated as best-effort. If it ever changes or vanishes, a Codex-only workspace can fall back to setting `GDD_SESSION_ID` (case (b) above), and nothing else breaks.

Critically, the session id comes from the harness on **every** call (fresh shells don't persist exports), so orientation and `ws commit` independently read the same value — orientation to *write* the file, `ws commit` to *find* it. No coordination state is needed beyond the file itself.

"No session id resolves at all" (a plain script, or a human in a non-agent terminal) is the rung-4 hard error: the caller is told to pass `--human` for a manual commit (no trailer), or to establish an identity (`ws orient` / `ws whoami --set`) if they are an agent after all. We never invent an identity and never silently drop attribution.

---

## Identity determination (at orientation)

The session file's value is **re-determined fresh each session**, by the agent, at `ws orient`. This is what makes "per-session" an actual refresh rather than a copy of a stale default.

- The agent determines its own identity from its self-knowledge: Claude writes `Claude <model> <noreply@anthropic.com>`; Codex writes `Codex <model> <noreply@openai.com>`. (Provider → default no-reply email is a small built-in table; the model string is the agent's best self-report.)
- **Confident → write silently.** No prompt. This is what keeps the single-agent experience friction-free: orientation already runs every session, and this adds one silent file write.
- **Cannot determine its model → ask the human** for the identity string, then write.
- The human can always override after the fact via `ws whoami --set`.

The value is **never** sourced from `.env` or frontmatter. The hard-refresh-per-session is the whole mechanism for correctness; sourcing from static config would reintroduce drift.

This **replaces** the orientation skill's current "Commit attribution refresh (main agent only)" step, which rewrote `.env`'s `CLAUDE_MODEL`/`GDD_CO_AUTHOR` default (ask-first, per PR #100's review fix). The new step writes the session file instead of `.env` (via `ws whoami --set "Name" <email>` — the split-arg form keeps angle brackets off the command line so it passes the permission hook). Sub-agents skip this step and use `--co-author-file` instead.

---

## Session file

- **Path:** `.tmp/gdd-agent-sessions/<session-id>.env`. Under `.tmp/` (gitignored; spared by a default `ws clean`, swept only by `ws clean --sessions`). Per-workspace by construction — each workspace has its own `.tmp/`, so multiple workspaces on one machine never collide (a case the author flagged as possible).
- **Format:** env-style `KEY=value` lines, sourced or grep-read. Phase 1 writes exactly one line: `GDD_CO_AUTHOR=Claude Opus 4.8 <noreply@anthropic.com>`. The format is the extension point — Phase 2 adds `GDD_MODE=…`, `GDD_ROLE=…`, etc. to the same file.
- **Written by:** orientation (silently/with-ask) and `ws whoami --set`. **Read by:** `ws commit` (and, in Phase 2, mode/role consumers).
- **Lifecycle:** created at orient, lives for the session, pruned by `ws clean --sessions` (a default `ws clean` spares it; see Resilience). Stale files from ended sessions are harmless clutter that `ws clean --sessions` collects during deliberate housekeeping.

---

## Resilience & `ws clean` interaction

The hard-error-on-missing behavior (rung 3) **is** the resilience mechanism, and it falls out for free from the always-on model: every primary session establishes a file at orient, so a *missing* file for a resolvable session id means it was removed mid-session — and `ws commit` says so clearly instead of guessing.

`ws clean` interaction (as built): by default it **spares the entire `.tmp/gdd-agent-sessions/` dir** — every session's identity, not just the caller's. The original plan was "spare current, sweep the rest," but that's unsafe for *concurrent* sessions: a finishing session running a reflexive `ws clean` can't tell an ended session's file from a still-live one, and sweeping a live session's identity (or, in Phase 2, its mode/role settings) would break it out from under the user. So the default protects them all. The deliberate-housekeeping path is `ws clean --sessions`, which sweeps ended sessions' files **but still spares the current session's** (the running agent survives). The agent should only suggest `--sessions` during formal housekeeping, after confirming with the human that no other live sessions need those files. A swept session re-establishes on its next commit via the rung-3 error.

---

## `ws whoami` command

A small read-mostly command:

- `ws whoami` — prints the identity `ws commit` would currently use (from the session file), or, when no session id resolves, a note that a commit here needs `--human` or an established identity. Read-only; the "who will this commit as?" check.
- `ws whoami --set "Name <email>"` (human) or `ws whoami --set "Name" <email>` (the split-arg form an agent uses — no angle brackets on the command line, so it clears the permission hook) — writes/rewrites the current session's identity file. The re-establish path the rung-3/4 errors point at. Validates the `<…@…>` shape (shared with `ws commit`). Errors if no session id resolves (telling the caller to set `GDD_SESSION_ID`).

Naming: `whoami` reads naturally for "which identity am I committing as." Alternative considered: `ws session identity show/set` — rejected as wordier for a frequently-typed check.

---

## Sub-agent identity: `--co-author-file` (no hook/allowlist changes)

A sub-agent shares its parent's `CLAUDE_CODE_SESSION_ID`, so the session-file rung would attribute its commits to the parent. The escape hatch is the `--co-author-file <name>` flag:

1. **The sub-agent writes its own identity file.** At init (or before its first commit), it determines its identity from what it is and writes `.tmp/gdd-agent-sessions/<parent-session-id>--<label>.env` containing one line `GDD_CO_AUTHOR="Claude <model> <noreply@anthropic.com>"`. `.tmp/` is a scratch dir, so the Write is auto-allowed even for a background sub-agent. The `<parent>--<label>` key avoids collisions between concurrent sub-agents, groups them under the parent, and `ws clean` sweeps them as ordinary clutter (they are not the current session's own file, so the clean carve-out does not spare them — correct, since sub-agents are ephemeral).
2. **The sub-agent commits with the flag:** `ws commit --co-author-file <parent>--<label> yggdrasil .commits/<f>.md`. Only the bare name is passed; `ws commit` resolves it under `.tmp/gdd-agent-sessions/`.

Why this beats the original inline-env-prefix plan: the flag value is a plain file name — no `<email>` angle brackets on the command line, so it never trips the hook's **Tier 1 redirect deny** (the blocker that killed the inline form, see the Revision note), and `ws commit --co-author-file …` matches the existing `Bash(ws commit:*)` allow, so **no hook change and no allowlist change are needed**. This is strictly simpler than the prefix-strip machinery it replaces.

**Hook: the attribution-prefix strip is removed.** `strip_claude_model_prefix` in `.claude/hooks/gdd-permission-hook.sh` is deleted outright — with no env-prefix attribution mechanism, it is dead code, and removing it shrinks the security surface (no "strip a leading VAR=value before matching" logic at all). The two general security regression tests are kept (adapted): an `LD_PRELOAD=` prefix must NOT auto-allow, and an env-prefixed command must NOT auto-allow (the bare `git commit` redirect-deny is covered by its own existing test).

**Allowlist: the `CLAUDE_MODEL=*` patterns are removed, not replaced.** The four `Bash(CLAUDE_MODEL=* …commit:*)` entries in `.claude/settings.json` are deleted; nothing is added, because `ws commit --co-author-file …` already matches the bare `Bash(ws commit:*)`. `docs/gdd/permissions.md`'s "Bounded `CLAUDE_MODEL=` attribution prefix" section is removed (the mechanism it documented no longer exists), and any empirical-matcher rows that referenced it are updated per that doc's cross-reference rule.

---

## Legacy cleanup (drop pre-GA, clean break)

Pre-1.0, before stricter SemVer applies, this design removes the superseded mechanisms rather than carrying them:

- **`CLAUDE_MODEL`** — removed from `.env.example`, `scripts/ws-commit.sh` (resolution + help text), the orientation skill, and the hook + allowlist (the strip and the `Bash(CLAUDE_MODEL=* …)` patterns are deleted, not re-pointed). No back-compat alias.
- **`identity.co_authored_by`** — removed from `scripts/ws-commit.sh` resolution and from the ecosystem-config documentation/schema references. (If any realm currently sets it, the migration note is: establish a session identity at orient, or use `--co-author-file`.)
- **`.env`-sourced and inline-env `GDD_CO_AUTHOR`** — removed entirely. `.env.example` drops it; `ws-commit.sh` reads no identity from the environment at all. A human committing without an agent passes `--human` (no trailer); an agent uses its session file or `--co-author-file`. An agent session never consults `.env`.

This directly serves the author's "drop legacy stuff like the old CLAUDE variable before we go GA" intent and the Thalamus note to audit/delete stale agent/model config.

---

## Testing

Bats (deterministic, in-repo):

- `ws-commit.sh` resolution: `--co-author-file <name>` reads the named file and wins over the session file; a missing named file errors; session file used otherwise; **hard error** for an agent session (session id present) with no file (asserting the re-establish message); the `<…@…>` validation rejects no-email/junk identities resolved from a file; an environment `GDD_CO_AUTHOR` is **never consulted** (proves no drift); the no-session case **errors guiding to `--human`**, and `--human` commits with no trailer.
- Session id resolution precedence: `GDD_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` > `CODEX_THREAD_ID`; "none resolves" → error.
- `ws whoami`: bare prints the resolved identity + source (or the no-session note); `--set` writes the file (both the bracketed and split-arg forms); re-establish after a simulated wipe restores a working `ws commit`.
- `ws clean`: spares all session identity files by default; `--sessions` sweeps ended ones but still spares the current session's.
- Hook: `ws commit --co-author-file …` auto-approves (matches `ws commit:*`); the strip is gone; the two security regressions hold (an `LD_PRELOAD=` prefix and an env-prefixed command do not auto-allow).

Manual (cannot be bats'd — requires real agent sessions): the **two-agent acceptance test** — Claude and Codex committing concurrently in the same workspace, each producing the correct `Co-Authored-By`. This is the gate that validates the whole design and the reason Codex (not just Claude) is in Phase 1.

---

## Phase 2+ roadmap — the session-config layer

> **Status update (2026-07-09):** Phase 2 **shipped** via PR #111 — stance (the post-rename term for `mode`) / role / mentoring are session-scoped through `ws session set/get`, retired from Thalamus frontmatter (the template now points at the session file). Phase 3 (allowlist flavors) remains roadmap; the adjacent per-*agent* allowlist question is tracked separately in issue #127.

Phase 1 is the first tenant of a broader idea worth recording (and captured in the Dionysus Thalamus): GDD currently stores `mode:` and `role:` in Thalamus frontmatter, which is **per-workspace**, but those are genuinely **per-session** concerns. One workspace routinely runs concurrent sessions wanting different things — the Scribe-role friction (an open Obsidian session shouldn't force the whole workspace to Scribe while you also do GDD work here), or mentoring-mode + a pointed-at cluster wanting a different allowlist **flavor** that warns on non-tutorial-namespace commands.

The session file Phase 1 introduces is the natural home for all of it: `{identity, mode, role, allowlist-flavor}` keyed by session id, established fresh at orient. It does not replace the Thalamus (durable cross-session memory stays there) — it peels off the things that were only in frontmatter because there was nowhere better.

- **Phase 2:** session-scoped `mode`/`role` — retire them from global frontmatter into the session file; orientation establishes them per session; consumers read the session file. Its own brainstorm → spec.
- **Phase 3:** allowlist **flavors** keyed to session mode (e.g. mentoring + cluster context → namespace-guard warnings). Pairs with the `R1` hook platform-split. Its own brainstorm → spec.

Each is deferred to its own design cycle; Phase 1 only guarantees the file format and orient-write mechanism can carry them.

---

## Open questions / boundaries

- **Model-version accuracy is best-effort.** The agent can confidently-but-wrongly believe its own version (the harness can relabel mid-session, as happened here). Per-session re-determination + human override is the honest ceiling; we do not claim more.
- **Sub-agent session id sharing** is assumed (sub-agents share the parent's `CLAUDE_CODE_SESSION_ID`), which is *why* a sub-agent must name its own file via `--co-author-file` rather than rely on session resolution (which would find the parent's file). If a future harness gives sub-agents distinct ids, `--co-author-file` still works unchanged, and a sub-agent could alternatively write its own session file — so the design holds either way.
- **`CODEX_THREAD_ID` durability** is the one external dependency; the `GDD_SESSION_ID` override is the designed mitigation, and re-validating Codex's session surface is part of the two-agent acceptance test.
