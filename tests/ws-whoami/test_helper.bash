REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"
setup_whoami() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"; mkdir -p "$ROOT_DIR/.tmp"
    export ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"; echo 'components: {}' > "$ECOSYSTEM"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"; echo 'identity: {}' > "$ECOSYSTEM_LOCAL"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID GDD_CO_AUTHOR
    export GDD_SESSION_ID="whoami-test"
}
run_ws() { run env WS_FOOTER_DISABLE=1 bash "$WS_BIN" "$@"; }
