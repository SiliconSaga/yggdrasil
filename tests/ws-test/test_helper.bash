# Shared helpers for ws-test bats tests.
#
# Each test builds a synthetic workspace under $BATS_TEST_TMPDIR and uses
# the "yggdrasil" component name, which ws_resolve_target special-cases
# to COMPONENT_DIR=$ROOT_DIR (short-circuiting ecosystem/clone checks — same
# trick as the ws-commit tests). A single non-template realm (realm-test)
# is created so ws_detect_realm resolves it, and an adapter YAML provides
# the test command. Stub executables echo the args they receive so we can
# assert how ws-test routed the filter.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_TEST_BIN="$REPO_ROOT/scripts/ws-test.sh"

setup_synthetic_realm() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/root"
    export REALMS_DIR="$ROOT_DIR/realms"
    # Point ECOSYSTEM_LOCAL at a path that won't exist so ws_detect_realm
    # falls through to auto-detecting our single realm-test directory,
    # regardless of the caller's real environment.
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"

    mkdir -p "$REALMS_DIR/realm-test/adapters"
    mkdir -p "$ROOT_DIR/tests"

    # Stub `pytest` that echoes the args it received.
    cat > "$ROOT_DIR/pytest" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/pytest"

    # Stub `python` for adapter command dispatch tests.
    cat > "$ROOT_DIR/python" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/python"
}

# Write the realm adapter's commands.test for the synthetic component.
write_adapter_test() {
    local cmd="$1"
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<EOF
commands:
  test: "$cmd"
EOF
}

run_ws_test() {
    run bash "$WS_TEST_BIN" "$@"
}
