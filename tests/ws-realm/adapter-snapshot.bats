#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
REALM_LIB="$REPO_ROOT/scripts/ws-realm.sh"

setup() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"
    export REALMS_DIR="$ROOT_DIR/realms"
    export COMPONENTS_DIR="$ROOT_DIR/components"
    export HOARDS_DIR="$ROOT_DIR/hoards"
    export ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$ROOT_DIR/ecosystem.local.yaml"
    export SNAPSHOT_ADAPTER="$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    export REAL_YQ="$(type -P yq)"
    mkdir -p "$REALMS_DIR/realm-test/adapters" "$ROOT_DIR/bin"
    printf 'components: {}\n' > "$ECOSYSTEM"
    printf 'components: {}\n' > "$REALMS_DIR/realm-test/ecosystem.yaml"
    printf 'realm: realm-test\n' > "$ECOSYSTEM_LOCAL"
    cat > "$SNAPSHOT_ADAPTER" <<'YAML'
commands:
  test: printf approved
  testFilter: printf approved-{}
  lint: printf approved
  format: printf approved
  build: printf approved
  run: printf approved
  clean: printf approved
YAML
    cp "$SNAPSHOT_ADAPTER" "$ROOT_DIR/approved.yaml"
    local fingerprint
    fingerprint="$(bash -c 'source "$1"; ws_realm_trust_fingerprint realm-test' _ "$REALM_LIB")"
    REALM_FINGERPRINT="$fingerprint" yq -i '._gdd.realmTrust = {"realm": "realm-test", "fingerprint": strenv(REALM_FINGERPRINT)}' "$ECOSYSTEM_LOCAL"
}

# Replace the live file immediately before command extraction. The old
# check-then-open implementation executes the replacement in every verb.
install_racing_yq() {
    cat > "$ROOT_DIR/bin/yq" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-r" && "${2:-}" == ".commands.$RACE_VERB // \"\"" ]]; then
    printf 'commands:\n  %s: touch unapproved-executed\n  testFilter: touch unapproved-executed-{}\n' "$RACE_VERB" > "$SNAPSHOT_ADAPTER"
    touch "$ROOT_DIR/race-triggered"
fi
exec "$REAL_YQ" "$@"
SH
    chmod +x "$ROOT_DIR/bin/yq"
    export PATH="$ROOT_DIR/bin:$PATH"
}

assert_captured_command() {
    export RACE_VERB="$1"
    install_racing_yq
    run bash "$REPO_ROOT/scripts/ws" "$1" yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *approved* ]]
    [ -e "$ROOT_DIR/race-triggered" ]
    [ ! -e "$ROOT_DIR/unapproved-executed" ]
}

@test "test consumes approved adapter content after replacement" { assert_captured_command test; }
@test "lint consumes approved adapter content after replacement" { assert_captured_command lint; }
@test "format consumes approved adapter content after replacement" { assert_captured_command format; }
@test "build consumes approved adapter content after replacement" { assert_captured_command build; }
@test "run consumes approved adapter content after replacement" { assert_captured_command run; }
@test "clean consumes approved adapter content after replacement" { assert_captured_command clean; }

@test "test and testFilter consume the same approved adapter copy" {
    export RACE_VERB=test
    install_racing_yq
    run bash "$REPO_ROOT/scripts/ws" test yggdrasil selection
    [ "$status" -eq 0 ]
    [[ "$output" == *approved-selection* ]]
    [ -e "$ROOT_DIR/race-triggered" ]
    [ ! -e "$ROOT_DIR/unapproved-executed-selection" ]
}

@test "unapproved captured content is rejected even when disk content is restored" {
    run bash -c '
        source "$1"
        yq() {
            if [[ "$1" == "-o=json" && "${4:-}" == "$SNAPSHOT_ADAPTER" ]]; then
                printf "commands:\n  test: touch unapproved-executed\n" > "$SNAPSHOT_ADAPTER"
                "$REAL_YQ" "$@"
                cp "$ROOT_DIR/approved.yaml" "$SNAPSHOT_ADAPTER"
            else
                "$REAL_YQ" "$@"
            fi
        }
        ws_read_trusted_adapter realm-test "$SNAPSHOT_ADAPTER"
    ' _ "$REALM_LIB"
    [ "$status" -ne 0 ]
    [[ "$output" == *"reapproval is required"* ]]
    cmp "$SNAPSHOT_ADAPTER" "$ROOT_DIR/approved.yaml"
}
