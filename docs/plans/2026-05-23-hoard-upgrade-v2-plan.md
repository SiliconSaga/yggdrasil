# `ws hoard upgrade` v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-enable `ws hoard upgrade` as a provenance-tracked, plan-first, agent-mediated, backed-up upgrade flow, and prove it by giving `thalami` a Meta Bind plugin + an `ArcDashboard.md` controls region.

**Architecture:** Each hoard gets a git-committed `.hoard.yaml` (`template` + `applied_version`). A template's `.upgrade/upgrade.yaml` gains a `version` and a `managed_regions` block. `ws hoard upgrade <hoard> --plan` resolves the template via `.hoard.yaml`, diffs desired-state vs live, and prints a classified change set without touching anything. `--apply` snapshots the whole hoard to `.upgrade-backup/<ts>/`, executes the plan, and bumps `applied_version`. `--rollback` restores the latest snapshot. A `gdd-hoard-upgrade` skill runs `--plan`, proposes the risky changes to the human, then runs `--apply`. Design: [`2026-05-23-hoard-upgrade-v2-design.md`](2026-05-23-hoard-upgrade-v2-design.md).

**Tech Stack:** Bash (sourced, non-strict-mode functions in `scripts/ws-hoard-upgrade.sh`), `yq` v4 (YAML read), `jq` (JSON patch), `gh` (plugin release download — stubbed in tests), bats (tests under `tests/ws-hoard-upgrade/`).

---

## File Structure

- `scripts/ws-hoard-upgrade.sh` — **modified.** Add provenance read/write, manifest-version read, plan computation/classification, backup, rollback, region splice; refactor `_ws_hoard_upgrade_from_template` so `--apply` reuses its plugin/data/core/files logic; rewrite the public `ws_hoard_upgrade` to dispatch `--plan`/`--apply`/`--rollback`/`--template` and drop the `WS_HOARD_UPGRADE_ENABLED` gate.
- `scripts/ws-hoard.sh` — **modified.** Update the `upgrade)` dispatch + `ws hoard help` text to mention the new flags. (`ws hoard init` already calls the internal apply path; add the `.hoard.yaml` write there — Task 8.)
- `scripts/ws` — **modified.** One-line top-comment help update for `hoard upgrade`.
- `templates/hoards/thalami/.upgrade/upgrade.yaml` — **created.** `version: 1` baseline (Dataview only), then bumped to `version: 2` (adds Meta Bind + the ArcDashboard region) in the same task.
- `templates/hoards/thalami/.upgrade/regions/arcdashboard-controls.md` — **created.** The Meta Bind controls block spliced into `ArcDashboard.md`.
- `templates/hoards/thalami/.hoard.yaml` — **created.** Seed provenance shipped with the template (`template: thalami`, `applied_version: <current version>`), copied into new hoards by `ws hoard init`.
- `templates/hoards/thalami/.gitignore` — **modified.** Ignore `.upgrade-backup/`.
- `.agent/skills/gdd-hoard-upgrade/SKILL.md` — **created.** Orchestrates plan → propose → apply.
- `tests/ws-hoard-upgrade/test_helper.bash` — **created.** Isolation harness (`ROOT_DIR`/`HOARDS_DIR`/`TEMPLATES_DIR`), fake-`gh` shim, fixture builders.
- `tests/ws-hoard-upgrade/upgrade.bats` — **created.** All behavior tests.
- `docs/gdd/hoards.md` — **modified.** Document the new upgrade flow + `.hoard.yaml`.

**Function naming contract (used across tasks):**

- `_ws_hoard_provenance_read <hoard_dir>` → prints `<template> <applied_version>`, returns 1 if absent/invalid.
- `_ws_hoard_provenance_write <hoard_dir> <template> <version>`.
- `_ws_hoard_manifest_version <template_dir>` → prints integer `version`, returns 1 if no manifest.
- `_ws_hoard_region_splice <file> <id> <source_file>` → insert-with-anchor or replace-between-markers.
- `_ws_hoard_backup <hoard_dir>` → creates `.upgrade-backup/<ts>/`, prints its path.
- `_ws_hoard_rollback <hoard_dir>` → restores latest snapshot, returns 1 if none.
- `_ws_hoard_upgrade_plan <hoard_dir> <template_dir>` → prints classified plan lines `CLASS\tDETAIL`.
- `ws_hoard_upgrade <hoard> [--plan|--apply|--rollback] [--template <name>]` → public entry.

Plan line classes (stable contract for the skill): `uptodate`, `provenance`, `additive`, `region-insert`, `region-edit`, `destructive`.

---

## Task 1: Provenance read/write (`.hoard.yaml`)

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh` (add two functions near the top, after the header comment / before `ws_hoard_upgrade_help`)
- Create: `tests/ws-hoard-upgrade/test_helper.bash`
- Create: `tests/ws-hoard-upgrade/upgrade.bats`

- [ ] **Step 1: Write the test helper**

Create `tests/ws-hoard-upgrade/test_helper.bash`:

```bash
# Shared helpers for ws-hoard-upgrade bats tests.
#
# Sources ws-hoard-upgrade.sh directly (it's a function library) and
# exercises its functions against an isolated TEMPLATES_DIR / HOARDS_DIR
# under $BATS_TEST_TMPDIR. Plugin downloads are stubbed with a fake `gh`
# on PATH so no network is touched.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup_dirs() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"
    export TEMPLATES_DIR="$ROOT_DIR/templates"
    export HOARDS_DIR="$ROOT_DIR/hoards"
    mkdir -p "$HOARDS_DIR" "$TEMPLATES_DIR/hoards"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/ws-hoard-upgrade.sh"
}

