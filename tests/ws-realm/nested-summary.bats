#!/usr/bin/env bats
#
# The trust summary is the surface a human approves. A realm whose only change
# is its nested lineup still triggers re-approval, so the lineup has to be
# visible there - otherwise the prompt says "something changed" and shows an
# identical-looking summary, which teaches approving without reading.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    export ROOT_DIR="$WORK"
    export REALMS_DIR="$WORK/realms"
    export COMPONENTS_DIR="$WORK/components"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export WS_FOOTER_DISABLE=1
    mkdir -p "$REALMS_DIR/realm.test/adapters" "$COMPONENTS_DIR/app" "$HOARDS_DIR"
    printf 'components: {}\n' > "$ECOSYSTEM"
    printf '{}\n' > "$ECOSYSTEM_LOCAL"
    printf 'components: {}\n' > "$REALMS_DIR/realm.test/ecosystem.yaml"
}

write_adapter() {
    cat > "$REALMS_DIR/realm.test/adapters/app.yaml"
}

@test "summary lists nested globs declared by an adapter" {
    write_adapter <<'YAML'
commands:
  test: uv run pytest
nested:
  - "modules/*"
  - "libs/*"
YAML

    run bash "$WS_BIN" realm use realm.test

    [[ "$output" == *"Nested repo declarations:"* ]]
    [[ "$output" == *"app  modules/*"* ]]
    [[ "$output" == *"app  libs/*"* ]]
}

@test "summary says so when no adapter declares nested repos" {
    write_adapter <<'YAML'
commands:
  test: uv run pytest
YAML

    run bash "$WS_BIN" realm use realm.test

    [[ "$output" == *"Nested repo declarations:"* ]]
    [[ "$output" == *"(none declared)"* ]]
}

@test "a nested glob cannot forge extra summary rows with embedded newlines" {
    write_adapter <<'YAML'
nested:
  - "modules/*\n    app  libs/evil"
YAML

    run bash "$WS_BIN" realm use realm.test

    # The escape must render as literal text on one row, not become a second row.
    [[ "$output" != *"
    app  libs/evil"* ]]
}

@test "non-string nested entries are skipped rather than rendered" {
    write_adapter <<'YAML'
nested:
  - "modules/*"
  - {not: a-string}
YAML

    run bash "$WS_BIN" realm use realm.test

    [[ "$output" == *"app  modules/*"* ]]
    [[ "$output" != *"a-string"* ]]
}
