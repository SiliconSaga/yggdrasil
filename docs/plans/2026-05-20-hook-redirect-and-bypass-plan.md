# Hook Redirect-to-`ws` and Session-Scoped Bypass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Tier 2 redirect-deny that catches raw `git commit` / `git push` / `gh pr create` and points the agent at the corresponding `ws` subcommand. Pair it with a session-scoped bypass mechanism: `ws hook-bypass <slug>` writes a marker file the hook honors for the current `CLAUDE_SESSION_ID`. The `ws hook-bypass` subcommand itself is force-prompted via the ask-tier — that's the security gate.

**Architecture:** The existing `.claude/hooks/gdd-permission-hook.sh` is extended with a third decision tier (between composition-deny and the existing ask-tier) plus a new `[redirect-commands]` section in `hook-rules`. A new `scripts/ws-hook-bypass.sh` writes session-keyed marker files under `.tmp/hook-bypass/`. The marker check lives inside the redirect tier — a matching marker turns the deny into an allow with a `BYPASS-ALLOW` audit entry. Tier numbering renumbers from 1-2-3-4 to 1-2-3-4-5 throughout.

**Tech Stack:** Bash (hook + ws CLI); `jq` (already a hook dependency); bats (`tests/hook/`, `tests/ws-cli/`); flat sectioned text config (existing format extended with a 3-column pipe-separated section).

**Spec:** [`2026-05-20-hook-redirect-and-bypass-design.md`](2026-05-20-hook-redirect-and-bypass-design.md)

> **Correction (2026-05-22, post-implementation):** the Goal above and some snippets below say the marker keys off `CLAUDE_SESSION_ID`. The implementation resolves `${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}` — the real Claude Code env var is `CLAUDE_CODE_SESSION_ID`, discovered during the live acceptance walk-through (the `CLAUDE_SESSION_ID`-only form was unset in practice and the bypass was non-functional until fixed). The ask pattern also shipped as the narrower `ws hook-bypass [a-z]*`. This plan is kept as the historical execution record; `.claude/hooks/` and `scripts/ws-hook-bypass.sh` are authoritative.

---

## Notes on this plan

- **Branch:** all work is on `feat/hook-redirect-and-bypass` (off `main`). The design doc is already committed there (`ab9306a`).
- **Verification model:** hook decision logic is genuinely testable — bats invokes the hook with synthetic JSON payloads (now including `session_id`) and asserts on emitted JSON + the audit log. TDD applies to Tasks 2-4 and Task 7. Config files, comment-block renumbering, the dispatcher wiring, the interactive script, and doc updates have no unit tests — verification there is read-back.
- **bash 3.2 compatibility:** old macOS ships bash 3.2, where `"${arr[@]}"` on an empty array errors under `set -u`. Every array expansion uses the safe form `${arr[@]+"${arr[@]}"}`. Do not "simplify" it.
- **`ws commit`:** commit via `bash scripts/ws commit yggdrasil .commits/<file>.md` with an `add:` bodyfile, per the workspace convention. Each task ends with a single commit.
- **Hook line numbers** below refer to the current file (731 lines, post-ask-tier).
- **Tier renumbering caveat:** the renumbering (Task 5) is comment-only — the *behavior* is established in Tasks 2-4. Until Task 5 runs, the in-script comments call the new tier "Tier 2 (new)" inline; the renumbered comment block lands as one focused commit.
- **Ask-pattern narrowness for `--help` UX:** the ask-list entry uses `ws hook-bypass [a-z]*` rather than `ws hook-bypass *` so that `ws hook-bypass --help` and `ws hook-bypass -h` fall through to settings.json allowlist matching instead of force-prompting for help text. The character-class `[a-z]` matches slug-shaped first chars and excludes leading-dash flags. Tested in Task 6.

## File map

**Create:**

- `scripts/ws-hook-bypass.sh` — the new subcommand script (Task 7)
- `tests/ws-cli/hook-bypass.bats` — bats coverage for `ws hook-bypass` (Task 7)
- `tests/hook/interactive-redirect-acceptance.md` — scripted live acceptance test (Task 10)

**Modify:**

- `.claude/hooks/gdd-permission-hook.sh` — parser extension + new tier + audit helper + renumbering (Tasks 2-5)
- `.claude/hooks/hook-rules` — add `[redirect-commands]` section + `ws hook-bypass [a-z]*` ask-list entry (Task 6)
- `.claude/hooks/README.md` — document new tier + bypass mechanism (Task 9)
- `.claude/settings.json` — allowlist `ws hook-bypass --help`, `ws hook-bypass -h`, `ws help hook-bypass` (Task 8)
- `scripts/ws` — dispatch the new subcommand + help-text entry (Task 8)
- `tests/hook/test_helper.bash` — add session_id payload support + helpers (Task 1)
- `tests/hook/gdd-permission-hook.bats` — new redirect + bypass tests (Tasks 2-4)
- `docs/gdd/permissions.md` — add redirect + bypass (Task 9)
- `docs/gdd/agent-training.md` — explain redirect + bypass loop (Task 9)
- `docs/gdd/trust-and-safety.md` — record redirect as training-aid layer (Task 9)
- `AGENTS.md` — one-line mention pointing at hook from the ws-first reflex table (Task 9)

---

## Task 1: Extend `test_helper.bash` with session_id support and bypass-marker helpers

**Files:**

- Modify: `tests/hook/test_helper.bash`

The hook's bypass-check needs `session_id` from the stdin payload. The existing `run_hook` helper doesn't supply one, and bypass tests need to write marker files under the synthetic `$WORK/.tmp/hook-bypass/` directory. Add helpers; do not break existing tests.

- [ ] **Step 1: Add `run_hook_with_session` helper**

In `tests/hook/test_helper.bash`, after the existing `run_hook()` definition (line 110-125), append:

```bash
# Build a tool-call payload that includes session_id, and pipe it
# into the hook. Used by tests that exercise the bypass-marker logic
# (Tier 2). Args: $1 = command string, $2 = session_id, $3 = cwd
# (defaults to $WORK).
run_hook_with_session() {
    local cmd="$1"
    local session_id="$2"
    local cwd="${3:-$WORK}"
    local payload
    payload=$(jq -nc --arg cmd "$cmd" --arg cwd "$cwd" --arg sid "$session_id" \
        '{session_id:$sid, tool_input:{command:$cmd}, cwd:$cwd}')
    run "$TIMEOUT_BIN" 10 bash "$HOOK_BIN" <<< "$payload"
}
```

- [ ] **Step 2: Add `write_bypass_marker` helper**

In the same file, after `write_local_hook_rules()` (line 87), append:

```bash
# Write a bypass marker file under $WORK/.tmp/hook-bypass/<slug>.bypass
# with the given session_id and optional reason. Used by Tier 2 bypass
# tests to simulate a marker created by `ws hook-bypass`.
# Args: $1 = slug, $2 = session_id, $3 = reason (optional)
write_bypass_marker() {
    local slug="$1"
    local session_id="$2"
    local reason="${3:-}"
    mkdir -p "$WORK/.tmp/hook-bypass"
    cat > "$WORK/.tmp/hook-bypass/$slug.bypass" <<EOF
session_id: $session_id
slug: $slug
created_at: 2026-05-20T15:00:00Z
reason: $reason
EOF
}
```

- [ ] **Step 3: Verify existing bats tests still pass**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats`
Expected: all current tests pass (no behavior change yet).

- [ ] **Step 4: Commit**

Write `.commits/hook-bypass-test-helper.md`:

```yaml
---
message: "test(hook): add session_id + bypass-marker helpers to test_helper"
add:
  - tests/hook/test_helper.bash
---

Prep work for the redirect + bypass tier (`hook-v2-extensions` arc):

- `run_hook_with_session` — emits a payload with `session_id` so Tier 2
  bypass-check tests can match a marker against the current session.
