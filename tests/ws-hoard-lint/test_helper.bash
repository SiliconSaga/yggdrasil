# Shared helpers for ws-hoard-lint bats tests.
#
# Same fixture mechanism as ws-hoard-scan: each fixture is a directory
# under fixtures/ containing a hoards/ tree, and HOARDS_DIR is pointed
# at it through the environment (ws-hoard.sh honors it via parameter
# expansion, so no flag wiring is needed).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

load_fixture() {
    local fixture="$1"
    export HOARDS_DIR="$BATS_TEST_DIRNAME/fixtures/$fixture/hoards"
    # Hard-fail rather than skip on a missing fixture — a typo'd name
    # that silently downgrades to `skip` is indistinguishable from a
    # deliberate skip, which hides coverage gaps.
    if [[ ! -d "$HOARDS_DIR" ]]; then
        echo "ERROR: fixture missing: $fixture (path: $HOARDS_DIR)" >&2
        return 1
    fi
}

# Run `ws hoard lint` against the loaded fixture. Requires load_fixture
# first — without it HOARDS_DIR falls back to the workspace's real hoard
# tree, and assertions would silently be testing the author's own notes
# instead of the fixture.
run_lint() {
    if [[ -z "${HOARDS_DIR:-}" ]]; then
        echo "ERROR: HOARDS_DIR is not set; call load_fixture <name> first" >&2
        return 1
    fi
    run bash "$WS_BIN" hoard lint "$@"
}
