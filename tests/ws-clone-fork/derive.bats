#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CLONE_FORK_BIN="$REPO_ROOT/scripts/ws-clone-fork.sh"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_BIN" "$BATS_TEST_TMPDIR/components"

    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
echo "404 Project Not Found" >&2
exit 1
SH
    chmod +x "$TEST_BIN/glab"

    export PATH="$TEST_BIN:$PATH"
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/missing-local.yaml"
    export COMPONENTS_DIR="$BATS_TEST_TMPDIR/components"
    export SOURCE_TOKEN="source-token"
    export FORK_TOKEN="fork-token"
}

write_ecosystem() {
    cat > "$ECOSYSTEM"
}

run_clone_fork() {
    run bash "$CLONE_FORK_BIN" widget
}

@test "homes.fork.namespace derives an absolute fork-home project path" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.example.com/my-team/gdd/alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/my-team/gdd/alice-fork-group/widget: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 2 ]
    [[ "$output" == *"Fork     : my-team/gdd/alice-fork-group/widget"* ]]
    [[ "$output" == *"Cross-group fork detected"* ]]
}

@test "forkRepo override wins over homes.fork.namespace" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.example.com/my-team/gdd/alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/explicit/forks/widget: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
    forkRepo: https://gitlab.example.com/explicit/forks/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 2 ]
    [[ "$output" == *"Fork     : explicit/forks/widget"* ]]
    [[ "$output" != *"Fork     : my-team/gdd/alice-fork-group/widget"* ]]
}

@test "homes.fork.namespace rejects a different host" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: other-gitlab.example.com/my-team/gdd/alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 1 ]
    [[ "$output" == *"identity.homes.fork.namespace host (other-gitlab.example.com) differs from source host (gitlab.example.com)"* ]]
}

@test "missing homes.fork.namespace is rejected without forkRepo override" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/source/team/alice-fork-group/widget: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 1 ]
    [[ "$output" == *"identity.homes.fork.namespace is not set in ecosystem config"* ]]
}

@test "source remote collision keeps unrelated upstream remote intact" {
    SOURCE_BARE="$BATS_TEST_TMPDIR/source.git"
    FORK_BARE="$BATS_TEST_TMPDIR/fork.git"
    UNRELATED_BARE="$BATS_TEST_TMPDIR/unrelated.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    git init -q "$SEED"
    git -C "$SEED" config user.name "Test User"
    git -C "$SEED" config user.email "test@example.local"
    echo "seed" > "$SEED/file.txt"
    git -C "$SEED" add file.txt
    git -C "$SEED" commit -q -m "seed"
    git -C "$SEED" branch -M main
    git init -q --bare "$SOURCE_BARE"
    git init -q --bare "$FORK_BARE"
    git init -q --bare "$UNRELATED_BARE"
    git -C "$SEED" push -q "$SOURCE_BARE" main
    git -C "$SEED" push -q "$FORK_BARE" main
    git -C "$SEED" push -q "$UNRELATED_BARE" main

    TARGET="$COMPONENTS_DIR/widget"
    git clone -q "$FORK_BARE" "$TARGET"
    git -C "$TARGET" remote rename origin alice-fork-group
    git -C "$TARGET" remote add upstream "$UNRELATED_BARE"
    # Git for Windows normalizes local paths when storing a remote URL
    # (/d/… → D:/…), so assert against what git stored, not the raw shell path.
    UNRELATED_STORED="$(git -C "$TARGET" remote get-url upstream)"
    git -C "$TARGET" remote add _srcprobe "$SOURCE_BARE"
    SOURCE_STORED="$(git -C "$TARGET" remote get-url _srcprobe)"
    git -C "$TARGET" remote remove _srcprobe

    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
project="${@: -1}"
case "$project" in
  projects/source%2Falice-fork-group%2Fwidget)
    cat <<JSON
{"id":1,"default_branch":"main","ssh_url_to_repo":"$SOURCE_BARE","http_url_to_repo":"$SOURCE_BARE","web_url":"https://gitlab.example.com/source/alice-fork-group/widget"}
JSON
    ;;
  projects/forks%2Falice-fork-group%2Fwidget)
    cat <<JSON
{"id":2,"default_branch":"main","import_status":"finished","ssh_url_to_repo":"$FORK_BARE","http_url_to_repo":"$FORK_BARE","web_url":"https://gitlab.example.com/forks/alice-fork-group/widget"}
JSON
    ;;
  *)
    echo "unexpected glab api call: $*" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$TEST_BIN/glab"
    export SOURCE_BARE FORK_BARE

    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.example.com/forks/alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/alice-fork-group/widget: SOURCE_TOKEN
    gitlab.example.com/forks/alice-fork-group: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/alice-fork-group/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 0 ]
    [ "$(git -C "$TARGET" remote get-url upstream)" = "$UNRELATED_STORED" ]
    [ "$(git -C "$TARGET" remote get-url upstream-2)" = "$SOURCE_STORED" ]
}

