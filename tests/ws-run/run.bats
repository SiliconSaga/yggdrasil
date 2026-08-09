#!/usr/bin/env bats

# Tests for `ws run`. It resolves commands.run from the active realm
# adapter, runs it in the component directory, passes extra args through,
# and errors helpfully when no run command is configured.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "run refuses stale active-realm trust for workspace targets" {
    write_adapter_run "./runstub"
    RUN_CMD="./runstub --windowed" yq -i \
        '.commands.run = strenv(RUN_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_run yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/run_ran.marker" ]
}

@test "run executes the adapter's commands.run" {
    write_adapter_run "./runstub"
    run_ws_run yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUN_ARGS:"* ]]
}

@test "run passes extra args through to the run target" {
    write_adapter_run "./runstub"
    run_ws_run yggdrasil --port 3001
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUN_ARGS:--port 3001"* ]]
}

@test "run executes in the component directory" {
    write_adapter_run "./runstub"
    run_ws_run yggdrasil
    [ "$status" -eq 0 ]
    [ -f "$ROOT_DIR/run_ran.marker" ]
}

@test "run errors helpfully when no commands.run is configured" {
    # Adapter exists but declares only a test command, no run.
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<'EOF'
commands:
  test: "true"
EOF
    approve_synthetic_realm
    run_ws_run yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No run command configured"* ]]
}

@test "run rejects malformed adapter YAML as stale trust" {
    # An unterminated flow mapping cannot match the content that was approved.
    printf 'commands: {\n' > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    run_ws_run yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
}

@test "run with no component prints usage and exits nonzero" {
    run_ws_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: ws run"* ]]
}

@test "run --help prints usage and exits 0" {
    run_ws_run --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws run"* ]]
}