- `write_bypass_marker` — writes a synthetic `.tmp/hook-bypass/<slug>.bypass`
  file with frontmatter the hook will parse for `session_id` / `reason`.

No production change yet; the helpers exist so the next task can land
TDD-first.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-bypass-test-helper.md`

---

## Task 2: Extend hook parser to recognize `[redirect-commands]`

**Files:**

- Modify: `.claude/hooks/gdd-permission-hook.sh` (parser at lines 324-361)
- Modify: `tests/hook/gdd-permission-hook.bats`

The existing `_parse_rules_file` function recognizes three sections (`scratch-dirs`, `ask-commands`, `allow-extras`). Add a fourth: `redirect-commands` with three pipe-separated columns.

- [ ] **Step 1: Write the failing test**

In `tests/hook/gdd-permission-hook.bats`, append at end of file (after the last existing test):

```bash
# ─── Tier 2 redirect-deny — parser ──────────────────────────────────

@test "redirect: malformed [redirect-commands] entry (2 columns) is skipped with warning" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
malformed-entry | only-two-columns
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook "git commit -m x"
    [ "$status" -eq 0 ]
    # Well-formed entry still fires
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
    # Malformed entry triggers a warning in the audit log
    grep -q "WARNING.*redirect-commands.*malformed" "$HOME/.claude/hook-audit.log"
}

@test "redirect: malformed slug (uppercase / underscore) is skipped" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git_commit | git commit* | bad slug, should skip
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook "git commit -m x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Use ws commit"* ]]
    [[ "$output" != *"bad slug"* ]]
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats -f redirect`
Expected: both tests FAIL (parser doesn't know about `[redirect-commands]` yet).

- [ ] **Step 3: Extend `_parse_rules_file`**

In `.claude/hooks/gdd-permission-hook.sh`, around line 316 (just after `allow_extras=()`), add a new module-scope array:

```bash
redirect_commands=()  # entries: "<slug>|<pattern>|<suggestion>"
```

Then in the `case "$section"` block inside `_parse_rules_file` (lines 339-357), add a new case arm before the `*)` catch-all:

```bash
                    redirect-commands)
                        # Parse three pipe-separated columns: slug | pattern | suggestion.
                        # Split on the first two " | " occurrences; remainder is suggestion.
                        local slug pattern suggestion rest
                        if [[ "$line" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [redirect-commands] entry, missing separator): $file" >> "$audit_log"
                            continue
                        fi
                        slug="${line%% | *}"
                        rest="${line#* | }"
                        if [[ "$rest" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [redirect-commands] entry, only two columns): $file" >> "$audit_log"
                            continue
                        fi
                        pattern="${rest%% | *}"
                        suggestion="${rest#* | }"
                        # Trim trailing whitespace from slug and pattern (suggestion is free text — keep as-is)
                        slug="${slug%"${slug##*[![:space:]]}"}"
                        pattern="${pattern%"${pattern##*[![:space:]]}"}"
                        # Validate slug shape: ^[a-z0-9-]+$
                        if [[ ! "$slug" =~ ^[a-z0-9-]+$ ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [redirect-commands] entry, bad slug '$slug'): $file" >> "$audit_log"
                            continue
                        fi
                        # Pack as "slug|pattern|suggestion" (internal separator, never displayed)
                        redirect_commands+=("$slug|$pattern|$suggestion")
                        ;;
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats -f redirect`
Expected: still FAIL — the parser stores entries but no tier yet emits deny. Tests check for `"Use ws commit"` in deny output, which only Task 3 produces.

These two tests will pass at the end of Task 3 (when Tier 2 actually evaluates `redirect_commands`). Carry them forward — do not commit yet.

- [ ] **Step 5: Hold the commit**

These parser changes belong with Task 3 (the tier that consumes them). Hold uncommitted; the combined parser + Tier 2 commit lands at the end of Task 3.

---

## Task 3: Add Tier 2 redirect-deny logic

**Files:**

- Modify: `.claude/hooks/gdd-permission-hook.sh` (after Tier 1, before existing Tier 2 ask-list at line 604)
- Modify: `tests/hook/gdd-permission-hook.bats`

Add a new evaluation block that walks `redirect_commands` and emits a deny with the suggestion text. The bypass-check is stubbed in this task (always "no marker") and gets implemented in Task 4. This separation keeps each task testable.

- [ ] **Step 1: Write the failing tests**

Append to `tests/hook/gdd-permission-hook.bats`:

```bash
@test "redirect: git commit denies with ws commit suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use `ws commit <comp> <bodyfile>` — handles Co-Authored-By trailer + bodyfile-driven staging.
git-push | git push* | Use `ws push <comp> [branch]` — handles fork-remote selection.
gh-pr-create | gh pr create* | Use `ws cr <comp> <title> <bodyfile>` — bodyfile-driven.
EOF
)"
    run_hook 'git commit -m "fix bug"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use \`ws commit"* ]]
}

@test "redirect: git push denies with ws push suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    run_hook "git push origin feature/x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws push"* ]]
}

@test "redirect: gh pr create denies with ws cr suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws cr"* ]]
}

@test "redirect: composition wins over redirect (T1 before T2)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook 'git commit -m x && git push'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
    [[ "$output" != *"Use ws commit"* ]]
}

@test "redirect: command outside [redirect-commands] passes through Tier 2" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_project_settings "Bash(ls *)"
    run_hook "ls -la"
    [ "$status" -eq 0 ]
    # Settings.json allow at Tier 4 should still match
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats -f redirect`
Expected: the new tests FAIL — no Tier 2 redirect block in the hook yet.

- [ ] **Step 3: Add Tier 2 redirect-deny block**

In `.claude/hooks/gdd-permission-hook.sh`, between the closing `;;` of Tier 1 (line 556, after the `*"|"*` case) and the comment `# ─── Normalization for matching` (line 558), insert:

```bash
# ─── Tier 2: Redirect deny — raw commands with a `ws` equivalent ────
#
# Walk redirect_commands (parsed from [redirect-commands] in hook-rules).
# A match emits `deny` with the entry's suggestion as the reason — the
# corrective text points at the right `ws` subcommand. Tier 1 (above)
# still runs first, so a composed `git commit -m x && git push` denies
# for composition, never for redirect — the composition message is
# more actionable.
#
# A bypass marker for the matching slug — written by `ws hook-bypass
# <slug>` with the current session_id — turns the deny into an allow
# (BYPASS-ALLOW audit entry). See bypass-check below.

# Normalize cmd once for matching (the same normalization Tier 3/4 use).
_t2_match_cmd="$(normalize_for_match "$cmd")"

# Read session_id from the stdin payload (already parsed at line 158
# above as the audit `event` was — we re-parse here to keep the Tier 2
# block self-contained).
_t2_session_id=$(echo "$input" | jq -r '.session_id // ""')

for _entry in ${redirect_commands[@]+"${redirect_commands[@]}"}; do
    # Entry shape: "<slug>|<pattern>|<suggestion>"
    _t2_slug="${_entry%%|*}"
    _t2_rest="${_entry#*|}"
    _t2_pattern="${_t2_rest%%|*}"
    _t2_suggestion="${_t2_rest#*|}"
    _t2_match_pattern="$(normalize_for_match "$_t2_pattern")"
    # shellcheck disable=SC2053
    if [[ "$_t2_match_cmd" == $_t2_match_pattern ]]; then
        # Bypass-marker check (stub in this task — always "no marker").
        # Task 4 wires the actual file lookup against $_t2_session_id.
        _t2_marker_path="$cwd/.tmp/hook-bypass/$_t2_slug.bypass"
        _t2_bypass_ok=0
        if [[ -f "$_t2_marker_path" ]]; then
            # Parse session_id and reason from the marker file.
            _t2_marker_sid=$(grep '^session_id:' "$_t2_marker_path" 2>/dev/null | sed 's/^session_id: *//')
            _t2_marker_reason=$(grep '^reason:' "$_t2_marker_path" 2>/dev/null | sed 's/^reason: *//')
            if [[ -n "$_t2_session_id" && "$_t2_marker_sid" == "$_t2_session_id" ]]; then
                _t2_bypass_ok=1
            fi
        fi
        if [[ "$_t2_bypass_ok" == "1" ]]; then
            # Implemented in Task 4 — placeholder allow that the next
            # task replaces with the BYPASS-ALLOW audit helper.
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-ALLOW [$_t2_slug] reason=\"$_t2_marker_reason\" [$event]: $(audit_safe "$cmd")" >> "$audit_log"
            printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
            exit 0
        fi
        deny "$_t2_suggestion"
    fi
