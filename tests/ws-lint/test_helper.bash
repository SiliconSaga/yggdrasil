# Shared helpers for ws-lint bats tests.
#
# Mirrors the ws-test harness: synthetic workspace under $BATS_TEST_TMPDIR,
# the "yggdrasil" component name (→ COMPONENT_DIR=$ROOT_DIR), a single
# realm-test realm with an adapter YAML, and a stub linter that records
# how it was invoked (args + that it ran in the component dir).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_LINT_BIN="$REPO_ROOT/scripts/ws-lint.sh"

setup_synthetic_realm() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/root"
    export REALMS_DIR="$ROOT_DIR/realms"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"

    mkdir -p "$REALMS_DIR/realm-test/adapters"
    printf 'realm: realm-test\n' > "$ECOSYSTEM_LOCAL"

    # Stub linter: drops a marker in its cwd (proves it ran in the
    # component dir, robust to /var vs /private/var symlink differences)
    # and echoes the args it received.
    cat > "$ROOT_DIR/lintstub" <<'EOF'
#!/usr/bin/env bash
touch lint_ran.marker
echo "LINT_ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/lintstub"
}

# Write the realm adapter with the given commands.lint value.
write_adapter_lint() {
    local cmd="$1"
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<EOF
commands:
  lint: "$cmd"
EOF
}

run_ws_lint() {
    run bash "$WS_LINT_BIN" "$@"
}
