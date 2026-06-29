#!/usr/bin/env bats

# Tests for `ws push` argument parsing — the --remote flag and the
# comp_set sentinel parser (both added in PR #115).
#
# The adjacent push.bats tests exercise git-push.sh directly (HTTPS
# auth, tag behavior, upstream-tracking). This file covers the ws
# push arg parser: --remote flag in every position, equal-sign form,
# forkRemote fallback, and error paths.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    FORK_DIR="$BATS_TEST_TMPDIR/fork.git"
    ALT_DIR="$BATS_TEST_TMPDIR/siliconsaga.git"

    git init -q --bare "$FORK_DIR"
    git init -q --bare "$ALT_DIR"

    git init -q "$WORK"
    git -C "$WORK" config user.name "Test User"
    git -C "$WORK" config user.email "test@example.local"
    echo "seed" > "$WORK/file.txt"
    git -C "$WORK" add file.txt
    git -C "$WORK" commit -q -m "seed"
    git -C "$WORK" branch -M main
    git -C "$WORK" remote add fork "$FORK_DIR"
    git -C "$WORK" remote add siliconsaga "$ALT_DIR"

    cat > "$WORK/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
components: {}
YAML
    cat > "$WORK/ecosystem.local.yaml" <<'YAML'
identity:
  human_account: testuser
YAML

    export ROOT_DIR="$WORK"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
}

run_ws_push() {
    run env WS_FOOTER_DISABLE=1 bash "$WS_BIN" push "$@"
}

remote_has_ref() {   # $1=bare-dir $2=full-ref (e.g. refs/heads/main)
    git --git-dir="$1" show-ref --verify --quiet "$2"
}

# ─── --remote flag routing ──────────────────────────────────────────

@test "ws push --remote: option-first form overrides identity.forkRemote" {
    # Regression for the original parsing bug: comp was assigned the
    # flag name ("--remote") before the loop ran, so option-first
    # invocations silently used the wrong component.
    run_ws_push --remote siliconsaga
    [ "$status" -eq 0 ]
    remote_has_ref "$ALT_DIR" refs/heads/main
    ! remote_has_ref "$FORK_DIR" refs/heads/main
}

@test "ws push --remote: flag accepted between component and explicit branch" {
    run_ws_push yggdrasil --remote siliconsaga main
    [ "$status" -eq 0 ]
    remote_has_ref "$ALT_DIR" refs/heads/main
    ! remote_has_ref "$FORK_DIR" refs/heads/main
}

@test "ws push --remote=name: equal-sign form overrides forkRemote" {
    run_ws_push --remote=siliconsaga
    [ "$status" -eq 0 ]
    remote_has_ref "$ALT_DIR" refs/heads/main
}

@test "ws push: identity.forkRemote used when --remote not specified" {
    run_ws_push
    [ "$status" -eq 0 ]
    remote_has_ref "$FORK_DIR" refs/heads/main
    ! remote_has_ref "$ALT_DIR" refs/heads/main
}

@test "ws push yggdrasil main: explicit component + branch without --remote uses forkRemote" {
    run_ws_push yggdrasil main
    [ "$status" -eq 0 ]
    remote_has_ref "$FORK_DIR" refs/heads/main
    ! remote_has_ref "$ALT_DIR" refs/heads/main
}

# ─── --remote error paths ──────────────────────────────────────────

@test "ws push --remote: rejects next arg that starts with a dash" {
    # --force, --upstream, etc. are not remote names; the parser
    # checks that the following arg doesn't start with -.
    run_ws_push --remote --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"--remote requires a git remote name"* ]]
}

@test "ws push --remote=: empty value errors before any git call" {
    run_ws_push --remote=
    [ "$status" -ne 0 ]
    [[ "$output" == *"--remote requires a git remote name"* ]]
}

# ─── positional arg error paths ────────────────────────────────────

@test "ws push with three positional args errors" {
    # comp, branch, extra — three positionals trip the sentinel guard.
    run_ws_push comp branch extra
    [ "$status" -ne 0 ]
    [[ "$output" == *"Too many positional arguments"* ]]
}

@test "ws push with unknown option errors" {
    run_ws_push --unknown
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option '--unknown'"* ]]
}
