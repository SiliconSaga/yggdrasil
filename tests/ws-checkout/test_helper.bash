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

# A component whose "remote" is a local bare repository carrying a change
# request head ref, the shape GitHub exposes as refs/pull/<n>/head. The work
# branch that made the commit is deleted again, so the only way to reach
# CR_SHA is the ref.
setup_cr_fixture() {
    setup_component_repo
    CR_REMOTE="$BATS_TEST_TMPDIR/remote.git"
    git init -q --bare "$CR_REMOTE"
    git -C "$COMPONENTS_DIR/terasology" remote add origin "$CR_REMOTE"
    git -C "$COMPONENTS_DIR/terasology" push -q origin main
    publish_cr_head "$COMPONENTS_DIR/terasology" 7 "first change"
}

# Add a commit on top of main and publish it only as <ref> on the repo's
# origin (default: the GitHub pull-request ref). Sets CR_SHA. Calling it again
# for the same number moves the change request.
publish_cr_head() { # <repo> <number> <text> [<ref>]
    local repo="$1" number="$2" text="$3" ref="${4:-refs/pull/$2/head}"
    git -C "$repo" switch -q -c cr-work
    printf '%s\n' "$text" >> "$repo/cr.txt"
    git -C "$repo" add cr.txt
    git -C "$repo" commit -qm "$text"
    CR_SHA="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" push -q -f origin "HEAD:$ref"
    git -C "$repo" switch -q main
    git -C "$repo" branch -q -D cr-work
}

# The nested shape with a change request on the module's own origin.
setup_nested_cr_fixture() {
    setup_nested_component
    local mod="$COMPONENTS_DIR/terasology/modules/Cooking"
    MOD_REMOTE="$BATS_TEST_TMPDIR/cooking.git"
    git init -q --bare "$MOD_REMOTE"
    git -C "$mod" remote add origin "$MOD_REMOTE"
    git -C "$mod" push -q origin main
    publish_cr_head "$mod" 3 "module change"
}

# Make the fixture's origin look like a GitLab remote without any network: the
# remote URL says gitlab.com, and git's url.<base>.insteadOf rewrites it to the
# local bare repo for every fetch. Provider detection reads the URL; git reads
# the rewrite.
make_origin_gitlab() { # <repo>
    git -C "$1" remote set-url origin "https://gitlab.com/group/terasology.git"
    git -C "$1" config url."$CR_REMOTE".insteadOf "https://gitlab.com/group/terasology.git"
}
