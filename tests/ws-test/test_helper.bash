# Shared helpers for ws-test bats tests.
#
# Each test builds a synthetic workspace under $BATS_TEST_TMPDIR and uses
# the "yggdrasil" component name, which ws_resolve_target special-cases
# to COMPONENT_DIR=$ROOT_DIR (short-circuiting ecosystem/clone checks — same
# trick as the ws-commit tests). A single non-template realm (realm-test)
# is created so ws_detect_realm resolves it, and an adapter YAML provides
# the test command. Stub executables echo the args they receive so we can
# assert how ws-test routed the filter. The synthetic local config explicitly
# selects that realm, matching the same trust boundary as a real workspace.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_TEST_BIN="$REPO_ROOT/scripts/ws-test.sh"
REALM_LIB="$REPO_ROOT/scripts/ws-realm.sh"

setup_synthetic_realm() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/root"
    export REALMS_DIR="$ROOT_DIR/realms"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"

    mkdir -p "$REALMS_DIR/realm-test/adapters"
    mkdir -p "$ROOT_DIR/tests"
    printf 'components: {}\n' > "$ROOT_DIR/ecosystem.yaml"
    printf 'components: {}\n' > "$REALMS_DIR/realm-test/ecosystem.yaml"
    printf 'realm: realm-test\n' > "$ECOSYSTEM_LOCAL"

    # Stub `pytest` that echoes the args it received.
    cat > "$ROOT_DIR/pytest" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/pytest"

    # Stub `python` for adapter command dispatch tests.
    cat > "$ROOT_DIR/python" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:'
printf '[%q]' "$@"
printf '\n'
EOF
    chmod +x "$ROOT_DIR/python"

    approve_synthetic_realm
}

approve_synthetic_realm() {
    local fingerprint
    fingerprint="$(bash -c 'source "$1"; ws_realm_trust_fingerprint realm-test' _ "$REALM_LIB")"
    REALM_FINGERPRINT="$fingerprint" yq -i '
        ._gdd.realmTrust = {
          "realm": "realm-test",
          "fingerprint": strenv(REALM_FINGERPRINT)
        }
    ' "$ECOSYSTEM_LOCAL"
}

# Write the realm adapter's commands.test for the synthetic component.
write_adapter_test() {
    local cmd="$1"
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<EOF
commands:
  test: "$cmd"
EOF
    approve_synthetic_realm
}

# Write both commands.test and the opt-in commands.testFilter, for runners
# whose filter syntax ws-test cannot infer.
write_adapter_test_filter() {
    local cmd="$1" filter_cmd="$2"
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<EOF
commands:
  test: "$cmd"
  testFilter: "$filter_cmd"
EOF
    approve_synthetic_realm
}

run_ws_test() {
    run bash "$WS_TEST_BIN" "$@"
}
