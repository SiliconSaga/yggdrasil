#!/usr/bin/env bats

# Lock in `ws hoard scan` classifier behavior against synthetic fixtures.
#
# Each test points HOARDS_DIR at fixtures/<scenario>/hoards/ and asserts
# the YAML inventory the classifier emits. The fixtures pin the exact
# trigger phrases the detection regex looks for — if upstream
# Claudesidian's CLAUDE.md template ever drops "PARA Method" or renames
# "Claudesidian", these tests fail loudly rather than letting detection
# silently regress.

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

@test "Claudesidian without .obsidian classifies as [claudesidian]" {
    load_fixture claudesidian-no-obsidian
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: borgr"* ]]
    [[ "$output" == *"flavors: [claudesidian]"* ]]
    # No standalone obsidian flavor on this hoard.
    [[ "$output" != *"flavors: [obsidian]"* ]]
    [[ "$output" != *"flavors: [obsidian, claudesidian]"* ]]
}

@test "Claudesidian with .obsidian classifies as [obsidian, claudesidian]" {
    load_fixture claudesidian-full
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: borgr"* ]]
    [[ "$output" == *"flavors: [obsidian, claudesidian]"* ]]
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

@test ".claude/ without CLAUDE.md does not classify" {
    load_fixture claude-no-claude-md
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: nameless"* ]]
    [[ "$output" == *"flavors: []"* ]]
}

@test ".claude/ + CLAUDE.md without trigger words does not classify" {
    load_fixture claude-without-trigger
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: plain"* ]]
    [[ "$output" == *"flavors: []"* ]]
    [[ "$output" != *"claudesidian"* ]]
}

@test "trigger word past line 30 is invisible (head -n 30 cutoff)" {
    load_fixture claude-trigger-late
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: plain"* ]]
    # Detection cutoff is the first 30 lines; the trigger lives past
    # line 30 in the fixture, so the classifier must NOT pick it up.
    [[ "$output" == *"flavors: []"* ]]
    [[ "$output" != *"claudesidian"* ]]
}

@test "lowercase 'claudesidian' trigger is detected (case-insensitive)" {
    load_fixture claude-trigger-lowercase
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: plain"* ]]
    [[ "$output" == *"flavors: [claudesidian]"* ]]
}

@test "'PARA Method' alone (without 'Claudesidian') still classifies" {
    load_fixture claude-trigger-para
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: plain"* ]]
    [[ "$output" == *"flavors: [claudesidian]"* ]]
}

@test "lowercase 'para method' trigger is detected (case-insensitive)" {
    # The detection regex is `-iE 'claudesidian|PARA Method'` —
    # case-insensitive on BOTH alternatives. This pins the lowercase
    # form of the PARA alternative; a regression that dropped the `-i`
    # flag would fail here even if the lowercase 'claudesidian' fixture
    # still passed (since lowercase 'claudesidian' literally matches
    # the regex's case).
    load_fixture claude-trigger-para-lowercase
    run_scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: plain"* ]]
    [[ "$output" == *"flavors: [claudesidian]"* ]]
}

@test "--flavor obsidian filters multi-fixture to obsidian-flagged hoards" {
    load_fixture multi
    run_scan --flavor obsidian
    [ "$status" -eq 0 ]
    # alpha (obsidian) and gamma (obsidian + claudesidian) match.
    [[ "$output" == *"name: alpha"* ]]
    [[ "$output" == *"name: gamma"* ]]
    # beta (claudesidian only) and thalami-host (thalami only) do not.
    [[ "$output" != *"name: beta"* ]]
    [[ "$output" != *"name: thalami-host"* ]]
}

@test "--flavor claudesidian filters to claudesidian-flagged hoards" {
    load_fixture multi
    run_scan --flavor claudesidian
    [ "$status" -eq 0 ]
    # beta (claudesidian) and gamma (obsidian + claudesidian) match.
    [[ "$output" == *"name: beta"* ]]
    [[ "$output" == *"name: gamma"* ]]
    # alpha (obsidian only) and thalami-host (thalami) do not.
    [[ "$output" != *"name: alpha"* ]]
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

@test "--flavor vault meta-flavor matches obsidian OR claudesidian (deduped)" {
    load_fixture multi
    run_scan --flavor vault --names-only
    [ "$status" -eq 0 ]
    # Three hoards have at least one vault-ish flavor: alpha, beta, gamma.
    # gamma has BOTH obsidian and claudesidian — must appear once, not twice.
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "beta" ]
    [ "${lines[2]}" = "gamma" ]
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
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "beta" ]
    [ "${lines[2]}" = "gamma" ]
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
