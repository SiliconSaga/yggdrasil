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

git_in() {
    local dir="$1"; shift
    git -C "$dir" "$@"
}

# A real repo whose trunk is named by the caller - the point of several of these
# tests is that the trunk is not always called "main".
make_repo() {
    local dir="$1" trunk="${2:-main}"
    mkdir -p "$dir"
    git -C "$dir" init -q -b "$trunk"
    git -C "$dir" config user.email "test@example.invalid"
    git -C "$dir" config user.name "Test"
    printf 'seed\n' > "$dir/seed.txt"
    git -C "$dir" add seed.txt
    git -C "$dir" commit -qm "seed"
}

commit_in() {
    local dir="$1" message="$2" file="${3:-work.txt}"
    printf '%s\n' "$message" >> "$dir/$file"
    git -C "$dir" add "$file"
    git -C "$dir" commit -qm "$message"
}

# A component whose trunk is `develop` and which has a topic branch ahead of it -
# the Terasology shape, and the one the old main/master-only detection could not
# handle at all.
setup_develop_component() {
    declare_component app
    make_repo "$COMPONENTS_DIR/app" develop
    git_in "$COMPONENTS_DIR/app" switch -q -c feature/x
    commit_in "$COMPONENTS_DIR/app" "first"
    commit_in "$COMPONENTS_DIR/app" "second"
}