done
```

- [ ] **Step 4: Run all hook tests**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats`
Expected: all tests pass — the five new `redirect:` tests plus the two `redirect:` parser tests from Task 2 plus every existing test.

If any pre-existing test now fails because Tier 2 catches a command it shouldn't, that's a real regression — investigate before continuing.

- [ ] **Step 5: Commit (parser + tier together)**

Write `.commits/hook-redirect-tier.md`:

```yaml
---
message: "feat(hook): add Tier 2 redirect deny + [redirect-commands] parser"
add:
  - .claude/hooks/gdd-permission-hook.sh
  - tests/hook/gdd-permission-hook.bats
---

Implement the first half of the `hook-v2-extensions` deep pair:

- Parser: extend `_parse_rules_file` to recognize a new
  `[redirect-commands]` section with three pipe-separated columns
  (slug | pattern | suggestion). Malformed entries (wrong column
  count, bad slug shape) log a warning to the audit log and degrade
  gracefully without crashing the hook.
- Tier 2 (new): redirect-deny block between Tier 1 composition and
  the existing ask logic. Walks `redirect_commands`, glob-matches
  against the normalized command, denies with the suggestion text as
  `permissionDecisionReason`.
- Bypass-marker check: inline inside Tier 2, parses
  `.tmp/hook-bypass/<slug>.bypass` for `session_id` matching the
  current session. Wired up here so the deny-with-bypass loop is
  testable end-to-end; the dedicated `BYPASS-ALLOW` audit helper +
  more granular tests land in the next task.

Tier renumbering (comment-only) lands separately in Task 5; until
then the new tier carries inline header comments naming it Tier 2.

Refs: `docs/plans/2026-05-20-hook-redirect-and-bypass-design.md`
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-redirect-tier.md`

---

## Task 4: Add bypass-marker test coverage + slug-isolation tests

**Files:**

- Modify: `tests/hook/gdd-permission-hook.bats`

Task 3 implemented the bypass-check inline. This task verifies it with the helper from Task 1 (`write_bypass_marker` + `run_hook_with_session`) and confirms the invariants: matching session_id allows, mismatched denies, slug isolation, bypass does not override Tier 1 or Tier 3.

- [ ] **Step 1: Write the new test cases**

Append to `tests/hook/gdd-permission-hook.bats`:

```bash
# ─── Tier 2 redirect — bypass marker ────────────────────────────────

@test "bypass: marker with matching session_id turns deny into allow" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend last commit"
    run_hook_with_session 'git commit --amend -m "fix"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason="amend last commit"' "$HOME/.claude/hook-audit.log"
}

@test "bypass: marker with mismatched session_id still denies" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-stale" "old session"
    run_hook_with_session 'git commit -m "fix"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
}

@test "bypass: marker with empty reason still allows, audit reason is empty" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" ""
    run_hook_with_session 'git commit -m "x"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason=""' "$HOME/.claude/hook-audit.log"
}

@test "bypass: git-commit marker does NOT bypass gh-pr-create deny (slug isolation)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session "gh pr create --title x --body y" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws cr"* ]]
}

@test "bypass: marker does NOT override Tier 1 composition deny" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session 'git commit -m x && git push' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "bypass: marker does NOT override Tier 3 ask-list" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
[ask-commands]
rm -rf*
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session "rm -rf .tmp/anything" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "bypass: empty session_id in payload means no marker can match" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "" "no-id"
    run_hook_with_session "git commit -m x" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "bypass: ws hook-bypass <slug> does not match any redirect pattern (pattern-collision invariant)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
[ask-commands]
ws hook-bypass [a-z]*
EOF
)"
    # Each known slug invocation should hit Tier 3 ask, NOT Tier 2 deny.
    for slug in git-commit git-push gh-pr-create; do
        run_hook "ws hook-bypass $slug"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    done
}
```

- [ ] **Step 2: Run the tests**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats -f bypass`
Expected: all 8 new bypass tests pass. The bypass logic was implemented in Task 3 — this task is purely verification + invariants.

If any fail, the most likely cause is a subtle Task 3 implementation bug. Read the failing test's command + expected output, then re-read the Tier 2 block.

- [ ] **Step 3: Commit**

Write `.commits/hook-bypass-tests.md`:

```yaml
---
message: "test(hook): cover Tier 2 bypass-marker behavior + invariants"
add:
  - tests/hook/gdd-permission-hook.bats
---

8 new bats tests exercising the bypass-marker logic landed in Task 3:

- matching session_id → ALLOW with BYPASS-ALLOW audit
- mismatched session_id → DENY (no bypass)
- empty reason → ALLOW with `reason=""` in audit (stable shape)
- slug isolation (a git-commit marker does NOT bypass gh-pr-create)
- bypass does NOT override Tier 1 composition deny
- bypass does NOT override Tier 3 ask-list
- empty session_id in payload → no marker can match
- pattern-collision invariant: `ws hook-bypass <slug>` does NOT match
  any redirect pattern (would deadlock the bypass flow)
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-bypass-tests.md`

---

## Task 5: Renumber tier comments throughout the hook script

**Files:**

- Modify: `.claude/hooks/gdd-permission-hook.sh`

Behavior is in place. Now the header comment block and inline `Tier N` references need to reflect the new 1-2-3-4-5 numbering: composition → redirect → ask → settings allow → extras allow.

- [ ] **Step 1: Update the DECISION TIERS section in the header comment**

In `.claude/hooks/gdd-permission-hook.sh` at lines 46-71 (the `# ─── DECISION TIERS (in order) ─────` block), replace the entire block with:

```text
# ─── DECISION TIERS (in order) ──────────────────────────────────────
#
# Tier 1 — Shell composition guard (DENY)
#   Reject any command containing &&, ||, ;, |, command substitution
#   (`...` or $(...)), or output/input redirection (>, <). Each arm
#   denies with a specific corrective message so the agent learns
#   what to do instead. This trains the agent to use one tool call
#   per action and to prefer native flags (--limit, --output) over
#   shell pipelines.
#
# Tier 2 — Redirect deny (DENY, with per-slug bypass override)
#   Commands matching a [redirect-commands] entry in hook-rules deny
#   with a corrective message pointing at the right `ws` subcommand
#   (e.g. `git commit` → use `ws commit`). Each entry declares a slug
#   (column 1), the deny pattern (column 2), and the suggestion text
#   (column 3, free text).
#
#   A session-scoped bypass marker — written by `ws hook-bypass
#   <slug>` after a human-approved ask prompt — overrides the deny
#   for that slug. The marker lives at .tmp/hook-bypass/<slug>.bypass
#   and is honored only when its session_id matches the current
#   CLAUDE_SESSION_ID. Marker hits log BYPASS-ALLOW to the audit log
#   with the slug + optional reason.
#
# Tier 3 — Ask-list from hook-rules [ask-commands] (ASK)
#   Destructive commands that should always prompt, even under
#   acceptEdits. Any match → ask.
#
# Tier 4 — Per-project allowlist from .claude/settings.json (ALLOW)
#   Walk up from $cwd, collect Bash(...) entries from each
#   .claude/settings.json found, then check $HOME/.claude/settings.json
#   too. Glob-match each pattern against the command. Any match → allow.
#
# Tier 5 — [allow-extras] from hook-rules.local (ALLOW, optional)
#   Personal per-machine glob patterns declared in hook-rules.local's
#   [allow-extras] section. Parsed into allow_extras above. Any
#   match → allow. Silently absent if hook-rules.local has no section.
#
# Default — Passthrough
#   Exit 0 with no JSON. Harness handles as normal.
#
# Config: the scratch-dir, ask-command, and redirect-command lists
# live in .claude/hooks/hook-rules (committed baseline); per-machine
# additions and [allow-extras] live in hook-rules.local (gitignored).
# See .claude/hooks/README.md.
```

- [ ] **Step 2: Update the Tier 2 inline section header**

The block added in Task 3 currently starts with `# ─── Tier 2: Redirect deny — raw commands with a \`ws\` equivalent ────`. Leave the header as-is — it's already Tier 2 in the new scheme. No change needed.

