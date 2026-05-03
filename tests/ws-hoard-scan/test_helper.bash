# Shared helpers for ws-hoard-scan bats tests.
#
# Each test loads a fixture by name (a directory under fixtures/) and
# points HOARDS_DIR at that fixture's hoards/ subdir. The ws-hoard.sh
# script honors HOARDS_DIR via parameter expansion:
#   : "${HOARDS_DIR:="$ROOT_DIR/hoards"}"
# so passing it through the environment is sufficient — no flag wiring
# needed.

# Resolve the repo root once (the workspace root is the parent of tests/).
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

load_fixture() {
    local fixture="$1"
    export HOARDS_DIR="$BATS_TEST_DIRNAME/fixtures/$fixture/hoards"
    [[ -d "$HOARDS_DIR" ]] || skip "fixture missing: $fixture (expected $HOARDS_DIR)"
}

# Convenience wrapper around `bash $WS_BIN hoard scan ...` so tests can
# stay short. Forwards all args to the scan subcommand. The caller is
# expected to have called load_fixture beforehand to set HOARDS_DIR.
run_scan() {
    run bash "$WS_BIN" hoard scan "$@"
}
