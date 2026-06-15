# Shared helpers for ws-push bats tests.
#
# Each test gets an isolated git repo plus a bare remote. Tests invoke
# git-push.sh directly so they exercise push behavior without depending
# on ecosystem component resolution.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
GIT_PUSH_BIN="$REPO_ROOT/scripts/git-push.sh"

init_push_repo() {
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"

    git init -q "$REPO_DIR"
    git -C "$REPO_DIR" config user.name "Test User"
    git -C "$REPO_DIR" config user.email "test@example.local"

    echo "hello" > "$REPO_DIR/file.txt"
    git -C "$REPO_DIR" add file.txt
    git -C "$REPO_DIR" commit -q -m "seed commit"

    git init -q --bare "$REMOTE_DIR"
    git -C "$REPO_DIR" remote add fork "$REMOTE_DIR"
    export GIT_PUSH_REMOTE="fork"
}

run_git_push() {
    run bash -c 'cd "$1" || exit 1; shift; exec bash "$@"' bash "$REPO_DIR" "$GIT_PUSH_BIN" "$@"
}

remote_ref_exists() {
    git --git-dir="$REMOTE_DIR" show-ref --verify --quiet "$1"
}

remote_ref_sha() {
    git --git-dir="$REMOTE_DIR" rev-parse "$1"
}
