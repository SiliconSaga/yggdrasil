# GDD Orientation, Discoverability & Commit Model Attribution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GDD orientation/discoverability reach agents who skip convention-driven orientation (sub-agents, post-compaction, non-Claude), and keep commit model attribution current — via a deterministic `ws orient` menu, a slim reflex contract, command footers, an adapter-aware hook backstop, and `.env`-driven attribution.

**Architecture:** Progressive-disclosure "buffet": L0 slim `AGENTS.md` menu + reflex contract → L1 deterministic `ws orient` → L2 `ws <cmd> --help`. Portable layers (contract, command, footers, `--help`) carry non-Claude agents; the PreToolUse hook is the Claude-only, adapter-aware backstop. Attribution flows from a self-updating `.env` default plus inline overrides for sub-agents.

**Tech Stack:** Bash (`scripts/ws*.sh`, `.claude/hooks/gdd-permission-hook.sh`), `yq`/`jq`, bats-core test suite (`tests/**/*.bats`, run via `ws test yggdrasil [filter]`), markdown (`AGENTS.md`, `gdd-orientation/SKILL.md`).

**Design:** `docs/plans/2026-06-02-gdd-orientation-and-attribution-design.md`

---

## Conventions for every task

- **Run tests:** `bash scripts/ws test yggdrasil '<filter-regex>'` (filter is a bats `--filter` over test names; omit to run all).
- **Commit:** workspace requires `ws commit` with a bodyfile — never raw `git commit`. Each commit step gives the bodyfile to write under `.commits/`, then run `bash scripts/ws commit yggdrasil .commits/<name>.md` (`ws commit` appends the `Co-Authored-By` trailer automatically).
- **Bats test files** start with `#!/usr/bin/env bats`, `load test_helper`, and a `setup()` calling the helper's init (see `tests/hook/gdd-permission-hook.bats` for the `init_hook_env` + `run_hook` pattern).

---

## File Structure

**Phase 0 (unblocked now):**
- Modify: `.claude/settings.json` — add `ws commit` + two explicit `CLAUDE_MODEL=*` prepend patterns, plus `ws test`/`ws lint`, to `permissions.allow`. **No change to `normalize_for_match`** (a general env-prefix strip is a security loophole — see Task 1).
- Modify: `tests/hook/gdd-permission-hook.bats` — allowlist + security-regression tests.
- Modify: `.env.example` — add `CLAUDE_MODEL`, freshness pass.
- Modify: `scripts/ws-commit.sh` — `commit_help()` documents attribution + sub-agent inline rule; update stale "(default: Opus 4.7)".
- Create: `tests/ws-commit/help.bats` — assert help documents attribution.
- Modify (docs, Task D0): `docs/gdd/permissions.md`, `docs/ws-cli-guide.md`.

**Phase 1 (gated — see Gating Gate below):**
- Create: `scripts/ws-orient.sh` — deterministic menu (subcommand survey + active realm + per-component adapters + skill index).
- Modify: `scripts/ws` — dispatch `orient`; append the L1 footer after subcommand output.
- Create: `tests/ws-orient/orient.bats` — output-shape tests.
- Modify: `.claude/hooks/gdd-permission-hook.sh` + `.claude/hooks/hook-rules` — adapter-aware test/lint redirects.
- Modify: `AGENTS.md` — cut to L0 menu + reflex contract.
- Modify: `.agent/skills/gdd-orientation/SKILL.md` — call `ws orient`; auto-refresh `.env` default; scan adapter commands. **(via `superpowers:writing-skills`)**
- Modify: `tests/smoke.bats` — assert reflex contract + orientation pointer present in `AGENTS.md`.
- Modify (docs, Task D1): `docs/gdd/agent-training.md`, `docs/gdd/trust-and-safety.md`, `docs/gdd/adapters.md`, `docs/gdd/realms.md`, `docs/gdd/features.md`, `docs/gdd/skills-reference.md`, `docs/ws-cli-guide.md`, `docs/gdd/permissions.md`.

