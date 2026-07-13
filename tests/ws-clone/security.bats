#!/usr/bin/env bats

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
printf '%s\n' "$*" >> "$GIT_LOG"
exit 0
SH
    chmod +x "$TEST_BIN/git"
    export PATH="$TEST_BIN:$PATH"
    export GIT_LOG
}

@test "declared component rejects a Git remote helper before git clone" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  unsafe:
    repo: ext::sh -c id
YAML

    run bash "$WORK/scripts/ws-clone.sh" unsafe

    [ "$status" -ne 0 ]
    [[ "$output" == *"remote helper"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "explicit URL mode rejects option-like repository values before git clone" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components: {}
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url --upload-pack=sh --name unsafe

    [ "$status" -ne 0 ]
    [[ "$output" == *"option-like"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "explicit URL mode retains intentional local clone support" {
    local source="$BATS_TEST_TMPDIR/source.git"
    mkdir -p "$source"
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components: {}
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url "$source" --name local-source

    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone"*"$source"* ]]
}

@test "template realm helper syntax is rejected before git clone" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  templateRealm: fd::7
components: {}
YAML

    run bash "$WORK/scripts/ws-realm.sh" init

    [ "$status" -ne 0 ]
    [[ "$output" == *"remote helper"* ]]
    [ ! -s "$GIT_LOG" ]
}
