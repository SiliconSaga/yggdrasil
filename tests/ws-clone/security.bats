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

@test "explicit URL mode rejects a different repo under a declared component name" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: https://github.com/example/widget.git
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url https://github.com/attacker/widget.git --name widget

    [ "$status" -ne 0 ]
    [[ "$output" == *"declared component"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "explicit URL mode permits the declared repo under its component name" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: https://github.com/example/widget.git
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url git@github.com:example/widget.git --name widget

    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone"*"example/widget.git"* ]]
}

@test "explicit URL mode preserves non-default SSH ports in repository identity" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: ssh://git@github.example:22/example/widget.git
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url ssh://git@github.example:2222/example/widget.git --name widget

    [ "$status" -ne 0 ]
    [[ "$output" == *"declared component"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "explicit URL mode preserves meaningful SSH usernames in repository identity" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: ssh://alice@github.example:22/example/widget.git
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url ssh://bob@github.example:22/example/widget.git --name widget

    [ "$status" -ne 0 ]
    [[ "$output" == *"declared component"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "explicit URL mode permits default-port SSH for the declared HTTPS repo" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: https://github.example/example/widget.git
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url ssh://git@github.example:22/example/widget.git --name widget

    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone"*"example/widget.git"* ]]
}

@test "explicit URL mode rejects a defaults gitOrg repo collision" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  gitOrg: https://github.com/example
components:
  widget:
    tier: supporting
YAML

    run bash "$WORK/scripts/ws-clone.sh" --url https://github.com/attacker/widget.git --name widget

    [ "$status" -ne 0 ]
    [[ "$output" == *"declared component"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "explicit URL mode ignores an unapproved realm for a unique clone" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components: {}
YAML
    mkdir -p "$WORK/realms/realm-stale"
    cat > "$WORK/realms/realm-stale/ecosystem.yaml" <<'YAML'
components:
  realm-widget:
    repo: https://github.com/example/realm-widget.git
YAML
    cat > "$WORK/ecosystem.local.yaml" <<'YAML'
realm: realm-stale
YAML

    run env "ECOSYSTEM_LOCAL=$WORK/ecosystem.local.yaml" "REALMS_DIR=$WORK/realms" bash "$WORK/scripts/ws-clone.sh" --url https://github.com/example/unique.git --name unique

    [ "$status" -eq 0 ]
    [[ "$(<"$GIT_LOG")" == *"clone"*"example/unique.git"* ]]
}

@test "explicit URL mode still rejects a root declaration when realm trust is stale" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: https://github.com/example/widget.git
YAML
    mkdir -p "$WORK/realms/realm-stale"
    cat > "$WORK/realms/realm-stale/ecosystem.yaml" <<'YAML'
components: {}
YAML
    cat > "$WORK/ecosystem.local.yaml" <<'YAML'
realm: realm-stale
YAML

    run env "ECOSYSTEM_LOCAL=$WORK/ecosystem.local.yaml" "REALMS_DIR=$WORK/realms" bash "$WORK/scripts/ws-clone.sh" --url https://github.com/attacker/widget.git --name widget

    [ "$status" -ne 0 ]
    [[ "$output" == *"declared component"* ]]
    [ ! -s "$GIT_LOG" ]
}

@test "canonical ecosystem flag adds an explicit URL clone to local config" {
    local source="$BATS_TEST_TMPDIR/adopted-source.git"
    mkdir -p "$source"
    printf 'components: {}\n' > "$WORK/ecosystem.yaml"
    printf 'components: {}\n' > "$WORK/ecosystem.local.yaml"

    run env "ECOSYSTEM_LOCAL=$WORK/ecosystem.local.yaml" bash "$WORK/scripts/ws-clone.sh" --url "$source" --name adopted-source --add-to-ecosystem

    [ "$status" -eq 0 ]
    [ "$(yq -r '.components."adopted-source".tier' "$WORK/ecosystem.local.yaml")" = "supporting" ]
    local expected_repo
    if command -v realpath >/dev/null 2>&1; then
        expected_repo="$(realpath "$source")"
    else
        expected_repo="$(cd "$(dirname "$source")" && pwd)/$(basename "$source")"
    fi
    # The stored form is pinned to the native mixed form on Git Bash
    # (cygpath -m via ws_native_path); elsewhere it stays POSIX.
    if command -v cygpath >/dev/null 2>&1; then
        expected_repo="$(cygpath -m "$expected_repo")"
    fi
    [ "$(yq -r '.components."adopted-source".repo' "$WORK/ecosystem.local.yaml")" = "$expected_repo" ]
}

@test "compatibility ecosystem flag retains the canonical adoption behavior" {
    local source="$BATS_TEST_TMPDIR/adopted-alias.git"
    mkdir -p "$source"
    printf 'components: {}\n' > "$WORK/ecosystem.yaml"
    printf 'components: {}\n' > "$WORK/ecosystem.local.yaml"

    run env "ECOSYSTEM_LOCAL=$WORK/ecosystem.local.yaml" bash "$WORK/scripts/ws-clone.sh" --url "$source" --name adopted-alias --add-eco

    [ "$status" -eq 0 ]
    [ "$(yq -r '.components."adopted-alias".tier' "$WORK/ecosystem.local.yaml")" = "supporting" ]
    local expected_repo
    if command -v realpath >/dev/null 2>&1; then
        expected_repo="$(realpath "$source")"
    else
        expected_repo="$(cd "$(dirname "$source")" && pwd)/$(basename "$source")"
    fi
    # The stored form is pinned to the native mixed form on Git Bash
    # (cygpath -m via ws_native_path); elsewhere it stays POSIX.
    if command -v cygpath >/dev/null 2>&1; then
        expected_repo="$(cygpath -m "$expected_repo")"
    fi
    [ "$(yq -r '.components."adopted-alias".repo' "$WORK/ecosystem.local.yaml")" = "$expected_repo" ]
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
