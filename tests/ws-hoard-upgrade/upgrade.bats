#!/usr/bin/env bats

load test_helper

setup() { setup_dirs; }

make_lock_refresh_template() {
    local template="${1:-thalami}"
    local main_digest="${2:-sha256:0000000000000000000000000000000000000000000000000000000000000000}"
    local manifest_digest="${3:-sha256:0000000000000000000000000000000000000000000000000000000000000000}"
    make_template "$template" "version: 1
plugins:
  - id: dataview
    name: Dataview
    description: Query engine.
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: $main_digest
      manifest.json: $manifest_digest
  - id: calendar
    name: Calendar
    description: Calendar view.
    repo: example/calendar
    pin: \"2.0.0\"
    assets:
      main.js: sha256:1111111111111111111111111111111111111111111111111111111111111111
      manifest.json: sha256:1111111111111111111111111111111111111111111111111111111111111111"
}

@test "plugin manifest requires an asset lock before download" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\""

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"asset lock"* ]]
}

@test "plugin manifest rejects malformed SHA-256 digests" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:not-a-digest
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid SHA-256 lock"* ]]
}

@test "plugin manifest requires executable and metadata assets" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d"

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires"* ]]
    [[ "$output" == *"manifest.json"* ]]
}

@test "plugin manifest rejects unsupported release asset names" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c
      plugin.zip: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d"

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported plugin asset"* ]]
}

@test "plugin manifest rejects option-like release pins" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"--repo\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid release pin"* ]]
}

@test "plugin manifest rejects duplicate plugin ids before staging" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/first
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c
  - id: dataview
    repo: example/second
    pin: \"2.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Duplicate plugin id 'dataview'"* ]]
}

@test "plugin manifest rejects plugin ids that alias on case-insensitive filesystems" {
    make_template thalami "version: 1
plugins:
  - id: Dataview
    repo: example/first
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c
  - id: dataview
    repo: example/second
    pin: \"2.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"

    run _ws_hoard_validate_plugin_manifest "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Plugin ids 'Dataview' and 'dataview' alias"* ]]
}

@test "SHA-256 helper hashes release assets portably" {
    printf 'stub\n' > "$BATS_TEST_TMPDIR/main.js"

    run _ws_hoard_sha256 "$BATS_TEST_TMPDIR/main.js"

    [ "$status" -eq 0 ]
    [ "$output" = "25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d" ]
}

@test "SHA-256 helper explains when no supported utility exists" {
    local empty_path="$BATS_TEST_TMPDIR/empty-bin"
    mkdir -p "$empty_path"
    printf 'stub\n' > "$BATS_TEST_TMPDIR/main.js"

    run bash -c 'PATH="$1"; source "$2"; _ws_hoard_sha256 "$3"' _ "$empty_path" "$REPO_ROOT/scripts/ws-hoard-upgrade.sh" "$BATS_TEST_TMPDIR/main.js"

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires sha256sum or shasum"* ]]
}

@test "checksum mismatch leaves the installed plugin unchanged" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:0000000000000000000000000000000000000000000000000000000000000000
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/dataview"
    printf 'trusted\n' > "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js"
    export TMPDIR="$BATS_TEST_TMPDIR/plugin-tmp"
    mkdir -p "$TMPDIR"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum mismatch"* ]]
    [ "$(cat "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js")" = "trusted" ]
    [ -z "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print -quit)" ]
}

@test "a later plugin verification failure leaves every installed plugin unchanged" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c
  - id: calendar
    repo: example/calendar
    pin: \"2.0.0\"
    assets:
      main.js: sha256:0000000000000000000000000000000000000000000000000000000000000000
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/dataview" "$HOARDS_DIR/h1/.obsidian/plugins/calendar"
    printf 'first-before\n' > "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js"
    printf 'second-before\n' > "$HOARDS_DIR/h1/.obsidian/plugins/calendar/main.js"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [ "$(cat "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js")" = "first-before" ]
    [ "$(cat "$HOARDS_DIR/h1/.obsidian/plugins/calendar/main.js")" = "second-before" ]
}

@test "missing required release asset leaves the installed plugin unchanged" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/dataview"
    printf 'trusted\n' > "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js"
    make_fake_gh
    export FAKE_GH_OMIT_MANIFEST=1

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"missing locked asset"* ]]
    [ "$(cat "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js")" = "trusted" ]
}

@test "downloaded stylesheet must be declared in the asset lock" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    make_fake_gh
    export FAKE_GH_WRITE_STYLES=1

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"undeclared asset"*"styles.css"* ]]
}

