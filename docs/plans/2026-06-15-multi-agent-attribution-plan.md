# Session-Scoped Commit Attribution (Phase 1) Implementation Plan

> **Revision (2026-06-16, during implementation):** The embedded task steps below started as the implementation draft; the as-built behavior differs in the places listed here and the as-built behavior wins over older snippets. The sub-agent escape hatch is no longer an inline `GDD_CO_AUTHOR=` env prefix (the required `<email>` angle brackets trip the permission hook's Tier 1 redirect deny), so the hook strip + `CLAUDE_MODEL=`→`GDD_CO_AUTHOR=` allowlist swap were dropped. Instead: sub-agents use `ws commit --co-author-file <name>` (reads `.tmp/gdd-agent-sessions/<name>.env`), the hook's attribution-prefix strip is **removed**, the `CLAUDE_MODEL=` allowlist patterns are **deleted** (no replacement — the flag matches `ws commit:*`), the inline-env and `.env`-sourced identity rungs are **dropped**, and the no-session case is a **hard error guiding to `--human`** rather than a silent no-trailer commit. PR review dogfooding also added a Codex-specific hardening fix: `ws review` multi-remote probing must report network/auth/provider lookup failures distinctly from true PR-not-found results. See the design doc's **Revision** note for the full rationale.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ws commit` attribute the right agent per session — resolving the `Co-Authored-By` identity from a per-session file established fresh at orient — so concurrent Claude + Codex sessions never collide or drift, and drop the legacy `CLAUDE_MODEL` / `identity.co_authored_by` paths.

**Architecture:** A tiny sourced helper (`scripts/ws-session.sh`) resolves the current session id (`GDD_SESSION_ID` → `CLAUDE_CODE_SESSION_ID` → `CODEX_THREAD_ID`) and reads/writes a per-session identity file at `.tmp/gdd-agent-sessions/<session-id>.env`. `ws commit` resolves identity as: `--human` suppresses the trailer, otherwise `--co-author-file <name>` wins for sub-agents, otherwise the current session file wins, otherwise the command hard-errors with guidance. There is no inline-env identity rung and no `.env`-sourced fallback. `ws whoami` shows/sets the session identity; orientation writes it; `ws clean` spares the current session's file. The old `CLAUDE_MODEL=` hook/allowlist bridge is deleted rather than replaced.

**As-built delta map:** Any older code block below that mentions inline `GDD_CO_AUTHOR=`, `.env` identity fallback, `strip_gdd_co_author_prefix`, or `GDD_CO_AUTHOR=*` allowlist entries is historical draft material. The live implementation uses `--co-author-file` for sub-agents, parses session identity files as data rather than shell, keeps `.env` out of attribution, deletes legacy `CLAUDE_MODEL=` allowances without replacement, and treats `ws review` provider lookup failures separately from 404/not-found misses.

**Tech Stack:** Bash 4+ (`scripts/ws*` + `.claude/hooks/gdd-permission-hook.sh`), bats-core (vendored at `tests/vendor/bats-core/`), `jq`/`yq`, markdown. Design: `docs/plans/2026-06-15-multi-agent-attribution-design.md`.

---

## Context the executing engineer needs

- **Branch:** all work lands on `feat/session-scoped-attribution` (already created off main, design doc already committed there). One PR via `ws cr` at the end.
- **Commit convention:** use `ws commit yggdrasil .commits/<name>.md` (never raw `git commit`). Write the bodyfile to `.commits/` with `add:` frontmatter. The trailer is appended automatically. **Note:** once Task 2 lands, *your own* `ws commit` needs a resolvable identity — the test helper handles tests, but for real commits ensure your session has one (`ws orient`, or `ws whoami --set "Codex GPT-5" noreply@openai.com` / the Claude equivalent).
- **Run tests:** `ws test yggdrasil` runs every `*.bats`. Focused loop: `bash tests/vendor/bats-core/bin/bats tests/<dir>/`.
- **No hard-wrapped prose** in markdown (single-line paragraphs/bullets) — `gdd-doc-writing`, enforced.
- **Fresh-shell-per-call:** each Bash tool call is a new shell; exported env does not persist. The session id is present in *every* call's env (harness-injected), which is why a per-call file keyed by it works. `ws hook-bypass` already reads `CLAUDE_CODE_SESSION_ID` this way (`scripts/ws-hook-bypass.sh:162`).
- **`.env` is sourced by some `ws` flows for tokens, but commit identity is not read from `.env`.** Identity comes only from `--co-author-file` or the current session file unless the caller passes `--human`.
- **Key current code:** the resolution block to replace is `scripts/ws-commit.sh:137-166`; the email validation (`email_re`) at 154-165 is reused as-is. Historical hook/settings work around `CLAUDE_MODEL=` was rejected during implementation and is not live scope. The orientation step to rewrite is `.agent/skills/gdd-orientation/SKILL.md:144-164`.

---

## File Structure

- **Create** `scripts/ws-session.sh` — sourced helper: `ws_resolve_session_id`, `ws_session_identity_path`, `ws_resolve_co_author`, `ws_write_session_identity`. One responsibility: session id + identity file.
- **Create** `scripts/ws-whoami.sh` — the `ws whoami` / `ws whoami --set` command.
- **Create** `tests/ws-session/` + `tests/ws-whoami/` — bats for the above.
- **Modify** `scripts/ws-commit.sh` — capture inline pre-`.env`; replace resolution block with `ws_resolve_co_author`; update help.
- **Modify** `scripts/ws` — dispatch `whoami`; add help line; add session-file carve-out to `ws_clean`.
- **Modify** `tests/ws-commit/test_helper.bash` — establish a deterministic test session identity.
- **Modify** `.agent/skills/gdd-orientation/SKILL.md` — write session file instead of `.env`.
- **Modify** `.env.example`, `docs/gdd/permissions.md`, `docs/ws-cli-guide.md` — legacy removal + doc updates.
- **Do not modify** `.claude/hooks/gdd-permission-hook.sh` / `.claude/settings.json` for a `GDD_CO_AUTHOR=` prefix replacement; that path was superseded by `--co-author-file`.

---

## Task 1: Session helper (`scripts/ws-session.sh`)

**Files:**
- Create: `scripts/ws-session.sh`
- Create: `tests/ws-session/session.bats`, `tests/ws-session/test_helper.bash`

- [ ] **Step 1: Write the helper**

Create `scripts/ws-session.sh`:

```bash
#!/usr/bin/env bash
# ws-session.sh — per-session identity helpers (sourced, never executed).
#
# Resolves the current agent session's id and the path to its identity
# file under .tmp/gdd-agent-sessions/<id>.env. See
# docs/plans/2026-06-15-multi-agent-attribution-design.md.

: "${ROOT_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"

# Resolve the current session id, first match wins:
#   GDD_SESSION_ID         explicit override (tests; harness w/o native id)
#   CLAUDE_CODE_SESSION_ID  Claude Code (present in every Bash call)
#   CODEX_THREAD_ID         Codex (observed; best-effort)
# Echoes the id, or empty string if none resolves.
ws_resolve_session_id() {
    printf '%s' "${GDD_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-}}}"
}

# Echo the identity-file path for the current session, or empty if no
# session id resolves. The id is filename-sanitized defensively.
ws_session_identity_path() {
    local sid; sid="$(ws_resolve_session_id)"
    [[ -z "$sid" ]] && return 0
    local safe="${sid//[^A-Za-z0-9._-]/_}"
    printf '%s' "${ROOT_DIR}/.tmp/gdd-agent-sessions/${safe}.env"
}

# Write the current session's identity file with GDD_CO_AUTHOR=<$1>.
# Returns 1 (with guidance on stderr) if no session id resolves.
ws_write_session_identity() {
    local identity="$1" path; path="$(ws_session_identity_path)"
    if [[ -z "$path" ]]; then
        echo "ERROR: No session id (GDD_SESSION_ID / CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID) — cannot write a session identity file." >&2
        echo "  In a non-agent shell, set GDD_CO_AUTHOR inline at commit time instead." >&2
        return 1
    fi
    mkdir -p "$(dirname "$path")"
    printf 'GDD_CO_AUTHOR="%s"\n' "$identity" > "$path"
}

# Resolve the Co-Authored-By identity for the current session.
# $1 = inline override (the pre-.env-source GDD_CO_AUTHOR), may be empty.
# Echoes the identity and returns 0; on failure prints guidance to stderr
# and returns 1. See the design doc's resolution chain.
ws_resolve_co_author() {
    local inline="${1:-}"
    if [[ -n "$inline" ]]; then printf '%s' "$inline"; return 0; fi
    local sid; sid="$(ws_resolve_session_id)"
    if [[ -n "$sid" ]]; then
        local path val; path="$(ws_session_identity_path)"
        if [[ -f "$path" ]]; then
            val="$( source "$path" >/dev/null 2>&1; printf '%s' "${GDD_CO_AUTHOR:-}" )"
            if [[ -n "$val" ]]; then printf '%s' "$val"; return 0; fi
        fi
        echo "ERROR: No commit identity for this session (it may have been cleared by 'ws clean', or orientation hasn't set it)." >&2
        echo "  Re-establish: 'ws orient', or 'ws whoami --set \"Name <email>\"'." >&2
        return 1
    fi
    # No agent session (human/script): discouraged .env GDD_CO_AUTHOR fallback.
    if [[ -n "${GDD_CO_AUTHOR:-}" ]]; then printf '%s' "$GDD_CO_AUTHOR"; return 0; fi
    echo "ERROR: No commit identity. In an agent session run 'ws orient' or 'ws whoami --set \"Name <email>\"'." >&2
    echo "  One-off manual commit: GDD_CO_AUTHOR=\"Name <email>\" ws commit <comp> <bodyfile>" >&2
    echo "  Repeated manual commits may set GDD_CO_AUTHOR in .env (discouraged — agent sessions ignore it)." >&2
    return 1
}
```

- [ ] **Step 2: Write the test helper**

Create `tests/ws-session/test_helper.bash`:

```bash
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SESSION_LIB="$REPO_ROOT/scripts/ws-session.sh"

setup_session_env() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$ROOT_DIR/.tmp"
    # Neutralize any inherited harness ids so GDD_SESSION_ID is authoritative.
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID GDD_SESSION_ID GDD_CO_AUTHOR
}

# Run a bash snippet with ws-session.sh sourced, echoing one function's result.
run_session() { run bash -c "ROOT_DIR='$ROOT_DIR'; source '$SESSION_LIB'; $1"; }
```

- [ ] **Step 3: Write failing tests**

Create `tests/ws-session/session.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() { setup_session_env; }

@test "session id precedence: GDD_SESSION_ID wins" {
    run_session 'GDD_SESSION_ID=g CLAUDE_CODE_SESSION_ID=c CODEX_THREAD_ID=x ws_resolve_session_id'
    [ "$output" = "g" ]
}
@test "session id precedence: CLAUDE before CODEX" {
    run_session 'CLAUDE_CODE_SESSION_ID=c CODEX_THREAD_ID=x ws_resolve_session_id'
    [ "$output" = "c" ]
}
@test "session id: CODEX when only it is set" {
    run_session 'CODEX_THREAD_ID=x ws_resolve_session_id'
    [ "$output" = "x" ]
}
@test "session id: empty when none set" {
    run_session 'ws_resolve_session_id'
    [ -z "$output" ]
}
@test "identity path: under .tmp/gdd-agent-sessions keyed by id" {
    run_session 'GDD_SESSION_ID=abc ws_session_identity_path'
    [[ "$output" == *"/.tmp/gdd-agent-sessions/abc.env" ]]
}
@test "write + resolve round-trips via the session file" {
    run_session 'GDD_SESSION_ID=s1 ws_write_session_identity "Claude Opus 4.8 <noreply@anthropic.com>"; GDD_SESSION_ID=s1 ws_resolve_co_author ""'
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Opus 4.8 <noreply@anthropic.com>" ]
}
@test "resolve: inline override wins over session file" {
    run_session 'GDD_SESSION_ID=s1 ws_write_session_identity "Claude Opus 4.8 <noreply@anthropic.com>"; GDD_SESSION_ID=s1 ws_resolve_co_author "Codex GPT-5 <noreply@openai.com>"'
    [ "$output" = "Codex GPT-5 <noreply@openai.com>" ]
}
@test "resolve: agent session with no file hard-errors" {
    run_session 'GDD_SESSION_ID=s1 ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}
@test "resolve: no session uses discouraged .env GDD_CO_AUTHOR" {
    run_session 'GDD_CO_AUTHOR="Human Dev <dev@example.com>" ws_resolve_co_author ""'
    [ "$status" -eq 0 ]
    [ "$output" = "Human Dev <dev@example.com>" ]
}
@test "resolve: no session, no .env → guidance error" {
    run_session 'ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity."* ]]
}
@test "resolve: .env value ignored when a session id is present" {
    run_session 'GDD_SESSION_ID=s1 GDD_CO_AUTHOR="Drifty <x@y.z>" ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}
```

- [ ] **Step 4: Run to verify failure**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-session/`
Expected: FAIL (file `scripts/ws-session.sh` not yet sourced cleanly / functions undefined) until Step 1's file exists; once it exists, all pass.

- [ ] **Step 5: Run to verify pass**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-session/`
Expected: all PASS.

- [ ] **Step 6: Commit**

Write `.commits/t1-ws-session.md` (`add:` `scripts/ws-session.sh`, `tests/ws-session/session.bats`, `tests/ws-session/test_helper.bash`) with message `feat(ws): session-id + per-session identity helpers (ws-session.sh)`, then `ws commit yggdrasil .commits/t1-ws-session.md`.

---

## Task 2: `ws commit` resolution rewrite

**Files:**
- Modify: `scripts/ws-commit.sh` (top capture + source; resolution block 137-166; help 40-52)
- Modify: `tests/ws-commit/test_helper.bash` (establish a test session identity)

- [ ] **Step 1: Update the test helper to establish a session identity**

In `tests/ws-commit/test_helper.bash`, inside `init_synthetic_repo()` after `export ROOT_DIR="$REPO_DIR"`, add:

```bash
    # Deterministic session identity for resolution (Task 2). GDD_SESSION_ID
    # wins over any inherited CLAUDE_CODE_SESSION_ID, so tests are hermetic.
    export GDD_SESSION_ID="ws-commit-test"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
    mkdir -p "$REPO_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR="Claude Opus 4.8 <noreply@anthropic.com>"\n' \
        > "$REPO_DIR/.tmp/gdd-agent-sessions/ws-commit-test.env"
```

- [ ] **Step 2: Run existing ws-commit tests to confirm they still pass with the helper change (pre-impl, should still use old resolution)**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-commit/`
Expected: PASS (helper now also sets GDD_SESSION_ID + a file; old resolution ignores them — still green).

- [ ] **Step 3: Capture inline GDD_CO_AUTHOR before sourcing `.env`, and source the session helper**

In `scripts/ws-commit.sh`, replace lines 17-22:

```bash
# Auto-source .env so agent attribution and other env are available
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"
```

with:

```bash
# Capture an inline GDD_CO_AUTHOR override BEFORE sourcing .env, so an
# explicit `GDD_CO_AUTHOR=… ws commit` prefix (the sub-agent escape) is
# distinguishable from a value that merely sits in .env (the discouraged
# human-manual fallback). See ws-session.sh / the design doc.
_INLINE_CO_AUTHOR="${GDD_CO_AUTHOR:-}"

# Auto-source .env so tokens (and the discouraged human-manual .env
# GDD_CO_AUTHOR) are available.
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"
# shellcheck source=ws-session.sh
source "$SCRIPT_DIR/ws-session.sh"
```

- [ ] **Step 4: Replace the resolution block**

In `scripts/ws-commit.sh`, replace lines 137-151 (from `# --- Build Co-Authored-By trailer from identity config ---` through the `fi` that closes the `elif [[ "$co_authored_by" != *"<"* ]]` block) with:

```bash
# --- Resolve the Co-Authored-By identity (session-scoped) ---
# Rungs: inline override → session file (agent) / discouraged .env (no
# agent) → hard error. No identity.co_authored_by, no CLAUDE_MODEL.
if ! co_authored_by="$(ws_resolve_co_author "$_INLINE_CO_AUTHOR")"; then
    exit 1
fi
```

Leave lines 152-166 (newline sanitize, `email_re` validation, `trailer=`) unchanged.

- [ ] **Step 5: Update the help text**

In `scripts/ws-commit.sh`, replace the "Model attribution:" block (lines 40-52) with:

```bash
        echo "Identity (Co-Authored-By trailer):"
        echo "  Resolved per session, not from static config:"
        echo "    1. inline GDD_CO_AUTHOR=\"…\" prefix (sub-agent escape)"
        echo "    2. this session's identity file (set at 'ws orient' or"
        echo "       'ws whoami --set'), keyed by the session id"
        echo "    3. else error — establish one (no silent fallback)"
        echo "  A non-agent shell (no session id) may use a discouraged"
        echo "  GDD_CO_AUTHOR in .env. Identity must include an email:"
        echo "    GDD_CO_AUTHOR=\"Codex GPT-5 <noreply@openai.com>\""
        echo "  Run 'ws whoami' to see who this session commits as."
```

- [ ] **Step 6: Add resolution tests to `tests/ws-commit/dry-run.bats`**

Append:

```bash
@test "inline GDD_CO_AUTHOR overrides the session file" {
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" "test: inline wins" "test.md"
    GDD_CO_AUTHOR="Codex GPT-5 <noreply@openai.com>" \
        run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Co-Authored-By: Codex GPT-5 <noreply@openai.com>"* ]]
}

@test "session file supplies identity when no inline" {
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" "test: session file" "test.md"
    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"* ]]
}

@test "agent session with no identity file hard-errors" {
    rm -f "$REPO_DIR/.tmp/gdd-agent-sessions/ws-commit-test.env"
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" "test: no identity" "test.md"
    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}

@test ".env GDD_CO_AUTHOR is ignored when a session id is present" {
    rm -f "$REPO_DIR/.tmp/gdd-agent-sessions/ws-commit-test.env"
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" "test: env ignored" "test.md"
    # Simulate a stale .env value via the process env; session id still set.
    GDD_CO_AUTHOR="" run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -ne 0 ]
}
```

(The existing `GDD_CO_AUTHOR without an email`/`junk` tests still pass — inline still flows through the `email_re` validation.)

- [ ] **Step 7: Run the ws-commit suite**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-commit/`
Expected: all PASS, including the four new cases.

- [ ] **Step 8: Commit**

Write `.commits/t2-ws-commit-resolution.md` (`add:` `scripts/ws-commit.sh`, `tests/ws-commit/test_helper.bash`, `tests/ws-commit/dry-run.bats`) with message `feat(ws): ws commit resolves identity per session (inline → session file → error)`, then `ws commit yggdrasil .commits/t2-ws-commit-resolution.md`.

---

## Task 3: `ws whoami` command

**Files:**
- Create: `scripts/ws-whoami.sh`
- Modify: `scripts/ws` (dispatch + help header)
- Create: `tests/ws-whoami/whoami.bats`, `tests/ws-whoami/test_helper.bash`

- [ ] **Step 1: Write `scripts/ws-whoami.sh`**

```bash
#!/usr/bin/env bash
# ws-whoami.sh — show or set the current session's commit identity.
# ws:use-when checking or setting who 'ws commit' will attribute as
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
_INLINE_CO_AUTHOR="${GDD_CO_AUTHOR:-}"
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"
source "$SCRIPT_DIR/ws-session.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: ws whoami [--set "Name <email>"]

  (no args)            Print the identity this session commits as, and how
                       it resolved (inline / session file / none).
  --set "Name <email>" Write this session's identity file (the re-establish
                       path; what 'ws orient' does automatically).