- [ ] **Step 3: Renumber the existing ask section header**

At line 604 (the existing `# ─── Tier 2: Ask-list — force a prompt for destructive commands ─────`), change `Tier 2` to `Tier 3`:

```text
# ─── Tier 3: Ask-list — force a prompt for destructive commands ─────
```

- [ ] **Step 4: Renumber the settings-allow section header**

At line 624 (the existing `# ─── Tier 3: Match against settings.json permissions.allow ────────`), change `Tier 3` to `Tier 4`:

```text
# ─── Tier 4: Match against settings.json `permissions.allow` ────────
```

- [ ] **Step 5: Renumber the allow-extras section header**

At line 697 (the existing `# ─── Tier 4: Allow via [allow-extras] from hook-rules.local ─────────`), change `Tier 4` to `Tier 5`:

```text
# ─── Tier 5: Allow via [allow-extras] from hook-rules.local ─────────
```

- [ ] **Step 6: Verify nothing else mentions a numbered tier**

Run: `grep -n "Tier [0-9]" .claude/hooks/gdd-permission-hook.sh`
Expected output: only the lines from steps 1-5 above. Five numbered headers + the inline references inside each block's docstring.

If grep surfaces other `Tier N` references that no longer match, update them inline.

- [ ] **Step 7: Run all bats tests to confirm comments-only**

Run: `bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats`
Expected: every test still passes. This was a comment-only change.

- [ ] **Step 8: Commit**

Write `.commits/hook-tier-renumber.md`:

```yaml
---
message: "docs(hook): renumber tiers to 1-2-3-4-5 after Tier 2 redirect addition"
add:
  - .claude/hooks/gdd-permission-hook.sh
---

Comment-only renumbering. The hook now has five tiers:

  1 — composition deny
  2 — redirect deny (new) + per-slug bypass override
  3 — ask-list (was 2)
  4 — settings.json allow (was 3)
  5 — hook-rules.local allow-extras (was 4)

No behavior change.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-tier-renumber.md`

---

## Task 6: Add v1 redirect entries + `ws hook-bypass` ask pattern to `hook-rules`

**Files:**

- Modify: `.claude/hooks/hook-rules`

This is the change that actually turns the workspace's hook on for the three v1 redirects.

- [ ] **Step 1: Append `[redirect-commands]` section**

At the end of `.claude/hooks/hook-rules` (after the existing `[ask-commands]` block), append:

```text

[redirect-commands]
# Raw commands with a ws equivalent. The hook denies a match in Tier 2
# (between composition deny and ask) with the suggestion text below.
# Format: <slug> | <pattern> | <suggestion>. Slug is kebab-case (^[a-z0-9-]+$);
# it doubles as the bypass-marker filename and the ws hook-bypass argument.
# Pattern is a bash glob. Suggestion is free text, ends the line, may contain
# pipes (parsing splits on the first two " | " only).
git-commit   | git commit*    | Use `ws commit <comp> <bodyfile>` — handles Co-Authored-By trailer + bodyfile-driven staging. See `ws help commit`. If `ws commit` doesn't fit (rare), run `ws hook-bypass git-commit` to request a session-scoped bypass.
git-push     | git push*      | Use `ws push <comp> [branch]` — handles fork-remote selection from identity.forkOrg and sets upstream on first push. `ws hook-bypass git-push` for a session-scoped bypass.
gh-pr-create | gh pr create*  | Use `ws cr <comp> <title> <bodyfile>` — bodyfile-driven, applies identity substitutions, picks the right token + remote. `ws hook-bypass gh-pr-create` for a session-scoped bypass.
```

- [ ] **Step 2: Add `ws hook-bypass [a-z]*` to `[ask-commands]`**

Inside the existing `[ask-commands]` section of `.claude/hooks/hook-rules`, append after `find*-execdir*`:

```text
ws hook-bypass [a-z]*
bash scripts/ws hook-bypass [a-z]*
```

The pattern uses `[a-z]*` (not `*`) so that `ws hook-bypass --help` and `ws hook-bypass -h` fall through to Tier 4 settings.json allow without force-prompting. Slug-shaped invocations (the security-relevant ones) still ask.

Two lines because the hook's normalization handles `bash scripts/ws` → `ws` symmetrically — but the ask-list match runs against the normalized form. Either form will match the first pattern after normalization, but keeping both makes the rule legible if normalization is ever revisited. (If normalization is confirmed bulletproof, the second line can later be dropped.)

- [ ] **Step 3: Verify the hook parses the new section**

Run a quick smoke test by running any hook test:

```bash
bash scripts/ws test yggdrasil tests/hook/gdd-permission-hook.bats -f composition
```

Expected: passes. The committed `hook-rules` is now richer; existing tests still pass because they each set their own synthetic `hook-rules` via `write_project_hook_rules`.

- [ ] **Step 4: Confirm `git commit` would now deny in this workspace**

Inspect with a payload sent to the live hook (the audit log is `$HOME/.claude/hook-audit.log`):

Write a one-shot test payload:

```bash
cat > .tmp/hook-test-payload.json <<'EOF'
{"session_id":"smoke","tool_input":{"command":"git commit -m smoke"},"cwd":"$PWD"}
EOF
```

Send via:

```bash
bash .claude/hooks/gdd-permission-hook.sh < .tmp/hook-test-payload.json
```

Expected output: JSON containing `"permissionDecision":"deny"` and a `permissionDecisionReason` mentioning `ws commit`.

Expected audit log entry (last line of `$HOME/.claude/hook-audit.log`): `DENY [git-commit]`. **NB:** the DENY audit line uses the slug in brackets only if the deny audit format is extended in this task; the current `deny()` helper writes just `DENY (<reason>): <cmd>`. The slug tag in the audit log is **not** part of v1; the slug is implicit in the reason text. If you want the slug tag, surface that as a follow-on observation rather than scope creep.

- [ ] **Step 5: Commit**

Write `.commits/hook-rules-redirect-entries.md`:

```yaml
---
message: "feat(hook): turn on redirect deny for git commit / git push / gh pr create"
add:
  - .claude/hooks/hook-rules
---

Adds the v1 [redirect-commands] entries that make Tier 2 (added in
the prior task) live in this workspace:

- git-commit   → ws commit
- git-push     → ws push
- gh-pr-create → ws cr

Also adds `ws hook-bypass [a-z]*` to the [ask-commands] baseline so
creating a bypass marker always force-prompts the human. The narrow
`[a-z]*` pattern (not `*`) keeps `ws hook-bypass --help` / `-h` from
prompting — they fall through to settings.json allow.

The matching `ws hook-bypass` subcommand lands in the next task.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-rules-redirect-entries.md`

---

## Task 7: Write `scripts/ws-hook-bypass.sh` and its bats coverage

**Files:**

- Create: `scripts/ws-hook-bypass.sh`
- Create: `tests/ws-cli/hook-bypass.bats`

The subcommand validates the slug, reads `$CLAUDE_SESSION_ID`, and writes the marker.

