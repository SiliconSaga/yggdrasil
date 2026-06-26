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
    export SOURCE_TOKEN="source-token"
    export FORK_NAMESPACE_TOKEN="fork-namespace-token"
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
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/my-team/alice: FORK_NAMESPACE_TOKEN
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
    cat > "$GIT_LOG"
    exit 0
    ;;
  "config --global")
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

@test "gitlab-auth selects write token from fork-home namespace before forkRemote leaf fallback" {
    run bash "$WS_BIN" gitlab-auth

    [ "$status" -eq 0 ]
    [[ "$(cat "$GLAB_LOG")" == *"--token fork-namespace-token"* ]]
    [[ "$(cat "$GIT_LOG")" == *"password=fork-namespace-token"* ]]
    [[ "$output" == *"Registering write token (FORK_NAMESPACE_TOKEN)"* ]]
}
