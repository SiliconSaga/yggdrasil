#!/usr/bin/env bats

# Lock in `ws hoard scan` classifier behavior against synthetic
# fixtures. Each test points HOARDS_DIR at fixtures/<scenario>/hoards/
# and asserts the YAML inventory the classifier emits.

load test_helper

@test "empty hoards/ produces no output (just .gitkeep)" {
    load_fixture empty-hoards
    run_scan
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "plain Obsidian vault classifies as [obsidian]" {
    load_fixture plain-obsidian
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: plain"* ]]
    [[ "$output" == *"flavors: [obsidian]"* ]]
}

@test "thalami default name (bare 'thalami') classifies as [thalami]" {
    # ws_classify_hoard() must agree with ws_detect_thalami_hoard():
    # both accept bare `thalami` (the current default for `ws hoard
    # init`) AND the legacy `thalami-*` suffixed form.
    load_fixture thalami-default
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: thalami"* ]]
    [[ "$output" == *"flavors: [thalami]"* ]]
}

@test "thalami suffixed name classifies as [thalami]" {
    load_fixture thalami-suffixed
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: thalami-host1"* ]]
    [[ "$output" == *"flavors: [thalami]"* ]]
}

@test "hoard without recognized markers classifies as []" {
    # The `multi` fixture's `beta` hoard has a CLAUDE.md + .claude/
    # but no .obsidian/ and no thalami name pattern — so it carries
    # no recognized flavor today. (Pre-sunset it classified as
    # claudesidian; that flavor was removed.)
    load_fixture multi
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: beta"* ]]
    # beta line should record empty flavors
    [[ "$output" == *"- name: beta"*"flavors: []"* ]] || \
        printf '%s\n' "$output" | grep -A1 'name: beta' | grep -q 'flavors: \[\]'
}

@test "--flavor obsidian filters multi-fixture to obsidian-flagged hoards" {
    load_fixture multi
    run_scan --flavor obsidian
    [ "$status" -eq 0 ]
    # alpha (obsidian) and gamma (obsidian) match.
    [[ "$output" == *"name: alpha"* ]]
    [[ "$output" == *"name: gamma"* ]]
    # beta (no flavor) and thalami-host (thalami only) do not.
    [[ "$output" != *"name: beta"* ]]
    [[ "$output" != *"name: thalami-host"* ]]
}

@test "--flavor thalami filters to thalami-flagged hoards" {
    load_fixture multi
    run_scan --flavor thalami
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: thalami-host"* ]]
    [[ "$output" != *"name: alpha"* ]]
    [[ "$output" != *"name: beta"* ]]
    [[ "$output" != *"name: gamma"* ]]
}

@test "--flavor vault meta-flavor matches obsidian-flavored hoards" {
    load_fixture multi
    run_scan --flavor vault --names-only
    [ "$status" -eq 0 ]
    # Two hoards have the obsidian flavor: alpha, gamma.
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "gamma" ]
}

@test "--flavor with no value errors out (exit 2)" {
    load_fixture empty-hoards
    run_scan --flavor
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR: --flavor requires a value"* ]]
}

@test "unknown flag errors out (exit 2)" {
    load_fixture empty-hoards
    run_scan --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR: Unknown flag: --bogus"* ]]
}

@test "--names-only emits bare names without YAML scaffolding" {
    load_fixture multi
    run_scan --names-only
    [ "$status" -eq 0 ]
    # All four hoards in the multi fixture, in sorted byte order.
    [ "${#lines[@]}" -eq 4 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "beta" ]
    [ "${lines[2]}" = "gamma" ]
    [ "${lines[3]}" = "thalami-host" ]
    # No YAML scaffolding leaked into the output.
    [[ "$output" != *"flavors:"* ]]
    [[ "$output" != *"path:"* ]]
}

@test "--flavor vault --names-only emits sorted bare names of vault hoards" {
    load_fixture multi
    run_scan --flavor vault --names-only
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "gamma" ]
}

@test "multi-fixture YAML output is sorted by hoard name under LC_ALL=C" {
    load_fixture multi
    run_scan
    [ "$status" -eq 0 ]
    # Pull just the `- name: <x>` lines and verify their order.
    local names
    names="$(printf '%s\n' "$output" | grep '^- name: ' | awk '{print $3}')"
    local expected
    expected="$(printf '%s\n' "alpha" "beta" "gamma" "thalami-host")"
    [ "$names" = "$expected" ]
}

@test "--help prints usage and exits 0" {
    load_fixture empty-hoards
    run_scan --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Flags:"* ]]
}

@test "-h short form prints usage and exits 0" {
    load_fixture empty-hoards
    run_scan -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "scan excludes hidden directories (consistent with ws_hoard_list bash glob)" {
    # Build a synthetic HOARDS_DIR with one regular hoard and one
    # hidden dir. ws_hoard_list's bash glob `$HOARDS_DIR/*/` won't match
    # leading dots; ws_hoard_scan must match that semantics so a stray
    # `.cache/` (or `.git/`) inside hoards/ doesn't appear as a hoard.
    export HOARDS_DIR="$BATS_TEST_TMPDIR/hidden/hoards"
    mkdir -p "$HOARDS_DIR/visible"
    mkdir -p "$HOARDS_DIR/.hidden"
    mkdir -p "$HOARDS_DIR/.cache"

    run bash "$WS_BIN" hoard scan --names-only
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "visible" ]
}

@test "scan follows symlinks-to-directories (consistent with ws_hoard_list bash glob)" {
    # Bash's default glob expansion on `$HOARDS_DIR/*/` follows symlinks
    # to directories. ws_hoard_scan must match that — users who symlink
    # an external vault into hoards/ should see it in scan output (and
    # therefore in scribe's vault discovery), not just in `ws hoard list`.
    export HOARDS_DIR="$BATS_TEST_TMPDIR/symlink/hoards"
    mkdir -p "$HOARDS_DIR/regular"
    # Real directory living outside hoards/, symlinked in
    local external="$BATS_TEST_TMPDIR/symlink/external-vault"
    mkdir -p "$external"
    ln -s "$external" "$HOARDS_DIR/linked"

    run bash "$WS_BIN" hoard scan --names-only
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    # find -L | LC_ALL=C sort guarantees this byte order.
    [ "${lines[0]}" = "linked" ]
    [ "${lines[1]}" = "regular" ]
}