- [ ] **Step 1: Write the failing bats tests**

Create `tests/ws-cli/hook-bypass.bats`:

```bash
#!/usr/bin/env bats

# Tests for `ws hook-bypass <slug> [--reason "<text>"]`.
#
# The subcommand validates <slug> against [redirect-commands] entries
# in .claude/hooks/hook-rules, reads $CLAUDE_SESSION_ID, and writes
# .tmp/hook-bypass/<slug>.bypass with frontmatter.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ws-hook-bypass.sh"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/.claude/hooks"
    # Synthetic hook-rules with three slugs.
    cat > "$WORK/.claude/hooks/hook-rules" <<'EOF'
[redirect-commands]
git-commit   | git commit*    | Use ws commit
git-push     | git push*      | Use ws push
gh-pr-create | gh pr create*  | Use ws cr
EOF
    export PROJECT_ROOT="$WORK"
}

@test "valid slug + session id writes marker" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 0 ]
    [ -f "$WORK/.tmp/hook-bypass/git-commit.bypass" ]
    grep -q '^session_id: session-abc$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    grep -q '^slug: git-commit$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    grep -q '^reason: $' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "--reason populates the reason field" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" git-commit --reason "amend last commit"
    [ "$status" -eq 0 ]
    grep -q '^reason: amend last commit$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "unknown slug exits 1 with helpful message" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" not-a-slug
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown slug"* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"git-push"* ]]
    [[ "$output" == *"gh-pr-create"* ]]
    [ ! -d "$WORK/.tmp/hook-bypass" ]
}

@test "missing CLAUDE_SESSION_ID exits 1" {
    unset CLAUDE_SESSION_ID
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_SESSION_ID"* ]]
    [ ! -f "$WORK/.tmp/hook-bypass/git-commit.bypass" ]
}

@test ".tmp/hook-bypass/ auto-created if absent" {
    export CLAUDE_SESSION_ID="session-abc"
    [ ! -d "$WORK/.tmp/hook-bypass" ]
    run bash "$SCRIPT" git-push
    [ "$status" -eq 0 ]
    [ -d "$WORK/.tmp/hook-bypass" ]
    [ -f "$WORK/.tmp/hook-bypass/git-push.bypass" ]
}

@test "re-running same slug overwrites the marker" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" git-commit --reason "first reason"
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" git-commit --reason "second reason"
    [ "$status" -eq 0 ]
    grep -q '^reason: second reason$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    ! grep -q '^reason: first reason$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--reason"* ]]
}

@test "-h is treated the same as --help" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no args prints usage and exits 1" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash scripts/ws test yggdrasil tests/ws-cli/hook-bypass.bats`
Expected: all 9 tests FAIL — the script doesn't exist yet.

- [ ] **Step 3: Write `scripts/ws-hook-bypass.sh`**

Create `scripts/ws-hook-bypass.sh`:

```bash
#!/usr/bin/env bash
# ws-hook-bypass.sh — write a session-scoped bypass marker for a Tier 2
# redirect-deny slug. The marker lets the matching command run for the
# rest of the current Claude Code session.
#
# Usage:
#   ws hook-bypass <slug> [--reason "<text>"]
#
# <slug> must appear as column 1 of a row in .claude/hooks/hook-rules
# under [redirect-commands]. The script writes
# .tmp/hook-bypass/<slug>.bypass with frontmatter the PreToolUse hook
# parses (session_id, slug, created_at, reason).
#
# The subcommand pattern `ws hook-bypass [a-z]*` is on the committed
# [ask-commands] baseline, so every invocation force-prompts the human —
# that's the security gate. The slug validation here guards against
# typos and accidental marker creation for unknown slugs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT can be set by callers (tests) or falls back to two
# levels up from this script's location (the yggdrasil root).
: "${PROJECT_ROOT:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

HOOK_RULES="$PROJECT_ROOT/.claude/hooks/hook-rules"

usage() {
    cat <<'HELP'
Usage: ws hook-bypass <slug> [--reason "<text>"]

  <slug>           Bypass slug — must match a row in [redirect-commands]
                   in .claude/hooks/hook-rules. Run with an unknown slug
                   to see the list of known slugs.
  --reason "<txt>" Optional. Captured in the marker file and echoed into
                   each BYPASS-ALLOW audit-log entry for retro grep.

Writes .tmp/hook-bypass/<slug>.bypass with the current CLAUDE_SESSION_ID.
The PreToolUse hook honors this marker for matching commands in this
session only. ws clean (or any .tmp/ purge) sweeps stale markers.

Examples:
  ws hook-bypass git-commit --reason "git commit --amend; ws commit no amend support yet"
  ws hook-bypass gh-pr-create --reason "cross-fork PR, ws cr lacks --upstream support today"
HELP
}

# --help / -h
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# No args → usage + exit 1
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

slug="$1"
shift

# Parse optional --reason
reason=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            [[ $# -ge 2 ]] || { echo "ERROR: --reason requires a value" >&2; exit 1; }
            reason="$2"
            shift 2 ;;
        --reason=*)
            reason="${1#--reason=}"
            shift ;;
        *)
            echo "ERROR: Unknown argument '$1'" >&2
            usage >&2
            exit 1 ;;
    esac
done

# Enumerate known slugs from hook-rules
known_slugs=()
if [[ -f "$HOOK_RULES" ]]; then
    in_section=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        # Trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == "#"* ]] && continue
        if [[ "$line" == "["*"]" ]]; then
            in_section="${line#[}"
            in_section="${in_section%]}"
            continue
        fi
        if [[ "$in_section" == "redirect-commands" ]]; then
            # Column 1 (slug) — substring up to first " | "
            if [[ "$line" == *" | "* ]]; then
                s="${line%% | *}"
                # Trim trailing whitespace
                s="${s%"${s##*[![:space:]]}"}"
                # Only accept valid slug shape
                if [[ "$s" =~ ^[a-z0-9-]+$ ]]; then
                    known_slugs+=("$s")
                fi
            fi
        fi
    done < "$HOOK_RULES"
fi

# Validate slug
slug_ok=0
for s in ${known_slugs[@]+"${known_slugs[@]}"}; do
    if [[ "$s" == "$slug" ]]; then
        slug_ok=1
        break
    fi
done
if [[ "$slug_ok" != "1" ]]; then
    echo "ERROR: Unknown slug '$slug'." >&2
    if [[ ${#known_slugs[@]} -gt 0 ]]; then
        echo "Known slugs (from $HOOK_RULES):" >&2
        for s in ${known_slugs[@]+"${known_slugs[@]}"}; do
            echo "  - $s" >&2
        done
    else
        echo "No [redirect-commands] entries found in $HOOK_RULES." >&2
    fi
    exit 1
fi

# Validate CLAUDE_SESSION_ID
if [[ -z "${CLAUDE_SESSION_ID:-}" ]]; then
    echo "ERROR: CLAUDE_SESSION_ID is not set." >&2
    echo "  This command only makes sense inside an active Claude Code session." >&2
    echo "  The marker it would write keys off CLAUDE_SESSION_ID; without it the" >&2
    echo "  hook can never match the marker against a session." >&2
    exit 1
fi

# Write the marker
marker_dir="$PROJECT_ROOT/.tmp/hook-bypass"
marker_path="$marker_dir/$slug.bypass"
mkdir -p "$marker_dir"

# ISO-8601 UTC, no microseconds — readable and stable across hosts.
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$marker_path" <<EOF
session_id: $CLAUDE_SESSION_ID
slug: $slug
created_at: $created_at
reason: $reason
EOF

echo "bypass marker written: $marker_path (session ${CLAUDE_SESSION_ID:0:8}...)"
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/ws test yggdrasil tests/ws-cli/hook-bypass.bats`
Expected: all 9 tests PASS.

If any fail, read the failing assertion + the script logic. Most likely culprits: slug regex, marker file format, exit codes for missing args.

