# Hook Ask-Tier and Rules File — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `ask`-tier to the PreToolUse hook — destructive commands emit `permissionDecision: "ask"` and prompt in any permission mode — and externalize the hook's scratch-dir list and allowlist-extras into a single transparent layered config (`hook-rules` + `hook-rules.local`), retiring `safe-bash-extras`.

**Architecture:** One security-critical bash script (`.claude/hooks/gdd-permission-hook.sh`) is extended: a flat-file config parser (pure bash, no new dependency), a new `ask()` decision helper, a new Tier 2 ask-tier, the existing tiers renumbered to 3/4, scratch-dirs and allow-extras sourced from config. Plus two new config files, bats coverage, an interactive acceptance script, and updates to five hook-related docs.

**Tech Stack:** Bash (the hook + parser); `jq` (already a hook dependency — JSON payload + decision output); bats (`tests/vendor/bats-core`, existing `tests/hook/` suite); flat sectioned text config.

**Spec:** [`2026-05-17-hook-ask-tier-design.md`](2026-05-17-hook-ask-tier-design.md)

---

## Notes on this plan

- **Branch:** all work is on `feat/hook-ask-tier` (off `main`). The `WS_HOOK_DEBUG` change and the design doc are already committed there (`ea794ae`, `c171f4e`, `b43dc2b`).
- **Verification model:** hook decision logic is genuinely testable — bats invokes the hook with a synthetic JSON payload and asserts on emitted JSON + the audit log. TDD applies to the hook tasks (Tasks 5-7). Config files, the header comment block, the interactive script, and the doc updates have no unit tests — verification there is read-back, exactly as in the thalamus-arc-dashboard and PKM plans.
- **bash 3.2 compatibility:** old macOS ships bash 3.2, where `"${arr[@]}"` on an empty array errors under `set -u`. Every array expansion in this plan uses the safe form `${arr[@]+"${arr[@]}"}`. Do not "simplify" it.
- **Existing bats suite migration:** this change invalidates two groups of existing tests — the Edit/Write scratch-dir tests (scratch dirs move from hardcoded to config) and the `safe-bash-extras` Tier 3 tests (that file retires). Tasks 6 and 7 explicitly migrate them; do not leave them failing.
- **`ws commit`:** commit via `bash scripts/ws commit yggdrasil .commits/<file>.md` with an `add:` bodyfile, per the workspace convention.
- **Hook line numbers** below refer to the current file at commit `ea794ae` (648 lines).

## File map

**Create:**
- `.claude/hooks/hook-rules` — committed config baseline (`[scratch-dirs]`, `[ask-commands]`)
- `.claude/hooks/hook-rules.local.example` — committed per-machine template (adds `[allow-extras]`)
- `tests/hook/interactive-acceptance.md` — scripted live acceptance test

**Modify:**
- `.claude/hooks/gdd-permission-hook.sh` — the hook (Tasks 5-8)
- `.gitignore` — add `hook-rules.local`, drop `safe-bash-extras`
- `tests/hook/test_helper.bash` — new helpers
- `tests/hook/gdd-permission-hook.bats` — new tests + migrate invalidated ones
- `.claude/hooks/README.md`, `docs/gdd/permissions.md`, `docs/gdd/agent-training.md`, `docs/gdd/trust-and-safety.md`, `docs/gdd/roles-and-modes.md` — doc updates

**Delete:**
- `.claude/hooks/safe-bash-extras`, `.claude/hooks/safe-bash-extras.example`

---

## Task 1: Create the `hook-rules` baseline config

**Files:**
- Create: `.claude/hooks/hook-rules`

- [ ] **Step 1: Write the file**

Create `.claude/hooks/hook-rules` with exactly this content:

```text
# GDD hook rules — committed baseline.
#
# Read by .claude/hooks/gdd-permission-hook.sh. Per-machine overrides
# go in hook-rules.local (copy hook-rules.local.example). Format: flat
# sectioned text — [section] headers, one entry per line, '#' comments,
# blank lines ignored.

[scratch-dirs]
# Edit/Write tool calls under these workspace-relative paths auto-allow.
# Mirror the "Workspace-local scratch" section of .gitignore.
.tmp/
.commits/
.crs/
.issues/
.outputs/

[ask-commands]
# Glob patterns. A match makes the hook emit permissionDecision: "ask" —
# a forced permission prompt in any mode, NOT a block. The agent still
# runs the command once the human approves. Patterns match the full
# command string; '*' matches any substring.
rm -rf*
rm -fr*
rm -r *
rm -r-*
git reset --hard*
git clean -f*
git clean -d*
find * -delete*
```

- [ ] **Step 2: Verify**

Run: `grep -c "^\[" .claude/hooks/hook-rules`
Expected: `2` (two section headers).

Run: `head -1 .claude/hooks/hook-rules`
Expected: `# GDD hook rules — committed baseline.`

---

## Task 2: Create the `hook-rules.local.example` template

**Files:**
- Create: `.claude/hooks/hook-rules.local.example`