@test "verified release without a stylesheet installs successfully" {
    make_template thalami "version: 1
plugins:
  - id: calendar
    repo: example/calendar
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -eq 0 ]
    [ -f "$HOARDS_DIR/h1/.obsidian/plugins/calendar/main.js" ]
    [ ! -e "$HOARDS_DIR/h1/.obsidian/plugins/calendar/styles.css" ]
}

@test "verified release installs its locked stylesheet" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c
      styles.css: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d"
    make_hoard h1
    make_fake_gh
    export FAKE_GH_WRITE_STYLES=1

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -eq 0 ]
    [ "$(cat "$HOARDS_DIR/h1/.obsidian/plugins/dataview/styles.css")" = "stub" ]
}

@test "successful verified replacement removes a stale stylesheet" {
    make_template thalami "version: 1
plugins:
  - id: calendar
    repo: example/calendar
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/calendar"
    printf 'old-style\n' > "$HOARDS_DIR/h1/.obsidian/plugins/calendar/styles.css"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -eq 0 ]
    [ ! -e "$HOARDS_DIR/h1/.obsidian/plugins/calendar/styles.css" ]
}

@test "lock refresh rejects an unknown template" {
    make_fake_gh

    run ws_hoard_lock missing-template

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown hoard template"* ]]
}

@test "hoard lock help exits cleanly without downloading" {
    export FAKE_GH_CALLS="$BATS_TEST_TMPDIR/gh-calls"
    make_fake_gh

    run bash "$REPO_ROOT/scripts/ws-hoard.sh" lock --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws hoard lock <template> [--plugin <id>]"* ]]
    [ ! -e "$FAKE_GH_CALLS" ]
}

@test "lock refresh rejects an unknown plugin" {
    make_lock_refresh_template
    make_fake_gh

    run ws_hoard_lock thalami --plugin missing-plugin

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown plugin"* ]]
}

@test "lock refresh bootstraps a missing asset mapping for a new plugin" {
    make_template thalami "version: 1
plugins:
  - id: dataview
    name: Dataview
    repo: example/dataview
    pin: \"1.0.0\""
    make_fake_gh
    local manifest="$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    run ws_hoard_lock thalami --plugin dataview

    [ "$status" -eq 0 ]
    [ "$(yq '.plugins[0].assets."main.js"' "$manifest")" = "sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d" ]
    [ "$(yq '.plugins[0].assets."manifest.json"' "$manifest")" = "sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c" ]
}

@test "single-plugin lock refresh updates only the selected asset mapping" {
    local refreshed_main="sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d"
    local refreshed_manifest="sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    local expected="$BATS_TEST_TMPDIR/expected-upgrade.yaml"
    make_lock_refresh_template thalami "$refreshed_main" "$refreshed_manifest"
    cp "$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml" "$expected"
    make_lock_refresh_template
    make_fake_gh
    local manifest="$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    run ws_hoard_lock thalami --plugin dataview

    [ "$status" -eq 0 ]
    cmp -s "$manifest" "$expected"
}

@test "complete lock refresh updates every plugin atomically" {
    make_lock_refresh_template
    make_fake_gh
    local manifest="$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    run ws_hoard_lock thalami

    [ "$status" -eq 0 ]
    [ "$(yq '[.plugins[].assets."main.js"] | unique | .[]' "$manifest")" = "sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d" ]
    [ "$(yq '[.plugins[].assets."manifest.json"] | unique | .[]' "$manifest")" = "sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c" ]
}

@test "lock refresh keeps asset mappings readable in block style" {
    make_lock_refresh_template
    make_fake_gh
    local manifest="$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"

    run ws_hoard_lock thalami --plugin dataview

    [ "$status" -eq 0 ]
    grep -q '^    assets:$' "$manifest"
    ! grep -q 'assets: {' "$manifest"
}

@test "failed lock refresh leaves the manifest byte-for-byte unchanged" {
    make_lock_refresh_template
    make_fake_gh
    export FAKE_GH_FAIL_REPO=example/calendar
    export TMPDIR="$BATS_TEST_TMPDIR/lock-tmp"
    mkdir -p "$TMPDIR"
    local manifest="$TEMPLATES_DIR/hoards/thalami/.upgrade/upgrade.yaml"
    local before
    before="$(cat "$manifest")"

    run ws_hoard_lock thalami

    [ "$status" -ne 0 ]
    [ "$(cat "$manifest")" = "$before" ]
    [ -z "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print -quit)" ]
}