- [ ] **Step 5: Commit**

Write `.commits/ws-hook-bypass-script.md`:

```yaml
---
message: "feat(ws): add ws-hook-bypass.sh + bats coverage"
add:
  - scripts/ws-hook-bypass.sh
  - tests/ws-cli/hook-bypass.bats
---

Implements the `ws hook-bypass <slug> [--reason "<text>"]` subcommand:

- Reads known slugs from [redirect-commands] in .claude/hooks/hook-rules
- Validates <slug> against that list (unknown → exit 1 + listing)
- Requires $CLAUDE_SESSION_ID (absent → exit 1)
- Writes .tmp/hook-bypass/<slug>.bypass with frontmatter
  (session_id, slug, created_at, reason)
- --help / -h print usage; no args → usage + exit 1

The subcommand is wired into the ws dispatcher in the next task.

9 bats tests cover the happy paths, error paths, and the --reason
field shape (matching the hook's parser expectations from Task 4).
```

Run: `bash scripts/ws commit yggdrasil .commits/ws-hook-bypass-script.md`

---

## Task 8: Wire `ws hook-bypass` into the dispatcher + settings.json allowlist for --help

**Files:**

- Modify: `scripts/ws`
- Modify: `.claude/settings.json`

The script exists but `ws hook-bypass …` doesn't reach it yet.

- [ ] **Step 1: Add `hook-bypass` to the help text**

In `scripts/ws`, find the `# Commands:` header (line 8). Insert a new line after `mcp-status` (line 39), before `help`:

```text
#   hook-bypass <slug> [--reason "<text>"]  Write a session-scoped bypass marker
#                     for a Tier 2 redirect-deny slug. See `ws hook-bypass --help`.
```

- [ ] **Step 2: Add `hook-bypass` to the case dispatcher**

In `scripts/ws`, in the `case "$COMMAND" in` block (lines 644-730), add a new arm before `*)`:

```bash
    hook-bypass)
        bash "$SCRIPT_DIR/ws-hook-bypass.sh" "$@"
        ;;
```

The conventional spot is alphabetical, near `help`, but consistency with the existing dispatcher (which is mostly order-of-introduction) is fine — drop it next to `mcp-status` (line 724-725) and before `*)` (line 726).

- [ ] **Step 3: Add help-passthrough allowlist entries to `.claude/settings.json`**

In `.claude/settings.json`, inside the `permissions.allow` array, add (e.g. just after `Bash(ws mcp-status)` at line 249):

```json
      "Bash(ws hook-bypass --help)",
      "Bash(ws hook-bypass -h)",
      "Bash(bash scripts/ws hook-bypass --help)",
      "Bash(bash scripts/ws hook-bypass -h)",
      "Bash(ws help hook-bypass)",
      "Bash(bash scripts/ws help hook-bypass)",
```

These let `--help` / `-h` reach the user without a prompt. The slug-shaped invocations (`ws hook-bypass git-commit`, etc.) still pass through Tier 3 ask thanks to the `ws hook-bypass [a-z]*` pattern added in Task 6.

- [ ] **Step 4: Verify `ws help` lists the new command**

Run: `bash scripts/ws help`
Expected: output includes the new `hook-bypass <slug> [--reason ...]` line.

- [ ] **Step 5: Verify `ws hook-bypass --help` works**

Run: `bash scripts/ws hook-bypass --help`
Expected: prints the usage block from `ws-hook-bypass.sh`. Exit code 0.

- [ ] **Step 6: Verify unknown slug routes correctly**

Run: `bash scripts/ws hook-bypass not-a-slug`
Expected: exit 1 with "Unknown slug" and the list of known slugs. The hook will ask first (because of the `ws hook-bypass [a-z]*` ask-pattern); a human approving will then see the slug error.

- [ ] **Step 7: Commit**

Write `.commits/ws-hook-bypass-dispatcher.md`:

```yaml
---
message: "feat(ws): wire ws hook-bypass into dispatcher + allowlist --help"
add:
  - scripts/ws
  - .claude/settings.json
---

Final wiring for the new subcommand:

- scripts/ws — help text + case dispatch arm for `ws hook-bypass`
- .claude/settings.json — allowlist `ws hook-bypass --help`, `-h`, and
  `ws help hook-bypass` so the help path doesn't force-prompt

Slug-shaped invocations (ws hook-bypass git-commit, etc.) still pass
through Tier 3 ask via the `ws hook-bypass [a-z]*` pattern added to
hook-rules in the prior commit — that's the security gate.
```

Run: `bash scripts/ws commit yggdrasil .commits/ws-hook-bypass-dispatcher.md`

---

## Task 9: Documentation updates

**Files:**

- Modify: `.claude/hooks/README.md`
- Modify: `docs/gdd/permissions.md`
- Modify: `docs/gdd/agent-training.md`
- Modify: `docs/gdd/trust-and-safety.md`
- Modify: `AGENTS.md`

Five separate doc edits. Group them into one commit at the end.

- [ ] **Step 1: Update `.claude/hooks/README.md`**

The README's "PreToolUse hook" section lists four tiers (1-4). Update to five and add the redirect tier + bypass section.

Find the numbered list at lines 9-15 of `.claude/hooks/README.md`. Replace:

```markdown
1. **Deny shell composition** (`&&`, `||`, `;`, pipes, command substitution, redirects) with a corrective message that tells the agent how to retry. Trains the agent to use separate tool calls and native `ws` flags (`--limit`, `--compact`, `--output`) instead of shell composition.
2. **Ask** (force a permission prompt) for anything matching a glob in the `[ask-commands]` section of `hook-rules` (committed baseline) or `hook-rules.local` (per-machine). The hook emits `permissionDecision: "ask"`, which surfaces a human-facing prompt regardless of the session permission mode — including `acceptEdits` and `bypassPermissions`. The command is NOT blocked; once the human approves it runs normally. This tier exists specifically to intercept destructive commands like `rm -rf` on some directory within the workspace that `acceptEdits` would otherwise auto-approve silently (to perhaps some surprise! But mass file deletion *could* be considered an "edit" technically).
3. **Allow** anything matching `permissions.allow` patterns in `.claude/settings.json` — the hook normalizes both the command and the pattern so bare `ws status` and verbose `bash scripts/ws status` both match a single pattern in either style.
4. **Allow** anything matching a glob in the `[allow-extras]` section of `hook-rules.local`. Per-machine personal extras for tools you trust on your laptop without committing them to the project config.
5. **Pass** everything else goes to default behavior based on other config.
```

with:

```markdown
1. **Deny shell composition** (`&&`, `||`, `;`, pipes, command substitution, redirects) with a corrective message that tells the agent how to retry. Trains the agent to use separate tool calls and native `ws` flags (`--limit`, `--compact`, `--output`) instead of shell composition.
2. **Deny raw `git commit` / `git push` / `gh pr create`** (and any other entry in the `[redirect-commands]` section of `hook-rules`) with a corrective message pointing at the right `ws` subcommand. A session-scoped bypass marker — written by `ws hook-bypass <slug>` after a human-approved ask prompt — overrides the deny for that slug. See [Redirect tier and bypass](#redirect-tier-and-bypass) below.
3. **Ask** (force a permission prompt) for anything matching a glob in the `[ask-commands]` section of `hook-rules` (committed baseline) or `hook-rules.local` (per-machine). The hook emits `permissionDecision: "ask"`, which surfaces a human-facing prompt regardless of the session permission mode — including `acceptEdits` and `bypassPermissions`. The command is NOT blocked; once the human approves it runs normally. This tier exists specifically to intercept destructive commands like `rm -rf` on some directory within the workspace that `acceptEdits` would otherwise auto-approve silently (to perhaps some surprise! But mass file deletion *could* be considered an "edit" technically).
4. **Allow** anything matching `permissions.allow` patterns in `.claude/settings.json` — the hook normalizes both the command and the pattern so bare `ws status` and verbose `bash scripts/ws status` both match a single pattern in either style.
5. **Allow** anything matching a glob in the `[allow-extras]` section of `hook-rules.local`. Per-machine personal extras for tools you trust on your laptop without committing them to the project config.
6. **Pass** everything else goes to default behavior based on other config.
```

