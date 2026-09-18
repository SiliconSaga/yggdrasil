#!/usr/bin/env bats

# `ws clone` makes a blobless partial clone by default and lets
# WS_CLONE_FILTER override or disable the filter. A stub git records the argv
# it received, so the tests assert the exact clone command rather than the
# result of a real clone.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/workspace"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    GIT_LOG="$BATS_TEST_TMPDIR/git.log"
    mkdir -p "$WORK/scripts" "$WORK/components" "$WORK/realms" "$TEST_BIN"
    cp "$REPO_ROOT/scripts/ws-clone.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"

    cat > "$TEST_BIN/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "hash-object" ]]; then
    [[ "${2:-}" == "--stdin" ]] && { cat >/dev/null 2>&1 || true; }
    printf '%s\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    exit 0
fi
printf '%s\n' "$*" >> "$GIT_LOG"
exit 0
SH
    chmod +x "$TEST_BIN/git"
    export PATH="$TEST_BIN:$PATH"
    export GIT_LOG
    unset WS_CLONE_FILTER

    SOURCE="$BATS_TEST_TMPDIR/source"
    mkdir -p "$SOURCE"
    printf 'components: {}\n' > "$WORK/ecosystem.yaml"
}

@test "clone is blobless by default" {
    run bash "$WORK/scripts/ws-clone.sh" --url "$SOURCE" --name widget
    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone --filter=blob:none --origin "* ]]
}

@test "WS_CLONE_FILTER= (empty) makes a full clone" {
    WS_CLONE_FILTER='' run bash "$WORK/scripts/ws-clone.sh" --url "$SOURCE" --name widget
    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone --origin "* ]]
    [[ "$(<"$GIT_LOG")" != *"--filter"* ]]
}

@test "WS_CLONE_FILTER passes another filter spec through" {
    WS_CLONE_FILTER=tree:0 run bash "$WORK/scripts/ws-clone.sh" --url "$SOURCE" --name widget
    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone --filter=tree:0 --origin "* ]]
}

@test "a declared component clones blobless too" {
    # A declared repo is validated as a remote, so a local path would be
    # refused here; the stub git never contacts the URL.
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: https://github.com/example/widget.git
YAML
    run bash "$WORK/scripts/ws-clone.sh" widget
    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone --filter=blob:none --origin "* ]]
}
