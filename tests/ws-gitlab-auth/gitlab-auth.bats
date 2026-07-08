#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    WORK="$BATS_TEST_TMPDIR/work"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    GIT_LOG="$BATS_TEST_TMPDIR/git.log"
    GLAB_LOG="$BATS_TEST_TMPDIR/glab.log"

    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards" "$STUB_BIN"

    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export GITLAB_HOST="gitlab.example.com"
    export GITLAB_SOURCE_TOKEN="source-token"
    export GITLAB_FORK_NAMESPACE_TOKEN="fork-namespace-token"
    export GIT_LOG GLAB_LOG

    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
  homes:
    fork:
      namespace: gitlab.example.com/my-team/alice
defaults:
  gitProviders:
    gitlab.example.com: gitlab
  gitTokens:
    gitlab.example.com/source/team/widget: GITLAB_SOURCE_TOKEN
    gitlab.example.com/my-team/alice: GITLAB_FORK_NAMESPACE_TOKEN
components:
  widget:
    repo: https://gitlab.example.com/source/team/widget.git
YAML
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML

    cat > "$STUB_BIN/glab" <<'SH'
#!/usr/bin/env bash
{
  printf 'glab:'
  printf ' %q' "$@"
  printf ' token=%s\n' "${GITLAB_TOKEN:-}"
} >> "$GLAB_LOG"
exit 0
SH
    chmod +x "$STUB_BIN/glab"

    cat > "$STUB_BIN/git" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "credential approve")
    cat >> "$GIT_LOG"
    printf '%s\n' "---" >> "$GIT_LOG"
    exit 0
    ;;
  "config --global")
    if [[ "${4:-}" == "true" ]]; then
      printf 'config %s=%s\n' "${3:-}" "${4:-}" >> "$GIT_LOG"
      exit 0
    fi
    echo "stub-helper"
    exit 0
    ;;
  "ls-remote https://gitlab.example.com/source/team/widget.git")
    exit 0
    ;;
esac
echo "unexpected git invocation: $*" >&2
exit 1
SH
    chmod +x "$STUB_BIN/git"

    export PATH="$STUB_BIN:$PATH"
}

@test "gitlab-auth selects write token from fork-home namespace" {
    run bash "$WS_BIN" gitlab-auth

    [ "$status" -eq 0 ]
    [[ "$(cat "$GLAB_LOG")" == *"--token fork-namespace-token"* ]]
    [[ "$(cat "$GIT_LOG")" == *"password=fork-namespace-token"* ]]
    [[ "$output" == *"Registering write token (GITLAB_FORK_NAMESPACE_TOKEN)"* ]]
}

@test "gitlab-auth stores path-scoped source and fork credentials and verifies with source token" {
    run bash "$WS_BIN" gitlab-auth

    [ "$status" -eq 0 ]
    [[ "$(cat "$GIT_LOG")" == *"path=my-team/alice"* ]]
    [[ "$(cat "$GIT_LOG")" == *"password=fork-namespace-token"* ]]
    [[ "$(cat "$GIT_LOG")" == *"path=source/team/widget"* ]]
    [[ "$(cat "$GIT_LOG")" == *"path=source/team/widget.git"* ]]
    [[ "$(cat "$GIT_LOG")" == *"password=source-token"* ]]
    [[ "$output" == *"Stored path-scoped credentials"* ]]
    [[ "$output" == *"verified using GITLAB_SOURCE_TOKEN"* ]]
}

@test "gitlab-auth requires explicit fork-home namespace for write token selection" {
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
defaults:
  gitProviders:
    gitlab.example.com: gitlab
  gitTokens:
    gitlab.example.com/source/team/widget: GITLAB_SOURCE_TOKEN
    gitlab.example.com/source/team/fork: GITLAB_FORK_NAMESPACE_TOKEN
components:
  widget:
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run bash "$WS_BIN" gitlab-auth

    [ "$status" -eq 1 ]
    [[ "$output" == *"identity.homes.fork.namespace is not set in ecosystem config"* ]]
    [[ ! -s "$GLAB_LOG" ]]
    [[ ! -s "$GIT_LOG" ]]
}
