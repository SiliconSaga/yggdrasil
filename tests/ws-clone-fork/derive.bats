#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CLONE_FORK_BIN="$REPO_ROOT/scripts/ws-clone-fork.sh"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_BIN" "$BATS_TEST_TMPDIR/components"

    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
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

@test "nested forkRemote derivation remains supported" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
defaults:
  forkConvention: nested
  gitTokens:
    gitlab.example.com/source/team/widget: SOURCE_TOKEN
    gitlab.example.com/source/team/alice-fork-group/widget: FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML

    run_clone_fork

    [ "$status" -eq 2 ]
    [[ "$output" == *"Fork     : source/team/alice-fork-group/widget"* ]]
}
