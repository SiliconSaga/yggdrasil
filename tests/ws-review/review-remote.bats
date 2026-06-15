#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    WORK="$BATS_TEST_TMPDIR/work"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$WORK/components/app" "$WORK/realms" "$WORK/hoards" "$BIN_DIR"

    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  gitProviders:
    gitlab.com: gitlab
components:
  app:
    repo: https://gitlab.com/upstream-group/project.git
YAML

    git -C "$WORK/components/app" init -q
    git -C "$WORK/components/app" config user.name "Test User"
    git -C "$WORK/components/app" config user.email "test@example.local"
    echo "hello" > "$WORK/components/app/README.md"
    git -C "$WORK/components/app" add README.md
    git -C "$WORK/components/app" commit -q -m "seed"
    git -C "$WORK/components/app" remote add origin https://gitlab.com/upstream-group/project.git
    git -C "$WORK/components/app" remote add fork https://gitlab.com/example-group/forked-project.git

    cat > "$BIN_DIR/glab" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "api" ]]; then
    echo "unexpected glab command: $*" >&2
    exit 1
fi

case "${2:-}" in
    projects/*/merge_requests/1)
        cat <<'JSON'
{"title":"Test MR","state":"opened","author":{"username":"review-bot"},"source_branch":"feature/source-project","target_branch":"main","web_url":"https://gitlab.com/example-group/forked-project/-/merge_requests/1"}
JSON
        ;;
    projects/*/merge_requests/1/approvals)
        echo '{"approved_by":[]}'
        ;;
    projects/*/merge_requests/1/discussions)
        echo '[]'
        ;;
    *)
        echo "unexpected glab api path: ${2:-}" >&2
        exit 1
        ;;
esac
BASH
    chmod +x "$BIN_DIR/glab"
}

run_ws_review() {
    run env \
        "PATH=$BIN_DIR:$PATH" \
        "ROOT_DIR=$WORK" \
        "COMPONENTS_DIR=$WORK/components" \
        "REALMS_DIR=$WORK/realms" \
        "HOARDS_DIR=$WORK/hoards" \
        "ECOSYSTEM=$WORK/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$WORK/ecosystem.local.yaml" \
        "GITLAB_TOKEN=dummy-token" \
        bash "$WS_BIN" review "$@"
}

@test "review errors actionably when a CR number exists on multiple remotes" {
    run_ws_review app 1 --compact

    [ "$status" -ne 0 ]
    [[ "$output" == *"CR #1 found on multiple remotes"* ]]
    [[ "$output" == *"origin=upstream-group/project"* ]]
    [[ "$output" == *"fork=example-group/forked-project"* ]]
    [[ "$output" == *"--remote <name>"* ]]
}

@test "review --remote selects a specific remote when CR numbers overlap" {
    run_ws_review app 1 --remote fork --compact

    [ "$status" -eq 0 ]
    [[ "$output" == *"=== CR #1 (example-group/forked-project) ==="* ]]
    [[ "$output" == *"Title: Test MR"* ]]
    [[ "$output" != *"found on multiple remotes"* ]]
}
