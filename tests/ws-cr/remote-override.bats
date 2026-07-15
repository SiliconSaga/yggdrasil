#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    GIT_CR_BIN="$REPO_ROOT/scripts/git-cr.sh"

    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards" "$WORK/.crs"

    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"

    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
components: {}
YAML
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML

    BODYFILE="$WORK/.crs/body.md"
    cat > "$BODYFILE" <<'MD'
> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).

Body text.
MD

    git init -q "$WORK"
    git -C "$WORK" config user.name "Test User"
    git -C "$WORK" config user.email "test@example.local"
    echo "seed" > "$WORK/file.txt"
    git -C "$WORK" add file.txt
    git -C "$WORK" commit -q -m "seed commit"
    git -C "$WORK" checkout -q -b feature/cr-remote-override
    git -C "$WORK" remote add fork https://github.com/example/fork.git
    git -C "$WORK" remote add alt https://github.com/alt/project.git

    GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$GH_STUB_DIR"
    cat > "$GH_STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status")
    exit 0
    ;;
  "api repos/"*)
    echo main
    exit 0
    ;;
  "pr create")
    {
      printf 'pr:'
      printf ' %q' "$@"
      printf '\n'
    } > "$GH_LOG"
    echo "https://github.com/alt/project/pull/1"
    exit 0
    ;;
esac
echo "unexpected gh invocation: $*" >&2
exit 1
SH
    chmod +x "$GH_STUB_DIR/gh"
    export GH_LOG
    export PATH="$GH_STUB_DIR:$PATH"
}

@test "ws cr --remote selects an alternate fork remote" {
    run bash "$WS_BIN" cr yggdrasil --remote alt "test: alternate CR remote" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening CR for alt/project/feature/cr-remote-override"* ]]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
    [[ "$(cat "$GH_LOG")" == *"--head feature/cr-remote-override"* ]]
}

@test "GIT_CR_REMOTE selects an alternate fork remote" {
    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=alt bash "$2" "test: alternate CR remote" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening CR for alt/project/feature/cr-remote-override"* ]]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
    [[ "$(cat "$GH_LOG")" == *"--head feature/cr-remote-override"* ]]
}

@test "ws cr --remote rejects a following option as the remote name" {
    run bash "$WS_BIN" cr yggdrasil --remote --upstream "test: invalid remote" .crs/body.md

    [ "$status" -ne 0 ]
    [[ "$output" == *"--remote requires a git remote name"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --remote rejects a following option as the remote name" {
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote --upstream "test: invalid remote" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"--remote requires a git remote name"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --upstream refuses a same-provider cross-host token route" {
    git -C "$WORK" remote set-url alt https://github.enterprise.test/upstream/project.git
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
defaults:
  gitProviders:
    github.enterprise.test: github
components: {}
YAML

    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=fork bash "$2" --upstream "test: cross-host CR" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Cross-host CR creation is not supported"* ]]
    [[ "$output" == *"github.com"* ]]
    [[ "$output" == *"github.enterprise.test"* ]]
    [[ ! -f "$GH_LOG" ]]
}
