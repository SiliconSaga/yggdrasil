#!/usr/bin/env bats

# Tests for the target form of `ws clean`: `ws clean <comp>` runs the
# adapter's commands.clean in the component directory, while the bare
# and flag forms keep sweeping workspace draft files (covered in
# clean.bats). Drives the full dispatcher so the routing split between
# the two forms is what's exercised.

load test_helper

REALM_LIB="$REPO_ROOT/scripts/ws-realm.sh"

setup() {
    init_clean_workspace

    mkdir -p "$REALMS_DIR/realm-test/adapters"
    printf 'components: {}\n' > "$REALMS_DIR/realm-test/ecosystem.yaml"
    printf 'realm: realm-test\n' >> "$ECOSYSTEM_LOCAL"

    # Stub cleaner: drops a marker in its cwd and echoes the args it got.
    cat > "$ROOT_DIR/cleanstub" <<'EOF'
#!/usr/bin/env bash
touch clean_ran.marker
echo "CLEAN_ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/cleanstub"
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

write_adapter_clean() {
    local cmd="$1"
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<EOF
commands:
  clean: "$cmd"
EOF
    approve_synthetic_realm
}

@test "clean <comp> runs the adapter's commands.clean" {
    write_adapter_clean "./cleanstub"
    run_ws clean yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAN_ARGS:"* ]]
    [ -f "$ROOT_DIR/clean_ran.marker" ]
}

@test "clean <comp> passes extra args through" {
    write_adapter_clean "./cleanstub"
    run_ws clean yggdrasil --deep
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAN_ARGS:--deep"* ]]
}

@test "clean <comp> refuses stale active-realm trust" {
    write_adapter_clean "./cleanstub"
    CLEAN_CMD="./cleanstub --deep" yq -i \
        '.commands.clean = strenv(CLEAN_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws clean yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/clean_ran.marker" ]
}

@test "clean <comp> errors helpfully when no commands.clean is configured" {
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<'EOF'
commands:
  test: "true"
EOF
    approve_synthetic_realm
    run_ws clean yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No clean command configured"* ]]
    [[ "$output" == *"Bare 'ws clean' sweeps workspace draft files"* ]]
}

@test "bare clean still sweeps drafts, untouched by the target form" {
    export WS_CLEAN_MINE_THRESHOLD=1
    make_drafts .commits 2
    run_ws clean --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned 2 draft file(s) total."* ]]
}

@test "clean with an unknown flag still errors as before" {
    run_ws clean --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: ws clean"* ]]
}
