#!/usr/bin/env bats
#
# Fork-and-PR for a repo nested inside a component. The checkout already exists
# and the host project's tooling owns it, so this path must adopt in place -
# never clone, and never read ecosystem config for an upstream a module does
# not have an entry in.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    CLONE_FORK_BIN="$REPO_ROOT/scripts/ws-clone-fork.sh"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_BIN"

    # Fail the provider call loudly, so a test that reaches the network stage
    # still ends deterministically and we can assert on what was derived first.
    cat > "$TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "STUB-GH-CALLED $*" >&2
exit 1
SH
    chmod +x "$TEST_BIN/gh"
    export PATH="$TEST_BIN:$PATH"

    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards"
    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export WS_FOOTER_DISABLE=1
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
    export GH_TOKEN="stub-token"

    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: dev
  forkRemote: ForkHome
  homes:
    fork:
      namespace: ForkHome
components:
  terasology:
    repo: https://github.com/MovingBlocks/Terasology.git
YAML
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"

    mkdir -p "$REALMS_DIR/community/adapters" "$REALMS_DIR/community/.git"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    printf 'nested:\n  - "modules/*"\n' > "$REALMS_DIR/community/adapters/terasology.yaml"
    mkdir -p "$COMPONENTS_DIR/terasology"
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]
}

make_nested_repo() {
    local origin_url="$1"
    local dir="$COMPONENTS_DIR/terasology/modules/Cooking"
    mkdir -p "$dir"
    git -C "$dir" init -q -b develop
    git -C "$dir" config user.email "t@example.invalid"
    git -C "$dir" config user.name "T"
    [[ -n "$origin_url" ]] && git -C "$dir" remote add origin "$origin_url"
    printf '%s\n' "$dir"
}

@test "refuses --add-to-ecosystem for a nested target" {
    make_nested_repo "https://github.com/Terasology/Cooking.git" >/dev/null

    run bash "$CLONE_FORK_BIN" terasology/modules/Cooking --add-to-ecosystem

    # Caught by the existing --add-to-ecosystem/--url pairing rule, which a
    # nested target does not change. Asserted so a future refactor that moves
    # nested resolution earlier cannot quietly let the combination through.
    [ "$status" -ne 0 ]
    [[ "$output" == *"--add-to-ecosystem only applies with --url"* ]]
}

@test "explains itself when the nested repo has no origin" {
    make_nested_repo "" >/dev/null

    run bash "$CLONE_FORK_BIN" terasology/modules/Cooking

    [ "$status" -ne 0 ]
    [[ "$output" == *"has no 'origin' remote"* ]]
}

@test "refuses when origin already points into the fork home" {
    make_nested_repo "https://github.com/ForkHome/Cooking.git" >/dev/null

    run bash "$CLONE_FORK_BIN" terasology/modules/Cooking

    [ "$status" -ne 0 ]
    [[ "$output" == *"already points into the fork home"* ]]
}

@test "derives the upstream from origin rather than ecosystem config" {
    make_nested_repo "https://github.com/Terasology/Cooking.git" >/dev/null

    run bash "$CLONE_FORK_BIN" terasology/modules/Cooking

    # It must reach the provider stage naming the module's own upstream. If it
    # had fallen back to ecosystem config it would be talking about Terasology
    # the component (MovingBlocks/Terasology), which is a different repo.
    [[ "$output" == *"Terasology/Cooking"* ]]
    [[ "$output" != *"MovingBlocks/Terasology.git"* ]]
}

@test "refuses an undeclared nested repo" {
    run bash "$CLONE_FORK_BIN" terasology/modules/Ghost

    [ "$status" -ne 0 ]
}
