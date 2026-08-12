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

clone_component() {
    mkdir -p "$COMPONENTS_DIR/$1"
}

create_realm() {
    mkdir -p "$REALMS_DIR/$1/.git"
}

create_hoard() {
    mkdir -p "$HOARDS_DIR/$1/.git"
}

run_ws() {
    run bash "$WS_BIN" "$@"
}

create_nested_repo() {
    mkdir -p "$COMPONENTS_DIR/$1/$2/.git"
}

add_nested_glob() {
    local comp="$1" glob="$2"
    NESTED_GLOB="$glob" yq -i '.nested += [strenv(NESTED_GLOB)]' \
        "$REALMS_DIR/community/adapters/$comp.yaml"
    approve_nested_realm
}

approve_nested_realm() {
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]
}

# A component that declares nested repos, with one present and the realm
# approved — the shape Terasology's modules/ actually has.
setup_nested_component() {
    declare_component terasology
    clone_component terasology
    create_nested_repo terasology modules/Health

    mkdir -p "$REALMS_DIR/community/adapters" "$REALMS_DIR/community/.git"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    cat > "$REALMS_DIR/community/adapters/terasology.yaml" <<'YAML'
nested:
  - "modules/*"
YAML
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"
    approve_nested_realm
}
