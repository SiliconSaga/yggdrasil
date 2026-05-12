# Shared helpers for ws-smoke bats tests.
#
# Smoke-level coverage of read-only ws subcommands — the ones that
# just inspect state and print output. These tests catch regressions
# where a refactor breaks help/list/status output, AND act as a
# safety net that the hook (when active in a real session) won't
# stall on a no-op call.
#
# Each test gets an isolated $WORK directory under $BATS_TEST_TMPDIR
# with a minimal ecosystem stub. Tests invoke the `ws` dispatcher
# directly (via bash) so subcommand routing is exercised.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

init_workspace() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards"
    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"

    # Minimal upstream ecosystem. No components → ws list output is
    # deterministic (the header rows only).
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML

    export HOSTNAME="testhost"
}

run_ws() {
    # All ws smoke tests run with a 10s timeout to catch
    # infinite-loop / blocking regressions early. Read-only commands
    # should complete in milliseconds; anything approaching the
    # timeout is the regression we want to surface.
    run timeout 10 bash "$WS_BIN" "$@"
}
