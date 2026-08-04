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
