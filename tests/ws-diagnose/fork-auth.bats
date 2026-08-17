#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    MAIN="$WORK/main"
    LINKED="$WORK/linked"
    mkdir -p "$MAIN" "$WORK/components"
    git init -q "$MAIN"
    git -C "$MAIN" config user.name "T"
    git -C "$MAIN" config user.email "t@example.local"
    git -C "$MAIN" commit -q --allow-empty -m seed
    git -C "$MAIN" worktree add -q -b topic "$LINKED"
    ln -s "$LINKED" "$WORK/components/demo"
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
    export WS_FOOTER_DISABLE=1
}

@test "ws diagnose recognizes a linked worktree" {
    run env GITLAB_SOURCE_TOKEN=fake-token bash "$WS_BIN" diagnose demo --no-api-check

    [ "$status" -eq 0 ]
    [[ "$output" == *"Clone          : ✓ present (branch: topic)"* ]]
    [[ "$output" != *"not cloned"* ]]
}

@test "ws diagnose explains authentication is not authorization" {
    run env GITLAB_SOURCE_TOKEN=fake-token bash "$WS_BIN" diagnose demo --no-api-check

    [ "$status" -eq 0 ]
    [[ "$output" == *"does not prove push, fork, or CR authorization"* ]]
}

@test "ws diagnose warns when the configured fork remote is absent" {
    run env GITLAB_SOURCE_TOKEN=fake-token bash "$WS_BIN" diagnose demo --no-api-check

    [ "$status" -eq 0 ]
    [[ "$output" == *"configured fork remote 'realdev-forks' is not present"* ]]
    [[ "$output" == *"ws clone-fork demo"* ]]
}