This is the per-machine template. Its `[allow-extras]` section carries the commented-out patterns migrated from `safe-bash-extras.example`.

- [ ] **Step 1: Write the file**

Create `.claude/hooks/hook-rules.local.example` with exactly this content:

```text
# hook-rules.local.example — copy to hook-rules.local and edit.
#
# This file is COMMITTED as a template. The live hook-rules.local is
# gitignored — per-machine, not project policy. The hook reads it after
# the committed hook-rules and merges:
#
#   [scratch-dirs]   — entries ADD to the baseline
#   [ask-commands]   — entries ADD to the baseline (additive-only:
#                      you can make MORE commands prompt, never fewer —
#                      removing a baseline ask-command is not supported)
#   [allow-extras]   — personal allow-patterns; only valid here, never
#                      in the committed baseline
#
# To use:
#   1. cp hook-rules.local.example hook-rules.local
#   2. Uncomment / add entries below
#   3. On any line you uncomment, delete its trailing '# ...' comment —
#      the hook matches the WHOLE line, so an inline comment becomes
#      part of the pattern and breaks the match

[scratch-dirs]
# Extra scratch dirs to auto-allow Edit/Write under, on this machine.
# (none by default)

[ask-commands]
# Extra destructive commands to force a prompt for, on this machine.
# (none by default)

[allow-extras]
# Bash glob patterns auto-allowed on this machine without prompting.
# Safe only while the hook's Tier 1 composition deny is active.
# Uncomment the ones you're tired of approving.
# ls *
# pwd
# cat *
# head *
# tail *
# wc *
# stat *
# tree
# tree *
# grep *
# jq *
# yq *
```

- [ ] **Step 2: Verify**

Run: `grep -c "^\[" .claude/hooks/hook-rules.local.example`
Expected: `3` (three section headers).

---

## Task 3: Update `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Find the hook-related ignore lines**

Run: `grep -n "safe-bash-extras\|hooks/" .gitignore`
Expected: a line ignoring `.claude/hooks/safe-bash-extras` (the gitignored live extras file).

- [ ] **Step 2: Replace the `safe-bash-extras` ignore with `hook-rules.local`**

Find the line that ignores the live extras file (it looks like `/.claude/hooks/safe-bash-extras` or `.claude/hooks/safe-bash-extras`). Replace that single line with:

```text
/.claude/hooks/hook-rules.local
```

If the comment above it mentions `safe-bash-extras`, update the comment to say `hook-rules.local` instead. No other `.gitignore` lines change.

- [ ] **Step 3: Verify**

Run: `grep -n "hook-rules.local" .gitignore`
Expected: one line.

Run: `grep -c "safe-bash-extras" .gitignore`
Expected: `0`.

---

## Task 4: Add bats helpers for hook-rules

**Files:**
- Modify: `tests/hook/test_helper.bash`

- [ ] **Step 1: Add two helper functions**

In `tests/hook/test_helper.bash`, after the `write_user_extras()` function (ends around line 62), add:

```bash
# Write a project-level hook-rules file with the given content.
write_project_hook_rules() {
    printf '%s\n' "$1" > "$WORK/.claude/hooks/hook-rules"
}

# Write a project-level hook-rules.local file with the given content.
write_local_hook_rules() {
    printf '%s\n' "$1" > "$WORK/.claude/hooks/hook-rules.local"
}
```

- [ ] **Step 2: Verify**

Run: `grep -c "write_project_hook_rules\|write_local_hook_rules" tests/hook/test_helper.bash`
Expected: `2` or more.

---

## Task 5: Hook — config parser, `ask()` helper, Tier 2 ask-tier

**Files:**
- Modify: `.claude/hooks/gdd-permission-hook.sh`
- Test: `tests/hook/gdd-permission-hook.bats`

This task adds the config-parsing block, the `ask()` decision helper, and the Tier 2 ask-tier. It is TDD: write the bats tests first.

- [ ] **Step 1: Write the failing bats tests**

Append these tests to `tests/hook/gdd-permission-hook.bats`:

```bash
# ─── Tier 2: ask-list ───────────────────────────────────────────────

@test "ask: rm -rf matches the baseline ask-list and emits ask" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: rm-family ask reason carries the symlink caution" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/"
    [[ "$output" == *"symlinks"* ]]
}

@test "ask: non-rm ask reason has no symlink caution" {
    write_project_hook_rules "[ask-commands]
git reset --hard*"
    run_hook "git reset --hard HEAD~1"
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" != *"symlinks"* ]]
}

@test "ask: Tier 1 composition denies before the ask-tier is reached" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/ && echo done"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: hook-rules.local ask-command is additive (also asks)" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    write_local_hook_rules "[ask-commands]
shutdown*"
    run_hook "shutdown now"
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: a malformed hook-rules (entry before any section) degrades, no crash" {
    write_project_hook_rules "rm -rf*
[ask-commands]
rm -rf*"
    run_hook "ls"
    [ "$status" -eq 0 ]
}

@test "ask: no hook-rules file present → no ask, passthrough still works" {
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: the seven new `ask:` tests FAIL (the hook does not yet emit `ask`).

- [ ] **Step 3: Add the `ask()` helper**

In `.claude/hooks/gdd-permission-hook.sh`, immediately after the `deny()` function's closing `}` (line 259) and before the `# ─── Tool routing` comment (line 261), insert:

```bash

# ask() — force a permission prompt without blocking. Used by the
# Tier 2 ask-list for destructive-but-sometimes-legitimate commands.
# Unlike deny(), the agent can still run the command once the human
# approves; unlike allow(), it never auto-runs. The `ask` decision
# overrides the harness's permission mode — it prompts even under
# acceptEdits / bypassPermissions.
#
# PermissionRequest has no "ask" behavior; for that event the hook
# passes through (exit 0, no JSON), which yields to the default
# prompt — the same net effect. (PermissionRequest is dormant in this
# workspace; this branch is parity-only.)
ask() {
    local reason="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ASK [$event] ($(audit_safe "$reason")): $(audit_safe "$cmd")" >> "$audit_log"
    if [[ "$event" == "PermissionRequest" ]]; then
        exit 0
    fi
    jq -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}
```

- [ ] **Step 4: Add the config-parsing block**

Immediately after the `ask()` helper you just added, and still before the `# ─── Tool routing` comment, insert:

```bash

# ─── Hook rules config ──────────────────────────────────────────────
#
# Flat sectioned text at .claude/hooks/hook-rules (committed baseline)
# and .claude/hooks/hook-rules.local (gitignored per-machine override).
# Parsed by pure bash — no yq/jq dependency for config. Three sections:
#   [scratch-dirs]  — Edit/Write auto-allow path prefixes (Tier consumer)
#   [ask-commands]  — Tier 2 ask-list glob patterns
#   [allow-extras]  — Tier 4 allow glob patterns (hook-rules.local only)
# hook-rules.local entries ADD to the baseline (additive merge).
scratch_dirs=()
ask_commands=()
allow_extras=()

# Parse one rules file, appending entries to the section arrays. A
# content line before any [section] header is a file error: log a
# warning and skip the rest of that file (degrade to whatever's
# already parsed — never crash the hook).
_parse_rules_file() {
    local file="$1"
    local section="" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == "#"* ]] && continue
        case "$line" in
            "["*"]")
                section="${line#\[}"
                section="${section%\]}"
                ;;
            *)
                case "$section" in
                    scratch-dirs) scratch_dirs+=("$line") ;;
                    ask-commands) ask_commands+=("$line") ;;
                    allow-extras) allow_extras+=("$line") ;;
                    *)
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: content before any [section], file skipped): $file" >> "$audit_log"
                        return
                        ;;
                esac
                ;;
        esac
    done < "$file"
}

# Locate .claude/hooks/hook-rules by walking up from $cwd (closest
# wins), same upward-walk + prev-equals-dir guard as collect_patterns.
_rules_dir=""
_rd="$cwd"
_rp=""
while [[ "$_rd" != "$_rp" && "$_rd" != "/" && "$_rd" != "." && "$_rd" != "" ]]; do
    if [[ -f "$_rd/.claude/hooks/hook-rules" ]]; then
        _rules_dir="$_rd/.claude/hooks"
        break
    fi
    _rp="$_rd"
    _rd=$(dirname "$_rd")
done
if [[ -n "$_rules_dir" ]]; then
    _parse_rules_file "$_rules_dir/hook-rules"
    [[ -f "$_rules_dir/hook-rules.local" ]] && _parse_rules_file "$_rules_dir/hook-rules.local"
fi
```

- [ ] **Step 5: Add the Tier 2 ask-tier**

The Tier 1 `case` statement ends with `esac` at line 441. Immediately after that `esac`, and before the `# ─── Normalization for matching` comment (line 443), insert:

```bash

# ─── Tier 2: Ask-list — force a prompt for destructive commands ─────
#
# A match emits `ask`: the harness prompts regardless of permission
# mode (acceptEdits included), but the agent may still run the command
# once the human approves. The ask-list is a safety FLOOR — it is
# checked before the Tier 3/4 allow logic, so a destructive command
# prompts even if some allowlist entry would otherwise pass it.
for _ask in ${ask_commands[@]+"${ask_commands[@]}"}; do
    # shellcheck disable=SC2053
    if [[ "$cmd" == $_ask ]]; then
        _ask_reason="This command is on the GDD hook's ask-list — destructive or hard to undo. Confirm before proceeding."
        case "$cmd" in
            rm|rm\ *)
                _ask_reason="$_ask_reason Caution: symlinks here could delete outside the workspace."
                ;;
        esac
        ask "$_ask_reason"
    fi
done
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: all tests PASS, including the seven new `ask:` tests and every pre-existing test (Tier 1 deny, etc. — untouched).

- [ ] **Step 7: Commit**

Write `.commits/hook-ask-tier-core.md`:

```markdown
---
message: "feat(hook): config parser, ask() helper, Tier 2 ask-list"