---

## Gating Gate (before starting Phase 1)

Do **not** begin Phase 1 until both hold (per the design's sequencing):
1. The 4 in-flight PRs land: realm-siliconsaga #6/#7, heimdall #7, nordri #16.
2. knarr's `ws test`/`ws lint` adapter work ships — so `ws orient`'s adapter enumeration reflects the real adapter schema (it parses those files; the schema must be settled first).

Phase 1 task bodies below specify interfaces + tests now; finalize per-line adapter-parsing once the schema is known. Phase 0 has no such dependency and can execute immediately.

---

# PHASE 0 — Unblocked

## Task 1: Allowlist `ws commit` + explicit attribution-prepend patterns

**Why:** make `ws commit` auto-approved by default (instead of hand-added per workspace), and allow the `CLAUDE_MODEL="…" ws commit` attribution prepend — via **explicit, bounded** patterns, **not** a general env-prefix strip.

**Security note (the reason this task does NOT touch `normalize_for_match`):** a general "strip leading `VAR=value`" would be a privilege escalation. The stripped assignment is removed only for *matching* but stays on the *executed* command, so `LD_PRELOAD=…/evil.so ws status` / `PATH=/tmp/evil ws status` / `GIT_SSH_COMMAND="…" ws push` would auto-approve without a prompt and then run with an attacker-controlled environment. We bound the allowance to `CLAUDE_MODEL`, which is code-execution-inert (only feeds the `Co-Authored-By` trailer string, newline-sanitized at `ws-commit.sh:135`).

**Files:**
- Modify: `.claude/settings.json` (`permissions.allow` array)
- Test: `tests/hook/gdd-permission-hook.bats`

- [ ] **Step 1: Write failing tests** (functional + security regression)

Append to `tests/hook/gdd-permission-hook.bats`:

```bash
# ─── ws commit allowlist + bounded attribution prepend ──────────────

@test "allow: bare 'ws commit' is allowlisted" {
    run_hook "ws commit yggdrasil .commits/x.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: CLAUDE_MODEL prefix on ws commit is allowlisted" {
    run_hook 'CLAUDE_MODEL="Opus 4.8" ws commit yggdrasil .commits/x.md'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: CLAUDE_MODEL prefix on bash scripts/ws commit is allowlisted" {
    run_hook 'CLAUDE_MODEL="Opus 4.8" bash scripts/ws commit yggdrasil .commits/x.md'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ws test / ws lint allowlisted under the realm trust model (design § Adapter
# trust). They run adapter-defined commands; trust is established at realm
# scan/activation (orientation risk-scan) + surfaced by `ws orient`, NOT by
# withholding the allowlist.
@test "allow: ws test is allowlisted" {
    run_hook "ws test knarr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: ws lint is allowlisted" {
    run_hook "ws lint knarr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: a general env-prefix strip must NOT exist — an arbitrary env
# assignment on an allowlisted command must not silently auto-approve.
@test "security: LD_PRELOAD prefix on an allowlisted command does NOT auto-allow" {
    run_hook 'LD_PRELOAD=/tmp/evil.so ws status'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: an env prefix must not bypass a redirect deny.
@test "security: env prefix does NOT let a redirect-denied command through" {
    run_hook 'CLAUDE_MODEL="x" git commit -m y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws commit"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/ws test yggdrasil 'ws commit|CLAUDE_MODEL prefix|ws test is|ws lint is|LD_PRELOAD|env prefix'`
Expected: the five `allow:` tests FAIL (patterns not yet present). The two `security:` tests should already PASS (nothing strips env prefixes today) — they are regression guards that must STAY green after Step 3.

- [ ] **Step 3: Add the three explicit allow patterns**

In `.claude/settings.json`, add to `permissions.allow` (keep the array's existing style/ordering — place near other `ws` entries):

```json
"Bash(ws commit:*)",
"Bash(CLAUDE_MODEL=* ws commit:*)",
"Bash(CLAUDE_MODEL=* bash scripts/ws commit:*)",
"Bash(ws test:*)",
"Bash(ws lint:*)",
```

The bare `Bash(ws commit:*)` covers both `ws commit` and `bash scripts/ws commit` via the *existing* `scripts/` normalization (same for `ws test`/`ws lint`). The two `CLAUDE_MODEL=*` patterns cover the prepend for both dispatch forms (normalization does not reach past a leading env assignment, so both must be listed explicitly). `ws test`/`ws lint` are allowlisted under the realm trust model (design § Adapter trust) — their executed adapter commands are made auditable by `ws orient` (Task 4d) and trust-scanned at realm activation (Task 8), not gated by withholding the allowlist.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/ws test yggdrasil 'ws commit|CLAUDE_MODEL prefix|ws test is|ws lint is|LD_PRELOAD|env prefix'`
Expected: all seven PASS (five allow + two security guards still green). Then the full hook suite:
Run: `bash scripts/ws test yggdrasil 'gdd-permission-hook'`
Expected: PASS (no regressions).

> **Matcher caveat:** if the embedded `CLAUDE_MODEL=*` glob does not match cleanly in the hook's pattern evaluator (verify via Step 4), fall back to a normalization strip scoped to **only** a leading `CLAUDE_MODEL=value` (never arbitrary `VAR=`). That remains safe because `CLAUDE_MODEL` is code-execution-inert; the `LD_PRELOAD` security test still guards the boundary. Do not generalize the strip.

- [ ] **Step 5: Commit**

Write `.commits/allowlist-ws-commit-attribution.md`:

```markdown
---
message: "feat(perms): allowlist ws commit/test/lint + bounded CLAUDE_MODEL attribution prepend"
add:
  - .claude/settings.json
  - tests/hook/gdd-permission-hook.bats
---

Allowlist `ws commit` by default and allow the `CLAUDE_MODEL="…" ws commit`
attribution prepend via explicit, bounded patterns. Also allowlist `ws test`/
`ws lint` under the realm trust model (a realm is an extension of your own
hoards / the team you joined; adapter commands are surfaced by `ws orient` and
trust-scanned at realm activation, not gated by withholding the allowlist).
Deliberately NOT a general env-prefix strip in normalize_for_match — that would
let arbitrary env vars (LD_PRELOAD, PATH, GIT_SSH_COMMAND) ride onto allowlisted
commands with the approval prompt suppressed. Two security regression tests lock
the boundary.
```

Run: `bash scripts/ws commit yggdrasil .commits/allowlist-ws-commit-attribution.md`

---

## Task 2: Add `CLAUDE_MODEL` to `.env.example` + freshness pass

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Add the attribution line**

In `.env.example`, add (mirroring the live `.env`), placed near other exports:

```bash
# Model name used in the ws commit Co-Authored-By trailer (ws-commit.sh).
# The :- form supplies a default but still lets an inline override pass
# through, e.g. CLAUDE_MODEL="Sonnet 4.6" ws commit … for a sub-agent.
export CLAUDE_MODEL="${CLAUDE_MODEL:-Opus 4.8}"
```

- [ ] **Step 2: Freshness pass**

Read `.env.example` top to bottom. Cross-check each documented var against what the scripts actually read today (grep `scripts/` for each var name). Remove or correct any var that no longer exists; add a one-line comment for any script-read var that's missing. Do not add secrets — keep placeholder values.

- [ ] **Step 3: Commit**

Write `.commits/env-example-claude-model.md`:

```markdown
---
message: "docs(env): add CLAUDE_MODEL to .env.example + freshness pass"
add:
  - .env.example
---

Document the CLAUDE_MODEL attribution default (matches live .env) and
reconcile .env.example with the vars the ws scripts actually read.
```

Run: `bash scripts/ws commit yggdrasil .commits/env-example-claude-model.md`

---

## Task 3: Document attribution + sub-agent rule in `ws commit --help`

**Files:**
- Modify: `scripts/ws-commit.sh:38-39` (and surrounding `commit_help`)
- Test: `tests/ws-commit/help.bats` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/ws-commit/help.bats`:

```bash
#!/usr/bin/env bats

# ws commit --help documents model attribution + the sub-agent inline rule.

setup() {
    ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "ws commit --help mentions CLAUDE_MODEL and the .env default" {
    run bash "$ROOT_DIR/scripts/ws-commit.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLAUDE_MODEL"* ]]
    [[ "$output" == *".env"* ]]
}

@test "ws commit --help explains the sub-agent inline override" {
    run bash "$ROOT_DIR/scripts/ws-commit.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"sub-agent"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/ws test yggdrasil 'ws commit --help'`
Expected: FAIL — second test fails (no "sub-agent" text; current help only has the one-line CLAUDE_MODEL note).

- [ ] **Step 3: Update the help text**

In `scripts/ws-commit.sh`, replace the single line at `:39`:

```bash
        echo "Set CLAUDE_MODEL to control the model name (default: Opus 4.7)."
```

with:

```bash
        echo "Model attribution:"
        echo "  The trailer name resolves as: identity.co_authored_by (if set"
        echo "  in the merged ecosystem config) else \"Claude \$CLAUDE_MODEL\"."
        echo "  CLAUDE_MODEL is auto-sourced from .env (the workspace default;"
        echo "  keep it current there rather than prepending it every commit)."
        echo "  SUB-AGENTS: if you commit while running on a non-default model"
        echo "  (e.g. Sonnet vs the workspace Opus default), prepend it inline:"
        echo "    CLAUDE_MODEL=\"Sonnet 4.6\" ws commit <comp> <bodyfile>"
        echo "  Inline is correct for sub-agents — a shared .env rewrite from"
        echo "  parallel sub-agents would race."
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/ws test yggdrasil 'ws commit --help'`
Expected: PASS (both).

- [ ] **Step 5: Commit**

Write `.commits/ws-commit-help-attribution.md`:

```markdown
---
message: "docs(ws-commit): document model attribution + sub-agent inline rule in --help"
add:
  - scripts/ws-commit.sh
  - tests/ws-commit/help.bats
---

Expand `ws commit --help` (the L2 "bite" in the orientation buffet) to cover
attribution resolution, the .env default, and the sub-agent inline override.
```

Run: `bash scripts/ws commit yggdrasil .commits/ws-commit-help-attribution.md`

---

## Task D0: Phase 0 documentation sweep

**Files:**
- Modify: `docs/gdd/permissions.md`
- Modify: `docs/ws-cli-guide.md`

- [ ] **Step 1: Update `docs/gdd/permissions.md`.** Document that `ws commit`, `ws test`, and `ws lint` are allowlisted by default. Document the bounded `CLAUDE_MODEL=*` attribution-prepend patterns. Add a short "Why not a general env-prefix strip" note explaining the `LD_PRELOAD`/`PATH`/`GIT_SSH_COMMAND` escalation (assignment stripped for matching but kept on execution → prompt suppressed) and that the allowance is bounded to the code-execution-inert `CLAUDE_MODEL`.
- [ ] **Step 2: Update `docs/ws-cli-guide.md`.** Under `ws commit`, document attribution: `CLAUDE_MODEL` resolution, the `.env` default, and the sub-agent inline-override rule — mirroring the expanded `--help` from Task 3.
- [ ] **Step 3: Build docs strict.** Run: `mkdocs build --strict` Expected: builds clean, no broken-link/nav warnings. (If `mkdocs` isn't installed locally, note that CI `.github/workflows/docs.yml` enforces `--strict` on merge.)
- [ ] **Step 4: Commit.** Write `.commits/docs-phase0-permissions.md`:

```markdown
---
message: "docs(gdd): document ws commit/test/lint allowlist + attribution (Phase 0)"
add:
  - docs/gdd/permissions.md
  - docs/ws-cli-guide.md
---

Reflect the Phase 0 permission + attribution changes in the GDD docs:
allowlisted ws commit/test/lint, the bounded CLAUDE_MODEL prepend, the
rejected general env-prefix strip, and ws commit attribution behavior.
```

Run: `bash scripts/ws commit yggdrasil .commits/docs-phase0-permissions.md`

---

# PHASE 1 — Gated (see Gating Gate)

> Specified to interface + test level. Finalize adapter-parsing once knarr's `ws lint`/adapter schema ships. Use `superpowers:subagent-driven-development` per task; Task 8 additionally requires `superpowers:writing-skills`.

## Task 4: `ws orient` — deterministic menu command

**Files:**
- Create: `scripts/ws-orient.sh`
- Modify: `scripts/ws` (dispatch `orient`)
- Test: `tests/ws-orient/orient.bats`

Sub-steps (each its own TDD cycle — write bats assertion, run-fail, implement section, run-pass):

- [ ] **4a — Scaffold + dispatch.** `ws-orient.sh` sources `ws-realm.sh`, prints a titled "Workspace toolset (`ws orient`)" header, exits 0. Wire `orient)` into the `scripts/ws` dispatch case. Test: `@test "ws orient runs and prints a header"` asserts status 0 and header text.
- [ ] **4b — Subcommand survey.** Print one line per `ws` subcommand as `name — use when …`. Source the list from a single authored table in `ws-orient.sh` (the "use when" phrasing is judgment, kept here, not in each script). Test asserts presence of `commit`, `test`, `lint`, `orient` rows and the phrase "use when".
- [ ] **4c — Active realm.** Detect the active realm via the same logic `gdd-orientation` Step 0c uses (`ecosystem.local.yaml` `realm:` selector, else a single `realm-*/`). Print "Active realm: <name>" + a pointer to its `AGENTS.md`/realm index skill, or "Active realm: none". Test (fixture realm) asserts the realm name appears.
- [ ] **4d — Per-component adapters (+ resolved command).** For each cloned component, read its adapter (schema per knarr's shipped `ws lint`/`ws test` work) and print which of `ws test`/`ws lint`/`ws build` are wired, e.g. `knarr → ws test [pytest], ws lint [ruff]`; unwired → `foo → no test adapter (wire: …)`. **Also print the resolved command string** — `knarr → ws test [runs: python3 -m pytest tests/]` — so the executed command is auditable despite the `ws` wrapper (adapter-trust mitigation; see design § Adapter trust). Test (fixtures: one wired, one unwired) asserts both forms render and that the wired form includes the `runs:` command. *Finalize parsing against the real schema at execution time.*
- [ ] **4e — Skill index.** List workspace + active-realm skill names + descriptions (frontmatter only, no bodies). Test asserts a known skill name appears with its description.

Commit after each sub-step with a `.commits/ws-orient-<part>.md` bodyfile (`add:` lists `scripts/ws-orient.sh`, `scripts/ws`, `tests/ws-orient/orient.bats`).

## Task 5: Command-output footer

**Files:**
- Modify: `scripts/ws` (append footer after a subcommand completes)
- Test: `tests/ws-smoke/read-only.bats` (extend)

- [ ] Add a `_ws_footer()` emitting one dim line to **stderr** after subcommand dispatch (stderr so it never pollutes captured stdout/piped data): `↪ switching tasks? \`ws orient\` lists the toolset for what's here.` Suppress for `orient` itself and for `--help`/`help`. Test: `@test "ws status prints the orient footer on stderr"` runs `ws status`, asserts the footer text on stderr and that stdout is unaffected. Commit (`.commits/ws-footer.md`).

## Task 6: Adapter-aware test/lint hook redirects

**Files:**
- Modify: `.claude/hooks/hook-rules` (`[redirect-commands]`)
- Modify: `.claude/hooks/gdd-permission-hook.sh` (adapter-aware branch)
- Test: `tests/hook/gdd-permission-hook.bats`

- [ ] Add redirect entries for `pytest`/`python -m pytest`/`gradle test` → `ws test` and `ruff`/`black`/`mypy` → `ws lint`. In the hook, when a test/lint redirect matches, resolve the target component from `$cwd` and check adapter presence:
  - adapter wired → **deny-with-bypass** (message: "use `ws test` — adapter wired; `ws test --help` for filters"), reusing the existing `ws hook-bypass` machinery.
  - no adapter → **allow** + one-time nudge (message: "no `ws test` adapter for <comp> yet — consider wiring one; running raw this time").
- [ ] Tests: `@test "deny: raw pytest in a component WITH a test adapter"`, `@test "allow+nudge: raw pytest in a component WITHOUT an adapter"`, `@test "deny: raw ruff with a lint adapter"`. Use fixture component dirs with/without adapters. Commit (`.commits/hook-adapter-aware-redirects.md`).

## Task 7: Cut `AGENTS.md` to L0 + reflex contract

**Files:**
- Modify: `AGENTS.md`
- Test: `tests/smoke.bats` (extend)

- [ ] Replace the fat § Skills + § Workspace CLI prose with: a slim utilities menu (one-liners), the "active realm present — load its skills on demand" note, the reflex contract block (unconditional verbs commit/push/cr/issue/clone/exec + the `ws orient` meta-rule for test/lint/build), and the single hard pointer: "read the orientation skill at session start / after compaction / when dispatched fresh." Keep deep content discoverable via `ws orient`/`--help`, not inline.
- [ ] Test: `@test "AGENTS.md carries the reflex contract and orientation pointer"` greps `AGENTS.md` for the contract marker line and the orientation-skill pointer. Commit (`.commits/agents-md-l0-cut.md`).

## Task 8: Rework `gdd-orientation` skill — call `ws orient` + auto-refresh `.env`

**REQUIRED SUB-SKILL:** `superpowers:writing-skills` (authoring/restructuring a skill).

**Files:**
- Modify: `.agent/skills/gdd-orientation/SKILL.md`

- [ ] Use `superpowers:writing-skills` to restructure the startup sequence so the factual steps **call `ws orient`** (single deterministic source) instead of re-describing the toolset in prose; the skill keeps only judgment (trust verification, mode/role, tone, stale-audit).
- [ ] Add a startup step: the agent knows its own model — if `.env`'s `CLAUDE_MODEL` default token is stale vs the running model, rewrite just that token (preserve the `${CLAUDE_MODEL:-…}` form so inline overrides still win). Keep this a main-agent-only step (sub-agents use the inline rule from Task 3).
- [ ] **Extend the risk/trust-verification step to adapter commands.** The skill already watches for "evil" instructions in components/skills; on realm scan/activation it must also read the active realm's **adapter command strings** (alongside AGENTS.md + realm skills), flagging `curl|sh` / base64 / out-of-repo writes / network calls in a test/lint command and noting findings in Thalamus. Scale rigor by realm provenance (own/team realm light; wild/internet realm heavy). This is the load-bearing counterpart to blanket-allowlisting `ws test`/`ws lint` — see design § Adapter trust.
- [ ] Verify per writing-skills (RED test below). Commit (`.commits/gdd-orientation-ws-orient.md`).

## Task D1: Phase 1 documentation sweep

**Files:**
- Modify: `docs/gdd/agent-training.md`, `docs/gdd/trust-and-safety.md`, `docs/gdd/adapters.md`, `docs/gdd/realms.md`, `docs/gdd/features.md`, `docs/gdd/skills-reference.md`, `docs/ws-cli-guide.md`, `docs/gdd/permissions.md`

Each doc its own edit → build-strict → keep going; one commit at the end.

- [ ] **`docs/gdd/agent-training.md` (largest).** Document the progressive-disclosure "buffet" (L0 slim AGENTS.md + reflex contract → L1 `ws orient` → L2 `ws <cmd> --help`), the tripwire-verb reflex contract as the reassess trigger, the per-command footer, and the hook as the Claude-only backstop.
- [ ] **`docs/gdd/trust-and-safety.md`.** Trust verification now covers **adapter commands** (alongside AGENTS.md + realm skills) at realm scan/activation; provenance-scaled rigor (own/team realm light, wild/internet realm heavy).
- [ ] **`docs/gdd/adapters.md`.** Adapter trust model + executable-config-surface framing; `ws orient` surfaces the resolved command per component.
- [ ] **`docs/gdd/realms.md`.** "A realm is an extension of your own hoards / the team you joined" trust framing, or a pointer to `trust-and-safety.md` as canonical.
- [ ] **`docs/gdd/features.md`.** Add `ws orient` + the reflex/footer discoverability layer as features.
- [ ] **`docs/gdd/skills-reference.md`.** `gdd-orientation` now calls `ws orient`, auto-refreshes the `.env` default, and scans adapter commands.
- [ ] **`docs/ws-cli-guide.md`.** Add the `ws orient` subcommand (purpose, what it surveys, the resolved-command surfacing).
- [ ] **`docs/gdd/permissions.md`.** The adapter-aware test/lint hook redirects (allow-with-nudge when unwired; deny-with-bypass when wired).
- [ ] **Build docs strict.** Run: `mkdocs build --strict` Expected: clean (no broken-link/nav warnings).
- [ ] **Commit.** Write `.commits/docs-phase1-orientation.md` (`add:` lists all eight docs above); message: `docs(gdd): document ws orient, reflex contract, adapter trust + orientation rework (Phase 1)`. Run: `bash scripts/ws commit yggdrasil .commits/docs-phase1-orientation.md`

---

## Testing — RED test (whole-feature acceptance)

After Phase 1, dispatch a fresh sub-agent with the knarr scenario verbatim: "you're working on this Python component, run the pytest suite + lint."
- **Expected post-change:** it consults `ws orient`, finds `knarr → ws test [pytest] / ws lint [ruff]`, and runs those instead of raw `pytest`/`ruff`.
- **No-adapter variant:** point it at a component with no adapter; confirm the hook **allows-with-nudge** rather than spinning on a deny.
Run the same against the paused Knarr session (this workspace) and the Heimdall session (Loki) for independent-context coverage.

Full suite green gate: `bash scripts/ws test yggdrasil` → all bats pass.

---

## Self-Review (against the design)

- **Spec coverage:** L0/L1/L2 hierarchy → Tasks 4,5,7; reflex contract → Task 7; footer → Task 5; adapter-aware hook → Task 6; active realm → Task 4c; attribution (.env default/example/help/allowlist/prepend) → Tasks 1,2,3 + Task 8 auto-refresh; `ws orient`/skill split → Tasks 4,8. Cross-agent portability is satisfied by Tasks 4/5/7 living in non-hook layers. ✔
- **Phasing:** Phase 0 (Tasks 1-3 + D0) has no gating dependency; Phase 1 (Tasks 4-8 + D1) sits behind the Gating Gate. ✔
- **Docs coverage:** the GDD prose impacted is covered by Tasks D0 (permissions, ws-cli-guide) and D1 (agent-training, trust-and-safety, adapters, realms, features, skills-reference, ws-cli-guide, permissions); each verified with `mkdocs build --strict`. ✔
- **No raw git:** every commit step uses `ws commit` + bodyfile. ✔
- **Open design questions** (naming `ws orient`; allow-with-nudge vs always-deny for unwired test/lint; exact tripwire-verb set) are surfaced for the reviewer and do not block Phase 0.