@test "lock refresh falls back to a v-prefixed release tag" {
    make_lock_refresh_template
    make_fake_gh
    export FAKE_GH_FAIL_TAG=1.0.0
    export FAKE_GH_CALLS="$BATS_TEST_TMPDIR/gh-calls"

    run ws_hoard_lock thalami --plugin dataview

    [ "$status" -eq 0 ]
    [ "$(awk 'NR == 1 { print $2 }' "$FAKE_GH_CALLS")" = "1.0.0" ]
    [ "$(awk 'NR == 2 { print $2 }' "$FAKE_GH_CALLS")" = "v1.0.0" ]
}

@test "hoard help advertises the lock refresh command" {
    run bash "$REPO_ROOT/scripts/ws-hoard.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"lock <template> [--plugin <id>]"* ]]
}

@test "hoard lock dispatches through the public command" {
    make_lock_refresh_template
    make_fake_gh

    run bash "$REPO_ROOT/scripts/ws-hoard.sh" lock thalami --plugin dataview

    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated plugin asset lock"* ]]
}

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
    ln -s "$BATS_TEST_TMPDIR/outside" "$HOARDS_DIR/h1/linked" 2>/dev/null || true
    [[ -L "$HOARDS_DIR/h1/linked" ]] || skip "real symlinks not supported on this platform"

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

@test "fixed community plugin target rejects a symlink before backup or write" {
    make_template thalami "version: 2
plugins: []"
    make_hoard h1
    _ws_hoard_provenance_write "$HOARDS_DIR/h1" thalami 1
    mkdir -p "$HOARDS_DIR/h1/.obsidian"
    local outside="$BATS_TEST_TMPDIR/outside-settings.json"
    printf 'preserve\n' > "$outside"
    rm -f "$HOARDS_DIR/h1/.obsidian/community-plugins.json"
    ln -s "$outside" "$HOARDS_DIR/h1/.obsidian/community-plugins.json" 2>/dev/null || true
    [[ -L "$HOARDS_DIR/h1/.obsidian/community-plugins.json" ]] || skip "real symlinks not supported on this platform"

    run ws_hoard_upgrade h1 --apply

    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink target"* ]]
    [ "$(cat "$outside")" = "preserve" ]
    [ ! -e "$HOARDS_DIR/h1/.upgrade-backup" ]
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

@test "plugin download rejects a symlinked per-plugin destination" {
    make_template thalami "version: 2
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins" "$BATS_TEST_TMPDIR/outside-plugin"
    printf 'preserve\n' > "$BATS_TEST_TMPDIR/outside-plugin/marker.txt"
    ln -s "$BATS_TEST_TMPDIR/outside-plugin" "$HOARDS_DIR/h1/.obsidian/plugins/dataview" 2>/dev/null || true
    [[ -L "$HOARDS_DIR/h1/.obsidian/plugins/dataview" ]] || skip "real symlinks not supported on this platform"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink target"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/outside-plugin/marker.txt")" = "preserve" ]
    [ ! -e "$BATS_TEST_TMPDIR/outside-plugin/main.js" ]
}

@test "plugin download rejects a symlinked release asset" {
    make_template thalami "version: 2
plugins:
  - id: dataview
    repo: example/dataview
    pin: \"1.0.0\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
    make_hoard h1
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/dataview"
    local outside_asset="$BATS_TEST_TMPDIR/outside-main.js"
    printf 'preserve\n' > "$outside_asset"
    ln -s "$outside_asset" "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js" 2>/dev/null || true
    [[ -L "$HOARDS_DIR/h1/.obsidian/plugins/dataview/main.js" ]] || skip "real symlinks not supported on this platform"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink target"* ]]
    [ "$(cat "$outside_asset")" = "preserve" ]
}

@test "plugin data overlay rejects a symlinked destination" {
    make_template thalami "version: 2
plugins: []"
    make_hoard h1
    mkdir -p "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview"
    printf '{\"safe\":true}\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview/data.json"
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins" "$BATS_TEST_TMPDIR/outside-data"
    printf 'preserve\n' > "$BATS_TEST_TMPDIR/outside-data/marker.txt"
    ln -s "$BATS_TEST_TMPDIR/outside-data" "$HOARDS_DIR/h1/.obsidian/plugins/dataview" 2>/dev/null || true
    [[ -L "$HOARDS_DIR/h1/.obsidian/plugins/dataview" ]] || skip "real symlinks not supported on this platform"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink target"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/outside-data/marker.txt")" = "preserve" ]
    [ ! -e "$BATS_TEST_TMPDIR/outside-data/data.json" ]
}

