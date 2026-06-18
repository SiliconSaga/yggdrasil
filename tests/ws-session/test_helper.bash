REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SESSION_LIB="$REPO_ROOT/scripts/ws-session.sh"

setup_session_env() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$ROOT_DIR/.tmp"
    # Neutralize any inherited harness ids so GDD_SESSION_ID is authoritative.
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID GDD_SESSION_ID GDD_CO_AUTHOR
}

# Run a bash snippet with ws-session.sh sourced, echoing one function's result.
run_session() { run bash -c "ROOT_DIR='$ROOT_DIR'; source '$SESSION_LIB'; $1"; }