Then, after the `### Rules configuration` section (around line 21), add a new section before `## Optional: PermissionRequest hook` (line 50):

```markdown
### Redirect tier and bypass

The Tier 2 redirect-deny channels three raw commands toward the workspace's `ws` wrappers:

| Slug | Pattern | Use this instead |
|---|---|---|
| `git-commit` | `git commit*` | `ws commit <comp> <bodyfile>` — bodyfile-driven, attaches the Co-Authored-By trailer |
| `git-push` | `git push*` | `ws push <comp> [branch]` — picks the fork remote from `identity.forkOrg`, sets upstream on first push |
| `gh-pr-create` | `gh pr create*` | `ws cr <comp> <title> <bodyfile>` — bodyfile-driven, applies identity substitutions |

A deny here is a *training* signal, not a safety floor (that's Tier 3 ask). The hook trusts the workspace's own `ws` wrappers to do the right thing — attribution, remote selection, token coverage. When a legitimate edge case exists (`ws` doesn't yet support what you need), the agent can request a bypass:

1. Agent hits the deny; corrective message names `ws hook-bypass <slug>` as the escape hatch.
2. Agent runs `ws hook-bypass <slug> --reason "<why>"`. The subcommand is on the ask-list, so the human gets a permission prompt.
3. Human approves; the script writes `.tmp/hook-bypass/<slug>.bypass` keyed to `$CLAUDE_SESSION_ID`.
4. Agent retries the raw command; the hook finds the marker, matches session_id, and emits an allow with audit `BYPASS-ALLOW [<slug>] reason="<text>": <cmd>`.
5. The marker is honored for the rest of the session. Next session's `CLAUDE_SESSION_ID` differs, so the marker is stale; `ws clean` sweeps `.tmp/` whenever you want a clean slate.

The recurring-bypass pattern — same slug bypassed every session — is a signal that the corresponding `ws` subcommand needs to grow that capability. Periodic `grep BYPASS-ALLOW ~/.claude/hook-audit.log` surfaces it.

**Adding a new redirect.** Append a row to the `[redirect-commands]` section of `.claude/hooks/hook-rules`: `<slug> | <pattern> | <suggestion>`. The slug must match `^[a-z0-9-]+$`. The pattern is a bash glob. The suggestion is free text (column 3, may contain pipes — parsing splits on the first two ` | ` only). The new slug is automatically bypassable via `ws hook-bypass <new-slug>`; no script change needed.
```

- [ ] **Step 2: Update `docs/gdd/permissions.md`**

Find the existing allow/deny/ask discussion in `docs/gdd/permissions.md`. Add (after the discussion of `ask`) a new subsection:

```markdown
### Redirect deny + session-scoped bypass

Tier 2 of the PreToolUse hook denies a curated list of raw commands (`git commit`, `git push`, `gh pr create`) that have a `ws` wrapper equivalent. The deny carries a corrective message pointing at the right `ws` subcommand.

This is a *training* layer, not a safety floor — the `ws` wrappers add attribution, remote selection, and bodyfile flows that AGENTS.md documents but training-data reflex drifts away from. A legitimate edge case (the `ws` subcommand doesn't yet support what's needed) escapes via `ws hook-bypass <slug>`, which writes a marker file keyed to `$CLAUDE_SESSION_ID`. The marker is honored for the rest of the session.

The `ws hook-bypass <slug>` subcommand itself is on the ask-list — every invocation force-prompts the human. The security boundary is the ask-tier; no env-var or cryptographic gate is added.

See `.claude/hooks/README.md` § Redirect tier and bypass for the operator-facing details.
```

- [ ] **Step 3: Update `docs/gdd/agent-training.md`**

This is the agent-friendly companion. Add a new subsection (location: after whatever existing subsection covers Tier 1 / composition denies — find by searching for "composition" in the file):

```markdown
### What happens when you reach for `git commit` / `git push` / `gh pr create`

These three raw commands deny at Tier 2 with a message pointing at the workspace's `ws` wrappers. The wrappers handle work the raw commands don't:

- `ws commit` — Co-Authored-By trailer, bodyfile-driven staging
- `ws push` — fork-remote selection from `identity.forkOrg`, sets upstream
- `ws cr` — bodyfile-driven PR body, identity substitutions, right token + remote

The deny is corrective, not punitive — when you see it, retry through the named `ws` subcommand. AGENTS.md's "ws-first reflex check" table maps every raw command in this category to its wrapper.

**When you genuinely need the raw command** (e.g., `git commit --amend` and `ws commit` doesn't support amend yet): run `ws hook-bypass <slug> --reason "<why>"`. The human gets a permission prompt; on approval, a session-scoped marker is written and the next matching raw command runs through. The bypass is per-slug — bypassing `git-commit` doesn't extend to `gh-pr-create`.

**Don't loop on the deny.** If your first instinct hits a Tier 2 deny twice in the same session, that's the moment to either (a) figure out the `ws` form, (b) request a bypass with a clear `--reason`, or (c) ask the human directly. Three identical denies is not the right shape.
```

- [ ] **Step 4: Update `docs/gdd/trust-and-safety.md`**

Find the section that records the hook's role in the trust model. Add a new bullet/paragraph:

```markdown
**Tier 2 redirect deny** is a training-aid layer, not a safety floor. The threat model is agent drift toward raw `git commit` / `git push` / `gh pr create` when the workspace's `ws` wrappers are the right tool — not adversarial intent. The bypass mechanism (`ws hook-bypass <slug>`) provides a documented escape hatch keyed to `$CLAUDE_SESSION_ID`. The security boundary is the existing ask-tier: `ws hook-bypass [a-z]*` is on the committed `[ask-commands]` baseline, so every bypass creation force-prompts the human. No env vars or HMACs added — the ask prompt is the gate.
```

- [ ] **Step 5: Update `AGENTS.md`**

Find the "ws-first reflex check" subsection table (around lines 124-138). Add a single line below the table, before the next subsection:

```markdown
**Hook enforcement:** the PreToolUse hook denies the three write-side raw commands above (`git commit` / `git push` / `gh pr create`) at Tier 2 with a corrective message pointing at the `ws` subcommand. See `.claude/hooks/README.md` § Redirect tier and bypass for the bypass mechanism if a legitimate edge case requires raw access.
```

- [ ] **Step 6: Verify the docs render**

Quick sanity check — open each file in a markdown previewer or read back, confirm tables render and section headers nest correctly.

Run: `grep -c "^### " .claude/hooks/README.md`
Expected: count increases by 1 (the new "Redirect tier and bypass" subsection).

- [ ] **Step 7: Commit**

Write `.commits/hook-redirect-bypass-docs.md`:

```yaml
---
message: "docs(hook): document Tier 2 redirect + session-scoped bypass"
add:
  - .claude/hooks/README.md
  - docs/gdd/permissions.md
  - docs/gdd/agent-training.md
  - docs/gdd/trust-and-safety.md
  - AGENTS.md
---

Five docs touched for the new Tier 2 redirect deny + bypass mechanism:

- .claude/hooks/README.md — five-tier list + new "Redirect tier and
  bypass" subsection with the operator-facing details
- docs/gdd/permissions.md — adds Tier 2 to the allow/deny/ask story
- docs/gdd/agent-training.md — agent-facing explanation of the deny +
  the deny-then-bypass loop
- docs/gdd/trust-and-safety.md — records redirect as a training-aid
  layer; ask-tier remains the security boundary
- AGENTS.md — one-liner under the ws-first reflex table pointing at
  the README for the bypass mechanism

The "adding a new redirect" note in the README documents the
hook-rules row format so future additions don't require a separate
plan.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-redirect-bypass-docs.md`

