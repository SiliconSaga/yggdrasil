#!/usr/bin/env bats

# `ws diagnose` is run when a push or CR failed, and the two things it most
# often needs to say are: the fork remote your identity is configured to push
# to is not on this clone, and a valid token is not the same as permission.
# Both are diagnosable offline, which is why they belong here rather than in
# the failing verb's error path.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    MAIN="$WORK/main"
    LINKED="$WORK/components/demo"
    mkdir -p "$MAIN" "$WORK/components" "$WORK/realms"
    git init -q "$MAIN"
    git -C "$MAIN" config user.name "T"
    git -C "$MAIN" config user.email "t@example.local"
    git -C "$MAIN" commit -q --allow-empty -m seed
    # A linked worktree: its .git is a FILE, which a directory-only clone check
    # once reported as "not cloned".
    git -C "$MAIN" worktree add -q -b topic "$LINKED"
    git -C "$MAIN" remote add upstream https://git.example.com/source/demo.git
    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  gitProviders:
    git.example.com: gitlab
  gitTokens:
    git.example.com/source: GITLAB_SOURCE_TOKEN
components:
  demo:
    tier: supporting
    repo: https://git.example.com/source/demo.git
identity:
  human_account: realdev
  forkRemote: realdev-forks
YAML
    export ROOT_DIR="$WORK"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export WS_FOOTER_DISABLE=1
}

run_diagnose() {
    run env GITLAB_SOURCE_TOKEN=fake-token bash "$WS_BIN" diagnose "$@" --no-api-check
}

@test "ws diagnose recognizes a linked worktree as a clone" {
    run_diagnose demo

    [ "$status" -eq 0 ]
    [[ "$output" == *"Clone          : ✓ present (branch: topic)"* ]]
    [[ "$output" != *"not cloned"* ]]
}

@test "ws diagnose explains that authentication is not authorization" {
    run_diagnose demo

    [ "$status" -eq 0 ]
    [[ "$output" == *"Authorization:"* ]]
    [[ "$output" == *"proves authentication only"* ]]
    [[ "$output" == *"does not prove push, fork, or CR authorization"* ]]
}

@test "ws diagnose warns when the configured fork remote is absent" {
    run_diagnose demo

    [ "$status" -eq 0 ]
    [[ "$output" == *"configured fork remote 'realdev-forks' is not present"* ]]
    [[ "$output" == *"ws clone-fork demo"* ]]
}

@test "ws diagnose drops the warning once the fork remote is present" {
    git -C "$LINKED" remote add realdev-forks https://git.example.com/realdev/demo.git

    run_diagnose demo

    [ "$status" -eq 0 ]
    [[ "$output" == *"realdev-forks"*"push/cr remote (identity.forkRemote)"* ]]
    [[ "$output" != *"is not present"* ]]
}

@test "ws diagnose does not classify a nested plain directory as a clone" {
    git -C "$MAIN" worktree remove --force "$LINKED"
    git init -q "$WORK/components"
    mkdir -p "$WORK/components/demo"

    run_diagnose demo

    [ "$status" -eq 0 ]
    [[ "$output" == *"Clone          : ✗ not cloned"* ]]
}

@test "ws diagnose does not suggest clone-fork for a realm" {
    git init -q "$WORK/realms/demo-realm"
    git -C "$WORK/realms/demo-realm" remote add upstream https://git.example.com/source/demo-realm.git

    run_diagnose demo-realm

    [ "$status" -eq 0 ]
    [[ "$output" != *"configured fork remote"* ]]
    [[ "$output" != *"ws clone-fork demo-realm"* ]]
}