# Build a template at $TEMPLATES_DIR/hoards/<name> with the given
# upgrade.yaml content ($2) and an optional region source file.
make_template() {
    local name="$1" yaml="$2"
    local dir="$TEMPLATES_DIR/hoards/$name"
    mkdir -p "$dir/.upgrade/regions"
    printf '%s\n' "$yaml" > "$dir/.upgrade/upgrade.yaml"
}

# Build a minimal hoard at $HOARDS_DIR/<name> with a .obsidian dir and
# an empty community-plugins.json. Caller adds files/provenance after.
make_hoard() {
    local name="$1"
    local dir="$HOARDS_DIR/$name"
    mkdir -p "$dir/.obsidian"
    printf '[]\n' > "$dir/.obsidian/community-plugins.json"
}

# Put a fake `gh` on PATH that emulates `gh release download ... --dir D`
# by writing dummy main.js + manifest.json into D. No network.
make_fake_gh() {
    local bindir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bindir"
    cat > "$bindir/gh" <<'SH'
#!/usr/bin/env bash
dir=""; prev=""
for a in "$@"; do [[ "$prev" == "--dir" ]] && dir="$a"; prev="$a"; done
if [[ -n "$dir" ]]; then
  mkdir -p "$dir"
  printf 'stub\n' > "$dir/main.js"
  printf '{"id":"stub"}\n' > "$dir/manifest.json"
fi
exit 0
SH
    chmod +x "$bindir/gh"
    export PATH="$bindir:$PATH"
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/ws-hoard-upgrade/upgrade.bats` with:

```bash
#!/usr/bin/env bats

load test_helper

setup() { setup_dirs; }

@test "provenance: write then read round-trips" {
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 3
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$status" -eq 0 ]
    [ "$output" = "thalami 3" ]
}

@test "provenance: read returns non-zero when absent" {
    make_hoard h1
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash scripts/ws test yggdrasil 'provenance'`
Expected: FAIL — `_ws_hoard_provenance_write: command not found` (functions don't exist yet).

- [ ] **Step 4: Implement**

In `scripts/ws-hoard-upgrade.sh`, after the header comment block and before `ws_hoard_upgrade_help()`, add:

```bash
# Read a hoard's provenance. Prints "<template> <applied_version>" on
# success; returns 1 if .hoard.yaml is missing or has no template.
_ws_hoard_provenance_read() {
    local hoard_dir="$1"
    local f="$hoard_dir/.hoard.yaml"
    [[ -f "$f" ]] || return 1
    local tmpl ver
    tmpl="$(yq '.template // ""' "$f" 2>/dev/null)"
    ver="$(yq '.applied_version // 0' "$f" 2>/dev/null)"
    [[ -n "$tmpl" && "$tmpl" != "null" ]] || return 1
    [[ "$ver" =~ ^[0-9]+$ ]] || ver=0
    printf '%s %s\n' "$tmpl" "$ver"
}

# Write a hoard's provenance file (git-committed, hoard root).
_ws_hoard_provenance_write() {
    local hoard_dir="$1" template="$2" version="$3"
    printf 'template: %s\napplied_version: %s\n' "$template" "$version" \
        > "$hoard_dir/.hoard.yaml"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash scripts/ws test yggdrasil 'provenance'`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add scripts/ws-hoard-upgrade.sh tests/ws-hoard-upgrade/
bash scripts/ws commit yggdrasil .commits/hoard-upgrade-provenance.md
```

(Bodyfile `message:` = `feat(hoard): add .hoard.yaml provenance read/write`; `add:` = `scripts/ws-hoard-upgrade.sh`, `tests/ws-hoard-upgrade/test_helper.bash`, `tests/ws-hoard-upgrade/upgrade.bats`.)

---

## Task 2: Manifest version read + "up to date" short-circuit

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh`
- Test: `tests/ws-hoard-upgrade/upgrade.bats`

- [ ] **Step 1: Write the failing test**

Append to `upgrade.bats`:

```bash
@test "manifest version: reads the integer version" {
    make_template thalami "version: 2
plugins: []"
    run _ws_hoard_manifest_version "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "manifest version: returns 1 when no manifest" {
    mkdir -p "$TEMPLATES_DIR/hoards/empty"
    run _ws_hoard_manifest_version "$TEMPLATES_DIR/hoards/empty"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/ws test yggdrasil 'manifest version'`
Expected: FAIL — function not found.

- [ ] **Step 3: Implement**

Add to `scripts/ws-hoard-upgrade.sh` (below the provenance functions):

```bash
# Print the integer `version` from a template's upgrade.yaml. Returns 1
# if the manifest is absent. Defaults a missing/invalid version to 0.
_ws_hoard_manifest_version() {
    local template_dir="$1"
    local f="$template_dir/.upgrade/upgrade.yaml"
    [[ -f "$f" ]] || return 1
    local v
    v="$(yq '.version // 0' "$f" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    printf '%s\n' "$v"
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash scripts/ws test yggdrasil 'manifest version'`
Expected: PASS.

- [ ] **Step 5: Commit**

Bodyfile `message:` = `feat(hoard): read manifest version`; `add:` the two changed files.

---

## Task 3: Plan computation (`--plan`, read-only)

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh`
- Test: `tests/ws-hoard-upgrade/upgrade.bats`

Plan output: one `CLASS<TAB>DETAIL` line per change. Classes: `uptodate`, `additive` (plugin not yet enabled; new data.json), `region-insert` (managed region markers absent in file), `region-edit` (markers present), `destructive` (core plugin currently enabled that will be disabled; `files_remove` target that exists). The function changes nothing.

- [ ] **Step 1: Write the failing tests**

Append to `upgrade.bats`:

```bash
@test "plan: up to date when applied_version >= version" {
    make_template thalami "version: 1
plugins: []"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [[ "$output" == *"uptodate"* ]]
}

@test "plan: new plugin is additive" {
    make_template thalami "version: 2
plugins:
  - id: obsidian-meta-bind-plugin
    name: Meta Bind
    repo: mProjectsCode/obsidian-meta-bind-plugin
    pin: \"1.4.1\""
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [[ "$output" == *"additive"*"obsidian-meta-bind-plugin"* ]]
}

@test "plan: managed region with no markers is region-insert" {
    make_template thalami "version: 2
plugins: []
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md"
    printf 'controls\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/regions/arcdashboard-controls.md"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    printf '# Dash\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [[ "$output" == *"region-insert"*"ArcDashboard.md#controls"* ]]
}

@test "plan: managed region with markers present is region-edit" {
    make_template thalami "version: 2
plugins: []
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md"
    printf 'controls\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/regions/arcdashboard-controls.md"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    printf '# Dash\n<!-- BEGIN upgrade-controls -->\nold\n<!-- END upgrade-controls -->\n' \
        > "$HOARDS_DIR/h1/ArcDashboard.md"
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [[ "$output" == *"region-edit"*"ArcDashboard.md#controls"* ]]
}

@test "plan: files_remove target that exists is destructive" {
    make_template thalami "version: 2
plugins: []
files_remove:
  - .obsidian/daily-notes.json"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    printf '{}\n' > "$HOARDS_DIR/h1/.obsidian/daily-notes.json"
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [[ "$output" == *"destructive"*"daily-notes.json"* ]]
}

@test "plan: changes nothing on disk" {
    make_template thalami "version: 2
plugins:
  - id: obsidian-meta-bind-plugin
    name: Meta Bind
    repo: mProjectsCode/obsidian-meta-bind-plugin
    pin: \"1.4.1\""
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    before="$(cat "$HOARDS_DIR/h1/.obsidian/community-plugins.json")"
    _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami" >/dev/null
    [ "$(cat "$HOARDS_DIR/h1/.obsidian/community-plugins.json")" = "$before" ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/ws test yggdrasil 'plan:'`
Expected: FAIL — function not found.

- [ ] **Step 3: Implement**

Add to `scripts/ws-hoard-upgrade.sh`:

```bash
# Compute and print the upgrade plan as CLASS<TAB>DETAIL lines, without
# modifying the hoard. CLASS ∈ uptodate|additive|region-insert|region-edit|
# destructive. Caller (skill/human) decides on the destructive + region lines.
_ws_hoard_upgrade_plan() {
    local hoard_dir="$1" template_dir="$2"
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    local cp_json="$hoard_dir/.obsidian/community-plugins.json"

    local version applied prov
    version="$(_ws_hoard_manifest_version "$template_dir")" || return 1
    if prov="$(_ws_hoard_provenance_read "$hoard_dir")"; then
        applied="${prov##* }"
    else
        applied=-1   # no provenance yet; everything is "new"
    fi
    if [[ "$applied" -ge "$version" ]]; then
        printf 'uptodate\tapplied %s >= version %s\n' "$applied" "$version"
        return 0
    fi

    # Plugins: additive if id not already in community-plugins.json.
    local n i id
    n="$(yq '.plugins // [] | length' "$upgrade_yaml")"
    i=0
    while [[ $i -lt $n ]]; do
        id="$(yq ".plugins[$i].id" "$upgrade_yaml")"
        if [[ -f "$cp_json" ]] && jq -e --arg id "$id" 'index($id)' "$cp_json" >/dev/null 2>&1; then
            :  # already enabled — no change
        else
            printf 'additive\tenable plugin %s\n' "$id"
        fi
        i=$((i+1))
    done

    # Managed regions: insert (markers absent) vs edit (markers present).
    local rn ri rfile rid begin
    rn="$(yq '.managed_regions // [] | length' "$upgrade_yaml")"
    ri=0
    while [[ $ri -lt $rn ]]; do
        rfile="$(yq ".managed_regions[$ri].file" "$upgrade_yaml")"
        rid="$(yq ".managed_regions[$ri].id" "$upgrade_yaml")"
        begin="<!-- BEGIN upgrade-$rid -->"
        if [[ -f "$hoard_dir/$rfile" ]] && grep -qF "$begin" "$hoard_dir/$rfile" 2>/dev/null; then
            printf 'region-edit\t%s#%s\n' "$rfile" "$rid"
        else
            printf 'region-insert\t%s#%s\n' "$rfile" "$rid"
        fi
        ri=$((ri+1))
    done

    # files_remove: destructive when the target exists.
    local fn fi rel
    fn="$(yq '.files_remove // [] | length' "$upgrade_yaml")"
    fi=0
    while [[ $fi -lt $fn ]]; do
        rel="$(yq ".files_remove[$fi]" "$upgrade_yaml")"
        [[ -e "$hoard_dir/$rel" ]] && printf 'destructive\tremove %s\n' "$rel"
        fi=$((fi+1))
    done

    # core_plugins_disable: destructive when currently enabled.
    local cn ci cid core_json
    core_json="$hoard_dir/.obsidian/core-plugins.json"
    cn="$(yq '.core_plugins_disable // [] | length' "$upgrade_yaml")"
    ci=0
    while [[ $ci -lt $cn ]]; do
        cid="$(yq ".core_plugins_disable[$ci]" "$upgrade_yaml")"
        if [[ -f "$core_json" ]] && jq -e --arg id "$cid" \
            'if type=="array" then index($id) else .[$id] == true end' \
            "$core_json" >/dev/null 2>&1; then
            printf 'destructive\tdisable core plugin %s\n' "$cid"
        fi
        ci=$((ci+1))
    done
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/ws test yggdrasil 'plan:'`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

Bodyfile `message:` = `feat(hoard): compute classified upgrade plan (read-only)`.

---

## Task 4: Whole-hoard backup + rollback

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh`
- Test: `tests/ws-hoard-upgrade/upgrade.bats`

- [ ] **Step 1: Write the failing tests**

Append to `upgrade.bats`:

```bash
@test "backup: snapshots hoard contents, excludes .git and .upgrade-backup" {
    make_hoard h1
    printf 'hello\n' > "$HOARDS_DIR/h1/note.md"
    mkdir -p "$HOARDS_DIR/h1/.git"; printf 'x\n' > "$HOARDS_DIR/h1/.git/config"
    run _ws_hoard_backup "$HOARDS_DIR/h1"
    [ "$status" -eq 0 ]
    local snap="$output"
    [ -f "$snap/note.md" ]
    [ ! -e "$snap/.git" ]
    [ ! -e "$snap/.upgrade-backup" ]
}

@test "rollback: restores the latest snapshot" {
    make_hoard h1
    printf 'original\n' > "$HOARDS_DIR/h1/note.md"
    _ws_hoard_backup "$HOARDS_DIR/h1" >/dev/null
    printf 'changed\n' > "$HOARDS_DIR/h1/note.md"
    run _ws_hoard_rollback "$HOARDS_DIR/h1"
    [ "$status" -eq 0 ]
    [ "$(cat "$HOARDS_DIR/h1/note.md")" = "original" ]
}

@test "rollback: errors when no snapshot exists" {
    make_hoard h1
    run _ws_hoard_rollback "$HOARDS_DIR/h1"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/ws test yggdrasil 'backup:|rollback:'`
Expected: FAIL — functions not found.

- [ ] **Step 3: Implement**

Add to `scripts/ws-hoard-upgrade.sh`:

```bash
# Snapshot the whole hoard into .upgrade-backup/<timestamp>/, excluding
# .git/ and .upgrade-backup/ itself. Prints the snapshot path. Returns 1
# on failure so callers can abort an apply before touching anything.
_ws_hoard_backup() {
    local hoard_dir="$1"
    local ts snap
    ts="$(date '+%Y%m%d-%H%M%S')"
    snap="$hoard_dir/.upgrade-backup/$ts"
    mkdir -p "$snap" || return 1
    local entry base
    for entry in "$hoard_dir"/* "$hoard_dir"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        [[ "$base" == ".git" || "$base" == ".upgrade-backup" ]] && continue
        cp -R "$entry" "$snap/" || return 1
    done
    printf '%s\n' "$snap"
}

# Restore the most recent .upgrade-backup/<ts>/ over the hoard. Returns 1
# if there is no snapshot.
_ws_hoard_rollback() {
    local hoard_dir="$1"
    local backups_dir="$hoard_dir/.upgrade-backup"
    [[ -d "$backups_dir" ]] || return 1
    local latest
    latest="$(find "$backups_dir" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
    [[ -n "$latest" ]] || return 1
    local entry base
    for entry in "$latest"/* "$latest"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        rm -rf "$hoard_dir/$base"
        cp -R "$entry" "$hoard_dir/"
    done
    printf 'Restored %s\n' "$latest"
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/ws test yggdrasil 'backup:|rollback:'`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

Bodyfile `message:` = `feat(hoard): whole-hoard backup + rollback`.

---

## Task 5: Managed-region splice (insert / replace)

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh`
- Test: `tests/ws-hoard-upgrade/upgrade.bats`

Insert (markers absent): append the wrapped region to the end of the file (deterministic, no fragile anchor heuristic in the script — the skill proposes an exact location to the human, but the mechanical default is append; see design "Managed regions"). Replace (markers present): swap the content between markers, preserving everything outside.

- [ ] **Step 1: Write the failing tests**

Append to `upgrade.bats`:

```bash
@test "region splice: inserts wrapped block when markers absent" {
    make_hoard h1
    printf '# Dash\nbody\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    printf 'CONTROLS\n' > "$BATS_TEST_TMPDIR/src.md"
    run _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/src.md"
    [ "$status" -eq 0 ]
    grep -qF "<!-- BEGIN upgrade-controls -->" "$HOARDS_DIR/h1/ArcDashboard.md"
    grep -qF "CONTROLS" "$HOARDS_DIR/h1/ArcDashboard.md"
    grep -qF "# Dash" "$HOARDS_DIR/h1/ArcDashboard.md"
}

@test "region splice: replaces between markers, preserves outside" {
    make_hoard h1
    printf '# Dash\n<!-- BEGIN upgrade-controls -->\nOLD\n<!-- END upgrade-controls -->\ntail\n' \
        > "$HOARDS_DIR/h1/ArcDashboard.md"
    printf 'NEW\n' > "$BATS_TEST_TMPDIR/src.md"
    run _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/src.md"
    [ "$status" -eq 0 ]
    grep -qF "NEW" "$HOARDS_DIR/h1/ArcDashboard.md"
    ! grep -qF "OLD" "$HOARDS_DIR/h1/ArcDashboard.md"
    grep -qF "tail" "$HOARDS_DIR/h1/ArcDashboard.md"
}

@test "region splice: idempotent on re-run with same source" {
    make_hoard h1
    printf '# Dash\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    printf 'NEW\n' > "$BATS_TEST_TMPDIR/src.md"
    _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/src.md"
    _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/src.md"
    run grep -cF "<!-- BEGIN upgrade-controls -->" "$HOARDS_DIR/h1/ArcDashboard.md"
    [ "$output" -eq 1 ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/ws test yggdrasil 'region splice'`
Expected: FAIL — function not found.

- [ ] **Step 3: Implement**

Add to `scripts/ws-hoard-upgrade.sh`:

```bash
# Splice a template-managed region into a file. If the BEGIN marker is
# present, replace everything between BEGIN/END; otherwise append a freshly
# wrapped block. Content outside the markers is preserved verbatim.
_ws_hoard_region_splice() {
    local file="$1" id="$2" source_file="$3"
    local begin="<!-- BEGIN upgrade-$id -->"
    local end="<!-- END upgrade-$id -->"
    local out
    out="$(mktemp)"
    if [[ -f "$file" ]] && grep -qF "$begin" "$file" 2>/dev/null; then
        awk -v b="$begin" -v e="$end" -v insert="$source_file" '
            $0 == b { print; while ((getline line < insert) > 0) print line; close(insert); skip=1; next }
            $0 == e { skip=0 }
            !skip { print }
        ' "$file" > "$out"
    else
        {
            [[ -f "$file" ]] && cat "$file"
            printf '\n%s\n' "$begin"
            cat "$source_file"
            printf '%s\n' "$end"
        } > "$out"
    fi
    mv "$out" "$file"
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/ws test yggdrasil 'region splice'`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

Bodyfile `message:` = `feat(hoard): managed-region splice (insert/replace)`.

---

## Task 6: `--apply` (backup → execute → bump provenance)

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh` (add `_ws_hoard_upgrade_apply`; it reuses the existing plugin-download / data.json / community-plugins.json / core-disable / files_remove logic already in `_ws_hoard_upgrade_from_template`, then adds region splices + provenance bump)
- Test: `tests/ws-hoard-upgrade/upgrade.bats`

- [ ] **Step 1: Write the failing tests**

Append to `upgrade.bats`:

```bash
@test "apply: backs up, enables plugin, splices region, bumps provenance" {
    make_fake_gh
    make_template thalami "version: 2
plugins:
  - id: obsidian-meta-bind-plugin
    name: Meta Bind
    description: x
    repo: mProjectsCode/obsidian-meta-bind-plugin
    pin: \"1.4.1\"
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md"
    printf 'CONTROLS\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/regions/arcdashboard-controls.md"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    printf '# Dash\n' > "$HOARDS_DIR/h1/ArcDashboard.md"

    run _ws_hoard_upgrade_apply "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    # backup exists
    [ -n "$(find "$HOARDS_DIR/h1/.upgrade-backup" -mindepth 1 -maxdepth 1 -type d)" ]
    # plugin enabled
    jq -e 'index("obsidian-meta-bind-plugin")' "$HOARDS_DIR/h1/.obsidian/community-plugins.json"
    # region spliced
    grep -qF "CONTROLS" "$HOARDS_DIR/h1/ArcDashboard.md"
    # provenance bumped
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$output" = "thalami 2" ]
}

@test "apply: aborts before changes if backup fails" {
    make_template thalami "version: 2
plugins: []"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    # Make .upgrade-backup un-creatable by planting a FILE where the dir goes.
    printf 'x\n' > "$HOARDS_DIR/h1/.upgrade-backup"
    run _ws_hoard_upgrade_apply "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -ne 0 ]
    # provenance unchanged
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$output" = "thalami 1" ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/ws test yggdrasil 'apply:'`
Expected: FAIL — `_ws_hoard_upgrade_apply` not found.

- [ ] **Step 3: Refactor + implement**

In `scripts/ws-hoard-upgrade.sh`, extract the body of the existing `_ws_hoard_upgrade_from_template` (the plugin download, data.json overlay, community-plugins.json write, core-disable, files_remove, README block — steps 1–6) so it is callable as `_ws_hoard_apply_manifest <template_dir> <hoard_dir>` (pure mechanical apply, no backup, no provenance). Keep `_ws_hoard_upgrade_from_template` as a thin caller of it (so `ws hoard init`'s existing call still works unchanged). Then add:

```bash
# Apply an upgrade end to end: backup, mechanical manifest apply, region
# splices, provenance bump. Aborts before any change if the backup fails.
_ws_hoard_upgrade_apply() {
    local hoard_dir="$1" template_dir="$2"
    local version
    version="$(_ws_hoard_manifest_version "$template_dir")" || return 1

    local snap
    if ! snap="$(_ws_hoard_backup "$hoard_dir")"; then
        echo "ERROR: backup failed; aborting upgrade (nothing changed)." >&2
        return 1
    fi
    echo "Backed up hoard to: $snap"

    # Mechanical manifest apply (plugins, data.json, community-plugins.json,
    # core-disable, files_remove, README block) — the extracted helper.
    _ws_hoard_apply_manifest "$template_dir" "$hoard_dir" || return 1

    # Managed regions.
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    local rn ri rfile rid rsrc
    rn="$(yq '.managed_regions // [] | length' "$upgrade_yaml")"
    ri=0
    while [[ $ri -lt $rn ]]; do
        rfile="$(yq ".managed_regions[$ri].file" "$upgrade_yaml")"
        rid="$(yq ".managed_regions[$ri].id" "$upgrade_yaml")"
        rsrc="$(yq ".managed_regions[$ri].source" "$upgrade_yaml")"
        _ws_hoard_region_splice "$hoard_dir/$rfile" "$rid" "$template_dir/.upgrade/$rsrc"
        echo "Spliced region $rfile#$rid"
        ri=$((ri+1))
    done

    # Provenance bump — last, so a mid-apply failure leaves it un-bumped
    # and the upgrade is safely retryable.
    local prov template
    prov="$(_ws_hoard_provenance_read "$hoard_dir" 2>/dev/null)" || prov=""
    template="$(basename "$template_dir")"
    _ws_hoard_provenance_write "$hoard_dir" "$template" "$version"
}
```

Note: `_ws_hoard_apply_manifest` must tolerate a manifest with `plugins: []` (the existing loop already guards `plugin_count > 0`). Confirm the extraction kept those guards.

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/ws test yggdrasil 'apply:'`
Expected: PASS (2 tests).

- [ ] **Step 5: Regression-check init path**

Run: `bash scripts/ws test yggdrasil 'standard flow'`
Expected: PASS — the existing `ws hoard init` flow tests (which call `_ws_hoard_upgrade_from_template`) still pass after the extraction.

- [ ] **Step 6: Commit**

Bodyfile `message:` = `feat(hoard): --apply (backup, manifest apply, regions, provenance bump)`.

---

## Task 7: Public command wiring + remove disable gate

**Files:**
- Modify: `scripts/ws-hoard-upgrade.sh` (rewrite `ws_hoard_upgrade` + `ws_hoard_upgrade_help`)
- Modify: `scripts/ws-hoard.sh` (the `upgrade)` dispatch already calls `ws_hoard_upgrade "$@"`; verify it forwards all args — adjust if it only forwards `$2`)
- Modify: `scripts/ws` (top-comment help line for `hoard upgrade`)
- Test: `tests/ws-hoard-upgrade/upgrade.bats`

- [ ] **Step 1: Write the failing tests**

Append to `upgrade.bats`:

```bash
@test "command: --plan prints a plan and changes nothing, no enable gate needed" {
    unset WS_HOARD_UPGRADE_ENABLED
    make_template thalami "version: 2
plugins:
  - id: obsidian-meta-bind-plugin
    name: Meta Bind
    repo: mProjectsCode/obsidian-meta-bind-plugin
    pin: \"1.4.1\""
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    run ws_hoard_upgrade h1 --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"additive"* ]]
}

@test "command: errors when hoard has no provenance and no --template" {
    make_template thalami "version: 1
plugins: []"
    make_hoard h1   # no .hoard.yaml
    run ws_hoard_upgrade h1 --plan
    [ "$status" -ne 0 ]
    [[ "$output" == *"--template"* ]]
}

@test "command: --template establishes provenance then plans" {
    make_template thalami "version: 2
plugins: []
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md"
    printf 'C\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/regions/arcdashboard-controls.md"
    make_hoard h1   # no .hoard.yaml
    printf '# Dash\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    run ws_hoard_upgrade h1 --plan --template thalami
    [ "$status" -eq 0 ]
    [[ "$output" == *"provenance"* ]]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/ws test yggdrasil 'command:'`
Expected: FAIL — current `ws_hoard_upgrade` is gated/positional-only.

- [ ] **Step 3: Implement**

Replace `ws_hoard_upgrade_help` and `ws_hoard_upgrade` in `scripts/ws-hoard-upgrade.sh`:

```bash
ws_hoard_upgrade_help() {
    cat >&2 <<'HELP'
Usage: ws hoard upgrade <hoard> [--plan | --apply | --rollback] [--template <name>]

  --plan       Show what would change; touch nothing (default).
  --apply      Back up the hoard, then apply the plan; bump .hoard.yaml.
  --rollback   Restore the most recent pre-apply backup.
  --template   Name the source template for a hoard with no .hoard.yaml yet
               (establishes provenance at the template's current version).

Reads the source template from <hoard>/.hoard.yaml. The gdd-hoard-upgrade
skill drives the propose-then-apply flow; run it instead of --apply by hand
when there are destructive or region changes to review.
HELP
}

# Public entry. Resolves template via .hoard.yaml (or --template for a
# not-yet-tracked hoard), then plans / applies / rolls back.
ws_hoard_upgrade() {
    local hoard_name="" mode="plan" template_override=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan) mode="plan" ;;
            --apply) mode="apply" ;;
            --rollback) mode="rollback" ;;
            --template) shift; template_override="${1:-}" ;;
            -h|--help) ws_hoard_upgrade_help; return 0 ;;
            -*) echo "ERROR: unknown flag '$1'" >&2; ws_hoard_upgrade_help; return 1 ;;
            *) hoard_name="$1" ;;
        esac
        shift
    done
    if [[ -z "$hoard_name" ]]; then
        ws_hoard_upgrade_help; return 1
    fi

    local hoard_dir="$HOARDS_DIR/$hoard_name"
    if [[ ! -d "$hoard_dir" ]]; then
        echo "ERROR: hoard not found: $hoard_dir" >&2
        return 1
    fi

    if [[ "$mode" == "rollback" ]]; then
        _ws_hoard_rollback "$hoard_dir" || { echo "ERROR: no backup to roll back to." >&2; return 1; }
        return 0
    fi

    # Resolve template + (for not-yet-tracked hoards) establish provenance.
    local template prov
    if prov="$(_ws_hoard_provenance_read "$hoard_dir")"; then
        template="${prov%% *}"
    elif [[ -n "$template_override" ]]; then
        template="$template_override"
        local tv
        tv="$(_ws_hoard_manifest_version "$TEMPLATES_DIR/hoards/$template")" || {
            echo "ERROR: template '$template' has no .upgrade/upgrade.yaml" >&2; return 1; }
        # Establish provenance at a baseline so only newer changes apply.
        # Baseline = current template version minus pending changes is not
        # knowable mechanically; we record the template's *current* version
        # ONLY when it equals the live state. For a brand-new adoption we
        # set applied_version = (version - 1) so the latest bump applies.
        local baseline=$(( tv > 0 ? tv - 1 : 0 ))
        _ws_hoard_provenance_write "$hoard_dir" "$template" "$baseline"
        echo "provenance	established $template @ $baseline (was untracked)"
    else
        echo "ERROR: $hoard_name has no .hoard.yaml; pass --template <name> to adopt it." >&2
        return 1
    fi

    local template_dir="$TEMPLATES_DIR/hoards/$template"
    if [[ ! -f "$template_dir/.upgrade/upgrade.yaml" ]]; then
        echo "ERROR: template '$template' has no .upgrade/upgrade.yaml" >&2
        return 1
    fi

    if [[ "$mode" == "plan" ]]; then
        _ws_hoard_upgrade_plan "$hoard_dir" "$template_dir"
    else
        _ws_hoard_upgrade_apply "$hoard_dir" "$template_dir"
    fi
}
```

Then in `scripts/ws-hoard.sh`, confirm the dispatch forwards all args: the case arm should be `upgrade) shift; ws_hoard_upgrade "$@" ;;` (not `ws_hoard_upgrade "$2"`). Adjust if needed. Update the `ws hoard help` heredoc line for `upgrade` to: `upgrade <hoard> [--plan|--apply|--rollback] [--template <name>]  Provenance-tracked upgrade`.

In `scripts/ws` top comment, change the `hoard upgrade` line to: `#   hoard upgrade <hoard> [--plan|--apply|--rollback]  Provenance-tracked plugin/config upgrade`.

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/ws test yggdrasil 'command:'`
Expected: PASS (3 tests).

- [ ] **Step 5: Full suite regression**

Run: `bash scripts/ws test yggdrasil`
Expected: all green (existing hoard tests + the new suite).

- [ ] **Step 6: Commit**

Bodyfile `message:` = `feat(hoard): wire --plan/--apply/--rollback, drop the disable gate`.

> **Baseline note (resolve during implementation):** the `applied_version = version - 1` baseline assumes the untracked hoard is exactly one bump behind. For the four live thalami hoards adopting at the v1→v2 step this is correct (they are at the v1 baseline). If a hoard could be more than one version behind, pass the true baseline explicitly — extend `--template` to accept `--at-version N` rather than guessing. Keep the simple `version-1` default unless a test shows it's wrong.

---

## Task 8: `ws hoard init` writes `.hoard.yaml`

**Files:**
- Modify: `scripts/ws-hoard.sh` (the `ws_hoard_init` flow, after the template copy + `_ws_hoard_upgrade_from_template` call)
- Test: `tests/ws-hoard-init/init.bats` (existing suite)

- [ ] **Step 1: Write the failing test**

Append to `tests/ws-hoard-init/init.bats` (mirror that file's existing fixture style):

```bash
@test "init writes .hoard.yaml provenance for the chosen template" {
    # (use the suite's existing init invocation for a template that ships
    #  .upgrade/upgrade.yaml; assert the file + contents)
    run_hoard_init thalami myhoard
    [ -f "$HOARDS_DIR/thalami-myhoard/.hoard.yaml" ]
    grep -qF "template: thalami" "$HOARDS_DIR/thalami-myhoard/.hoard.yaml"
}
```

(If the existing init suite uses different helper/argument names, match them — read `tests/ws-hoard-init/test_helper.bash` first.)

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/ws test yggdrasil 'writes .hoard.yaml'`
Expected: FAIL — no `.hoard.yaml` written.

- [ ] **Step 3: Implement**

In `ws_hoard_init` (in `scripts/ws-hoard.sh`), after the post-copy apply, add a provenance write set to the template's current version:

```bash
# Record provenance so `ws hoard upgrade` can resolve the source template.
if [[ -f "$template_dir/.upgrade/upgrade.yaml" ]]; then
    _ws_hoard_provenance_write "$hoard_dir" "$template" \
        "$(_ws_hoard_manifest_version "$template_dir")"
fi
```

(`$template`, `$template_dir`, `$hoard_dir` are already in scope in `ws_hoard_init`; confirm the exact variable names while editing.)

- [ ] **Step 4: Run to verify it passes**

Run: `bash scripts/ws test yggdrasil 'writes .hoard.yaml'`
Expected: PASS.

- [ ] **Step 5: Commit**

Bodyfile `message:` = `feat(hoard): ws hoard init records .hoard.yaml provenance`.

---

## Task 9: `thalami` template recipe + region + gitignore

**Files:**
- Create: `templates/hoards/thalami/.upgrade/upgrade.yaml`
- Create: `templates/hoards/thalami/.upgrade/regions/arcdashboard-controls.md`
- Create: `templates/hoards/thalami/.hoard.yaml`
- Modify: `templates/hoards/thalami/.gitignore`

- [ ] **Step 1: Verify the Meta Bind release tag**

Run: `gh release list -R mProjectsCode/obsidian-meta-bind-plugin -L 5`
Pick the latest stable tag; use it as `pin` below (the `1.4.1` in this plan is a placeholder pin that MUST be replaced with the verified tag). Confirm the plugin `id` by checking its `manifest.json` (`gh release download <tag> -R mProjectsCode/obsidian-meta-bind-plugin --pattern manifest.json --dir /tmp/mb && jq .id /tmp/mb/manifest.json`) — expected `obsidian-meta-bind-plugin`.

- [ ] **Step 2: Create the v2 manifest**

`templates/hoards/thalami/.upgrade/upgrade.yaml`:

```yaml
# Upgrade recipe for thalami hoards. version 1 = the Dataview-only
# baseline the existing hoards shipped with; version 2 adds Meta Bind and
# the ArcDashboard controls region.
version: 2
description: |
  Dataview for the ArcDashboard, plus Meta Bind for the dashboard's
  interactive controls (refresh + filter).
plugins:
  - id: dataview
    name: Dataview
    description: Query engine powering ArcDashboard.md.
    repo: blacksmithgu/obsidian-dataview
    pin: "0.5.68"
  - id: obsidian-meta-bind-plugin
    name: Meta Bind
    description: Inline inputs/buttons bound to frontmatter; powers the ArcDashboard controls.
    repo: mProjectsCode/obsidian-meta-bind-plugin
    pin: "REPLACE-WITH-VERIFIED-TAG"   # Step 1
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md
```

- [ ] **Step 3: Create the region source**

`templates/hoards/thalami/.upgrade/regions/arcdashboard-controls.md` — a Meta Bind button that force-refreshes Dataview (fixes the stale-`date(today)`), plus a note. Confirm the Meta Bind inline-button syntax against the pinned version's docs while editing; the block shape is:

```markdown
> [!tip]- Dashboard controls
> ```meta-bind-button
> label: "🔄 Refresh"
> style: default
> actions:
>   - type: command
>     command: dataview:dataview-force-refresh-views
> ```
> Refresh if the **Days** column reads negative — Dataview caches `date(today)` until the view re-renders.
```

- [ ] **Step 4: Seed template `.hoard.yaml`**

`templates/hoards/thalami/.hoard.yaml`:

```yaml
template: thalami
applied_version: 2
```

(New hoards are stamped by Task 8's init write, which recomputes the version; this seed keeps the template self-consistent for anyone copying it directly.)

- [ ] **Step 5: Ignore backups**

Append to `templates/hoards/thalami/.gitignore`:

```gitignore
# Pre-upgrade snapshots written by `ws hoard upgrade --apply`
.upgrade-backup/
```

- [ ] **Step 6: Commit**

Bodyfile `message:` = `feat(thalami): upgrade recipe v2 (Meta Bind + ArcDashboard controls)`.

---

## Task 10: `gdd-hoard-upgrade` skill

**Files:**
- Create: `.agent/skills/gdd-hoard-upgrade/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.agent/skills/gdd-hoard-upgrade/SKILL.md` with frontmatter (`name`, `description`) matching the repo's other skills, and a body that encodes the flow:

```markdown
---
name: gdd-hoard-upgrade
description: Use when upgrading a hoard from its template (ws hoard upgrade) — runs the plan, proposes destructive/region changes to the human, then applies with a backup.
---

# Upgrading a hoard

1. Run `ws hoard upgrade <hoard> --plan` (add `--template <name>` if the hoard has no `.hoard.yaml` yet). Read the classified plan lines (`uptodate`, `provenance`, `additive`, `region-insert`, `region-edit`, `destructive`).
2. If `uptodate`: stop, report nothing to do.
3. `additive` lines are safe — note them.
4. For each `region-insert`: open the target file, propose an exact insertion point to the human (the mechanical default is append-to-end; suggest a better spot if the file has obvious structure). For `region-edit`: show the diff of the managed block. For `destructive`: name the file/plugin and why the template removes it, and get explicit approval.
5. Once the human approves, run `ws hoard upgrade <hoard> --apply`. Report the backup path it prints.
6. Tell the human to open the hoard in Obsidian (plugins activate on launch) and to `ws hoard upgrade <hoard> --rollback` if anything looks wrong.

Never run `--apply` before the human has approved the `destructive` and `region-*` lines from `--plan`.
```

- [ ] **Step 2: Commit**

Bodyfile `message:` = `feat(skill): gdd-hoard-upgrade orchestration`.

---

## Task 11: Docs

**Files:**
- Modify: `docs/gdd/hoards.md` (add a "Upgrading a hoard" section: `.hoard.yaml`, the plan/apply/rollback flow, the skill)
- Modify: `scripts/ws-hoard-upgrade.sh` header comment (replace the "DISABLED pending provenance fix" framing with the new flow; keep the yggdrasil#54 future-work note about data.json merge)

- [ ] **Step 1: Update `docs/gdd/hoards.md`**

Add a section documenting: `.hoard.yaml` provenance, `ws hoard upgrade <hoard> --plan/--apply/--rollback`, the whole-hoard backup under `.upgrade-backup/`, and that the `gdd-hoard-upgrade` skill drives the propose-then-apply loop. Single-line prose (no-hard-wrap rule).

- [ ] **Step 2: Update the script header comment**

Rewrite the top-of-file comment in `scripts/ws-hoard-upgrade.sh` to describe the v2 flow (provenance-resolved template, plan/apply/rollback, backup, regions) and drop the "DISABLED" paragraph. Keep the note that `data.json` is still overwrite-on-apply (three-way merge deferred — yggdrasil#54).

- [ ] **Step 3: Commit**

Bodyfile `message:` = `docs(hoard): document the v2 upgrade flow`.

---

## Self-Review

**Spec coverage:** provenance (Tasks 1, 8) ✓; versioned manifest (Task 2, 9) ✓; `--plan` classification (Task 3) ✓; backup + rollback (Task 4) ✓; managed regions (Task 5) ✓; `--apply` + provenance bump (Task 6) ✓; wiring + re-enable / drop gate (Task 7) ✓; adopt existing hoards via `--template` (Task 7) ✓; thalami v1→v2 + Meta Bind + ArcDashboard region (Task 9) ✓; skill (Task 10) ✓; docs (Task 11) ✓. Deferred items (data.json three-way merge, per-version migrations, component upgrades) are intentionally untouched per the design's non-goals.

**Placeholder scan:** the only deliberate unknowns are the Meta Bind `pin` and the exact inline-button syntax (Task 9 Steps 1–3), each with an explicit verification command rather than a vague TODO. The `version - 1` adoption baseline is flagged with a resolve-during-implementation note bounded to the thalami v1→v2 case.

**Type/name consistency:** function names match the File Structure contract across tasks (`_ws_hoard_provenance_read/write`, `_ws_hoard_manifest_version`, `_ws_hoard_region_splice`, `_ws_hoard_backup`, `_ws_hoard_rollback`, `_ws_hoard_upgrade_plan`, `_ws_hoard_upgrade_apply`, `_ws_hoard_apply_manifest`, `ws_hoard_upgrade`). Plan line classes are consistent between Task 3 (emit) and Task 10 (consume).
