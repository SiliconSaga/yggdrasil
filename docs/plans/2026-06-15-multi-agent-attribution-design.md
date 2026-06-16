# Multi-Agent Commit Attribution — Session-Scoped Identity (Phase 1) — Design

**Date:** 2026-06-15
**Status:** Design (approved; ready for implementation plan)
**Arc:** `multi-agent-attribution` (cross-workspace: Dionysus + FG4WWY622F)
**Builds on:** PR #100 (introduced `GDD_CO_AUTHOR` as an agent-neutral trailer identity + `ws push` tags)
**Related:** `docs/plans/2026-06-08-gdd-ga-readiness-design.md` (`R1` hook platform-split — the natural pair), `.claude/hooks/gdd-permission-hook.sh` (`strip_claude_model_prefix`, the prefix-strip precedent), `scripts/ws-hook-bypass.sh` (the `<session-id>` marker precedent this mirrors)

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

## The resolution chain (the heart)

`ws commit` resolves the `Co-Authored-By` identity as follows:

1. **Inline `GDD_CO_AUTHOR`** — captured from the process environment **before** `ws-commit.sh` sources `.env`. Any value present at this point can only have come from an explicit inline prefix (`GDD_CO_AUTHOR="…" ws commit …`), because the resolver never uses a `.env`-sourced value for an agent session (see below). This is the **sub-agent escape hatch** and it wins over everything, because a sub-agent shares its parent's session id and would otherwise resolve to the parent's session file.
2. **Otherwise, branch on whether this is an agent session** — i.e. whether a session id resolves (resolution below):
   - **Agent session** (a session id resolves): the **session file** `.tmp/gdd-agent-sessions/<session-id>.env`. If it is missing → **hard error** (the resilience path). An agent session never falls through to `.env` — that fall-through is exactly the drift this design removes, so a missing file must surface, not silently resolve.
   - **No agent session** (no session id — a human committing manually, or a script): a `GDD_CO_AUTHOR` set in **`.env`**, used **only here** and **explicitly discouraged**. This is the rare human-without-agent escape; it is isolated to the no-session path, so it can never affect an agent session.
3. **If none of the above resolves → error**, with guidance covering every case: `"No commit identity. In an agent session, run 'ws orient' or 'ws whoami --set \"Name <email>\"' to establish one (it may have been cleared by 'ws clean'). For a one-off manual commit, prefix 'GDD_CO_AUTHOR=\"Name <email>\" ws commit …'. For repeated manual commits without an agent you may set GDD_CO_AUTHOR in .env, though this is discouraged — agent sessions establish identity automatically and ignore the .env value."`

What is **removed** or **demoted** from the chain that exists today:

