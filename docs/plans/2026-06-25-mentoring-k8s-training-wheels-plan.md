# Mentoring Training Wheels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give GDD's mentoring overlay real teeth — a per-session config layer carrying stance/role/mentoring + a k8s practice scope, a guarded `ws k8s` wrapper that hard-blocks out-of-scope cluster writes, and a hook that stops agents reflexively bypassing the guard.

**Architecture:** Extend the Phase-1 session file (`.tmp/gdd-agent-sessions/<id>.env`) with atomic multi-key get/set. Rename the `mode` axis to `stance` and split `mentoring` into a composable boolean. Add a shared guard module (`ws-k8s-guard.sh`) consumed by both `ws k8s` (enforce) and the permission hook (auto-approve in-scope reads, deny known-bad). A dedicated `gdd-k8s` skill owns the practice workflow.

**Tech Stack:** Bash (POSIX-ish, `set -euo pipefail`), `yq`/`jq`, vendored `bats-core` for tests, Markdown skills/docs. Reference: `docs/plans/2026-06-25-mentoring-k8s-training-wheels-design.md` (merged).

## Global Constraints

- **Commits use `ws commit`, never raw git:** `bash scripts/ws commit yggdrasil .commits/<name>.md`. Each commit step gives the bodyfile `message:` and `add:` list. The Co-Authored-By trailer is appended automatically.
- **Tests run via the workspace runner:** `bash scripts/ws test yggdrasil '<bats-filter-regex>'` (vendored bats; a filter matches test names). Full suite: `bash scripts/ws test yggdrasil`.
- **No hard-wrapped prose** in any Markdown added/edited — one line per paragraph/bullet. Code blocks, tables, YAML frontmatter exempt.
- **Session file is data, never sourced:** all reads use line-loop `case "$line" in KEY=*)` parsing with a trailing-`\r` strip (`${line%$'\r'}`). Never `source`/`eval` the file.
- **Bash one-command-per-call** under the hook: no `&&`/`;`/`|` composition in commands the agent runs; use separate calls or native flags.
- **The guard is accident-prevention, not a security boundary** — wrapper help and the `gdd-k8s` skill must say so. Do not claim it withstands a determined adversary.
- **kubectl is stubbed in tests:** the wrapper resolves kubectl via `${KUBECTL:-kubectl}` so tests inject a fake on `PATH`/env. No test touches a real cluster.

---

## File Structure

**Created:**
- `scripts/ws-k8s.sh` — `ws k8s` subcommand: `scope set|show|clear` + guarded passthrough.
- `scripts/ws-k8s-guard.sh` — sourced lib: `k8s_guard_evaluate` (single source of truth for the verdict).
- `scripts/ws-session-config.sh` — thin `ws session get|set|show` CLI over the session helpers.
- `.agent/skills/gdd-k8s/SKILL.md` — the practice workflow skill.
- `docs/gdd/roles-and-stances.md` — renamed/rewritten from `roles-and-modes.md`.
- Tests: `tests/ws-session/config.bats`, `tests/ws-k8s/guard.bats`, `tests/ws-k8s/wrapper.bats`, `tests/ws-k8s/test_helper.bash`, and new cases in `tests/hook/gdd-permission-hook.bats`.

**Modified:**
- `scripts/ws-session.sh` — add `ws_session_get`/`ws_session_set` (atomic), refactor identity read/write through them.
- `scripts/ws` — dispatch arms `session)` and `k8s)`; `# Commands:` help lines.
- `.claude/hooks/gdd-permission-hook.sh` — `[scoped-redirect-commands]` parse arm + new tier loop (redirect + read-auto-approve + temp-script scan).
- `.claude/hooks/hook-rules` — new `[scoped-redirect-commands]` section + the kubectl rule.
- `.claude/settings.json` — allow `Bash(ws session:*)` (read/write of `.tmp` is benign); deliberately NO `ws k8s` allow entry.
- `templates/thalamus.md`, five `hoards/thalami-Cervator/*-thalamus.md` — drop `mode:`/`role:` keys.
- Skills + docs rename sweep: `.agent/skills/{gdd,gdd-orientation,gdd-mentoring,gdd-quick,gdd-zen,gdd-flow,gdd-housekeeping,gdd-review-triage}/SKILL.md`, `docs/gdd/{skills-reference,hoards,features,thalamus,index}.md`, `templates/components/gh-pages/README.md`, `mkdocs.yml`.

---

## Phase 1 — Session-config layer

### Task 1: Atomic `ws_session_get` / `ws_session_set`

**Files:**
- Modify: `scripts/ws-session.sh` (add two functions; refactor `ws_read_identity_file`/`ws_write_session_identity` to use them)
- Test: `tests/ws-session/config.bats` (new), reusing `tests/ws-session/test_helper.bash`

**Interfaces:**
- Produces: `ws_session_get <KEY> [path]` → prints the value of the first `KEY=` line (empty if absent); `ws_session_set <KEY> <VALUE>` → atomic read-modify-write preserving all other keys. Both treat the file as data.
- Consumes: existing `ws_session_identity_path` (`ws-session.sh:31-33`), `ws_session_identity_path_for` (`:22-27`).

- [ ] **Step 1: Write the failing test**

Create `tests/ws-session/config.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup() { setup_session_env; }

@test "session_set then session_get round-trips one key" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = "flow" ]
}

@test "session_set preserves sibling keys (no clobber)" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_session_set GDD_ROLE developer; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = "flow" ]
}

@test "session_set updates an existing key in place" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_session_set GDD_STANCE quick; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = "quick" ]
}

@test "identity and stance coexist in the same file" {
    run_session 'GDD_SESSION_ID=s1 ws_write_session_identity "Claude Opus 4.8 <noreply@anthropic.com>"; GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_resolve_co_author ""'
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Opus 4.8 <noreply@anthropic.com>" ]
}

@test "session_set value is data, not shell" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE "$(echo pwn)"; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = '$(echo pwn)' ]
}

@test "session_set rejects a newline in the value" {
    run_session $'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE "fl\now"'
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/ws test yggdrasil 'session_set'`
Expected: FAIL — `ws_session_set: command not found` (or similar).

- [ ] **Step 3: Add the two functions and refactor identity helpers**

In `scripts/ws-session.sh`, add after `ws_session_identity_path` (line 33):

```bash
# Read a single KEY from the session file (or a given path). Data-only —
# never sourced. Prints the value of the first matching KEY= line; empty
# if absent. Usage: ws_session_get <KEY> [path]
ws_session_get() {
    local key="${1:-}" path="${2:-}"
    [[ -n "$path" ]] || path="$(ws_session_identity_path)"
    [[ -n "$key" && -n "$path" && -f "$path" ]] || return 0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            "$key="*) printf '%s' "${line#"$key="}"; return 0 ;;
        esac
    done < "$path"
}

# Atomic read-modify-write of one KEY in the session file, preserving all
# other keys. Writes to a temp file in the same dir then mv (atomic rename)
# so a concurrent reader never sees a half-written file. Usage:
# ws_session_set <KEY> <VALUE>
ws_session_set() {
    local key="${1:-}" value="${2:-}" path; path="$(ws_session_identity_path)"
    if [[ -z "$path" ]]; then
        echo "ERROR: No session id (GDD_SESSION_ID / CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID) — cannot write session config." >&2
        return 1
    fi
    [[ -n "$key" ]] || { echo "ERROR: ws_session_set requires a KEY." >&2; return 1; }
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        echo "ERROR: session value cannot contain newlines." >&2
        return 1
    fi
    mkdir -p "$(dirname "$path")"
    local tmp; tmp="$(mktemp "$(dirname "$path")/.session.XXXXXX")"
    local found=0 line
    if [[ -f "$path" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            case "$line" in
                "$key="*) printf '%s=%s\n' "$key" "$value" >> "$tmp"; found=1 ;;
                *)        printf '%s\n' "$line" >> "$tmp" ;;
            esac
        done < "$path"
    fi
    [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$path"
}
```

