#!/usr/bin/env bats

# Lock in `ws hoard lint` behavior against synthetic fixtures.
#
# The motivating bug is the `unparseable` fixture: an unescaped `"`
# inside a double-quoted `next:` scalar closed it early, the whole
# frontmatter block stopped parsing, and every arc on that host silently
# disappeared from the ArcDashboard for three days. Nothing reported it,
# because the three enforcement layers for the arc schema were all prose.

load test_helper

@test "a schema-conformant hoard reports status: ok and exits 0" {
    load_fixture clean
    run_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"status: ok"* ]]
    [[ "$output" == *"findings: 0"* ]]
    [[ "$output" == *"arcs: 2"* ]]
}

@test "unparseable frontmatter is reported as such, not as missing keys" {
    # The distinction matters: 'missing key' reads as one sloppy field,
    # while the actual consequence is that the entire file drops out of
    # the dashboard. Reporting the wrong one sends you editing the wrong
    # thing.
    load_fixture unparseable
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"YAML PARSE FAILURE"* ]]
    [[ "$output" == *"invisible to the dashboard"* ]]
    [[ "$output" == *"unparseable_files: 1"* ]]
}

@test "a parse failure does not also emit per-arc findings for that file" {
    # Once the document fails to parse we cannot read its arcs at all,
    # so any per-arc finding would be fabricated. Guards against a
    # regression where the arc loop runs on an empty parse result and
    # reports every key as missing.
    load_fixture unparseable
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" != *"missing required key"* ]]
    [[ "$output" == *"findings: 1"* ]]
}

@test "missing required keys are named individually" {
    load_fixture schema-violations
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing-several-keys: missing required key: name"* ]]
    [[ "$output" == *"missing-several-keys: missing required key: started"* ]]
    [[ "$output" == *"missing-several-keys: missing required key: last_touched"* ]]
}

@test "an unknown status is flagged with the accepted set" {
    load_fixture schema-violations
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"bogus-status: unknown status 'simmering'"* ]]
    [[ "$output" == *"active review parked closed promoted"* ]]
}

@test "an overgrown next is flagged with its actual length" {
    load_fixture schema-violations
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"overgrown-next: next is 255 chars (max 200)"* ]]
}

@test "a multi-line next is flagged separately from length" {
    load_fixture schema-violations
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"multiline-next: next spans 2 lines"* ]]
}

@test "WS_ARC_NEXT_MAX raises the length threshold" {
    # Non-vacuous: the same fixture that fails at the default must pass
    # the length check at a raised ceiling, proving the knob is read
    # rather than the finding simply being absent for another reason.
    load_fixture schema-violations
    WS_ARC_NEXT_MAX=500 run_lint
    [ "$status" -eq 1 ]
    [[ "$output" != *"overgrown-next: next is"* ]]
    [[ "$output" == *"bogus-status: unknown status"* ]]
}

@test "an empty arcs list is clean, not a finding" {
    load_fixture no-arcs
    run_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"status: ok"* ]]
    [[ "$output" == *"arcs: 0"* ]]
}

@test "a file with no frontmatter at all is reported" {
    load_fixture no-frontmatter
    run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"no frontmatter block"* ]]
}

@test "a hoard with no thalamus files reports a status, not an error" {
    load_fixture empty-hoard
    run_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"status: no-thalamus-files"* ]]
}

@test "an explicit hoard name overrides active-hoard detection" {
    load_fixture clean
    run_lint thalami
    [ "$status" -eq 0 ]
    [[ "$output" == *"hoard: thalami"* ]]
}

@test "a nonexistent hoard name exits 2, distinct from a findings exit" {
    load_fixture clean
    run_lint no-such-hoard
    [ "$status" -eq 2 ]
    [[ "$output" == *"no such hoard"* ]]
}

@test "an unknown flag exits 2 rather than being read as a hoard name" {
    load_fixture clean
    run_lint --nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "--help exits 0 and documents the exit codes" {
    load_fixture clean
    run_lint --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 clean, 1 findings, 2 tooling failure"* ]]
}
