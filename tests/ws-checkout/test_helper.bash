REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

init_workspace() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards"

    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export WS_FOOTER_DISABLE=1

    cat > "$ECOSYSTEM" <<'YAML'
identity: {}
components: {}
YAML
    printf '{}\n' > "$ECOSYSTEM_LOCAL"
}

declare_component() {
    local name="$1"
    COMPONENT_NAME="$name" yq -i '.components[strenv(COMPONENT_NAME)] = {"repo": "https://example.invalid/repo.git"}' "$ECOSYSTEM"
}

run_ws() {
    run bash "$WS_BIN" "$@"
}

# A real git repo, not a bare .git directory - these tests assert on actual
# branch state, so the fixtures have to be something git will operate on.
make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "test@example.invalid"
    git -C "$dir" config user.name "Test"
    printf 'seed\n' > "$dir/seed.txt"
    git -C "$dir" add seed.txt
    git -C "$dir" commit -qm "seed"
}

current_branch() {
    git -C "$1" rev-parse --abbrev-ref HEAD
}

# A cloned component that is a real repo.
setup_component_repo() {
    declare_component terasology
    make_repo "$COMPONENTS_DIR/terasology"
}

# The Terasology shape: a component with real nested module repos, declared by
# glob in an approved realm adapter.
setup_nested_component() {
    setup_component_repo
    make_repo "$COMPONENTS_DIR/terasology/modules/Cooking"

    mkdir -p "$REALMS_DIR/community/adapters" "$REALMS_DIR/community/.git"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    cat > "$REALMS_DIR/community/adapters/terasology.yaml" <<'YAML'
nested:
  - "modules/*"
YAML
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]
}
