# Shared helpers for ws-push bats tests.
#
# Each test gets an isolated git repo plus a bare remote. Tests invoke
# git-push.sh directly so they exercise push behavior without depending
# on ecosystem component resolution.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
GIT_PUSH_BIN="$REPO_ROOT/scripts/git-push.sh"
REAL_GIT="$(command -v git)"

init_push_repo() {
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"

    # -b main: tests push the literal branch "main", so the initial branch
    # must not depend on the host's init.defaultBranch (unset on CI runners).
    git init -q -b main "$REPO_DIR"
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

install_git_push_spy() {
    GIT_PUSH_SPY_DIR="$BATS_TEST_TMPDIR/git-spy"
    GIT_PUSH_SPY_LOG="$BATS_TEST_TMPDIR/git-push-spy.log"
    mkdir -p "$GIT_PUSH_SPY_DIR"
    cat > "$GIT_PUSH_SPY_DIR/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "push" ]]; then
    {
        printf 'GIT_TERMINAL_PROMPT=%s\n' "${GIT_TERMINAL_PROMPT-}"
        # Literal <unset> rather than an empty string, so a test can tell
        # "cleared to empty" (the non-interactive guarantee) apart from
        # "never set" (an inherited editor askpass would still fire).
        printf 'GIT_ASKPASS=%s\n' "${GIT_ASKPASS-<unset>}"
        printf 'SSH_ASKPASS=%s\n' "${SSH_ASKPASS-<unset>}"
        printf 'GIT_CONFIG_COUNT=%s\n' "${GIT_CONFIG_COUNT-}"
        i=0
        while [[ $i -lt ${GIT_CONFIG_COUNT:-0} ]]; do
            key_var="GIT_CONFIG_KEY_$i"
            val_var="GIT_CONFIG_VALUE_$i"
            printf '%s=%s\n' "$key_var" "${!key_var-}"
            printf '%s=%s\n' "$val_var" "${!val_var-}"
            i=$((i + 1))
        done
        printf 'args:'
        printf ' %q' "$@"
        printf '\n'
    } > "$GIT_PUSH_SPY_LOG"
    exit 0
fi
exec "$REAL_GIT" "$@"
SH
    chmod +x "$GIT_PUSH_SPY_DIR/git"
    export REAL_GIT GIT_PUSH_SPY_LOG
    export PATH="$GIT_PUSH_SPY_DIR:$PATH"
}

remote_ref_exists() {
    git --git-dir="$REMOTE_DIR" show-ref --verify --quiet "$1"
}

remote_ref_sha() {
    git --git-dir="$REMOTE_DIR" rev-parse "$1"
}
