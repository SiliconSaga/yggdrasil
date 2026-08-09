# Shared helpers for ws-run bats tests.
#
# Mirrors the ws-build harness: synthetic workspace under $BATS_TEST_TMPDIR,
# the "yggdrasil" component name (→ COMPONENT_DIR=$ROOT_DIR), a single
# realm-test realm with an adapter YAML, and a stub run target that records
# how it was invoked (args + that it ran in the component dir).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_RUN_BIN="$REPO_ROOT/scripts/ws-run.sh"
REALM_LIB="$REPO_ROOT/scripts/ws-realm.sh"

setup_synthetic_realm() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/root"
    export REALMS_DIR="$ROOT_DIR/realms"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"

    mkdir -p "$REALMS_DIR/realm-test/adapters"
    printf 'components: {}\n' > "$ROOT_DIR/ecosystem.yaml"
    printf 'components: {}\n' > "$REALMS_DIR/realm-test/ecosystem.yaml"
    printf 'realm: realm-test\n' > "$ECOSYSTEM_LOCAL"

    # Stub run target: drops a marker in its cwd (proves it ran in the
    # component dir) and echoes the args it received.
    cat > "$ROOT_DIR/runstub" <<'EOF'
#!/usr/bin/env bash
touch run_ran.marker
echo "RUN_ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/runstub"

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

# Write the realm adapter with the given commands.run value.
write_adapter_run() {
    local cmd="$1"
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<EOF
commands:
  run: "$cmd"
EOF
    approve_synthetic_realm
}

run_ws_run() {
    run bash "$WS_RUN_BIN" "$@"
}
