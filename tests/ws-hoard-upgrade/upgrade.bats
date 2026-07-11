#!/usr/bin/env bats

load test_helper

setup() { setup_dirs; }

@test "provenance rejects a template name that traverses outside hoards templates" {
    make_hoard h1
    mkdir -p "$TEMPLATES_DIR/outside/.upgrade"
    printf 'version: 1\nplugins: []\n' > "$TEMPLATES_DIR/outside/.upgrade/upgrade.yaml"
    printf 'template: ../outside\napplied_version: 0\n' > "$HOARDS_DIR/h1/.hoard.yaml"

    run ws_hoard_upgrade h1 --plan

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid hoard template name"* ]]
}

@test "manifest files_remove traversal is rejected before backup or deletion" {
    make_template thalami "version: 2
plugins: []
files_remove:
  - ../victim.txt"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    printf 'preserve\n' > "$HOARDS_DIR/victim.txt"
    make_fake_gh

    run ws_hoard_upgrade h1 --apply

    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes the hoard root"* ]]
    [ -f "$HOARDS_DIR/victim.txt" ]
    [ ! -e "$HOARDS_DIR/h1/.upgrade-backup" ]
}

@test "manifest files_remove rejects a symlink escape" {
    make_template thalami "version: 2
plugins: []
files_remove:
  - linked/victim.txt"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    mkdir -p "$BATS_TEST_TMPDIR/outside"
    printf 'preserve\n' > "$BATS_TEST_TMPDIR/outside/victim.txt"
    ln -s "$BATS_TEST_TMPDIR/outside" "$HOARDS_DIR/h1/linked"

    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"

    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes the hoard root"* ]]
    [ -f "$BATS_TEST_TMPDIR/outside/victim.txt" ]
}

@test "manifest paths reject control characters before resolution" {
    make_hoard h1

    run _ws_hoard_contained_path "$HOARDS_DIR/h1" $'notes/unsafe\nname.md' "hoard"

    [ "$status" -ne 0 ]
    [[ "$output" == *"control character"* ]]
}

@test "manifest plugin id traversal is rejected before backup or download" {
    make_template thalami "version: 2
plugins:
  - id: ../../../escaped-plugin
    repo: example/plugin
    pin: \"1.0.0\""
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    make_fake_gh

    run ws_hoard_upgrade h1 --apply

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid plugin id"* ]]
    [ ! -e "$HOARDS_DIR/escaped-plugin" ]
    [ ! -e "$HOARDS_DIR/h1/.upgrade-backup" ]
}

@test "managed region destination traversal is rejected before splice" {
    make_template thalami "version: 2
plugins: []
managed_regions:
  - file: ../outside.md
    id: controls
    source: regions/controls.md"
    printf 'new\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/regions/controls.md"
    make_hoard h1
    printf 'preserve\n' > "$HOARDS_DIR/outside.md"

    run _ws_hoard_apply_regions "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"

    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes the hoard root"* ]]
    [ "$(cat "$HOARDS_DIR/outside.md")" = "preserve" ]
}

@test "managed region source traversal is rejected before splice" {
    make_template thalami "version: 2
plugins: []
managed_regions:
  - file: Dashboard.md
    id: controls
    source: ../outside.md"
    printf 'untrusted\n' > "$TEMPLATES_DIR/hoards/thalami/outside.md"
    make_hoard h1
    printf 'preserve\n' > "$HOARDS_DIR/h1/Dashboard.md"

    run _ws_hoard_apply_regions "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"

    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes the template upgrade root"* ]]
    [ "$(cat "$HOARDS_DIR/h1/Dashboard.md")" = "preserve" ]
}

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
    [ "$status" -eq 0 ]
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
    [ "$status" -eq 0 ]
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
    [ "$status" -eq 0 ]
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

