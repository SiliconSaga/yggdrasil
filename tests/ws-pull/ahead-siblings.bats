#!/usr/bin/env bats
#
# Regression cover for the failure that let a release get cut from stale source:
# a fork-cloned component tracks its FORK, so `ws pull` follows the fork and
# reports "Already up to date" while the canonical upstream sits ahead. The
# checkout looks current and isn't.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    UPSTREAM="$BATS_TEST_TMPDIR/upstream.git"
    FORK="$BATS_TEST_TMPDIR/fork.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    export ROOT_DIR="$WORK"
    export REALMS_DIR="$WORK/realms"
    export COMPONENTS_DIR="$WORK/components"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    mkdir -p "$WORK/scripts" "$REALMS_DIR" "$COMPONENTS_DIR" "$HOARDS_DIR"
    cp "$REPO_ROOT/scripts/ws-pull.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"
    PULL_BIN="$WORK/scripts/ws-pull.sh"
    printf 'components:\n  app:\n    repo: %s\n' "$UPSTREAM" > "$ECOSYSTEM"
    printf 'notes: keep\n' > "$ECOSYSTEM_LOCAL"

    # Seed a canonical repo, then a fork of it at the same commit.
    git init -q "$SEED"
    git -C "$SEED" config user.name "Test Author"
    git -C "$SEED" config user.email "author@example.test"
    printf 'v1\n' > "$SEED/app.txt"
    git -C "$SEED" add app.txt
    git -C "$SEED" commit -q -m "seed"
    git clone -q --bare "$SEED" "$UPSTREAM"
    git clone -q --bare "$SEED" "$FORK"
    git -C "$SEED" remote add upstream "$UPSTREAM"

    # Clone the FORK — this is what ws clone-fork produces, so local main
    # tracks the fork and the canonical remote is a second, untracked remote.
    git clone -q "$FORK" "$COMPONENTS_DIR/app"
    git -C "$COMPONENTS_DIR/app" remote rename origin fork
    git -C "$COMPONENTS_DIR/app" remote add canonical "$UPSTREAM"
    git -C "$COMPONENTS_DIR/app" config user.name "Test User"
    git -C "$COMPONENTS_DIR/app" config user.email "user@example.test"
    git -C "$COMPONENTS_DIR/app" branch --set-upstream-to=fork/main main 2>/dev/null \
        || git -C "$COMPONENTS_DIR/app" branch --set-upstream-to=fork/master master
}

advance_upstream() {
    printf '%s\n' "$1" > "$SEED/app.txt"
    git -C "$SEED" add app.txt
    git -C "$SEED" commit -q -m "$1"
    git -C "$SEED" push -q upstream HEAD
}

@test "pull highlights a canonical remote that is ahead of the tracked fork" {
    advance_upstream "v2"

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    # The pull itself legitimately succeeds against the fork...
    [[ "$output" == *"PULL: app"* ]]
    # ...but the untracked canonical remote must be surfaced.
    [[ "$output" == *"AHEAD: canonical/"* ]]
    [[ "$output" == *"1 commit(s) ahead"* ]]
    [[ "$output" == *"ws clone-fork app"* ]]
}

@test "pull counts multiple commits the canonical remote is ahead by" {
    advance_upstream "v2"
    advance_upstream "v3"

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" == *"2 commit(s) ahead"* ]]
}

@test "pull stays quiet when the canonical remote matches the tracked fork" {
    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL: app"* ]]
    [[ "$output" != *"AHEAD:"* ]]
}

@test "pull stays quiet when the fork is ahead of canonical" {
    # The ordinary in-progress case: local work pushed to the fork only.
    printf 'local\n' > "$COMPONENTS_DIR/app/app.txt"
    git -C "$COMPONENTS_DIR/app" add app.txt
    git -C "$COMPONENTS_DIR/app" commit -q -m "local work"
    git -C "$COMPONENTS_DIR/app" push -q fork HEAD

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" != *"AHEAD:"* ]]
}

@test "an unreachable extra remote does not fail the pull" {
    git -C "$COMPONENTS_DIR/app" remote add broken "$BATS_TEST_TMPDIR/does-not-exist.git"
    advance_upstream "v2"

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" == *"AHEAD: canonical/"* ]]
}