@test "existing source-named remote pointing elsewhere is preserved" {
    SOURCE_BARE="$BATS_TEST_TMPDIR/source.git"
    FORK_BARE="$BATS_TEST_TMPDIR/fork.git"
    UNRELATED_BARE="$BATS_TEST_TMPDIR/unrelated.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    git init -q "$SEED"
    git -C "$SEED" config user.name "Test User"
    git -C "$SEED" config user.email "test@example.local"
    echo "seed" > "$SEED/file.txt"
    git -C "$SEED" add file.txt
    git -C "$SEED" commit -q -m "seed"
    git -C "$SEED" branch -M main
    git init -q --bare "$SOURCE_BARE"
    git init -q --bare "$FORK_BARE"
    git init -q --bare "$UNRELATED_BARE"
    git -C "$SEED" push -q "$SOURCE_BARE" main
    git -C "$SEED" push -q "$FORK_BARE" main
    git -C "$SEED" push -q "$UNRELATED_BARE" main

    TARGET="$COMPONENTS_DIR/widget"
    git clone -q "$FORK_BARE" "$TARGET"
    git -C "$TARGET" remote rename origin alice-fork-group
    git -C "$TARGET" remote add team "$UNRELATED_BARE"
    # See the upstream test above — assert against git's stored form, not the raw path.
    UNRELATED_STORED="$(git -C "$TARGET" remote get-url team)"
    git -C "$TARGET" remote add _srcprobe "$SOURCE_BARE"
    SOURCE_STORED="$(git -C "$TARGET" remote get-url _srcprobe)"
    git -C "$TARGET" remote remove _srcprobe

    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
project="${@: -1}"
case "$project" in
  projects/source%2Fteam%2Fwidget)
    cat <<JSON
{"id":1,"default_branch":"main","ssh_url_to_repo":"$SOURCE_BARE","http_url_to_repo":"$SOURCE_BARE","web_url":"https://gitlab.example.com/source/team/widget"}
JSON
    ;;
  projects/forks%2Falice-fork-group%2Fwidget)
    cat <<JSON
{"id":2,"default_branch":"main","import_status":"finished","ssh_url_to_repo":"$FORK_BARE","http_url_to_repo":"$FORK_BARE","web_url":"https://gitlab.example.com/forks/alice-fork-group/widget"}
JSON
    ;;
  *)
    echo "unexpected glab api call: $*" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$TEST_BIN/glab"
    export SOURCE_BARE FORK_BARE

    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.example.com/forks/alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/forks/alice-fork-group: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 0 ]
    [ "$(git -C "$TARGET" remote get-url team)" = "$UNRELATED_STORED" ]
    [ "$(git -C "$TARGET" remote get-url team-2)" = "$SOURCE_STORED" ]
}

@test "fork-token source probe surfaces transient errors instead of cross-group helper" {
    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${@: -1}" in
  projects/forks%2Falice-fork-group%2Fwidget)
    echo "404 Project Not Found" >&2
    exit 1
    ;;
  projects/source%2Fteam%2Fwidget)
    if [[ "${GITLAB_TOKEN:-}" == "fork-token" ]]; then
      echo "dial tcp: lookup gitlab.example.com: no such host" >&2
      exit 1
    fi
    cat <<JSON
{"id":1,"default_branch":"main","ssh_url_to_repo":"git@gitlab.example.com:source/team/widget.git","http_url_to_repo":"https://gitlab.example.com/source/team/widget.git","web_url":"https://gitlab.example.com/source/team/widget"}
JSON
    ;;
  *)
    echo "unexpected glab api call: $*" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$TEST_BIN/glab"

    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.example.com/forks/alice-fork-group
defaults:
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/forks/alice-fork-group: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 1 ]
    [[ "$output" == *"Fork token failed while probing source-project access"* ]]
    [[ "$output" == *"dial tcp"* ]]
    [[ "$output" != *"Cross-group fork detected"* ]]
}
