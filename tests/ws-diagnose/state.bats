#!/usr/bin/env bats
#
# `ws diagnose` answers "is this ready to send, and against what?" — so it has
# to report working-tree and branch state, not just remotes and tokens. These
# are the questions actually being asked when it is run before a push or CR.

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

    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: realdev
components:
  app:
    repo: https://example.invalid/app.git
YAML
    printf '{}\n' > "$ECOSYSTEM_LOCAL"
}

make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "t@example.invalid"
    git -C "$dir" config user.name "T"
    printf 'seed\n' > "$dir/seed.txt"
    git -C "$dir" add seed.txt
    git -C "$dir" commit -qm seed
}

run_diagnose() {
    run env -u GH_TOKEN -u GITHUB_TOKEN bash "$WS_BIN" diagnose "$@" --no-api-check
}

@test "reports a clean working tree" {
    make_repo "$COMPONENTS_DIR/app"

    run_diagnose app

    [[ "$output" == *"Working tree   : ✓ clean"* ]]
}

@test "counts uncommitted changes" {
    make_repo "$COMPONENTS_DIR/app"
    printf 'edited\n' > "$COMPONENTS_DIR/app/seed.txt"
    printf 'new\n' > "$COMPONENTS_DIR/app/extra.txt"

    run_diagnose app

    [[ "$output" == *"2 uncommitted change(s)"* ]]
}

@test "says so when the branch has no upstream" {
    make_repo "$COMPONENTS_DIR/app"

    run_diagnose app

    [[ "$output" == *"Tracking       : none"* ]]
}

@test "reports the tracking branch with divergence both ways" {
    make_repo "$BATS_TEST_TMPDIR/upstream"
    git clone -q "$BATS_TEST_TMPDIR/upstream" "$COMPONENTS_DIR/app"
    git -C "$COMPONENTS_DIR/app" config user.email "t@example.invalid"
    git -C "$COMPONENTS_DIR/app" config user.name "T"

    # One commit only we have, one only the upstream has.
    printf 'ours\n' > "$COMPONENTS_DIR/app/ours.txt"
    git -C "$COMPONENTS_DIR/app" add ours.txt
    git -C "$COMPONENTS_DIR/app" commit -qm ours
    printf 'theirs\n' > "$BATS_TEST_TMPDIR/upstream/theirs.txt"
    git -C "$BATS_TEST_TMPDIR/upstream" add theirs.txt
    git -C "$BATS_TEST_TMPDIR/upstream" commit -qm theirs
    git -C "$COMPONENTS_DIR/app" fetch -q origin

    run_diagnose app

    [[ "$output" == *"ahead 1, behind 1"* ]]
}

@test "counts nested repos for a host component without status-sweeping them" {
    make_repo "$COMPONENTS_DIR/app"
    make_repo "$COMPONENTS_DIR/app/modules/Alpha"
    make_repo "$COMPONENTS_DIR/app/modules/Beta"

    mkdir -p "$REALMS_DIR/community/adapters" "$REALMS_DIR/community/.git"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    printf 'nested:\n  - "modules/*"\n' > "$REALMS_DIR/community/adapters/app.yaml"
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]

    run_diagnose app

    [[ "$output" == *"Nested repos   : 2"* ]]
    [[ "$output" == *"ws status app --nested"* ]]
}

@test "omits the nested line for a component that declares none" {
    make_repo "$COMPONENTS_DIR/app"

    run_diagnose app

    [[ "$output" != *"Nested repos"* ]]
}