- `identity.co_authored_by` (ecosystem-config pinned override) — **deleted**. Identity must never live above the session level; a stale pinned value can only cause the drift this design exists to prevent.
- The legacy `Claude $CLAUDE_MODEL <…>` fallback — **removed** (see Legacy cleanup).
- `.env`-sourced `GDD_CO_AUTHOR` — **demoted to a discouraged human-manual-only last resort.** It is read *only* when no session id resolves (rung 2's no-agent branch). An **agent** session never consults it, so a stale `.env` value cannot drift agent attribution — the original goal — while a human who genuinely commits without an agent still has a (discouraged) durable option rather than being forced to prefix every commit. `.env` is removed from `.env.example` as a documented default to keep people off it by default.

The email-shaped validation from PR #100 (`<…@…>` required) is retained and applied to whatever the chain resolves.

---

## Session id resolution

The session id keys the session file. It resolves, first match wins:

1. `GDD_SESSION_ID` — optional explicit override. **Not set in normal operation.** Two narrow uses: (a) tests, which must simulate a session without a real harness id; (b) a future harness that injects no usable session var (deferred — see Non-goals).
2. `CLAUDE_CODE_SESSION_ID` — injected by Claude Code into every Bash call's environment. Proven: `ws hook-bypass` already keys its markers on it.
3. `CODEX_THREAD_ID` — Codex's per-thread id, observed present in the environment. Flagged as undocumented; treated as best-effort. If it ever changes or vanishes, a Codex-only workspace can fall back to setting `GDD_SESSION_ID` (case (b) above), and nothing else breaks.

Critically, the session id comes from the harness on **every** call (fresh shells don't persist exports), so orientation and `ws commit` independently read the same value — orientation to *write* the file, `ws commit` to *find* it. No coordination state is needed beyond the file itself.

"No session id resolves at all" (a plain script, or a human in a non-agent terminal) is the no-agent branch of rung 2: a discouraged `.env GDD_CO_AUTHOR` may serve there, and failing that the rung-3 error guides the caller (inline for a one-off; the discouraged `.env` for repeated manual commits; or `ws orient` if they are in an agent session after all). We never invent an identity.

---

## Identity determination (at orientation)

The session file's value is **re-determined fresh each session**, by the agent, at `ws orient`. This is what makes "per-session" an actual refresh rather than a copy of a stale default.

- The agent determines its own identity from its self-knowledge: Claude writes `Claude <model> <noreply@anthropic.com>`; Codex writes `Codex <model> <noreply@openai.com>`. (Provider → default no-reply email is a small built-in table; the model string is the agent's best self-report.)
- **Confident → write silently.** No prompt. This is what keeps the single-agent experience friction-free: orientation already runs every session, and this adds one silent file write.
- **Cannot determine its model → ask the human** for the identity string, then write.
- The human can always override after the fact via `ws whoami --set`.

The value is **never** sourced from `.env` or frontmatter. The hard-refresh-per-session is the whole mechanism for correctness; sourcing from static config would reintroduce drift.

This **replaces** the orientation skill's current "Commit attribution refresh (main agent only)" step, which rewrote `.env`'s `CLAUDE_MODEL`/`GDD_CO_AUTHOR` default (ask-first, per PR #100's review fix). The new step writes the session file instead of `.env`. Sub-agents still skip this step and use the inline override.

---

## Session file

- **Path:** `.tmp/gdd-agent-sessions/<session-id>.env`. Under `.tmp/` (already gitignored; already swept by `ws clean`). Per-workspace by construction — each workspace has its own `.tmp/`, so multiple workspaces on one machine never collide (a case the author flagged as possible).
- **Format:** env-style `KEY=value` lines, sourced or grep-read. Phase 1 writes exactly one line: `GDD_CO_AUTHOR=Claude Opus 4.8 <noreply@anthropic.com>`. The format is the extension point — Phase 2 adds `GDD_MODE=…`, `GDD_ROLE=…`, etc. to the same file.
- **Written by:** orientation (silently/with-ask) and `ws whoami --set`. **Read by:** `ws commit` (and, in Phase 2, mode/role consumers).
- **Lifecycle:** created at orient, lives for the session, pruned by `ws clean` (see Resilience). Stale files from ended sessions are harmless clutter that `ws clean` collects.

---

## Resilience & `ws clean` interaction

The hard-error-on-missing behavior (rung 3) **is** the resilience mechanism, and it falls out for free from the always-on model: every primary session establishes a file at orient, so a *missing* file for a resolvable session id means it was removed mid-session — and `ws commit` says so clearly instead of guessing.

`ws clean` refinement: it **spares the current session's identity file** (the one keyed by the caller's own resolved session id) and sweeps the rest. Rationale: running `ws clean` in your own session shouldn't break your own next commit, but stale files from *other/ended* sessions are exactly the clutter `ws clean` should collect. If a *concurrent* session's file is swept, that session re-establishes on its next commit via the rung-3 error — the scenario the author specified ("a different session trying `ws commit` will just get a clean message to please redo its identity"). The carve-out is a one-line exclusion (skip `<current-session-id>.env`); the simpler "sweep all, everyone re-establishes" is the fallback if the carve-out proves awkward.

---

## `ws whoami` command

A small read-mostly command:

- `ws whoami` — prints the identity `ws commit` would currently use **and how it resolved** (inline / session file / none). Read-only; the "who will this commit as?" check.
- `ws whoami --set "Name <email>"` — writes/rewrites the current session's identity file. The re-establish path the rung-3 error points at. Validates the `<…@…>` shape (shared with `ws commit`). Errors if no session id resolves (telling the caller to set `GDD_SESSION_ID` or use inline).

Naming: `whoami` reads naturally for "which identity am I committing as." Alternative considered: `ws session identity show/set` — rejected as wordier for a frequently-typed check.

---

## Sub-agent inline override + hook/allowlist changes

Sub-agents keep the inline form, now on `GDD_CO_AUTHOR` (not the removed `CLAUDE_MODEL`): `GDD_CO_AUTHOR="Claude Sonnet 4.6 <noreply@anthropic.com>" ws commit …`. For this to auto-approve cleanly (rather than prompt), two existing Claude-specific mechanisms move from `CLAUDE_MODEL` to `GDD_CO_AUTHOR`:

- **Hook prefix strip:** `strip_claude_model_prefix` in `.claude/hooks/gdd-permission-hook.sh` becomes `strip_gdd_co_author_prefix` — strips a single leading `GDD_CO_AUTHOR=<value>` (quoted or unquoted) from the **match copy only** before allow/redirect matching, exactly as the `CLAUDE_MODEL` version did. The security boundary is preserved: `GDD_CO_AUTHOR` is code-execution-inert (it only feeds the newline-sanitized trailer string), so stripping it for matching cannot smuggle a denied command through, and the two security regression tests (an `LD_PRELOAD=` prefix must NOT auto-allow; a prefixed `git commit` must still DENY) are re-pointed at `GDD_CO_AUTHOR` and kept.
- **Allowlist patterns:** the four `Bash(CLAUDE_MODEL=* …commit:*)` entries in `.claude/settings.json` become `Bash(GDD_CO_AUTHOR=* …commit:*)` (both `ws commit:*` and `bash scripts/ws commit:*` dispatch forms). `docs/gdd/permissions.md`'s "Bounded `CLAUDE_MODEL=` attribution prefix" section is rewritten for `GDD_CO_AUTHOR`, and its empirical-matcher rows updated, per that doc's cross-reference rule.

---

## Legacy cleanup (drop pre-GA, clean break)

Pre-1.0, before stricter SemVer applies, this design removes the superseded mechanisms rather than carrying them:

- **`CLAUDE_MODEL`** — removed from `.env.example`, `scripts/ws-commit.sh` (resolution + help text), the orientation skill, and the hook/allowlist (re-pointed to `GDD_CO_AUTHOR` above). No back-compat alias.
- **`identity.co_authored_by`** — removed from `scripts/ws-commit.sh` resolution and from the ecosystem-config documentation/schema references. (If any realm currently sets it, the migration note is: move to a session identity or inline override.)
- **`.env`-sourced `GDD_CO_AUTHOR`** — removed from `.env.example` as a documented default so people don't reach for it by reflex. `ws-commit.sh` still reads it, but *only* in the no-agent-session path (a human committing manually), where it is the discouraged last resort described in the resolution chain. An agent session never consults it.

This directly serves the author's "drop legacy stuff like the old CLAUDE variable before we go GA" intent and the Thalamus note to audit/delete stale agent/model config.

---

## Testing

Bats (deterministic, in-repo):

- `ws-commit.sh` resolution: inline wins over a present session file; session file used when no inline; **hard error** for an agent session (session id present) with no file (asserting the re-establish message); the `<…@…>` validation still rejects no-email/junk identities; a `.env`-set `GDD_CO_AUTHOR` is **ignored when a session id is present** (agent — proves no drift) but **used when no session id resolves** (the discouraged human-manual path); the all-absent case errors with the full guidance message.
- Session id resolution precedence: `GDD_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` > `CODEX_THREAD_ID`; "none resolves" → error.
- `ws whoami`: bare prints the resolved identity + source; `--set` writes the file; re-establish after a simulated wipe restores a working `ws commit`.
- `ws clean`: spares the current session's identity file, sweeps others.
- Hook: `GDD_CO_AUTHOR=` prefix strips for matching (auto-approves the inline form); the two security regressions hold under the rename.

Manual (cannot be bats'd — requires real agent sessions): the **two-agent acceptance test** — Claude and Codex committing concurrently in the same workspace, each producing the correct `Co-Authored-By`. This is the gate that validates the whole design and the reason Codex (not just Claude) is in Phase 1.

---

## Phase 2+ roadmap — the session-config layer

Phase 1 is the first tenant of a broader idea worth recording (and captured in the Dionysus Thalamus): GDD currently stores `mode:` and `role:` in Thalamus frontmatter, which is **per-workspace**, but those are genuinely **per-session** concerns. One workspace routinely runs concurrent sessions wanting different things — the Scribe-role friction (an open Obsidian session shouldn't force the whole workspace to Scribe while you also do GDD work here), or mentoring-mode + a pointed-at cluster wanting a different allowlist **flavor** that warns on non-tutorial-namespace commands.

The session file Phase 1 introduces is the natural home for all of it: `{identity, mode, role, allowlist-flavor}` keyed by session id, established fresh at orient. It does not replace the Thalamus (durable cross-session memory stays there) — it peels off the things that were only in frontmatter because there was nowhere better.

- **Phase 2:** session-scoped `mode`/`role` — retire them from global frontmatter into the session file; orientation establishes them per session; consumers read the session file. Its own brainstorm → spec.
- **Phase 3:** allowlist **flavors** keyed to session mode (e.g. mentoring + cluster context → namespace-guard warnings). Pairs with the `R1` hook platform-split. Its own brainstorm → spec.

Each is deferred to its own design cycle; Phase 1 only guarantees the file format and orient-write mechanism can carry them.

---

## Open questions / boundaries

- **Model-version accuracy is best-effort.** The agent can confidently-but-wrongly believe its own version (the harness can relabel mid-session, as happened here). Per-session re-determination + human override is the honest ceiling; we do not claim more.
- **Sub-agent session id sharing** is assumed (sub-agents share the parent's `CLAUDE_CODE_SESSION_ID`), which is *why* inline wins. If a future harness gives sub-agents distinct ids, inline-wins is still correct (a sub-agent with no file of its own would fall to inline anyway) — so the precedence holds either way.
- **`CODEX_THREAD_ID` durability** is the one external dependency; the `GDD_SESSION_ID` override is the designed mitigation, and re-validating Codex's session surface is part of the two-agent acceptance test.