add:
  - .claude/hooks/gdd-permission-hook.sh
  - tests/hook/gdd-permission-hook.bats
  - tests/hook/test_helper.bash
---

Add the hook-rules config parser (pure bash, no new dependency), the
ask() decision helper (emits permissionDecision: "ask" — a forced
prompt that overrides permission mode without blocking), and the
Tier 2 ask-list. Destructive commands matching [ask-commands] now
prompt even in acceptEdits mode. rm-family matches carry a brief
symlink caution. Tier 1 composition deny still precedes the ask-tier.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-ask-tier-core.md`

---

## Task 6: Hook — scratch-dirs from config

**Files:**
- Modify: `.claude/hooks/gdd-permission-hook.sh` (the Edit/Write branch, lines 334-347)
- Test: `tests/hook/gdd-permission-hook.bats`

The Edit/Write branch currently iterates a hardcoded scratch-dir list. Switch it to the parsed `[scratch-dirs]` config. The config-parsing block from Task 5 runs before the Edit/Write branch, so `scratch_dirs` is populated.

- [ ] **Step 1: Migrate the existing Edit/Write bats tests**

Run: `grep -n "run_hook_write\|scratch" tests/hook/gdd-permission-hook.bats`
to find the existing Edit/Write scratch-dir tests. Each currently relies on the hardcoded list. For every existing test that calls `run_hook_write` and expects a scratch-dir allow, add a `write_project_hook_rules` call at the top of the test body seeding the standard dirs:

```bash
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
```

Tests that expect Edit/Write to *passthrough* (non-scratch path) need no rules file, but adding the same block does not change their outcome — seed them too for consistency.

- [ ] **Step 2: Add a test proving scratch-dirs come from config**

Append to `tests/hook/gdd-permission-hook.bats`:

```bash
@test "scratch: a config-only scratch dir auto-allows Edit" {
    write_project_hook_rules "[scratch-dirs]
.myscratch/"
    run_hook_write "Edit" ".myscratch/note.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "scratch: a dir NOT in config does not auto-allow" {
    write_project_hook_rules "[scratch-dirs]
.tmp/"
    run_hook_write "Edit" ".notscratch/note.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}
```

- [ ] **Step 3: Run the tests to verify the new ones fail**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: the two new `scratch:` tests FAIL (hook still uses the hardcoded list, so `.myscratch/` is not recognized).

- [ ] **Step 4: Replace the hardcoded scratch loop**

In the Edit/Write branch, replace this block (lines 334-347):

```bash
    # Scratch dirs that auto-allow Edit / Write. Mirrors the
    # "Workspace-local scratch" section of the project's .gitignore —
    # the two lists should stay in lockstep so anything safe to commit
    # nothing-for is also safe to edit without prompting. Order by
    # frequency-of-use so the first match (most common) is cheapest.
    for prefix in ".tmp/" ".commits/" ".crs/" ".issues/" ".outputs/"; do
        if [[ "$abs_path" == "$project_dir/$prefix"* ]]; then
            # cmd is empty for Edit/Write — re-purpose it so the
            # audit-log entry names the tool + path instead of
            # silently logging a blank command.
            cmd="$tool_name $file_path"
            allow "scratch-dir: $prefix"
        fi
    done
```

with:

```bash
    # Scratch dirs that auto-allow Edit / Write come from the
    # [scratch-dirs] section of hook-rules (parsed above). The baseline
    # mirrors the "Workspace-local scratch" section of .gitignore;
    # hook-rules.local may add more. If no hook-rules file was found,
    # scratch_dirs is empty and every Edit/Write passes through.
    for prefix in ${scratch_dirs[@]+"${scratch_dirs[@]}"}; do
        if [[ "$abs_path" == "$project_dir/$prefix"* ]]; then
            # cmd is empty for Edit/Write — re-purpose it so the
            # audit-log entry names the tool + path instead of
            # silently logging a blank command.
            cmd="$tool_name $file_path"
            allow "scratch-dir: $prefix"
        fi
    done
```

- [ ] **Step 5: Run the full suite**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: all tests PASS — the two new `scratch:` tests and the migrated Edit/Write tests.

- [ ] **Step 6: Commit**

Write `.commits/hook-scratch-from-config.md`:

```markdown
---
message: "feat(hook): source scratch-dirs from hook-rules config"

add:
  - .claude/hooks/gdd-permission-hook.sh
  - tests/hook/gdd-permission-hook.bats
---

The Edit/Write branch's scratch-dir list moves from a hardcoded array
to the [scratch-dirs] section of hook-rules. Behavior is unchanged for
the standard five dirs; the list is now visible in config and
overridable per-machine. Existing Edit/Write tests migrated to seed a
hook-rules file.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-scratch-from-config.md`

---

## Task 7: Hook — renumber Tier 2→3, retire `safe-bash-extras`, add Tier 4 allow-extras

**Files:**
- Modify: `.claude/hooks/gdd-permission-hook.sh` (the old Tier 2 + Tier 3 blocks, lines 489-627)
- Test: `tests/hook/gdd-permission-hook.bats`

The settings.json allowlist becomes Tier 3 (rename only — logic unchanged). The `safe-bash-extras` extras tier (old Tier 3) becomes Tier 4 and reads `[allow-extras]` from the parsed config instead.

- [ ] **Step 1: Migrate the existing `safe-bash-extras` bats tests**

Run: `grep -n "extras\|safe-bash" tests/hook/gdd-permission-hook.bats`
to find the existing Tier 3 extras tests. They use `write_project_extras` / `write_user_extras`. Rewrite each to use `write_local_hook_rules` with an `[allow-extras]` section instead. For example, a test that did:

```bash
    write_project_extras "rev *"
    run_hook "rev file.txt"
```

becomes:

```bash
    write_local_hook_rules "[allow-extras]
rev *"
    run_hook "rev file.txt"
```

Delete any test that specifically asserts *user-level* `safe-bash-extras` behavior — user-level hook config is a non-goal (the design's Non-goals). Keep the project-level allow assertions, retargeted to `[allow-extras]`.

- [ ] **Step 2: Add a test proving safe-bash-extras is no longer consulted**

Append to `tests/hook/gdd-permission-hook.bats`:

```bash
@test "allow-extras: a hook-rules.local [allow-extras] pattern allows" {
    write_local_hook_rules "[allow-extras]
sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow-extras: a legacy safe-bash-extras file is ignored" {
    write_project_extras "sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}
```

- [ ] **Step 3: Run the tests to verify the new ones fail**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: the two new `allow-extras:` tests FAIL (the hook still reads `safe-bash-extras`, not `[allow-extras]`).

- [ ] **Step 4: Rename the settings.json tier header to Tier 3**

In `.claude/hooks/gdd-permission-hook.sh`, find the line (489):

```bash
# ─── Tier 2: Match against settings.json `permissions.allow` ────────
```

Replace with:

```bash
# ─── Tier 3: Match against settings.json `permissions.allow` ────────
```

No other change to that block (lines 490-560) — its logic is unchanged.

- [ ] **Step 5: Replace the old Tier 3 extras block with Tier 4 allow-extras**

Replace the entire block from `# ─── Tier 3: Extras files (optional, layered) ───` (line 562) through the end of the `done < <(collect_extras_files)` loop (line 627) with:

```bash
# ─── Tier 4: Allow via [allow-extras] from hook-rules.local ─────────
#
# Personal allow-patterns the user trusts on this machine — migrated
# from the retired safe-bash-extras file into the [allow-extras]
# section of hook-rules.local (gitignored, per-machine). Parsed into
# allow_extras above. Each entry is a bash glob matched against the
# normalized command; any match → allow. Empty if hook-rules.local is
# absent or has no [allow-extras] section.
for _extra in ${allow_extras[@]+"${allow_extras[@]}"}; do
    match_extra="$(normalize_for_match "$_extra")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $match_extra ]]; then
        allow "hook-rules.local [allow-extras]: $_extra"
    fi
done
```

This deletes `collect_extras_files()` and the extras `while` loop — `safe-bash-extras` is no longer read anywhere.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: all tests PASS — the new `allow-extras:` tests, the migrated extras tests, and every untouched test.

- [ ] **Step 7: Commit**

Write `.commits/hook-tier4-allow-extras.md`:

```markdown
---
message: "feat(hook): renumber tiers, retire safe-bash-extras for [allow-extras]"

add:
  - .claude/hooks/gdd-permission-hook.sh
  - tests/hook/gdd-permission-hook.bats
---

Renumber the settings.json allowlist to Tier 3 (logic unchanged) and
replace the safe-bash-extras extras tier with Tier 4, which reads the
[allow-extras] section of hook-rules.local. collect_extras_files() and
the safe-bash-extras read path are removed. Existing extras tests
migrated to [allow-extras]; user-level extras tests dropped (user-level
hook config is a non-goal).
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-tier4-allow-extras.md`

---

## Task 8: Hook — renumber the header comment block

**Files:**
- Modify: `.claude/hooks/gdd-permission-hook.sh` (header comment, lines 40-104)

The header's `DECISION TIERS` section and surrounding comments still describe the old 1-2-3 scheme and `safe-bash-extras`. No code; verification is read-back.

- [ ] **Step 1: Replace the DECISION TIERS comment section**

Replace the block from `# ─── DECISION TIERS (in order) ───` (line 40) through the `# Default — Passthrough` / `#   Exit 0 with no JSON. Harness handles as normal.` lines (line 62) with:

```bash
# ─── DECISION TIERS (in order) ──────────────────────────────────────
#
# Tier 1 — Shell composition guard (DENY)
#   Reject any command containing &&, ||, ;, |, command substitution
#   (`...` or $(...)), or output/input redirection (>, <). Each arm
#   denies with a specific corrective message.
#
# Tier 2 — Ask-list (ASK)
#   Commands matching an [ask-commands] glob in hook-rules emit
#   permissionDecision: "ask" — a forced prompt in any permission mode
#   (acceptEdits included), without blocking. Checked before the allow
#   tiers so a destructive command is a safety floor that outranks any
#   allow rule.
#
# Tier 3 — Per-project allowlist from .claude/settings.json (ALLOW)
#   Walk up from $cwd, collect Bash(...) entries from each
#   .claude/settings.json found, then check $HOME/.claude/settings.json
#   too. Glob-match each pattern against the command. Any match → allow.
#
# Tier 4 — Allow-extras from hook-rules.local (ALLOW, optional)
#   The [allow-extras] section of .claude/hooks/hook-rules.local —
#   per-machine personal allow-patterns. Glob-matched; any match → allow.
#
# Default — Passthrough
#   Exit 0 with no JSON. Harness handles as normal.
#
# Config: scratch-dir and ask-command lists live in
# .claude/hooks/hook-rules (committed) with per-machine additions in
# hook-rules.local (gitignored). See .claude/hooks/README.md.
```

- [ ] **Step 2: Fix the THREAT MODEL tier reference**

In the THREAT MODEL comment, find `Keep deny logic conservative (Tier 1 below) and allow logic narrow (Tiers 2-3).` (line 37) and replace `(Tiers 2-3)` with `(Tiers 3-4)`.

- [ ] **Step 3: Fix the REGISTRATION / extras-file footer comment**

Replace the footer lines (101-103):

```bash
# The Tier 3 extras file ($HOME/.claude/hooks/safe-bash-extras) is
# per-user / per-machine, NOT shipped in the repo. Each developer
# manages their own extras alongside the shared hook.
```

with:

```bash
# The hook-rules.local file (.claude/hooks/hook-rules.local) is
# per-machine, gitignored, NOT shipped in the repo. Copy it from
# hook-rules.local.example. The committed hook-rules baseline IS
# shipped and is the transparent source of truth for scratch dirs
# and ask-commands.
```

- [ ] **Step 4: Verify**

Run: `grep -n "Tier 4\|safe-bash-extras\|hook-rules" .claude/hooks/gdd-permission-hook.sh`
Expected: `Tier 4` and `hook-rules` references present; **zero** `safe-bash-extras` matches anywhere in the script.

- [ ] **Step 5: Run the full suite (no behavior change expected)**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

Write `.commits/hook-header-renumber.md`:

```markdown
---
message: "docs(hook): renumber header comment tiers, drop safe-bash-extras refs"

add:
  - .claude/hooks/gdd-permission-hook.sh
---

Update the hook's header comment block for the 1-2-3-4 tier scheme and
the hook-rules config. No code change. Confirms zero remaining
safe-bash-extras references in the script.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-header-renumber.md`

---

## Task 9: Delete the retired `safe-bash-extras` files

**Files:**
- Delete: `.claude/hooks/safe-bash-extras`, `.claude/hooks/safe-bash-extras.example`

- [ ] **Step 1: Confirm nothing reads them**

Run: `grep -rn "safe-bash-extras" .claude/ docs/ scripts/ tests/`
Expected: only `tests/hook/test_helper.bash` (the `write_project_extras` / `write_user_extras` helpers, kept so the "legacy file ignored" test in Task 7 still works) and possibly `tests/hook/gdd-permission-hook.bats` (that one test). No references in the hook script or docs. If a doc still references it, that is fixed in Task 11 — note it but proceed.

- [ ] **Step 2: Delete the files**

Run: `git rm ".claude/hooks/safe-bash-extras" ".claude/hooks/safe-bash-extras.example"`

(The live `safe-bash-extras` is gitignored and may not be tracked — if `git rm` reports it's not tracked, run `rm -f .claude/hooks/safe-bash-extras` to remove the working-tree copy and `git rm .claude/hooks/safe-bash-extras.example` for the tracked template alone.)

- [ ] **Step 3: Verify**

Run: `ls .claude/hooks/`
Expected: `README.md`, `gdd-permission-hook.sh`, `hook-rules`, `hook-rules.local.example` — no `safe-bash-extras*`.

- [ ] **Step 4: Run the full suite**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: all PASS (the "legacy file ignored" test writes its own throwaway `safe-bash-extras` into the bats tmp tree — unaffected by the repo deletion).

- [ ] **Step 5: Commit**

Write `.commits/hook-retire-safe-bash-extras.md`:

```markdown
---
message: "chore(hook): delete retired safe-bash-extras files"

add:
  - .claude/hooks/safe-bash-extras.example
---

Remove the safe-bash-extras template; its role is now [allow-extras]
in hook-rules.local. The gitignored live file (if present) is removed
from the working tree as a local cleanup.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-retire-safe-bash-extras.md`

(If `git rm` already staged the deletion, `ws commit` with the `add:` entry records it; verify with `git status` after.)

---

## Task 10: Create the interactive acceptance script

**Files:**
- Create: `tests/hook/interactive-acceptance.md`

- [ ] **Step 1: Write the file**

Create `tests/hook/interactive-acceptance.md` with exactly this content:

````markdown
# Hook ask-tier — interactive acceptance script

bats (`gdd-permission-hook.bats`) verifies the hook's *output*. It cannot
verify the *prompt the human sees*. This script is the gap-filler: the
agent runs it live, the human watches the prompts.

**How to run:** ask the agent to "run the hook acceptance script." The
agent announces the batch, runs each command in order, and you confirm
each prompt matches the expected shape.

## Preconditions

- Session permission mode: `acceptEdits` (this is the mode the original
  bug appeared in — step 5 is the regression check).
- A throwaway dir exists: `.tmp/acceptance-probe/` and a second
  `.tmp/acceptance-probe-2/`. The agent creates them first.
- A throwaway git repo for step 2: `.tmp/acceptance-repo/` with one
  commit. The agent sets it up.

## Sequence

| # | Command | Expected prompt |
|---|---------|-----------------|
| 1 | `rm -rf .tmp/acceptance-probe` | `ask` prompt — reason mentions the ask-list **and** carries the symlink caution |
| 2 | `git -C .tmp/acceptance-repo reset --hard HEAD` | `ask` prompt — reason mentions the ask-list, **no** symlink caution |
| 3 | `ls -la` | no ask prompt (Tier 4 `[allow-extras]` if `ls *` is enabled locally; otherwise a normal harness prompt) |
| 4 | `echo hi && echo bye` | composition **deny** — blocked with the shell-composition message, NOT an ask |
| 5 | `rm -rf .tmp/acceptance-probe-2` | `ask` prompt **still appears** despite `acceptEdits` mode — the core regression check |

## Confirmation

For each step the human confirms: did the prompt appear, and did its
shape match the table? Step 5 is the pass/fail gate — if it does not
prompt, the ask-tier is not overriding `acceptEdits` and the fix is
incomplete.

## Teardown

The agent removes `.tmp/acceptance-probe*` and `.tmp/acceptance-repo`
after the run.
````

- [ ] **Step 2: Verify**

Run: `grep -c "^| [0-9]" tests/hook/interactive-acceptance.md`
Expected: `5` (five numbered sequence rows).

- [ ] **Step 3: Commit**

Write `.commits/hook-interactive-acceptance.md`:

```markdown
---
message: "test(hook): interactive acceptance script for ask-tier prompts"

add:
  - tests/hook/interactive-acceptance.md
---

A scripted live acceptance test the agent walks through with the human
to verify the actual permission prompts — the part bats cannot reach.
Step 5 is the acceptEdits-mode regression check.
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-interactive-acceptance.md`

---

## Task 11: Documentation updates

**Files:**
- Modify: `.claude/hooks/README.md`, `docs/gdd/permissions.md`, `docs/gdd/agent-training.md`, `docs/gdd/trust-and-safety.md`, `docs/gdd/roles-and-modes.md`

Each step: read the file, make the described change. No tests — verification is read-back.

- [ ] **Step 1: `.claude/hooks/README.md`**

Read the file. Update the `gdd-permission-hook.sh` tier description from three tiers to four: Tier 1 deny-composition, **Tier 2 ask-list (new)**, Tier 3 settings.json allow, Tier 4 `[allow-extras]` allow. Replace the "Adding a safe command (per-machine extras)" section's `safe-bash-extras` content with the `hook-rules` / `hook-rules.local` / `hook-rules.local.example` model (committed baseline + gitignored per-machine override, copy the `.example`). Document the `[scratch-dirs]` / `[ask-commands]` / `[allow-extras]` sections and that `[ask-commands]` is additive-only. Keep the `WS_HOOK_DISABLE` and `WS_HOOK_DEBUG` sections. Remove every `safe-bash-extras` mention.

Verify: `grep -c "safe-bash-extras" .claude/hooks/README.md` → `0`; `grep -c "Tier 4\|hook-rules" .claude/hooks/README.md` → non-zero.

- [ ] **Step 2: `docs/gdd/permissions.md`**

Read the file. Add `ask` as a third hook decision alongside allow / deny: the hook can force a permission prompt for a command (the ask-list), and `ask` overrides the session permission mode — it prompts even under `acceptEdits` / `bypassPermissions`. Place this where the doc describes the hook's allow/deny behavior.

Verify: `grep -c "ask" docs/gdd/permissions.md` → non-zero with the new content present.

- [ ] **Step 3: `docs/gdd/agent-training.md`**

Read the file. Add a short subsection: some destructive commands (`rm -rf`, `git reset --hard`, …) now always produce a permission prompt — the ask-tier — regardless of mode. Frame it as a deliberate agent-human confirmation checkpoint, not a failure or a denial: the agent proposes, the human confirms, the command then runs. This is consistent with the doc's existing "why you'll see deny output early" framing.

Verify: `grep -c "ask-tier\|ask-list" docs/gdd/agent-training.md` → non-zero.

- [ ] **Step 4: `docs/gdd/trust-and-safety.md`**

Read the file. Record the ask-tier as the destructive-command safety floor, and note the gap it closes: in `acceptEdits` mode the harness otherwise auto-approves Bash file-mutations (including `rm -rf`) on workspace paths with no prompt; the ask-tier intercepts and forces the prompt.

Verify: `grep -c "ask-tier\|acceptEdits" docs/gdd/trust-and-safety.md` → non-zero.

- [ ] **Step 5: `docs/gdd/roles-and-modes.md`**

Read the file. Accuracy review of the `acceptEdits` mode description: if it implies `acceptEdits` silently runs Bash commands, add a clause noting the hook's ask-tier still intercepts destructive commands. If the doc does not describe `acceptEdits` at that level of detail, no change is needed — record "reviewed, no change" in the commit message.

- [ ] **Step 6: Commit**

Write `.commits/hook-doc-updates.md`:

```markdown
---
message: "docs: ask-tier + hook-rules across hook-related docs"

add:
  - .claude/hooks/README.md
  - docs/gdd/permissions.md
  - docs/gdd/agent-training.md
  - docs/gdd/trust-and-safety.md
  - docs/gdd/roles-and-modes.md
---

Update the hook documentation set for the ask-tier and the hook-rules
config: README (four tiers, hook-rules model, drop safe-bash-extras),
permissions (ask as a third decision, overrides mode), agent-training
(the ask-tier as a confirmation checkpoint), trust-and-safety (the
acceptEdits gap it closes), roles-and-modes (accuracy review).
```

Run: `bash scripts/ws commit yggdrasil .commits/hook-doc-updates.md`

---

## Task 12: Full verification and branch wrap

- [ ] **Step 1: Run the full hook bats suite**

Run: `bash tests/vendor/bats-core/bin/bats tests/hook/gdd-permission-hook.bats`
Expected: all tests PASS.

- [ ] **Step 2: Run the broader bats suites the hook could affect**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-smoke/read-only.bats`
Expected: PASS (this suite includes hook-timeout assertions).

- [ ] **Step 3: Confirm no stray references**

Run: `grep -rn "safe-bash-extras" .claude/hooks/gdd-permission-hook.sh .claude/hooks/README.md docs/gdd/`
Expected: empty.

- [ ] **Step 4: Run the interactive acceptance script with the user**

Walk `tests/hook/interactive-acceptance.md` with the user as the final gate — especially step 5 (the `acceptEdits` regression check). Capture any prompt-shape mismatch and fix before the PR.

- [ ] **Step 5: Push and open the PR**

The branch `feat/hook-ask-tier` is ready. Push and open a CR against `main` per the workspace convention (`bash scripts/ws cr yggdrasil "<title>" <bodyfile>` — the bodyfile's first line must be the `> **AI-assisted change proposal.**` attribution from `templates/change.md`). Title: `feat: hook ask-tier + hook-rules config`.

- [ ] **Step 6: Update the Thalamus arc**

Note the hook ask-tier work as landed in the Dionysus thalamus (frontmatter `arcs:` and/or the relevant Observations entry — the `acceptEdits` / `rm -rf` observation can be marked resolved-by this branch). Commit per the thalami cadence (batched, not per-edit).

---

## Self-review

- [x] **Spec coverage:**
  - Ask-tier (`ask` decision, forced prompt) → Task 5 (`ask()` + Tier 2)
  - `hook-rules` committed baseline → Task 1
  - `hook-rules.local` + `.example` → Task 2; gitignore → Task 3
  - Flat sectioned format, pure-bash parse → Task 5 (`_parse_rules_file`)
  - Layered merge, additive-only ask-commands → Task 5 (parser appends; bats test "additive")
  - Tier renumbering 1-2-3-4 → Tasks 7 (Tier 3/4 headers) + 8 (header block)
  - Scratch-dirs from config → Task 6
  - Consolidation — `safe-bash-extras` → `[allow-extras]` → Task 7; deletion → Task 9
  - Symlink caution in `rm` ask-prompts → Task 5 (Tier 2 `case` rm-addendum)
  - bats coverage → Tasks 5, 6, 7 (TDD)
  - Interactive acceptance script → Task 10
  - Documentation updates (5 files) → Task 11
  - No new dependency → parser is pure bash (Task 5)
- [x] **No placeholders.** Every hook code block, config file, bats test, and the interactive script is given in full. Doc tasks (Task 11) specify concrete per-file content — prose docs are described, not code-blocked, which is correct for documentation work.
- [x] **Type/name consistency.** Array names (`scratch_dirs`, `ask_commands`, `allow_extras`) and the helper (`_parse_rules_file`) are used identically across Tasks 5, 6, 7. Section names (`scratch-dirs`, `ask-commands`, `allow-extras`) consistent across the config files (Tasks 1-2), the parser (Task 5), and the helpers. Tier numbers consistent: deny=1, ask=2, settings=3, extras=4.
- [x] **bats migration handled.** Tasks 6 and 7 explicitly migrate the Edit/Write and `safe-bash-extras` tests this change invalidates — they are not left failing.
- [x] **Ordering.** Config parser (Task 5) lands before its consumers (scratch-dirs Task 6, allow-extras Task 7). Header renumber (Task 8) after the tier logic is final. Deletion (Task 9) after Task 7 stops reading the files.

No issues found.
