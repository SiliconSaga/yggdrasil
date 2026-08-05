# Shared helpers for ws-hoard-init bats tests.
#
# Each test gets a fresh isolated workspace under $BATS_TEST_TMPDIR with:
#   - HOARDS_DIR     — empty hoards/ dir
#   - TEMPLATES_DIR  — points at <repo>/templates by default; tests that
#                      exercise yaml-driven flows override it to point
#                      at fixtures/templates/ so they can use synthetic
#                      template.yaml manifests.
#   - ECOSYSTEM      — minimal upstream ecosystem.yaml
#   - ECOSYSTEM_LOCAL — provides identity.human_account so
#                       ws_resolve_human_account() succeeds without
#                       reading the real workspace's ecosystem.local.yaml
#
# Tests invoke ws-hoard.sh directly (not the `ws` wrapper) so the env
# var overrides above propagate cleanly.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_HOARD_BIN="$REPO_ROOT/scripts/ws-hoard.sh"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

# Set up an isolated workspace for one test. Must be called from setup().
# After this returns:
#   $WORK     — root of the isolated workspace
#   $HOARDS_DIR, $TEMPLATES_DIR, $ECOSYSTEM, $ECOSYSTEM_LOCAL — exported
init_workspace() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/hoards" "$WORK/realms"

    # Default to the real templates dir so the standard cp -R flow can
    # be tested against the actually-shipped obsidian-vault template.
    # Tests that need synthetic templates overwrite TEMPLATES_DIR after
    # calling init_workspace.
    export HOARDS_DIR="$WORK/hoards"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export TEMPLATES_DIR="$REPO_ROOT/templates"
    export ROOT_DIR="$WORK"

    # Minimal upstream ecosystem (avoid pulling in the real one which
    # would resolve realm overlays and slow tests).
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: ""
components: {}
YAML

    # Local override providing identity.human_account
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML

    # Force HOSTNAME so ws_resolve_machine_name() is deterministic.
    export HOSTNAME="testhost"

    # Skip the upgrade phase that ws hoard init runs after copying a
    # template. Upgrade hits GitHub releases for plugin downloads,
    # which makes the standard-flow tests network-bound and flaky.
    # The upgrade flow has its own targeted tests; init tests assert
    # only the scaffold + git-init behavior.
    export WS_HOARD_NO_UPGRADE=1
}

# Build a bare git repo with a single seed commit and echo its file:// URL.
# Used as a synthetic upstream for yaml-driven init tests so they don't
# touch the network.
make_bare_upstream() {
    local name="${1:-upstream}"
    local bare="$BATS_TEST_TMPDIR/${name}.git"
    local seed="$BATS_TEST_TMPDIR/${name}-seed"
    # Force the bare repo's HEAD to `main` so it matches the branch the seed
    # pushes below (`git branch -M main`). Without --initial-branch, `git init
    # --bare` sets HEAD to the host git's default branch — which on machines
    # that haven't set init.defaultBranch=main is still `master`. The bare
    # would then advertise HEAD -> refs/heads/master (nonexistent), and
    # `git clone` would emit "remote HEAD refers to nonexistent ref" and check
    # out an empty tree, failing the yaml-flow tests on those machines only.
    git init -q --bare --initial-branch=main "$bare"
    git init -q "$seed"
    (
        cd "$seed"
        git -c user.name=seed -c user.email=seed@local commit \
            --allow-empty -q -m "seed"
        # Add a file so the resulting clone is non-empty
        echo "# $name" > README.md
        git add README.md
        git -c user.name=seed -c user.email=seed@local commit \
            -q -m "add README"
        git branch -M main
        git remote add origin "$bare"
        git push -q origin main
    )
    echo "file://$bare"
}

bare_head_for_url() {
    local url="$1"
    git --git-dir="${url#file://}" rev-parse refs/heads/main
}

# Run ws-hoard.sh init with the propagating env. Args are forwarded.
run_hoard_init() {
    run bash "$WS_HOARD_BIN" init "$@"
}

declare_component() {
    local name="$1"
    COMPONENT_NAME="$name" yq -i '.components[strenv(COMPONENT_NAME)] = {"repo": "https://example.invalid/repo.git"}' "$ECOSYSTEM"
}

create_realm() {
    mkdir -p "$REALMS_DIR/$1/.git"
}

install_failing_git() {
    local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
echo "UNEXPECTED GIT INVOCATION: $*" >&2
exit 99
SH
    chmod +x "$fake_bin/git"
    export PATH="$fake_bin:$PATH"
}

run_hoard_clone() {
    run bash "$WS_HOARD_BIN" "$@"
}
