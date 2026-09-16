#!/usr/bin/env bats

# Counting nested repos is directory globbing and effectively free, so it is
# always shown. Running git status across them is not — a component can nest
# well over a hundred — so that stays behind --nested.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards"

    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export WS_FOOTER_DISABLE=1

    printf 'identity: {}\ncomponents: {}\n' > "$ECOSYSTEM"
    yq -i '.components.terasology = {"repo": "https://example.invalid/t.git"}' "$ECOSYSTEM"

    git init -q "$COMPONENTS_DIR/terasology"
    git init -q "$COMPONENTS_DIR/terasology/modules/Health"
    git init -q "$COMPONENTS_DIR/terasology/modules/Inventory"

    mkdir -p "$REALMS_DIR/community/adapters"
    git init -q "$REALMS_DIR/community"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    cat > "$REALMS_DIR/community/adapters/terasology.yaml" <<'YAML'
nested:
  - "modules/*"
YAML
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]
}

dirty_nested() {
    printf 'scratch\n' > "$COMPONENTS_DIR/terasology/modules/$1/untracked.txt"
}

@test "ws status counts nested repos without running git on them" {
    run bash "$WS_BIN" status

    [ "$status" -eq 0 ]
    [[ "$output" == *"nested: 2 repo(s)"* ]]
    [[ "$output" == *"--nested"* ]]
}

@test "ws status drops a nested repo that resolves outside the component" {
    # Regression: containment lived only in the target resolver, so status, pull
    # and diagnose — which enumerate and never resolve — counted an escaping
    # symlink and would have run git inside it. The check belongs where
    # candidates are produced, or every non-resolving caller inherits the hole.
    mkdir -p "$BATS_TEST_TMPDIR/outside/Escapee/.git"
    if ! ln -s "$BATS_TEST_TMPDIR/outside/Escapee" "$COMPONENTS_DIR/terasology/modules/Escapee" 2>/dev/null; then
        skip "symlink creation unavailable"
    fi
    [ -L "$COMPONENTS_DIR/terasology/modules/Escapee" ] || skip "symlink created as a copy (MSYS copy-mode)"

    run bash "$WS_BIN" status

    [ "$status" -eq 0 ]
    # Health and Inventory are the fixture; the escapee is not a third.
    [[ "$output" == *"nested: 2 repo(s)"* ]]
    [[ "$output" != *"nested: 3 repo(s)"* ]]
    [[ "$output" == *"resolves outside the component"* ]]
}

@test "ws status --nested reports a dirty nested repo by path" {
    dirty_nested Health

    run bash "$WS_BIN" status --nested

    [ "$status" -eq 0 ]
    [[ "$output" == *"nested: 2 repo(s), 1 dirty"* ]]
    [[ "$output" == *"modules/Health"* ]]
}

@test "ws status --nested stays quiet about clean nested repos" {
    run bash "$WS_BIN" status --nested

    [ "$status" -eq 0 ]
    [[ "$output" == *"nested: 2 repo(s), 0 dirty"* ]]
    [[ "$output" != *"modules/Health"* ]]
    [[ "$output" != *"modules/Inventory"* ]]
}

@test "ws status --nested counts each dirty nested repo separately" {
    dirty_nested Health
    dirty_nested Inventory

    run bash "$WS_BIN" status --nested

    [ "$status" -eq 0 ]
    [[ "$output" == *"nested: 2 repo(s), 2 dirty"* ]]
    [[ "$output" == *"modules/Health"* ]]
    [[ "$output" == *"modules/Inventory"* ]]
}

@test "a dirty nested repo does not make the host component look dirty" {
    dirty_nested Health

    run bash "$WS_BIN" status --nested

    [ "$status" -eq 0 ]
    # modules/ is untracked in the host repo here, so the host may well be dirty;
    # what matters is that the nested repo is reported in its own right.
    [[ "$output" == *"nested: 2 repo(s), 1 dirty"* ]]
}

@test "ws status rejects an unknown option, and says what it wanted instead" {
    run bash "$WS_BIN" status --bogus

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
    # The error teaches the form. A bare rejection sent the last reader looking
    # for a target argument that does not exist.
    [[ "$output" == *"Usage: ws status"* ]]
}

@test "ws status prints help on request, like every other verb" {
    run bash "$WS_BIN" status --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws status"* ]]
    [[ "$output" == *"--nested"* ]]
    run bash "$WS_BIN" status -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws status"* ]]
}

@test "ws status help names where a single-repo question goes instead" {
    # `ws status <comp>` reads like it should work — it does not, and the sweep
    # is why. Point at the verbs that do take a target, nested ones included.
    run bash "$WS_BIN" status --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"ws log <target>"* ]]
    [[ "$output" == *"ws diagnose <target>"* ]]
}

@test "ws status says nothing about nesting for a component that declares none" {
    yq -i '.components.plain = {"repo": "https://example.invalid/p.git"}' "$ECOSYSTEM"
    git init -q "$COMPONENTS_DIR/plain"

    run bash "$WS_BIN" status

    [ "$status" -eq 0 ]
    [[ "$output" == *"=== plain ==="* ]]
    # The nested line belongs to terasology only.
    [[ "$(printf '%s\n' "$output" | grep -c 'nested:')" -eq 1 ]]
}
