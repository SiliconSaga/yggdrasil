#!/usr/bin/env bats

# `ws orient --check` — the enforcing counterpart to the ai_context rows that
# orient already renders.
#
# Rendering flags a dead pointer to whoever is reading. That is the right
# default: a pointer only matters at the moment someone follows it. But it
# means nothing exits non-zero when a realm adapter points at a doc that has
# been renamed or deleted, so the rot is only ever caught by a human happening
# to look. --check gives that same computation an exit code, so drift can be
# caught on a schedule instead.
#
# Kept in its own file rather than appended to orient.bats: the rendering tests
# there assert output, these assert exit status, and the two failure modes read
# very differently in a report.

load ../ws-smoke/test_helper

setup() {
    init_workspace
}

# The smoke helper's run_ws caps every call at 10s. That budget suits the
# read-only commands it was written for, but orient spawns two jq calls and a
# yq per ai_context row, and on a slow host a two-row adapter exceeds it — the
# pre-existing orient.bats ai_context tests fail exactly that way on Windows
# today. These tests need two rows to have a control, so they get their own
# budget. Still bounded: a genuine hang is caught, it just isn't confused with
# slowness. If orient's per-row cost is ever fixed, drop this and use run_ws.
run_orient() {
    run "$TIMEOUT_BIN" 60 bash "$WS_BIN" orient "$@"
}

# One resolvable pointer and one dead one. The resolvable row is not decoration
# — without it a check that failed unconditionally would pass every assertion
# below.
fixture_mixed() {
    mkdir -p "$WORK/components/demo/.git" "$WORK/components/demo/docs"
    printf '# real\n' > "$WORK/components/demo/docs/real.md"
    mkdir -p "$WORK/realms/realm-fixture/adapters"
    printf 'components: {}\n' > "$WORK/realms/realm-fixture/ecosystem.yaml"
    cat > "$WORK/realms/realm-fixture/adapters/demo.yaml" <<'YAML'
commands:
  test: "echo test"
ai_context:
  - path: "docs/real.md"
    description: "A doc that exists"
  - path: "docs/gone.md"
    description: "A doc that does not"
YAML
    run_ws realm use --trust realm-fixture
    [ "$status" -eq 0 ] || return 1
}

fixture_all_present() {
    mkdir -p "$WORK/components/demo/.git" "$WORK/components/demo/docs"
    printf '# real\n' > "$WORK/components/demo/docs/real.md"
    mkdir -p "$WORK/realms/realm-fixture/adapters"
    printf 'components: {}\n' > "$WORK/realms/realm-fixture/ecosystem.yaml"
    cat > "$WORK/realms/realm-fixture/adapters/demo.yaml" <<'YAML'
commands:
  test: "echo test"
ai_context:
  - path: "docs/real.md"
    description: "A doc that exists"
YAML
    run_ws realm use --trust realm-fixture
    [ "$status" -eq 0 ] || return 1
}

@test "ws orient --check: fails when an ai_context pointer no longer resolves" {
    fixture_mixed

    run_orient --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/gone.md"* ]]
}

@test "ws orient --check: names how many pointers rotted" {
    fixture_mixed

    run_orient --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"1 adapter ai_context pointer"* ]]
}

@test "ws orient --check: succeeds when every pointer resolves" {
    fixture_all_present

    run_orient --check

    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/real.md"* ]]
}

@test "ws orient --check: succeeds on a workspace declaring no ai_context at all" {
    # The common case. A check that treated "nothing declared" as "nothing
    # verified, therefore fail" would make the flag unusable everywhere else.
    mkdir -p "$WORK/components/bare/.git" "$WORK/realms/realm-fixture/adapters"
    printf 'components: {}\n' > "$WORK/realms/realm-fixture/ecosystem.yaml"
    cat > "$WORK/realms/realm-fixture/adapters/bare.yaml" <<'YAML'
commands:
  test: "echo bare"
YAML
    run_ws realm use --trust realm-fixture
    [ "$status" -eq 0 ]

    run_orient --check

    [ "$status" -eq 0 ]
}

@test "ws orient --check: a path that escapes the component counts as rot" {
    # INVALID PATH and MISSING are different diagnoses but the same problem for
    # a gate: the pointer cannot be followed. Pinned because an implementation
    # that only counted "missing" would pass an adapter full of traversal.
    mkdir -p "$WORK/components/demo/.git" "$WORK/realms/realm-fixture/adapters"
    printf '# outside\n' > "$WORK/outside.md"
    printf 'components: {}\n' > "$WORK/realms/realm-fixture/ecosystem.yaml"
    cat > "$WORK/realms/realm-fixture/adapters/demo.yaml" <<'YAML'
commands:
  test: "echo test"
ai_context:
  - path: "../../outside.md"
    description: "Must stay inside the component"
YAML
    run_ws realm use --trust realm-fixture
    [ "$status" -eq 0 ]

    run_orient --check

    [ "$status" -eq 1 ]
}

@test "ws orient: stays exit-zero on a dead pointer without --check" {
    # The default contract. Orient is the session-start command; making it fail
    # on doc rot would turn every orientation into a blocked start.
    fixture_mixed

    run_orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"(MISSING)"* ]]
}

@test "ws orient: rejects an unknown option" {
    run_orient --bogus

    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}