@test "backup: ensures .upgrade-backup/ is gitignored in a git-tracked hoard" {
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.git"
    printf '.obsidian/\n' > "$HOARDS_DIR/h1/.gitignore"
    _ws_hoard_backup "$HOARDS_DIR/h1" >/dev/null
    grep -qxF '.upgrade-backup/' "$HOARDS_DIR/h1/.gitignore"
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
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "region splice: malformed markers (BEGIN without END) error without rewriting" {
    make_hoard h1
    printf '# Dash\n<!-- BEGIN upgrade-controls -->\nstuff\nmore\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    local before
    before="$(cat "$HOARDS_DIR/h1/ArcDashboard.md")"
    printf 'NEW\n' > "$BATS_TEST_TMPDIR/src.md"
    run _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/src.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"malformed managed-region markers"* ]]
    # File untouched — no truncation.
    [ "$(cat "$HOARDS_DIR/h1/ArcDashboard.md")" = "$before" ]
}

@test "region splice: malformed markers (END without BEGIN) error without rewriting" {
    make_hoard h1
    printf '# Dash\n<!-- END upgrade-controls -->\ntail\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    local before
    before="$(cat "$HOARDS_DIR/h1/ArcDashboard.md")"
    printf 'NEW\n' > "$BATS_TEST_TMPDIR/src.md"
    run _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/src.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"malformed managed-region markers"* ]]
    [ "$(cat "$HOARDS_DIR/h1/ArcDashboard.md")" = "$before" ]
}

@test "apply: aborts and leaves provenance un-bumped when a region splice fails" {
    make_template thalami "version: 2
plugins: []
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md"
    printf 'CONTROLS\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/regions/arcdashboard-controls.md"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    # Malformed marker (BEGIN without END) makes the region splice fail mid-apply.
    printf '# Dash\n<!-- BEGIN upgrade-controls -->\nx\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    run _ws_hoard_upgrade_apply "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -ne 0 ]
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$output" = "thalami 1" ]
}

@test "region splice: missing source errors without writing the target" {
    make_hoard h1
    printf '# Dash\n' > "$HOARDS_DIR/h1/ArcDashboard.md"
    run _ws_hoard_region_splice "$HOARDS_DIR/h1/ArcDashboard.md" controls "$BATS_TEST_TMPDIR/does-not-exist.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"source not readable"* ]]
    [ "$(cat "$HOARDS_DIR/h1/ArcDashboard.md")" = "# Dash" ]
}

@test "region splice: inserting into a new file has no leading blank line" {
    make_hoard h1
    printf 'NEW\n' > "$BATS_TEST_TMPDIR/src.md"
    _ws_hoard_region_splice "$HOARDS_DIR/h1/brand-new.md" controls "$BATS_TEST_TMPDIR/src.md"
    run head -n 1 "$HOARDS_DIR/h1/brand-new.md"
    [ "$output" = "<!-- BEGIN upgrade-controls -->" ]
}

@test "rollback: removes files created after the snapshot" {
    make_hoard h1
    printf 'orig\n' > "$HOARDS_DIR/h1/note.md"
    _ws_hoard_backup "$HOARDS_DIR/h1" >/dev/null
    printf 'extra\n' > "$HOARDS_DIR/h1/new-file.md"
    run _ws_hoard_rollback "$HOARDS_DIR/h1"
    [ "$status" -eq 0 ]
    [ ! -e "$HOARDS_DIR/h1/new-file.md" ]
    [ -f "$HOARDS_DIR/h1/note.md" ]
}

@test "apply: creates .obsidian when the hoard lacks one" {
    make_template thalami "version: 1
plugins: []"
    mkdir -p "$HOARDS_DIR/h1"
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 0
    run _ws_hoard_upgrade_apply "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [ -d "$HOARDS_DIR/h1/.obsidian" ]
}