---

## Task 10: Interactive acceptance script

**Files:**

- Create: `tests/hook/interactive-redirect-acceptance.md`

bats verifies the hook's *output*; it cannot verify the prompt the human actually sees. Match the pattern from `tests/hook/interactive-acceptance.md` (which the ask-tier work introduced).

- [ ] **Step 1: Write the script**

Create `tests/hook/interactive-redirect-acceptance.md` with this content:

```markdown
# Interactive Acceptance — Tier 2 Redirect Deny + Bypass

This is a live "actor's script" the agent walks through with the human present. Bats covers the hook's emitted JSON and audit log; this script covers the prompt the human actually sees.

**Prerequisites:**

- Yggdrasil workspace cloned, current branch has the redirect tier merged.
- A throwaway clone of any harmless repo for the `git push` and `gh pr create` probes (so the script doesn't actually push to anything real). E.g.: `git clone --depth 1 <some test repo> /tmp/redirect-probe` and `cd /tmp/redirect-probe`.
- Audit log path open in a terminal: `tail -f ~/.claude/hook-audit.log`.

**The script.** Agent reads each step aloud (or echoes the announcement), runs the command, and waits for the human to confirm the prompt/output shape matches.

## Step 1 — `git commit` denies at Tier 2

Agent announces: *"I'll run `git commit -m \"acceptance probe\"`. Expect a Tier 2 deny pointing at `ws commit` and mentioning `ws hook-bypass git-commit`."*

Agent runs: `git commit -m "acceptance probe"`

Human confirms:

- [ ] Agent saw a deny output, not a silent pass
- [ ] Deny message names `ws commit`
- [ ] Deny message names `ws hook-bypass git-commit` as the escape hatch
- [ ] Audit log shows a `DENY` entry for this command

## Step 2 — `ws hook-bypass git-commit` force-prompts

Agent announces: *"Now `ws hook-bypass git-commit --reason \"acceptance test\"`. Expect a Tier 3 ask prompt (force-prompt, not a silent run), and on approval, a marker file under `.tmp/hook-bypass/git-commit.bypass`."*

Agent runs: `ws hook-bypass git-commit --reason "acceptance test"`

Human confirms:

- [ ] A permission prompt fires for the `ws hook-bypass` command
- [ ] On approval, the command exits 0 and prints `bypass marker written: ...`
- [ ] The file `.tmp/hook-bypass/git-commit.bypass` exists and contains `session_id:`, `slug: git-commit`, and `reason: acceptance test`

## Step 3 — Bypassed `git commit` now ALLOWs

Agent announces: *"Retrying `git commit -m \"acceptance probe\"` in this throwaway repo. Expect ALLOW with no prompt, and an audit line `BYPASS-ALLOW [git-commit] reason=\"acceptance test\"`."*

Agent runs: `git commit -m "acceptance probe"` (in the throwaway repo)

Human confirms:

- [ ] No prompt fired; the command ran through
- [ ] Audit log shows `BYPASS-ALLOW [git-commit] reason="acceptance test"`

## Step 4 — Slug isolation — `gh pr create` still denies

Agent announces: *"`gh pr create --title test --body test` — expect deny (the marker is for `git-commit`, not `gh-pr-create`)."*

Agent runs: `gh pr create --title test --body test`

Human confirms:

- [ ] Deny fired despite the active `git-commit` bypass
- [ ] Deny message names `ws cr` and `ws hook-bypass gh-pr-create`

## Step 5 — Composition still wins over bypass

Agent announces: *"`git commit -m \"x\" && echo done` — expect Tier 1 composition deny, NOT a Tier 2 redirect, NOT a bypass allow."*

Agent runs: `git commit -m "x" && echo done`

Human confirms:

- [ ] Deny fired with the Shell composition message
- [ ] Audit log entry is a `DENY` with "Shell composition" reason, not `BYPASS-ALLOW`

## Step 6 — Cleanup

Agent announces: *"`ws clean` to sweep the marker so the next session starts fresh."*

Agent runs: `ws clean`

Human confirms:

- [ ] `.tmp/hook-bypass/git-commit.bypass` no longer exists
- [ ] `ws clean` reported one or more files removed (the marker plus whatever else was in `.tmp/`)

## Step 7 — Marker stale after restart (optional, slow)

Skip if the human is short on time — the bats coverage covers session_id mismatch deterministically.

Agent announces: *"Re-create the marker, then we'll start a fresh Claude Code session and verify the bypass does NOT carry over."*

Agent runs: `ws hook-bypass git-commit --reason "stale test"` (approve at prompt).

Human starts a fresh Claude session in the same workspace; in that new session the agent runs `git commit -m "x"` and confirms it denies (the marker's session_id no longer matches).

## Pass criteria

All checkboxes in steps 1-6 ticked, optionally step 7. Any mismatch is a finding to surface.
```

- [ ] **Step 2: Verify the file lints clean**

Run any markdown lint pass you typically use, or just spot-check the headings:

Run: `grep -c "^## " tests/hook/interactive-redirect-acceptance.md`
Expected: 7 (six numbered steps + the "Pass criteria" closer).

- [ ] **Step 3: Run the script with the user**

This is the integration moment. Walk through steps 1-6 (and optionally 7) with the user. Surface any mismatch immediately — those become follow-up tickets, not silent regressions.

- [ ] **Step 4: Commit**

Write `.commits/hook-redirect-acceptance.md`:

```yaml
---
message: "test(hook): add interactive acceptance script for redirect + bypass"
add:
  - tests/hook/interactive-redirect-acceptance.md
---

bats covers the hook's emitted JSON and the audit log; this script
covers the prompt the human actually sees. Six steps walk through:

  1. git commit denies at Tier 2
  2. ws hook-bypass git-commit force-prompts and writes marker
  3. retried git commit ALLOWs with BYPASS-ALLOW audit
  4. gh pr create still denies (slug isolation)
  5. composition (Tier 1) still wins over bypass
  6. ws clean sweeps the marker

Optional step 7 verifies cross-session marker staleness (skip in a
hurry — bats covers this deterministically via session_id mismatch
tests in tests/hook/gdd-permission-hook.bats).

Follows the pattern set by tests/hook/interactive-acceptance.md from
the ask-tier work.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-redirect-acceptance.md`

---

## Final verification — before opening the CR

- [ ] **Step 1: All bats green**

Run: `bash scripts/ws test yggdrasil`
Expected: every bats file (`tests/hook/`, `tests/ws-cli/`, `tests/ws-smoke/`) passes. No skipped tests.

- [ ] **Step 2: Workspace smoke — `git commit` denies in this repo**

Run: `git commit --allow-empty -m "smoke test, should deny"`
Expected: the harness shows a deny from the hook with a `ws commit` corrective. Audit log records `DENY` with the redirect-pattern entry.

(Don't actually commit; the deny is the verification.)

- [ ] **Step 3: Workspace smoke — `ws hook-bypass git-commit` force-prompts**

Run: `bash scripts/ws hook-bypass git-commit --reason "smoke test"`
Expected: permission prompt fires; on approval, the marker is written and the command echoes the marker path.

After confirming, run `ws clean` to sweep the marker.

- [ ] **Step 4: Interactive acceptance**

Walk through `tests/hook/interactive-redirect-acceptance.md` once with the user.

- [ ] **Step 5: Open the CR**

Write `.crs/hook-redirect-and-bypass.md` from the template, summarize the design + plan + interactive verification, and run:

`bash scripts/ws cr yggdrasil "feat(hook): redirect deny + session-scoped bypass (hook-v2 deep pair)" .crs/hook-redirect-and-bypass.md`

CR body should reference the design doc and the implementation plan by relative path, list the redirect slugs added, and call out the renumbered tier scheme.