@test "plugin data overlay rejects a symlinked data file" {
    make_template thalami "version: 2
plugins: []"
    make_hoard h1
    mkdir -p "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview"
    printf '{\"safe\":true}\n' > "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview/data.json"
    mkdir -p "$HOARDS_DIR/h1/.obsidian/plugins/dataview"
    local outside_data="$BATS_TEST_TMPDIR/outside-data.json"
    printf 'preserve\n' > "$outside_data"
    ln -s "$outside_data" "$HOARDS_DIR/h1/.obsidian/plugins/dataview/data.json" 2>/dev/null || true
    [[ -L "$HOARDS_DIR/h1/.obsidian/plugins/dataview/data.json" ]] || skip "real symlinks not supported on this platform"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink target"* ]]
    [ "$(cat "$outside_data")" = "preserve" ]
}

@test "plugin data overlay rejects a symlinked template source" {
    make_template thalami "version: 2
plugins: []"
    make_hoard h1
    mkdir -p "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview"
    local outside_source="$BATS_TEST_TMPDIR/outside-template-data.json"
    printf '{"outside":true}\n' > "$outside_source"
    ln -s "$outside_source" "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview/data.json" 2>/dev/null || true
    [[ -L "$TEMPLATES_DIR/hoards/thalami/.upgrade/data/dataview/data.json" ]] || skip "real symlinks not supported on this platform"
    make_fake_gh

    run _ws_hoard_apply_manifest "$TEMPLATES_DIR/hoards/thalami" "$HOARDS_DIR/h1"

    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink target"* ]]
    [ "$(cat "$outside_source")" = '{"outside":true}' ]
    [ ! -e "$HOARDS_DIR/h1/.obsidian/plugins/dataview/data.json" ]
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
    pin: \"1.4.1\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
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
    pin: \"1.4.1\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
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

@test "rollback: same-second snapshots use creation order instead of a random suffix" {
    make_hoard h1
    local stub_dir="$BATS_TEST_TMPDIR/same-second-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/date" <<'SH'
#!/usr/bin/env bash
printf '20260713-120000\n'
SH
    chmod +x "$stub_dir/date"
    PATH="$stub_dir:$PATH"

    printf 'first\n' > "$HOARDS_DIR/h1/note.md"
    _ws_hoard_backup "$HOARDS_DIR/h1" >/dev/null
    printf 'second\n' > "$HOARDS_DIR/h1/note.md"
    _ws_hoard_backup "$HOARDS_DIR/h1" >/dev/null
    printf 'current\n' > "$HOARDS_DIR/h1/note.md"

    run _ws_hoard_rollback "$HOARDS_DIR/h1"

    [ "$status" -eq 0 ]
    [ "$(cat "$HOARDS_DIR/h1/note.md")" = "second" ]
}

@test "rollback: sequenced snapshot wins over same-second legacy random suffix" {
    make_hoard h1
    local backups="$HOARDS_DIR/h1/.upgrade-backup"
    mkdir -p "$backups/20260713-120000-ZZZZZZ"
    mkdir -p "$backups/20260713-120000-000001"
    printf 'legacy\n' > "$backups/20260713-120000-ZZZZZZ/note.md"
    printf 'sequenced\n' > "$backups/20260713-120000-000001/note.md"
    printf 'current\n' > "$HOARDS_DIR/h1/note.md"

    run _ws_hoard_rollback "$HOARDS_DIR/h1"

    [ "$status" -eq 0 ]
    [ "$(cat "$HOARDS_DIR/h1/note.md")" = "sequenced" ]
}

@test "rollback: errors when no snapshot exists" {
    make_hoard h1
    run _ws_hoard_rollback "$HOARDS_DIR/h1"
    [ "$status" -ne 0 ]
}

@test "rollback ignores non-snapshot directories that sort after real backups" {
    make_hoard h1
    printf 'original\n' > "$HOARDS_DIR/h1/note.txt"
    run _ws_hoard_backup "$HOARDS_DIR/h1"
    [ "$status" -eq 0 ]
    printf 'current\n' > "$HOARDS_DIR/h1/note.txt"
    mkdir -p "$HOARDS_DIR/h1/.upgrade-backup/zzz-evil"
    printf 'shadow\n' > "$HOARDS_DIR/h1/.upgrade-backup/zzz-evil/note.txt"

    run _ws_hoard_rollback "$HOARDS_DIR/h1"

    [ "$status" -eq 0 ]
    [ "$(cat "$HOARDS_DIR/h1/note.txt")" = "original" ]
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
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c
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
    pin: \"1.4.1\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
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
    pin: \"0.5.68\"
    assets:
      main.js: sha256:25cf54c697a69632c5952486ec189be371ddddc422bca30910f17b2c3a0ba31d
      manifest.json: sha256:770ec444d1f087cb3f957201681779d599e9174819a012dc2895a7699df2d35c"
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