@test "command: --template without a value errors" {
    make_hoard h1
    run ws_hoard_upgrade h1 --plan --template
    [ "$status" -ne 0 ]
    [[ "$output" == *"--template requires"* ]]
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

@test "command: --plan --template previews the adopted baseline WITHOUT writing provenance" {
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
    # Baseline (v1) is used in-memory so the plan shows the pending region.
    [[ "$output" == *"region-insert"* ]]
    # --plan must not mutate the hoard.
    [ ! -f "$HOARDS_DIR/h1/.hoard.yaml" ]
}

@test "command: --apply --template persists provenance (adoption)" {
    make_template thalami "version: 1
plugins: []"
    mkdir -p "$HOARDS_DIR/h1/.obsidian"
    run ws_hoard_upgrade h1 --apply --template thalami
    [ "$status" -eq 0 ]
    [ -f "$HOARDS_DIR/h1/.hoard.yaml" ]
    run _ws_hoard_provenance_read "$HOARDS_DIR/h1"
    [ "$output" = "thalami 1" ]
}

@test "apply --template: backup snapshot predates the adoption marker write" {
    make_template thalami "version: 1
plugins: []"
    mkdir -p "$HOARDS_DIR/h1/.obsidian"
    run ws_hoard_upgrade h1 --apply --template thalami
    [ "$status" -eq 0 ]
    local snap
    snap="$(find "$HOARDS_DIR/h1/.upgrade-backup" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$snap" ]
    # The marker was written AFTER the backup, so the snapshot must not have it.
    [ ! -e "$snap/.hoard.yaml" ]
    [ -f "$HOARDS_DIR/h1/.hoard.yaml" ]
}

@test "plan: a hoard plugin absent from the template is destructive" {
    make_template thalami "version: 2
plugins:
  - id: dataview
    name: Dataview
    repo: blacksmithgu/obsidian-dataview
    pin: \"0.5.68\""
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    printf '["dataview","some-extra-plugin"]\n' > "$HOARDS_DIR/h1/.obsidian/community-plugins.json"
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [[ "$output" == *"destructive"*"some-extra-plugin"* ]]
    # An in-template plugin (dataview) must NOT be flagged — it survives the
    # overwrite. Regression for the -o tsv false-positive found via live --plan.
    [[ "$output" != *"dataview"* ]]
}

@test "plan: a directory in files_remove is not flagged (apply uses rm -f)" {
    make_template thalami "version: 2
plugins: []
files_remove:
  - somedir"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    mkdir -p "$HOARDS_DIR/h1/somedir"
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [[ "$output" != *"somedir"* ]]
}

@test "apply: prunes old backups, keeping WS_HOARD_BACKUP_KEEP most recent" {
    make_template thalami "version: 1
plugins: []"
    mkdir -p "$HOARDS_DIR/h1/.obsidian"
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 0
    mkdir -p "$HOARDS_DIR/h1/.upgrade-backup/20260101-000001" \
             "$HOARDS_DIR/h1/.upgrade-backup/20260101-000002" \
             "$HOARDS_DIR/h1/.upgrade-backup/20260101-000003" \
             "$HOARDS_DIR/h1/.upgrade-backup/20260101-000004"
    export WS_HOARD_BACKUP_KEEP=3
    run _ws_hoard_upgrade_apply "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    # 4 pre-seeded + 1 from this apply = 5; pruned to the 3 newest.
    run find "$HOARDS_DIR/h1/.upgrade-backup" -mindepth 1 -maxdepth 1 -type d
    [ "${#lines[@]}" -eq 3 ]
}

@test "plan: an existing data.json the template would overlay is destructive" {
    make_template thalami "version: 2
plugins: []"
    mkdir -p "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview"
    printf '{}\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview/data.json"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/dataview"
    printf '{"existing":true}\n' > "$HOARDS_DIR/h1/.obsidian/plugins/dataview/data.json"
    run _ws_hoard_upgrade_plan "$HOARDS_DIR/h1" "$TEMPLATES_DIR/hoards/thalami"
    [ "$status" -eq 0 ]
    [[ "$output" == *"destructive"*"dataview data.json"* ]]
}

@test "command: a second positional argument errors" {
    make_hoard h1
    run ws_hoard_upgrade h1 extra-arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected extra argument"* ]]
}

@test "command: conflicting mode flags error" {
    make_hoard h1
    run ws_hoard_upgrade h1 --plan --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"only one of"* ]]
}