HELP
    exit 0
fi

if [[ "${1:-}" == "--set" ]]; then
    identity="${2:-}"
    [[ -n "$identity" ]] || { echo "ERROR: --set needs an identity, e.g. --set \"Codex GPT-5 <noreply@openai.com>\"" >&2; exit 1; }
    email_re='<[^[:space:]@<>]+@[^[:space:]@<>]+>'
    [[ "$identity" =~ $email_re ]] || { echo "ERROR: identity must include an email in angle brackets, e.g. \"Codex GPT-5 <noreply@openai.com>\"" >&2; exit 1; }
    ws_write_session_identity "$identity" || exit 1
    echo "Session identity set: $identity"
    exit 0
fi

if [[ -n "$1" ]] 2>/dev/null; then
    echo "ERROR: unknown argument '$1'. Run 'ws whoami --help'." >&2; exit 1
fi

if id="$(ws_resolve_co_author "$_INLINE_CO_AUTHOR")"; then
    if [[ -n "$_INLINE_CO_AUTHOR" ]]; then src="inline GDD_CO_AUTHOR"
    elif [[ -n "$(ws_resolve_session_id)" ]]; then src="session file"
    else src="discouraged .env"; fi
    echo "$id"
    echo "  (via $src)"
else
    exit 1
fi
```

Note: the `if [[ -n "$1" ]] 2>/dev/null` guard tolerates the no-arg case under `set -u` (use `if [[ $# -gt 0 ]]; then` if preferred — equivalent).

- [ ] **Step 2: Wire the dispatcher**

In `scripts/ws`, in the `case "$COMMAND" in` block, add before the `*)` catch-all:

```bash
    whoami)
        bash "$SCRIPT_DIR/ws-whoami.sh" "$@"
        ;;
```

And add to the `# Commands:` help header (after the `clean` line):

```bash
#   whoami [--set "Name <email>"]  Show/set this session's commit identity
```

- [ ] **Step 3: Write the test helper + failing tests**

Create `tests/ws-whoami/test_helper.bash`:

```bash
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"
setup_whoami() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"; mkdir -p "$ROOT_DIR/.tmp"
    export ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"; echo 'components: {}' > "$ECOSYSTEM"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"; echo 'identity: {}' > "$ECOSYSTEM_LOCAL"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID GDD_CO_AUTHOR
    export GDD_SESSION_ID="whoami-test"
}
run_ws() { run env WS_FOOTER_DISABLE=1 bash "$WS_BIN" "$@"; }
```

Create `tests/ws-whoami/whoami.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() { setup_whoami; }

@test "whoami --set writes the session identity, then whoami shows it" {
    run_ws whoami --set "Codex GPT-5 <noreply@openai.com>"
    [ "$status" -eq 0 ]
    run_ws whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *"Codex GPT-5 <noreply@openai.com>"* ]]
    [[ "$output" == *"via session file"* ]]
}
@test "whoami --set rejects an identity with no email" {
    run_ws whoami --set "Codex GPT-5"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must include an email"* ]]
}
@test "whoami errors cleanly when no identity established" {
    run_ws whoami
    [ "$status" -ne 0 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}
@test "whoami --help exits 0" {
    run_ws whoami --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws whoami"* ]]
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-whoami/`
Expected: all PASS.

- [ ] **Step 5: Add a smoke test for the dispatcher**

In `tests/ws-smoke/read-only.bats`, after the `ws diagnose --help` test, add:

```bash
@test "ws whoami --help: exits 0 and prints usage" {
    run_ws whoami --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws whoami"* ]]
}
```

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-smoke/` → Expected: PASS (includes the dispatcher-list regression guard, which now sees `whoami`).

- [ ] **Step 6: Commit**

Write `.commits/t3-ws-whoami.md` (`add:` `scripts/ws-whoami.sh`, `scripts/ws`, `tests/ws-whoami/whoami.bats`, `tests/ws-whoami/test_helper.bash`, `tests/ws-smoke/read-only.bats`) with message `feat(ws): ws whoami shows/sets the session commit identity`, then `ws commit yggdrasil .commits/t3-ws-whoami.md`.

---

## Task 4: `ws clean` spares the current session's identity file

**Files:**
- Modify: `scripts/ws` (`ws_clean` function)
- Modify: `tests/ws-clean/` (add a carve-out test; reuse its helper)

- [ ] **Step 1: Find the `.tmp/` sweep in `ws_clean`**

Read `ws_clean` in `scripts/ws` (the function building `tmp_entries` from `.tmp/`). It collects top-level `.tmp/` entries for `rm -rf`. The carve-out skips the current session's identity file's parent only for that one file.

- [ ] **Step 2: Add the carve-out**

In `ws_clean`, where `.tmp/` top-level entries are gathered for removal, exclude the current session's identity file. Source the helper near the top of `ws_clean` (or rely on it already being sourced by the dispatcher — `scripts/ws` sources `ws-realm.sh`; add `source "$SCRIPT_DIR/ws-session.sh"` near the top of `scripts/ws` alongside it). Then, when iterating `.tmp/` entries, compute `keep="$(ws_session_identity_path)"` once and skip removing exactly that path:

```bash
    local _keep_identity; _keep_identity="$(ws_session_identity_path)"
    # … inside the loop that appends a .tmp/ path $p to the removal list:
        if [[ -n "$_keep_identity" && "$p" == "$_keep_identity" ]]; then
            continue   # spare the current session's identity (self-wipe guard)
        fi
```

Because the identity file is nested (`.tmp/gdd-agent-sessions/<id>.env`), if `ws_clean` removes the whole `.tmp/gdd-agent-sessions/` dir as a single top-level entry, instead remove its children individually except `_keep_identity`. Implement whichever matches the existing loop shape; the invariant the test pins is: after `ws clean --force`, the current session's identity file still exists while a different session's file is gone.

- [ ] **Step 3: Write the test**

In `tests/ws-clean/` add `identity.bats` (load the dir's existing `test_helper`):

```bash
#!/usr/bin/env bats
load test_helper
setup() { init_clean_env 2>/dev/null || true; }  # use the dir's existing setup

@test "ws clean spares the current session's identity, sweeps others" {
    export GDD_SESSION_ID="keep-me"
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR="A <a@b.c>"\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env"
    printf 'GDD_CO_AUTHOR="B <b@c.d>"\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env"
    run env WS_FOOTER_DISABLE=1 bash "$WS_BIN" clean --force
    [ "$status" -eq 0 ]
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env" ]
    [ ! -f "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env" ]
}
```

Adjust the `setup`/var names to match `tests/ws-clean/test_helper.bash` (read it first; it defines `ROOT_DIR`, `WS_BIN`, and the threshold env). Set `WS_CLEAN_MINE_THRESHOLD=1` if needed so `--force` isn't required, or keep `--force` as above.

- [ ] **Step 4: Run**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-clean/`
Expected: all PASS (existing + new).

- [ ] **Step 5: Commit**

Write `.commits/t4-ws-clean-spare-identity.md` (`add:` `scripts/ws`, `tests/ws-clean/identity.bats`) with message `feat(ws): ws clean spares the current session's identity file`, then `ws commit yggdrasil .commits/t4-ws-clean-spare-identity.md`.

---

## Task 5: Orientation writes the session identity

**Files:**
- Modify: `.agent/skills/gdd-orientation/SKILL.md:144-164`

- [ ] **Step 1: Replace the attribution step**

Replace the entire `### Commit attribution refresh (main agent only)` section (lines 144-164) with:

```markdown
### Commit identity (main agent only)

`ws commit` attributes via a per-session identity file, established here. Determine your own identity from what you are — Claude → `Claude <model> <noreply@anthropic.com>`, Codex → `Codex <model> <noreply@openai.com>` — and write it:

```bash
ws whoami --set "Claude Opus 4.8" noreply@anthropic.com
```

Do this **silently** when you are confident of your identity — no prompt; it is one write and the single-agent case stays friction-free. Only **ask the human** if you genuinely cannot determine your model. The value is re-determined fresh each session (that is the whole point — a stale value can't drift in). The human can re-run `ws whoami --set` to correct it any time, and `ws whoami` shows the current resolution.

**Skip this entirely if you're a sub-agent.** A sub-agent writes its own identity file `.tmp/gdd-agent-sessions/<parent-session-id>--<label>.env` (one line: `GDD_CO_AUTHOR=Claude <model> <noreply@anthropic.com>` or the Codex equivalent) and commits with `ws commit --co-author-file <parent-session-id>--<label> …`.
```

- [ ] **Step 2: Verify the skill reads cleanly**

Run: `grep -n "ws whoami --set" .agent/skills/gdd-orientation/SKILL.md`
Expected: the new lines present; no remaining reference to rewriting `.env` for `GDD_CO_AUTHOR`/`CLAUDE_MODEL` in this section (`grep -n "CLAUDE_MODEL" .agent/skills/gdd-orientation/SKILL.md` → no output).

- [ ] **Step 3: Commit**

Write `.commits/t5-orient-identity.md` (`add:` `.agent/skills/gdd-orientation/SKILL.md`) with message `docs(skills): orientation establishes the session commit identity (ws whoami --set)`, then `ws commit yggdrasil .commits/t5-orient-identity.md`.

---

## Task 6: Superseded — no inline-prefix hook strip

**Decision:** Do not move the hook strip from `CLAUDE_MODEL=` to `GDD_CO_AUTHOR=`. The inline-env design is rejected because `GDD_CO_AUTHOR="Name <email>" ws commit …` crosses the Claude hook's Tier 1 redirect parser at the angle brackets, and because Codex-style permissioning should not depend on a Claude-only hook escape hatch.

**As-built behavior:** Sub-agents write a named identity file under `.tmp/gdd-agent-sessions/` and call `ws commit --co-author-file <name> …`. That flag matches the existing `ws commit:*` allow pattern, so no shell env-prefix stripping is needed.

**Verification:** `tests/hook/gdd-permission-hook.bats` keeps the regression that env-prefix tricks such as `GDD_CO_AUTHOR="x" git commit -m y` do not bypass redirect-deny behavior. The hook suite verifies the old `CLAUDE_MODEL=` allowances are gone and no replacement prefix allowances were introduced.

---

## Task 7: Superseded — no `GDD_CO_AUTHOR=` allowlist replacement

**Files:**
- Modify: `.claude/settings.json`
- Modify: `docs/gdd/permissions.md`

**As-built behavior:** Delete the legacy `CLAUDE_MODEL=*` commit allowances without adding `GDD_CO_AUTHOR=*` replacements. The supported sub-agent path is `ws commit --co-author-file <name>`, which is covered by the normal `ws commit:*` allow pattern and is easier to translate to non-Claude agents.

**Doc update:** `docs/gdd/permissions.md` should explain that commit attribution is handled by `ws commit` and session identity files, not by shell env-prefix permissions. Keep the empirical security rows that prove arbitrary env-prefixes still do not bypass deny/ask rules.

**Verification:** Run `ws audit-permissions` and `bash tests/vendor/bats-core/bin/bats tests/ws-audit-permissions/ tests/hook/`; expected result is clean audit output and passing tests.

---

## Task 8: Legacy removal, docs, and Codex dogfood hardening

**Files:**
- Modify: `.env.example`, `docs/ws-cli-guide.md`, `scripts/ws-review.sh`, `scripts/providers/github.sh`, `scripts/providers/gitlab.sh`, `tests/ws-review/probe.bats`

- [ ] **Step 1: Trim `.env.example`**

Remove the `GDD_CO_AUTHOR` default line and the legacy `CLAUDE_MODEL` line from the "Commit attribution" block, replacing with a short note:

```bash
# ── Commit attribution ───────────────────────────────────────
# Commit identity is per-session (set at 'ws orient' / 'ws whoami --set'),
# not configured here. A human in a non-agent shell should pass --human
# when intentionally committing without an agent Co-Authored-By trailer.
```

- [ ] **Step 2: Update `docs/ws-cli-guide.md` attribution section**

Replace the `### Model attribution` resolution list (the `identity.co_authored_by` → `GDD_CO_AUTHOR` → legacy `CLAUDE_MODEL` text and the `.env` default block) with the per-session resolution: `--human` → no trailer, otherwise `--co-author-file <name>` → named session file, otherwise current session file, otherwise hard error. Point at `ws whoami`, `ws commit --help`, and the design doc. Remove the `CLAUDE_MODEL`, `identity.co_authored_by`, inline-env, and `.env` fallback rungs.

- [ ] **Step 2.5: Preserve session files as data, not shell**

`scripts/ws-session.sh` must parse `GDD_CO_AUTHOR=` as a data line rather than `source` identity files. This keeps names containing quotes, `$`, or command-substitution syntax literal and avoids executing a session file. `ws_write_session_identity` writes `GDD_CO_AUTHOR=Name <email>` and rejects embedded newlines.

- [ ] **Step 2.6: Make `ws review` Codex-sandbox friendly**

During Codex dogfooding, `ws review yggdrasil 103` initially reported "not found" because the Codex sandbox blocked network access to GitHub and the multi-remote probe swallowed provider stderr. Fix the probe so provider failures are classified: HTTP 404/not-found remains a miss, but network/auth/API failures report "could not verify" with the provider error. Add a focused regression that stubs `gh api` with a DNS-style failure across multiple remotes.

- [ ] **Step 3: Grep for stragglers**

Run: `grep -rn "CLAUDE_MODEL" scripts/ docs/ .agent/ .claude/ .env.example`
Expected: no functional references remain (historical `docs/plans/*` design docs may mention it — leave those). Any live reference in `scripts/`/`docs/gdd`/skill files must be resolved.

Run: `grep -rn "identity.co_authored_by\|co_authored_by" scripts/`
Expected: no `ws-commit.sh` resolution use remains (the field is gone from the chain).

- [ ] **Step 4: Commit**

Write `.commits/t8-legacy-removal.md` (`add:` `.env.example`, `docs/ws-cli-guide.md`, `scripts/ws-review.sh`, `scripts/providers/github.sh`, `scripts/providers/gitlab.sh`, `tests/ws-review/probe.bats`) with message `refactor(ws): drop legacy attribution fallbacks and harden review probing`, then `ws commit yggdrasil .commits/t8-legacy-removal.md`.

---

## Task 9: Full suite + two-agent acceptance

- [ ] **Step 1: Full suite**

Run: `ws test yggdrasil`
Expected: all green. If any pre-existing test relied on the old attribution fallback (`Claude Opus 4.8` with no inline/session), update it to establish a session identity via the helper pattern from Task 2 Step 1.

- [ ] **Step 2: Real-world smoke (this workspace)**

Run: `ws whoami` → Expected: prints your current identity + source (you set one this session). Run a throwaway `ws commit` (or `--dry-run` via a bodyfile) → Expected: the trailer matches `ws whoami`.

- [ ] **Step 3: Two-agent acceptance (manual — the gate)**

In two terminals against the *same* workspace: one Claude session, one Codex session. In each, run `ws orient` (establishes that session's identity), then make a small commit. Confirm each commit's `Co-Authored-By` matches the agent that made it (Claude vs Codex), with no cross-contamination and no prompts beyond the can't-determine case. Record the result in the PR description. (Codex side also re-validates `CODEX_THREAD_ID` is present; if absent, set `GDD_SESSION_ID` in that session and note it.)

---

## Task 10: Arc/GA docs + PR

- [ ] **Step 1: Update the design doc status**

In `docs/plans/2026-06-15-multi-agent-attribution-design.md`, change `**Status:** Design (approved; ready for implementation plan)` to `**Status:** Implemented (PR <n>)` once the PR opens.

- [ ] **Step 2: Open the PR**

`ws push yggdrasil feat/session-scoped-attribution`, then `ws cr yggdrasil "feat(ws): session-scoped commit attribution (Phase 1)" .crs/session-attribution.md` (draft the body from `templates/change.md`: the resolution chain, the legacy cleanup, the two-agent acceptance result, and a pointer to the design doc + the Phase-2 roadmap). Then triage with `ws review yggdrasil <pr#>`.

- [ ] **Step 3: Thalamus + arc update**

Update the `multi-agent-attribution` arc `next:` in both `Dionysus-thalamus.md` and `FG4WWY622F-thalamus.md` (cross-workspace) to "Phase 1 landed (PR <n>); Phase 2 (session-scoped mode/role) is the next brainstorm." Commit the hoard at the natural endpoint.

---

## Self-Review

**Spec coverage:** resolution chain → Tasks 1-2; session id → Task 1; identity determination at orient → Task 5; session file → Tasks 1, 3, 5; resilience/hard-error → Tasks 1-2; `ws clean` carve-out → Task 4; `ws whoami` → Task 3; sub-agent `--co-author-file` path → Tasks 6-8; legacy hook/allowlist/env fallback removal → Tasks 6-8; Codex-sandbox `ws review` probe hardening → Task 8; testing → every task + Task 9. All spec sections covered.

**Placeholder scan:** every code step shows the actual bash/test code or the exact edit (old→new) and the run command + expected output. The two "match the existing loop/helper shape" notes (Task 4 Step 2, Task 4 Step 3) name the exact invariant to satisfy rather than guessing line numbers in a file whose offsets shift — acceptable because the behavior is pinned by the test.

**Type/name consistency:** `ws_resolve_session_id`, `ws_session_identity_path`, `ws_write_session_identity`, `ws_resolve_co_author`, and `--co-author-file` are used consistently across the helper, `ws whoami`, `ws commit`, tests, and docs. Session files are a one-line data format (`GDD_CO_AUTHOR=Name <email>`), parsed without `source`; legacy quoted files are intentionally not supported.

**Known risk to watch:** tests run inside a real Claude session, so `CLAUDE_CODE_SESSION_ID` is inherited; every test helper that exercises resolution **unsets it and sets `GDD_SESSION_ID`** (Task 1, 2, 3 helpers) so the suite is hermetic. If a forgotten suite inherits it, the symptom is a spurious "No commit identity for this session" — fix by adding the unset/GDD_SESSION_ID lines to that helper.
