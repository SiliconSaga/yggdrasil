#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_TEST_BIN="$REPO_ROOT/scripts/ws-test.sh"
REALM_LIB="$REPO_ROOT/scripts/ws-realm.sh"

setup() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"
    export REALMS_DIR="$ROOT_DIR/realms"
    export COMPONENTS_DIR="$ROOT_DIR/components"
    export HOARDS_DIR="$ROOT_DIR/hoards"
    export ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"
    mkdir -p \
        "$REALMS_DIR/realm-active/.git" \
        "$REALMS_DIR/realm-active/adapters" \
        "$REALMS_DIR/realm-target/.git" \
        "$HOARDS_DIR/hoard-target/.git" \
        "$COMPONENTS_DIR"
    printf 'components: {}\n' > "$ECOSYSTEM"
    printf 'components: {}\n' > "$REALMS_DIR/realm-active/ecosystem.yaml"
    printf 'realm: realm-active\n' > "$ECOSYSTEM_LOCAL"
    printf 'test:\n\t@touch auto-runner-executed\n' > "$REALMS_DIR/realm-target/Makefile"
    printf 'test:\n\t@touch auto-runner-executed\n' > "$HOARDS_DIR/hoard-target/Makefile"
}

approve_active_realm() {
    local fingerprint
    fingerprint="$(bash -c 'source "$1"; ws_realm_trust_fingerprint realm-active' _ "$REALM_LIB")"
    REALM_FINGERPRINT="$fingerprint" yq -i '
        ._gdd.realmTrust = {
          "realm": "realm-active",
          "fingerprint": strenv(REALM_FINGERPRINT)
        }
    ' "$ECOSYSTEM_LOCAL"
}

run_test_target() {
    run bash "$WS_TEST_BIN" "$1"
}

@test "realm targets refuse auto-detected test runners" {
    run_test_target realm-target

    [ "$status" -ne 0 ]
    [[ "$output" == *"approved realm adapter"* ]]
    [ ! -e "$REALMS_DIR/realm-target/auto-runner-executed" ]
}

@test "hoard targets refuse auto-detected test runners" {
    run_test_target hoard-target

    [ "$status" -ne 0 ]
    [[ "$output" == *"approved realm adapter"* ]]
    [ ! -e "$HOARDS_DIR/hoard-target/auto-runner-executed" ]
}

@test "trusted realm adapters remain available for realm targets" {
    cat > "$REALMS_DIR/realm-active/adapters/realm-target.yaml" <<'YAML'
commands:
  test: "printf adapter-ok"
YAML
    approve_active_realm

    run_test_target realm-target

    [ "$status" -eq 0 ]
    [ "$output" = "adapter-ok" ]
    [ ! -e "$REALMS_DIR/realm-target/auto-runner-executed" ]
}
