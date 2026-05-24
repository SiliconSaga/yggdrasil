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
    [ -n "$(find "$HOARDS_DIR/h1/.upgrade-backup" -mindepth 1 -maxdepth 1 -type d)" ]
    jq -e 'index("obsidian-meta-bind-plugin")' "$HOARDS_DIR/h1/.obsidian/community-plugins.json"
    grep -qF "CONTROLS" "$HOARDS_DIR/h1/ArcDashboard.md"
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$output" = "thalami 2" ]
}

@test "apply: aborts before changes if backup fails" {
    make_template thalami "version: 2
plugins: []"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    # Plant a FILE where the .upgrade-backup dir would go, so mkdir -p fails.
    printf 'x\n' > "$HOARDS_DIR/h1/.upgrade-backup"
    run _ws_hoard_upgrade_apply "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -ne 0 ]
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$output" = "thalami 1" ]
}

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
    make_hoard h1
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
    make_hoard h1
    printf '# Dash\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    run ws_hoard_upgrade h1 --plan --template thalami
    [ "$status" -eq 0 ]
    [[ "$output" == *"provenance"* ]]
}