Then refactor the existing helpers to go through them (DRY + makes identity writes merge-preserving). Replace `ws_read_identity_file` body (`:39-53`) to delegate:

```bash
ws_read_identity_file() {
    local path="${1:-}"
    [[ -n "$path" && -f "$path" ]] || return 0
    ws_session_get "GDD_CO_AUTHOR" "$path"
}
```

Replace the final line of `ws_write_session_identity` (the truncating `printf ... > "$path"` at `:68-69`) with a merge-preserving write:

```bash
    # (keep the existing session-id and newline guards above this line)
    ws_session_set "GDD_CO_AUTHOR" "$identity"
}
```

(Note: `ws_session_set` already does `mkdir -p`, so the now-redundant `mkdir -p "$(dirname "$path")"` at `:68` may be removed.)

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'session_set'`
Expected: PASS (all 6).

- [ ] **Step 5: Run the existing session/identity suite for regressions**

Run: `bash scripts/ws test yggdrasil 'round-trips|identity|whoami|co-author'`
Expected: PASS — the identity refactor must not regress `tests/ws-session/session.bats`, `tests/ws-whoami/whoami.bats`, `tests/ws-commit/*`.

- [ ] **Step 6: Commit**

Bodyfile `.commits/p1-session-getset.md` — `message:` `feat(ws): add atomic ws_session_get/set; route identity through them`; `add:` `scripts/ws-session.sh`, `tests/ws-session/config.bats`.
Run: `bash scripts/ws commit yggdrasil .commits/p1-session-getset.md`

### Task 2: `ws session` CLI subcommand

**Files:**
- Create: `scripts/ws-session-config.sh`
- Modify: `scripts/ws` (dispatch arm + `# Commands:` help line), `.claude/settings.json` (allow `ws session`)
- Test: `tests/ws-session/cli.bats` (new), reusing `tests/ws-whoami/test_helper.bash` style

**Interfaces:**
- Produces: `ws session get <KEY>` (prints value), `ws session set <KEY> <VALUE>` (writes, echoes confirmation), `ws session show` (prints all `KEY=value` lines). Errors with usage on unknown subcommand.
- Consumes: `ws_session_get`/`ws_session_set` from Task 1.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-session/cli.bats`:

```bash
#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"; mkdir -p "$ROOT_DIR/.tmp"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
    export GDD_SESSION_ID="cli-test"
}
run_ws() { run env WS_FOOTER_DISABLE=1 bash "$WS_BIN" "$@"; }

@test "ws session set then get round-trips" {
    run_ws session set GDD_STANCE flow
    [ "$status" -eq 0 ]
    run_ws session get GDD_STANCE
    [ "$status" -eq 0 ]
    [ "$output" = "flow" ]
}

@test "ws session show lists all keys" {
    run_ws session set GDD_STANCE flow
    run_ws session set GDD_ROLE developer
    run_ws session show
    [[ "$output" == *"GDD_STANCE=flow"* ]]
    [[ "$output" == *"GDD_ROLE=developer"* ]]
}

@test "ws session with an unknown subcommand errors" {
    run_ws session frobnicate
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run to verify fail**

Run: `bash scripts/ws test yggdrasil 'ws session'`
Expected: FAIL — `Unknown command 'session'`.

- [ ] **Step 3: Create the CLI script**

Create `scripts/ws-session-config.sh`:

```bash
#!/usr/bin/env bash
# ws-session-config.sh — get/set/show per-session config keys.
# ws:use-when reading or setting this session's stance/role/mentoring config
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
source "$SCRIPT_DIR/ws-session.sh"

usage() {
    echo "Usage: ws session get <KEY> | set <KEY> <VALUE> | show" >&2
}

sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in
    get) [[ $# -ge 1 ]] || { usage; exit 1; }; ws_session_get "$1" ;;
    set) [[ $# -ge 2 ]] || { usage; exit 1; }; ws_session_set "$1" "$2" && echo "session: set $1" ;;
    show)
        path="$(ws_session_identity_path)"
        if [[ -n "$path" && -f "$path" ]]; then cat "$path"; else echo "(no session file)"; fi
        ;;
    --help|-h|help) usage; exit 0 ;;
    *) usage; exit 1 ;;
esac
```

- [ ] **Step 4: Wire the dispatcher**

In `scripts/ws`, add an arm just before the `whoami)` arm (around line 975):

```bash
    session)
        bash "$SCRIPT_DIR/ws-session-config.sh" "$@"
        ;;
```

In the `# Commands:` block (lines 8-46), add after the `whoami` help line:

```
#   session get|set|show         Get/set this session's stance/role/mentoring config
```

- [ ] **Step 5: Allow it in settings.json**

In `.claude/settings.json` `permissions.allow`, add (mirroring the `ws test` pair at lines 56-57):

```json
      "Bash(ws session:*)",
      "Bash(bash scripts/ws session:*)",
```

- [ ] **Step 6: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'ws session'`
Expected: PASS (3).

- [ ] **Step 7: Commit**

Bodyfile `.commits/p1-session-cli.md` — `message:` `feat(ws): add 'ws session get|set|show' subcommand`; `add:` `scripts/ws-session-config.sh`, `scripts/ws`, `.claude/settings.json`, `tests/ws-session/cli.bats`.

### Task 3: Retire `mode:`/`role:` from Thalamus; orient establishes session stance/role/mentoring

**Files:**
- Modify: `templates/thalamus.md` (drop `mode:`/`role:`), the five `hoards/thalami-Cervator/*-thalamus.md` (drop keys), `.agent/skills/gdd-orientation/SKILL.md` (read/write session instead of frontmatter)
- Test: none mechanical (prose + template); verification is a grep

- [ ] **Step 1: Edit `templates/thalamus.md`**

Delete lines 5-6 (`mode:` and `role:`). Change the body comment on line 29 from `<!-- Mode defaults, interaction style, session habits -->` to `<!-- Interaction style, session habits -->`. Add a one-line note under the frontmatter block body (after the `# Thalamus` intro) stating stance/role/mentoring are now session-established (not stored here):

```markdown
> Stance, role, and mentoring are established per session in the session file (`ws session set …`), not stored here — they move around too much to pin per-machine.
```

- [ ] **Step 2: Edit the five thalami files**

For each of `Dionysus-thalamus.md`, `Loki-thalamus.md`, `Nano76Win11-thalamus.md`, `FG4WWY622F-thalamus.md`, `rasmuss-mbp-2-thalamus.md` under `hoards/thalami-Cervator/`: delete the `mode:` line (5) and `role:` line (6). Preserve all other frontmatter (`last_session`, `last_audit`, `staleness_days`, `arcs`, etc.).

- [ ] **Step 3: Update orientation skill**

In `.agent/skills/gdd-orientation/SKILL.md`, rewrite the "Parse Thalamus frontmatter" bullets (lines 119-120) from frontmatter-read to session-establish:

```markdown
- Establish **stance** for this session: `ws session set GDD_STANCE <quick|zen|flow>` — ask the human if unset, or default to `flow` when they want to move fast.
- Establish **role**: `ws session set GDD_ROLE <developer|designer|reviewer|scribe>` — ask if unset, default `developer`.
- Establish **mentoring** (composable overlay): `ws session set GDD_MENTORING <true|false>` — default `false`; offer to enable on a tutorial/practice signal.
- Read the current values any time with `ws session get GDD_STANCE` (etc.).
```

(The broader mode→stance prose rename across this file happens in Phase 2 Task 5; this step only changes the frontmatter-read mechanic.)

- [ ] **Step 4: Verify no consumer still reads frontmatter `mode:`/`role:`**

Run: `bash scripts/ws test yggdrasil` (full suite — confirms nothing in the session/orient path regressed).
Then a manual grep check (read-only): confirm `templates/thalamus.md` and the thalami files no longer contain `^mode:` / `^role:`.

- [ ] **Step 5: Commit**

Two commits — the workspace repo and the (separate-repo) thalami hoard cannot share one `ws commit`:
- `bash scripts/ws commit yggdrasil .commits/p1-retire-frontmatter.md` — `add:` `templates/thalamus.md`, `.agent/skills/gdd-orientation/SKILL.md`. Message: `feat(gdd): retire mode/role from Thalamus frontmatter; orient establishes session stance/role/mentoring`.
- `bash scripts/ws commit thalami-Cervator .commits/p1-thalami-keys.md` — `add:` the five `*-thalamus.md`. Message: `chore(thalami): drop retired mode/role frontmatter keys`. (Coordinate with the human: the coworker updates his single thalamus by hand per the design.)

### Task 3b: Harden `ws clean` against parallel sessions

**Files:**
- Modify: the `ws_clean` handling of session files (in `scripts/ws` `ws_clean` or `scripts/ws-clean.sh` — read it first to locate the `--sessions` branch)
- Test: `tests/ws-clean/identity.bats` (update the two existing session cases)

**Interfaces:**
- Today (from the existing tests): default `ws clean` spares ALL session files; `ws clean --sessions` sweeps *ended* sessions, sparing the current. Target: default AND `--sessions` never remove another session's file; only a new `--sessions-all` (full-system housekeeping) prunes ended-session files (still sparing the current). This stops a routine clean from bowling over a parallel session whose "ended" detection is imperfect.

- [ ] **Step 1: Read the current behavior**

Read the `--sessions` branch in `scripts/ws-clean.sh` (or `ws_clean` in `scripts/ws`) and the two cases in `tests/ws-clean/identity.bats` named `ws clean spares ALL session identities by default (protects concurrent sessions)` and `ws clean --sessions sweeps ended sessions but spares the current one`.

- [ ] **Step 2: Update the tests to the new contract**

Rename the second case's flag to `--sessions-all` (it keeps the same body: ended sessions swept, current spared). Add a new case asserting plain `--sessions` now spares all session files (no pruning):

```bash
@test "ws clean --sessions no longer prunes other sessions' files" {
    # seed an 'ended' session file + the current session file, run `ws clean --sessions`
    # assert BOTH survive (only --sessions-all prunes ended ones)
    # (mirror the fixture setup from the existing default-spares-all case)
}
```

- [ ] **Step 3: Run to verify the renamed/new cases fail**

Run: `bash scripts/ws test yggdrasil 'ws clean .*session'`
Expected: FAIL — `--sessions-all` unhandled; `--sessions` still prunes.

- [ ] **Step 4: Gate the sweep behind `--sessions-all`**

In the session-file branch: make the ended-session pruning fire only for `--sessions-all`. Treat plain `--sessions` as a spare-all no-op (or drop it with a one-line deprecation note in `ws clean --help`). Default behavior is unchanged (spare all).

- [ ] **Step 5: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'ws clean .*session'`
Expected: PASS.

- [ ] **Step 6: Commit**

Bodyfile `.commits/p1-clean-hardening.md` — `add:` the modified clean script, `tests/ws-clean/identity.bats`. Message: `fix(ws): gate ended-session pruning behind 'ws clean --sessions-all' (never bowl over parallel sessions)`.

---

## Phase 2 — Taxonomy rename sweep (mode → stance)

### Task 4: Rename and rewrite `roles-and-modes.md` → `roles-and-stances.md`

**Files:**
- Rename: `docs/gdd/roles-and-modes.md` → `docs/gdd/roles-and-stances.md`
- Modify: `mkdocs.yml:63` (nav), all docs/gdd cross-references

- [ ] **Step 1: Move the file and rewrite around the three concepts**

`git mv docs/gdd/roles-and-modes.md docs/gdd/roles-and-stances.md`. Rewrite: H1 `# Roles and Stances`; keep `## Roles` (table unchanged); rename `## Modes` → `## Stances` listing only `### Quick` / `### Zen` / `### Flow`; add a new `## Mentoring` section describing the composable boolean overlay (cite that it composes with any stance and any role). Update the closing line referencing `.agent/skills/gdd-<mode>/SKILL.md` → `.agent/skills/gdd-<stance>/SKILL.md` (plus the gdd-mentoring overlay). Add a one-line note that stance/role/mentoring are session-established (link the session file).

- [ ] **Step 2: Update `mkdocs.yml`**

Change line 63 from `- Roles and Modes: gdd/roles-and-modes.md` to `- Roles and Stances: gdd/roles-and-stances.md`.

- [ ] **Step 3: Update cross-references**

Replace every `roles-and-modes.md` link and "Roles and Modes" link text in `docs/gdd/skills-reference.md` (L20, L88), `docs/gdd/hoards.md` (L135), `docs/gdd/index.md` (L71), `docs/gdd/features.md` (L100) with `roles-and-stances.md` / "Roles and Stances". (Historical `docs/plans/*` references to the old path are frozen — see Task 6.)

- [ ] **Step 4: Verify the build / links**

Run: `bash scripts/ws test yggdrasil` (no broken-link assertions exist in bats, so this is a regression guard). Manual: grep `docs/gdd/` and `mkdocs.yml` for residual `roles-and-modes` — expect none.

- [ ] **Step 5: Commit**

Bodyfile `.commits/p2-roles-stances.md` — `add:` `docs/gdd/roles-and-stances.md` (new), `mkdocs.yml`, the four edited docs; **pre-stage the rename** with `git rm` of the old path is unnecessary — list the deleted old path in `add:` (ws commit's `add:` detects a tracked deletion). Message: `docs(gdd): rename Roles and Modes → Roles and Stances; add Mentoring overlay section`.

### Task 5: Sweep "mode" → "stance" across skills, docs, templates

**Files (exact, from the rename inventory):**
- Modify skills: `.agent/skills/gdd-quick/SKILL.md` (L4, L9, L47), `.agent/skills/gdd-zen/SKILL.md` (L4, L9, L39, L58, L61, L64), `.agent/skills/gdd-flow/SKILL.md` (L4, L6, L10, L17-18, L25, L43, L79, L95), `.agent/skills/gdd-mentoring/SKILL.md` (L4, L10, L37, L44, L53 — keep "mentoring" as the overlay name; remove the word "mode" where it implies a peer-of-quick/zen), `.agent/skills/gdd/SKILL.md` (L4-5, L22-23, L30, L49-70 incl. the Mode Behavior Matrix header, L85, L110, L113), `.agent/skills/gdd-housekeeping/SKILL.md` (L20, L308-309), `.agent/skills/gdd-review-triage/SKILL.md` (L22)
- Modify docs: `docs/gdd/skills-reference.md` (L5, L9, L11, L40, L41), `docs/gdd/hoards.md` (L49, L89), `docs/gdd/features.md` (L91, L93, L98, L100), `docs/gdd/thalamus.md` (L22, L45 sample, L50), `docs/gdd/index.md` (L27, L49, L56, L59)
- Modify templates: `templates/components/gh-pages/README.md` (L8-10, L244)

- [ ] **Step 1: Reframe the four mode skills**

`gdd-quick`/`gdd-zen`/`gdd-flow`: change frontmatter `description:` and H1 from "X mode" → "X stance" (e.g. `# GDD Quick Stance`, `Quick stance — minimal ceremony…`), and "## What This Mode Does NOT Do" → "## What This Stance Does NOT Do". In `gdd-zen` L61 "that's Flow mode" → "that's the Flow stance". `gdd-mentoring`: H1 `# GDD Mentoring` (drop "Mode"); L4 `Mentoring — a composable overlay: the AI explains decisions and teaches in context`; L37 "composes with other modes" → "composes with any stance". Each stance skill's body: replace standalone "mode" (in the stance sense) with "stance"; leave unrelated words (model, etc.) untouched.

- [ ] **Step 2: Reframe the orchestrator `gdd/SKILL.md`**

L49 `## Modes` → `## Stances` (+ a short note that mentoring is a separate overlay). L51 "Modes modify…" → "Stances modify…". L68 `## Mode Behavior Matrix` → `## Stance Behavior Matrix`; L70 table header `| Activity | Quick | Zen | Flow | Mentoring |` → `| Activity | Quick | Zen | Flow | + Mentoring |` (mentoring as an overlay column). L85 "Mode skill loads…" → "Stance skill loads…". L22-23, L30, L110, L113: "mode" → "stance" in the stance sense; keep "in mentoring … grow the human".

- [ ] **Step 3: Sweep the orientation skill's remaining mode prose**

In `.agent/skills/gdd-orientation/SKILL.md`, update the mode-sense references at L3, L8, L10, L16, L23, L26, the "Tutorial detection — offer mentoring" section (L131-144 — keep the mentoring offer, but it now sets `GDD_MENTORING=true` via `ws session set`), L214, L220, L223, the "Mode adaptation of orientation itself" section (L247-251 → "Stance adaptation…", with Quick/Zen/Flow bullets and a Mentoring overlay bullet), L264, L302.

- [ ] **Step 4: Sweep docs + the gh-pages template**

Apply the doc edits enumerated above: `## Modes — *how* to work` → `## Stances`; "the active mode lives in the per-machine thalamus frontmatter" → "the active stance is established per session (`ws session`)"; `docs/gdd/features.md` "## Modes — agent demeanor" → "## Stances — agent demeanor", "four modes" → "three stances (+ a mentoring overlay)", and the `mode:` frontmatter reference → session-established; `docs/gdd/thalamus.md` L45 sample `mode: zen` → remove (frontmatter no longer carries it); `templates/components/gh-pages/README.md` "Use mentoring mode" → "Turn on mentoring" (L8-10, L244).

- [ ] **Step 5: Verify**

Run: `bash scripts/ws test yggdrasil` (regression guard — confirms no skill/parse test broke). Manual grep: across `.agent/skills/`, `docs/gdd/` (excluding `samples/`), `templates/` there should be no remaining role/mode-sense "mode" (allow "model", "permission mode", etc.). Note any intentional residuals.

- [ ] **Step 6: Commit**

Bodyfile `.commits/p2-mode-stance-sweep.md` — `add:` all skill + doc + template files edited in Tasks 5. Message: `docs(gdd): rename mode→stance across skills, docs, templates; mentoring is a composable overlay`.

### Task 6: Freeze historical samples (decision record)

**Files:** `docs/gdd/samples/*.md`, `docs/plans/*` — **no edits**.

- [ ] **Step 1: Record the freeze**

These are dated session transcripts and prior plans; rewriting them would falsify a historical record. Leave as-is. Add a single sentence to `docs/gdd/samples/index.md` (if not present): "These are point-in-time transcripts; terminology (e.g. 'mode') reflects the GDD vocabulary at capture time." Commit with the Phase-2 sweep or as a tiny follow-up (`docs: note samples are historical transcripts`).

---

## Phase 3 — `ws-k8s-guard.sh` (shared guard)

### Task 7: `k8s_guard_evaluate` — verbs, context, namespace, verdicts

**Files:**
- Create: `scripts/ws-k8s-guard.sh`, `tests/ws-k8s/guard.bats`, `tests/ws-k8s/test_helper.bash`

**Interfaces:**
- Produces: `k8s_guard_evaluate <context> <namespaces-csv> <argv…>` → prints exactly one verdict on stdout: `NOT_K8S`, `NO_SCOPE`, `READ_IN_SCOPE`, `WRITE_IN_SCOPE`, or `BLOCK:<reason>`. Pure over its args except for default-namespace resolution, which calls `${KUBECTL:-kubectl}` (stubbable). Reads no global state.
- Verb lists: READ = `get describe logs top explain events api-resources api-versions version diff wait` plus `auth` (`can-i`) and `config` (`view get-contexts current-context`); WRITE = everything else recognized (`apply create delete patch replace edit scale autoscale rollout annotate label set expose run exec cp attach port-forward cordon uncordon drain taint`) and `config set-context|use-context|set`; **unknown verb → WRITE**.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-k8s/test_helper.bash`:

```bash
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
GUARD_LIB="$REPO_ROOT/scripts/ws-k8s-guard.sh"

# Stub kubectl: `config view --minify ...` prints a default namespace we control.
make_kubectl_stub() {
    local default_ns="$1"
    cat > "$BATS_TEST_TMPDIR/kubectl" <<EOF
#!/usr/bin/env bash
# minimal stub: only 'config view --minify' is consulted by the guard
case "\$*" in
    *"config view"*) echo "$default_ns" ;;
    *) echo "" ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/kubectl"
    export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
}

run_guard() { run bash -c "source '$GUARD_LIB'; k8s_guard_evaluate \"\$@\"" _ "$@"; }
```

Create `tests/ws-k8s/guard.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() { make_kubectl_stub "default"; }

@test "non-kubectl command is NOT_K8S" {
    run_guard "kind-practice" "alice-sandbox" ls -la
    [ "$output" = "NOT_K8S" ]
}

@test "no scope set is NO_SCOPE" {
    run_guard "" "" kubectl get pods
    [ "$output" = "NO_SCOPE" ]
}

@test "read anywhere on matching context is READ_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl get pods -n kube-system
    [ "$output" = "READ_IN_SCOPE" ]
}

@test "write to in-scope namespace is WRITE_IN_SCOPE" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n alice-sandbox
    [ "$output" = "WRITE_IN_SCOPE" ]
}

@test "write to out-of-scope namespace BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pod foo -n prod
    [[ "$output" == BLOCK:* ]]
}

@test "conflicting --context BLOCKs absolutely" {
    run_guard "kind-practice" "alice-sandbox" kubectl get pods --context other-cluster
    [[ "$output" == BLOCK:* ]]
}

@test "write with no -n uses the context default namespace" {
    make_kubectl_stub "alice-sandbox"
    run_guard "kind-practice" "alice-sandbox" kubectl scale deploy/foo --replicas=2
    [ "$output" = "WRITE_IN_SCOPE" ]
}

@test "write with default namespace out of scope BLOCKs" {
    make_kubectl_stub "default"
    run_guard "kind-practice" "alice-sandbox" kubectl scale deploy/foo --replicas=2
    [[ "$output" == BLOCK:* ]]
}

@test "--all-namespaces on a write BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl delete pods --all-namespaces
    [[ "$output" == BLOCK:* ]]
}

@test "unknown verb is treated as write (fail-safe)" {
    run_guard "kind-practice" "alice-sandbox" kubectl frobnicate -n prod
    [[ "$output" == BLOCK:* ]]
}
```

- [ ] **Step 2: Run to verify fail**

Run: `bash scripts/ws test yggdrasil 'NOT_K8S|READ_IN_SCOPE|WRITE_IN_SCOPE'`
Expected: FAIL — guard lib missing.

- [ ] **Step 3: Implement `scripts/ws-k8s-guard.sh`**

```bash
#!/usr/bin/env bash
# ws-k8s-guard.sh — shared k8s practice guard (sourced by ws-k8s.sh and the
# permission hook). Single source of truth for the allow/block verdict.

_k8s_is_read_verb() {
    case "$1" in
        get|describe|logs|top|explain|events|api-resources|api-versions|version|diff|wait|auth|config) return 0 ;;
        *) return 1 ;;
    esac
}

# Print one verdict: NOT_K8S | NO_SCOPE | READ_IN_SCOPE | WRITE_IN_SCOPE | BLOCK:<reason>
# Usage: k8s_guard_evaluate <context> <namespaces-csv> <argv...>
k8s_guard_evaluate() {
    local scope_ctx="$1" scope_ns_csv="$2"; shift 2
    # Recognize both `kubectl ...` and `ws k8s ...` forms.
    if [[ "$1" == "kubectl" ]]; then shift
    elif [[ "$1" == *"/ws" || "$1" == "ws" || "$1" == "bash" ]]; then
        # tolerate "ws k8s ..." / "bash scripts/ws k8s ..."
        while [[ $# -gt 0 && "$1" != "k8s" ]]; do shift; done
        [[ "$1" == "k8s" ]] && shift || { printf 'NOT_K8S'; return 0; }
    else
        printf 'NOT_K8S'; return 0
    fi
    [[ -z "$scope_ctx" ]] && { printf 'NO_SCOPE'; return 0; }

    # Walk args: find verb (first non-flag token), explicit --context, -n/--namespace, -A.
    local verb="" ctx_arg="" ns_arg="" all_ns=0 a
    local args=("$@")
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        a="${args[$i]}"
        case "$a" in
            --context) ctx_arg="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
            --context=*) ctx_arg="${a#--context=}";;
            -n|--namespace) ns_arg="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
            -n=*|--namespace=*) ns_arg="${a#*=}";;
            -A|--all-namespaces) all_ns=1 ;;
            -*) : ;;  # other flag, ignore
            *) [[ -z "$verb" ]] && verb="$a" ;;
        esac
        i=$((i+1))
    done

    # 1. Context force: a conflicting explicit --context is an absolute block.
    if [[ -n "$ctx_arg" && "$ctx_arg" != "$scope_ctx" ]]; then
        printf 'BLOCK:explicit --context %s != practice context %s' "$ctx_arg" "$scope_ctx"; return 0
    fi

    # 2. Reads are allowed anywhere on the matching context.
    if _k8s_is_read_verb "$verb"; then printf 'READ_IN_SCOPE'; return 0; fi

    # 3. Writes (incl. unknown verbs): namespace must be in scope.
    if [[ $all_ns -eq 1 ]]; then printf 'BLOCK:--all-namespaces write is not scope-bounded'; return 0; fi
    local target_ns="$ns_arg"
    if [[ -z "$target_ns" ]]; then
        target_ns="$("${KUBECTL:-kubectl}" config view --minify --context "$scope_ctx" -o 'jsonpath={..namespace}' 2>/dev/null)"
        [[ -z "$target_ns" ]] && target_ns="default"
    fi
    # CSV membership test.
    local ns
    IFS=',' read -ra _scope_ns <<< "$scope_ns_csv"
    for ns in "${_scope_ns[@]}"; do
        [[ "$ns" == "$target_ns" ]] && { printf 'WRITE_IN_SCOPE'; return 0; }
    done
    printf 'BLOCK:write target namespace %s is outside practice scope (%s)' "$target_ns" "$scope_ns_csv"
}
```

(Note: the stub in Step 1 prints the default namespace for any `config view` call; the real `-o jsonpath` form degrades to the stub's plain echo, which the test accommodates by matching on `config view`.)

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'NOT_K8S|NO_SCOPE|READ_IN_SCOPE|WRITE_IN_SCOPE|out-of-scope|conflicting|all-namespaces|unknown verb|default namespace'`
Expected: PASS (10).

- [ ] **Step 5: Commit**

Bodyfile `.commits/p3-guard.md` — `add:` `scripts/ws-k8s-guard.sh`, `tests/ws-k8s/guard.bats`, `tests/ws-k8s/test_helper.bash`. Message: `feat(k8s): add shared ws-k8s-guard k8s_guard_evaluate (context force + read/write scope verdicts)`.

### Task 8: `-f` manifest namespace parsing

**Files:**
- Modify: `scripts/ws-k8s-guard.sh` (resolve namespaces from local `-f` manifests)
- Test: `tests/ws-k8s/guard.bats` (new cases)

**Interfaces:**
- Consumes: `k8s_guard_evaluate` from Task 7. Produces: same verdicts, now also parsing `-f <file>` for `metadata.namespace` (via `yq`). Remote `-f <URL>`, `-f -` (stdin), or a namespaced doc with neither manifest ns nor `-n` → `BLOCK`.

- [ ] **Step 1: Write the failing test**

Append to `tests/ws-k8s/guard.bats`:

```bash
@test "apply -f with in-scope manifest namespace is WRITE_IN_SCOPE" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/m.yaml"
    [ "$output" = "WRITE_IN_SCOPE" ]
}

@test "apply -f with out-of-scope manifest namespace BLOCKs" {
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x\n  namespace: prod\n' > "$BATS_TEST_TMPDIR/m.yaml"
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f "$BATS_TEST_TMPDIR/m.yaml"
    [[ "$output" == BLOCK:* ]]
}

@test "apply -f a remote URL BLOCKs (cannot resolve)" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f https://example.com/x.yaml
    [[ "$output" == BLOCK:* ]]
}

@test "apply -f - (stdin) BLOCKs" {
    run_guard "kind-practice" "alice-sandbox" kubectl apply -f -
    [[ "$output" == BLOCK:* ]]
}
```

- [ ] **Step 2: Run to verify fail**

Run: `bash scripts/ws test yggdrasil 'apply -f'`
Expected: FAIL — current code treats `apply` (no `-n`) via default-ns resolution, not manifest parsing.

- [ ] **Step 3: Add `-f` handling to the guard**

In the arg-walk loop of `k8s_guard_evaluate`, capture `-f`/`--filename` values into an array `ffiles`. After the read/write split, before default-ns resolution, insert manifest resolution for writes:

```bash
    # -f manifest resolution (writes only). Any unresolved input is a BLOCK.
    if [[ ${#ffiles[@]} -gt 0 ]]; then
        local f doc_ns
        for f in "${ffiles[@]}"; do
            case "$f" in
                -|http://*|https://*) printf 'BLOCK:-f %s cannot be parsed for namespace (stdin/remote)' "$f"; return 0 ;;
            esac
            [[ -f "$f" ]] || { printf 'BLOCK:-f %s not found on disk' "$f"; return 0; }
            # Collect every document's metadata.namespace; empty → fall back to -n.
            while IFS= read -r doc_ns; do
                [[ -z "$doc_ns" || "$doc_ns" == "null" ]] && doc_ns="$ns_arg"
                [[ -z "$doc_ns" ]] && { printf 'BLOCK:-f %s has a namespaced doc with no namespace and no -n' "$f"; return 0; }
                local ok=0 n
                IFS=',' read -ra _sns <<< "$scope_ns_csv"
                for n in "${_sns[@]}"; do [[ "$n" == "$doc_ns" ]] && ok=1; done
                [[ $ok -eq 1 ]] || { printf 'BLOCK:-f %s targets namespace %s outside scope (%s)' "$f" "$doc_ns" "$scope_ns_csv"; return 0; }
            done < <(yq -r '.metadata.namespace // ""' "$f" 2>/dev/null)
        done
        printf 'WRITE_IN_SCOPE'; return 0
    fi
```

(Declare `local ffiles=()` near the other locals; add `-f|--filename) ffiles+=("${args[$((i+1))]:-}"); i=$((i+2)); continue ;;` and `-f=*|--filename=*) ffiles+=("${a#*=}");;` to the arg `case`.)

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'apply -f'`
Expected: PASS (4). Also re-run the Task 7 cases to confirm no regression.

- [ ] **Step 5: Commit**

Bodyfile `.commits/p3-manifest.md` — `add:` `scripts/ws-k8s-guard.sh`, `tests/ws-k8s/guard.bats`. Message: `feat(k8s): parse -f manifest namespaces in the guard; block stdin/remote/unresolved`.

---

## Phase 4 — `ws k8s` wrapper

### Task 9: `ws k8s scope set|show|clear` + guarded passthrough

**Files:**
- Create: `scripts/ws-k8s.sh`, `tests/ws-k8s/wrapper.bats`
- Modify: `scripts/ws` (dispatch arm + help line)

**Interfaces:**
- Consumes: `k8s_guard_evaluate` (Task 7-8), `ws_session_get`/`ws_session_set` (Task 1), `${KUBECTL:-kubectl}`.
- Produces: `ws k8s scope set --context <c> --namespace <n[,n]>` (validates, writes `GDD_K8S_CONTEXT`/`GDD_K8S_NAMESPACES`), `scope show`, `scope clear`; `ws k8s <kubectl args…>` (guarded — `BLOCK` rejects, else execs `${KUBECTL}` with `--context` forced when scoped).

- [ ] **Step 1: Write the failing test**

Create `tests/ws-k8s/wrapper.bats`:

```bash
#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"; mkdir -p "$ROOT_DIR/.tmp"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
    export GDD_SESSION_ID="k8s-test"
    # Stub kubectl: record argv, succeed; 'config get-contexts'/'get namespace' validate.
    cat > "$ROOT_DIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "KUBECTL_ARGS: $*" >> "$ROOT_DIR/kubectl.log"
case "$*" in
    *"get namespace prod"*) exit 1 ;;   # prod doesn't exist on this context
    *) exit 0 ;;
esac
EOF
    chmod +x "$ROOT_DIR/kubectl"
    export KUBECTL="$ROOT_DIR/kubectl"
}
run_ws() { run env WS_FOOTER_DISABLE=1 ROOT_DIR="$ROOT_DIR" KUBECTL="$KUBECTL" bash "$WS_BIN" "$@"; }

@test "scope set then show round-trips" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    [ "$status" -eq 0 ]
    run_ws k8s scope show
    [[ "$output" == *"kind-practice"* ]]
    [[ "$output" == *"alice-sandbox"* ]]
}

@test "no scope set: passthrough to kubectl" {
    run_ws k8s get pods
    [ "$status" -eq 0 ]
}

@test "in-scope read is allowed and forces --context" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    run_ws k8s get pods -n kube-system
    [ "$status" -eq 0 ]
    grep -q -- '--context kind-practice' "$ROOT_DIR/kubectl.log"
}

@test "out-of-scope write is rejected, kubectl not called" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    : > "$ROOT_DIR/kubectl.log"
    run_ws k8s delete pod foo -n prod
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside practice scope"* || "$output" == *"BLOCK"* ]]
    [ ! -s "$ROOT_DIR/kubectl.log" ]
}

@test "scope set rejects a nonexistent namespace" {
    run_ws k8s scope set --context kind-practice --namespace prod
    [ "$status" -ne 0 ]
}

@test "scope clear removes the scope" {
    run_ws k8s scope set --context kind-practice --namespace alice-sandbox
    run_ws k8s scope clear
    run_ws k8s scope show
    [[ "$output" == *"none"* || "$output" == *"no "* ]]
}
```

- [ ] **Step 2: Run to verify fail**

Run: `bash scripts/ws test yggdrasil 'scope set then show|passthrough to kubectl|in-scope read'`
Expected: FAIL — `Unknown command 'k8s'`.

- [ ] **Step 3: Implement `scripts/ws-k8s.sh`**

```bash
#!/usr/bin/env bash
# ws-k8s.sh — guarded kubectl wrapper (training wheels). See
# docs/plans/2026-06-25-mentoring-k8s-training-wheels-design.md.
# ws:use-when running kubectl during a guarded practice session
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
source "$SCRIPT_DIR/ws-session.sh"
source "$SCRIPT_DIR/ws-k8s-guard.sh"
KUBECTL="${KUBECTL:-kubectl}"

_k8s_scope() {
    local sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
    case "$sub" in
        show)
            local c n; c="$(ws_session_get GDD_K8S_CONTEXT)"; n="$(ws_session_get GDD_K8S_NAMESPACES)"
            if [[ -n "$c" ]]; then echo "context: $c"; echo "namespaces: $n"; else echo "scope: none"; fi ;;
        clear)
            ws_session_set GDD_K8S_CONTEXT ""; ws_session_set GDD_K8S_NAMESPACES ""; echo "scope cleared" ;;
        set)
            local ctx="" ns=""
            while [[ $# -gt 0 ]]; do case "$1" in
                --context) ctx="$2"; shift 2 ;;
                --namespace) ns="$2"; shift 2 ;;
                *) echo "ERROR: unknown arg '$1'" >&2; return 1 ;;
            esac; done
            [[ -n "$ctx" && -n "$ns" ]] || { echo "Usage: ws k8s scope set --context <c> --namespace <n[,n]>" >&2; return 1; }
            "$KUBECTL" config get-contexts "$ctx" >/dev/null 2>&1 || { echo "ERROR: context '$ctx' not found." >&2; return 1; }
            local one; IFS=',' read -ra _ns <<< "$ns"
            for one in "${_ns[@]}"; do
                "$KUBECTL" --context "$ctx" get namespace "$one" >/dev/null 2>&1 || { echo "ERROR: namespace '$one' not found on context '$ctx'." >&2; return 1; }
            done
            ws_session_set GDD_K8S_CONTEXT "$ctx"
            ws_session_set GDD_K8S_NAMESPACES "$ns"
            echo "practice scope armed: context=$ctx namespaces=$ns" ;;
        *) echo "Usage: ws k8s scope set|show|clear" >&2; return 1 ;;
    esac
}

main() {
    if [[ "${1:-}" == "scope" ]]; then shift; _k8s_scope "$@"; return; fi
    local ctx ns; ctx="$(ws_session_get GDD_K8S_CONTEXT)"; ns="$(ws_session_get GDD_K8S_NAMESPACES)"
    local verdict; verdict="$(k8s_guard_evaluate "$ctx" "$ns" kubectl "$@")"
    case "$verdict" in
        BLOCK:*) echo "ws k8s: blocked — ${verdict#BLOCK:}" >&2
                 echo "  widen with: ws k8s scope set --context $ctx --namespace <ns>" >&2; return 1 ;;
        NO_SCOPE|NOT_K8S) exec "$KUBECTL" "$@" ;;
        *) exec "$KUBECTL" --context "$ctx" "$@" ;;
    esac
}
main "$@"
```

- [ ] **Step 4: Wire the dispatcher + help**

In `scripts/ws`, add before `whoami)` (line 975):

```bash
    k8s)
        bash "$SCRIPT_DIR/ws-k8s.sh" "$@"
        ;;
```

In the `# Commands:` block, add:

```
#   k8s scope set|show|clear / k8s <args>   Guarded kubectl: prevalidate context + namespace
```

Do **not** add a `Bash(ws k8s:*)` allow entry to `.claude/settings.json` — the hook handles read auto-approve; writes should prompt.

- [ ] **Step 5: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'scope set then show|passthrough to kubectl|in-scope read|out-of-scope write|nonexistent namespace|scope clear'`
Expected: PASS (6).

- [ ] **Step 6: Commit**

Bodyfile `.commits/p4-ws-k8s.md` — `add:` `scripts/ws-k8s.sh`, `scripts/ws`, `tests/ws-k8s/wrapper.bats`. Message: `feat(k8s): add guarded 'ws k8s' wrapper (scope set/show/clear + enforced passthrough)`.

---

## Phase 5 — Hook integration

### Task 10: `[scoped-redirect-commands]` parse arm + array

**Files:**
- Modify: `.claude/hooks/gdd-permission-hook.sh` (array decl + parse arm)
- Test: `tests/hook/gdd-permission-hook.bats` (parse-doesn't-abort case)

**Interfaces:**
- Produces: `scoped_redirect_commands[]` entries packed as `slug|pattern|session-key|suggestion`. Consumed by Task 11's tier loop.

- [ ] **Step 1: Write the failing test**

Add to `tests/hook/gdd-permission-hook.bats` (mirroring the redirect test at :763):

```bash
@test "scoped-redirect: unknown-when-key-absent passes through (parse OK)" {
    write_project_hook_rules "$(cat <<'EOF'
[scoped-redirect-commands]
k8s | kubectl* | GDD_K8S_CONTEXT | Use `ws k8s <args>`.
EOF
)"
    run_hook 'kubectl get pods'
    [ "$status" -eq 0 ]
    # No scope file present, so no redirect — and the file must not be skipped.
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}
```

- [ ] **Step 2: Run to verify fail**

Run: `bash scripts/ws test yggdrasil 'scoped-redirect: unknown-when-key-absent'`
Expected: FAIL — without a parse arm, the `*)` default at `:456-463` skips the file (harmless here) but the array is never populated; Task 11 will need it. (This test passes trivially until Task 11 adds the redirect; keep it as the parse-safety guard.)

- [ ] **Step 3: Add the array + parse arm**

In `.claude/hooks/gdd-permission-hook.sh`, after line 356 add:

```bash
scoped_redirect_commands=()  # entries: "<slug>|<pattern>|<session-key>|<suggestion>"
```

In `_parse_rules_file`, add a new `case "$section"` arm after the `[adapter-redirect-commands]` arm (before the `*)` default at :456):

```bash
                    scoped-redirect-commands)
                        # 4 columns: slug | pattern | session-key | suggestion.
                        local sr_slug sr_pattern sr_key sr_suggestion sr_rest
                        if [[ "$line" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [scoped-redirect-commands], missing separator): $file" >> "$audit_log"
                            continue
                        fi
                        sr_slug="${line%% | *}"; sr_rest="${line#* | }"
                        sr_pattern="${sr_rest%% | *}"; sr_rest="${sr_rest#* | }"
                        if [[ "$sr_rest" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [scoped-redirect-commands], need 4 columns): $file" >> "$audit_log"
                            continue
                        fi
                        sr_key="${sr_rest%% | *}"; sr_suggestion="${sr_rest#* | }"
                        sr_slug="${sr_slug%"${sr_slug##*[![:space:]]}"}"
                        sr_pattern="${sr_pattern%"${sr_pattern##*[![:space:]]}"}"
                        sr_key="${sr_key%"${sr_key##*[![:space:]]}"}"
                        if [[ ! "$sr_slug" =~ ^[a-z][a-z0-9-]*$ ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: bad slug '$sr_slug'): $file" >> "$audit_log"
                            continue
                        fi
                        scoped_redirect_commands+=("$sr_slug|$sr_pattern|$sr_key|$sr_suggestion")
                        ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'scoped-redirect: unknown-when-key-absent'`
Expected: PASS.

- [ ] **Step 5: Commit**

Bodyfile `.commits/p5-parse.md` — `add:` `.claude/hooks/gdd-permission-hook.sh`, `tests/hook/gdd-permission-hook.bats`. Message: `feat(hook): parse [scoped-redirect-commands] section (4-column, session-key-gated)`.

### Task 11: Scoped-redirect tier — raw kubectl redirect + ws k8s read auto-approve + temp-script scan

**Files:**
- Modify: `.claude/hooks/gdd-permission-hook.sh` (new tier loop after Tier 2), `.claude/hooks/hook-rules` (the kubectl rule)
- Test: `tests/hook/gdd-permission-hook.bats` (redirect, auto-approve, block, script-scan, no-scope-passthrough)

**Interfaces:**
- Consumes: `scoped_redirect_commands[]` (Task 10), `match_cmd` (:786), `_t2_session_id` (:804), `_t2_project_root` (:814), `k8s_guard_evaluate` (sourced), `deny`/`allow` (:265,:288).

- [ ] **Step 1: Add the kubectl rule to `hook-rules`**

Append to `.claude/hooks/hook-rules`:

```
[scoped-redirect-commands]
# Raw tools redirected only when a session-key is set in the session file.
# Format: <slug> | <pattern> | <session-key> | <suggestion>.
k8s | kubectl* | GDD_K8S_CONTEXT | Use `ws k8s <args>` — a practice scope is active; raw kubectl bypasses the namespace guard. `ws hook-bypass k8s` to lift for this session.
```

- [ ] **Step 2: Write the failing tests**

Add to `tests/hook/gdd-permission-hook.bats` a helper to seed a session scope, then cases:

```bash
seed_k8s_scope() {  # $1=session_id, $2=context, $3=namespaces
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    cat > "$WORK/.tmp/gdd-agent-sessions/$1.env" <<EOF
GDD_K8S_CONTEXT=$2
GDD_K8S_NAMESPACES=$3
EOF
}

@test "scoped-redirect: raw kubectl redirects to ws k8s when scope active" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws k8s"* ]]
}

@test "scoped-redirect: raw kubectl passes through when NO scope" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'kubectl get pods' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: in-scope ws k8s read auto-approves" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s get pods -n kube-system' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "scoped-redirect: out-of-scope ws k8s write denies" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: temp script containing kubectl is denied under scope" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    printf '#!/bin/bash\nkubectl delete ns prod\n' > "$WORK/danger.sh"
    run_hook_with_session "bash $WORK/danger.sh" "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
```

- [ ] **Step 3: Run to verify fail**

Run: `bash scripts/ws test yggdrasil 'scoped-redirect: raw kubectl redirects|in-scope ws k8s read|temp script containing'`
Expected: FAIL — tier loop not present.

- [ ] **Step 4: Add the tier loop**

In `.claude/hooks/gdd-permission-hook.sh`, source the guard near the top (after the helper defs, before the tiers — guard path is alongside the hook's repo): add `source "${_rules_dir%/.claude/hooks}/scripts/ws-k8s-guard.sh" 2>/dev/null || true` once `_rules_dir` is known. Then, immediately after the Tier 2 loop (after line 861), add:

```bash
# Tier 2b — scoped redirects (session-key-gated). Fires only when the named
# session-file key is set. Reuses _t2_session_id and _t2_project_root.
_sr_envfile=""
if [[ -n "$_t2_session_id" ]]; then
    _sr_safe="${_t2_session_id//[^A-Za-z0-9._-]/_}"
    _sr_envfile="$_t2_project_root/.tmp/gdd-agent-sessions/${_sr_safe}.env"
fi
_sr_get() {  # read one KEY from the session env file as data
    local key="$1"; [[ -n "$_sr_envfile" && -f "$_sr_envfile" ]] || return 0
    local l; while IFS= read -r l || [[ -n "$l" ]]; do l="${l%$'\r'}"
        case "$l" in "$key="*) printf '%s' "${l#"$key="}"; return 0 ;; esac
    done < "$_sr_envfile"
}
for _entry in ${scoped_redirect_commands[@]+"${scoped_redirect_commands[@]}"}; do
    _sr_slug="${_entry%%|*}"; _sr_rest="${_entry#*|}"
    _sr_pattern="${_sr_rest%%|*}"; _sr_rest="${_sr_rest#*|}"
    _sr_key="${_sr_rest%%|*}"; _sr_suggestion="${_sr_rest#*|}"
    # Gate: only active when the session key is set.
    _sr_keyval="$(_sr_get "$_sr_key")"
    [[ -n "$_sr_keyval" ]] || continue
    # Bypass marker (same mechanism as Tier 2).
    _sr_marker="$_t2_project_root/.tmp/hook-bypass/$_sr_slug.bypass"
    if [[ -f "$_sr_marker" ]]; then
        _sr_msid="$(grep '^session_id:' "$_sr_marker" 2>/dev/null | sed 's/^session_id: *//' || true)"
        [[ -n "$_t2_session_id" && "$_sr_msid" == "$_t2_session_id" ]] && continue
    fi
    _sr_ctx="$(_sr_get GDD_K8S_CONTEXT)"; _sr_ns="$(_sr_get GDD_K8S_NAMESPACES)"
    # (a) ws k8s commands → route by guard verdict.
    if [[ "$match_cmd" == ws\ k8s\ * || "$match_cmd" == k8s\ * ]]; then
        _sr_verdict="$(k8s_guard_evaluate "$_sr_ctx" "$_sr_ns" $match_cmd 2>/dev/null || true)"
        case "$_sr_verdict" in
            READ_IN_SCOPE) allow "ws k8s in-scope read" ;;
            BLOCK:*) deny "ws k8s blocked: ${_sr_verdict#BLOCK:}. $_sr_suggestion" ;;
            *) : ;;  # WRITE_IN_SCOPE / NO_SCOPE → normal flow (prompt)
        esac
        continue
    fi
    # (b) raw tool matching the pattern → redirect.
    if [[ "$match_cmd" == $_sr_pattern ]]; then
        deny "$_sr_suggestion"
    fi
    # (c) temp-script scan: a script-exec whose file contains a raw match.
    case "$match_cmd" in
        bash\ *|sh\ *|source\ *|./*)
            _sr_file="${match_cmd#* }"; _sr_file="${_sr_file%% *}"
            if [[ -f "$_sr_file" ]] && grep -Eq '(^|[^[:alnum:]_])kubectl([^[:alnum:]_]|$)' "$_sr_file" 2>/dev/null; then
                deny "Script $_sr_file calls raw kubectl under an active practice scope — run each step via 'ws k8s', or 'ws hook-bypass $_sr_slug'."
            fi
            ;;
    esac
done
```

(Note the `# shellcheck disable=SC2053` convention applies to the `== $_sr_pattern` glob match, mirroring :823. `$match_cmd` is passed unquoted to `k8s_guard_evaluate` so its tokens become argv — acceptable because `match_cmd` is the normalized command string.)

- [ ] **Step 5: Run to verify pass**

Run: `bash scripts/ws test yggdrasil 'scoped-redirect:'`
Expected: PASS (all scoped-redirect cases).

- [ ] **Step 6: Run the full hook suite for regressions**

Run: `bash scripts/ws test yggdrasil 'redirect:|bypass:|adapter-redirect:|ask:|allow:|deny:'`
Expected: PASS — Tier 1/2/3/4/5 behavior unchanged.

- [ ] **Step 7: Commit**

Bodyfile `.commits/p5-tier.md` — `add:` `.claude/hooks/gdd-permission-hook.sh`, `.claude/hooks/hook-rules`, `tests/hook/gdd-permission-hook.bats`. Message: `feat(hook): scoped-redirect tier — raw kubectl redirect, ws k8s read auto-approve, temp-script scan`.

---

## Phase 6 — `gdd-k8s` skill + mentoring wiring

### Task 12: The `gdd-k8s` skill

**Files:**
- Create: `.agent/skills/gdd-k8s/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.agent/skills/gdd-k8s/SKILL.md` with frontmatter `name: gdd-k8s` and `description:` (use when a guarded kubectl practice is requested or `GDD_K8S_CONTEXT` is set). Body: the scope-capture flow (explain → `kubectl config get-contexts` → per-namespace confirm → `ws k8s scope set …` → confirm armed), the behavior summary (reads auto-approve, writes prompt + must be in-scope, raw kubectl and kubectl-bearing scripts redirected/blocked, how to widen/clear/bypass), and the "training wheels, not a security boundary" framing. No hard-wrapped prose.

- [ ] **Step 2: Verify it parses in orient**

Run: `bash scripts/ws orient` — confirm `[workspace] gdd-k8s` appears in the skill index.

- [ ] **Step 3: Commit**

Bodyfile `.commits/p6-skill.md` — `add:` `.agent/skills/gdd-k8s/SKILL.md`. Message: `feat(gdd): add gdd-k8s skill — guarded kubectl practice workflow`.

### Task 13: Mentoring invokes gdd-k8s; surface in skills-reference

**Files:**
- Modify: `.agent/skills/gdd-mentoring/SKILL.md`, `.agent/skills/gdd-orientation/SKILL.md`, `docs/gdd/skills-reference.md`

- [ ] **Step 1: Wire mentoring → gdd-k8s**

In `.agent/skills/gdd-mentoring/SKILL.md`, add a section: when the mentoring overlay is on and a k8s-practice signal fires ("practice kubectl", "test cluster access", "nervous about prod"), read `.agent/skills/gdd-k8s/SKILL.md` and run its scope-capture flow. Note any stance can invoke gdd-k8s; mentoring is the overlay most likely to and narrates each step.

- [ ] **Step 2: Mention in orientation + skills-reference**

In `.agent/skills/gdd-orientation/SKILL.md` "Tutorial detection" area, add that a k8s-practice signal can trigger `gdd-k8s`. In `docs/gdd/skills-reference.md`, add a `gdd-k8s` row under the practice/role skills.

- [ ] **Step 3: Verify + commit**

Run: `bash scripts/ws test yggdrasil` (full suite, final regression gate).
Bodyfile `.commits/p6-wiring.md` — `add:` the three files. Message: `feat(gdd): mentoring invokes gdd-k8s on a practice signal; list it in skills-reference`.

---

## Final verification

- [ ] **Full suite green:** `bash scripts/ws test yggdrasil` — all tests pass (existing + new session/k8s/hook cases).
- [ ] **Orient surfaces the new skill + no stray "mode":** `bash scripts/ws orient` shows `gdd-k8s`; manual grep confirms no role/mode-sense "mode" remains outside `docs/gdd/samples/` and `docs/plans/`.
- [ ] **Manual smoke (real or stubbed kubectl):** `ws k8s scope set …`, an in-scope read, an out-of-scope write (blocked), a raw `kubectl` (redirected), a kubectl-bearing temp script (blocked).
- [ ] **Open the CR:** `ws cr yggdrasil "feat: mentoring k8s training wheels" .crs/<body>.md` — budget 3–4 CodeRabbit rounds for a plan-sized change.

## Spec coverage (self-review)

- Taxonomy (design §1): Tasks 4-5. Session layer (§2): Tasks 1-3. `ws k8s` + guard (§3): Tasks 7-9. Hook (§4): Tasks 10-11. `gdd-k8s` + mentoring (§5): Tasks 12-13. Migration (§Migration): Tasks 3,4,5,6 (direct edits, no hoard upgrade, no legacy fallback). Testing (§Testing): per-task bats + stubbed kubectl. `ws clean` hardening and the stance-philosophy note are doc/behavior items folded into Tasks 3 and 5 respectively — **verify both are present before final commit** (ws clean: routine clean spares all session files; stance note: in `roles-and-stances.md`).
