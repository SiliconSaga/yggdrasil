#!/usr/bin/env bats

# Tests for `ws run`. It resolves commands.<action> from the active realm
# adapter, runs it in the component directory, passes extra args through,
# rejects reserved verbs and malformed action names, and errors helpfully
# when the action is not configured.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "run refuses stale active-realm trust for workspace targets" {
    write_adapter_action clean "./actionstub"
    CLEAN_CMD="./actionstub --deep" yq -i \
        '.commands.clean = strenv(CLEAN_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_run yggdrasil clean

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/action_ran.marker" ]
}

@test "run executes the adapter's named action" {
    write_adapter_action clean "./actionstub"
    run_ws_run yggdrasil clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTION_ARGS:"* ]]
}

@test "run passes extra args through to the action" {
    write_adapter_action clean "./actionstub"
    run_ws_run yggdrasil clean --deep
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTION_ARGS:--deep"* ]]
}

@test "run executes in the component directory" {
    write_adapter_action clean "./actionstub"
    run_ws_run yggdrasil clean
    [ "$status" -eq 0 ]
    [ -f "$ROOT_DIR/action_ran.marker" ]
}

@test "run rejects reserved verbs with a pointer to the dedicated command" {
    write_adapter_action test "./actionstub"
    run_ws_run yggdrasil test
    [ "$status" -ne 0 ]
    [[ "$output" == *"dedicated verb"* ]]
    [[ "$output" == *"ws test yggdrasil"* ]]
    [ ! -f "$ROOT_DIR/action_ran.marker" ]
}

@test "run rejects a malformed action name before any lookup" {
    write_adapter_action clean "./actionstub"
    run_ws_run yggdrasil 'clean; rm -rf /'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid action name"* ]]
    [ ! -f "$ROOT_DIR/action_ran.marker" ]
}

@test "run errors helpfully when the action is not configured" {
    write_adapter_action clean "./actionstub"
    run_ws_run yggdrasil deploy
    [ "$status" -ne 0 ]
    [[ "$output" == *"No 'deploy' action configured"* ]]
}

@test "run with too few args prints usage and exits nonzero" {
    run_ws_run yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: ws run"* ]]
}

@test "run --help prints usage and exits 0" {
    run_ws_run --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws run"* ]]
}
