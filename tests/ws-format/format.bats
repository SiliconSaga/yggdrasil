#!/usr/bin/env bats

# Tests for `ws format`. It resolves commands.format from the active realm
# adapter, runs the formatter in the component directory, passes extra args
# through, propagates its exit status, and errors helpfully when no format
# command is configured.
#
# `format` writes and `lint` checks, so the check form of a formatter belongs
# in commands.lint — see the header of scripts/ws-format.sh.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "format refuses stale active-realm trust for workspace targets" {
    write_adapter_format "./formatstub"
    FORMAT_CMD="./formatstub --all" yq -i \
        '.commands.format = strenv(FORMAT_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_format yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/format_ran.marker" ]
}

@test "format runs the adapter's commands.format" {
    write_adapter_format "./formatstub"
    run_ws_format yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"FORMAT_ARGS:"* ]]
}

@test "format passes extra args through to the formatter" {
    write_adapter_format "./formatstub"
    run_ws_format yggdrasil --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"FORMAT_ARGS:--all"* ]]
}

@test "format runs in the component directory" {
    write_adapter_format "./formatstub"
    run_ws_format yggdrasil
    [ "$status" -eq 0 ]
    # The stub touched its marker in cwd; it must land in the component dir.
    [ -f "$ROOT_DIR/format_ran.marker" ]
}

@test "format propagates a failing formatter" {
    # A formatter that cannot rewrite (unparseable source, read-only file)
    # must not be reported as success.
    write_adapter_format "./formatstub-fail"
    run_ws_format yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"FORMAT_VIOLATIONS"* ]]
}

@test "format errors helpfully when no commands.format is configured" {
    # Adapter exists but declares only a lint command, no format.
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<'EOF'
commands:
  lint: "true"
EOF
    approve_synthetic_realm
    run_ws_format yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No format command configured"* ]]
}

@test "format rejects malformed adapter YAML as stale trust" {
    # An unterminated flow mapping cannot match the content that was approved.
    printf 'commands: {\n' > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    run_ws_format yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
}

@test "format rejects a whitespace-only commands.format without executing args" {
    # Empty-argv dispatch would execute the passthrough args as the command
    # inside a pre-allowed verb — the stub must never run.
    write_adapter_format "   "
    run_ws_format yggdrasil ./formatstub
    [ "$status" -ne 0 ]
    [[ "$output" == *"whitespace-only"* ]]
    [ ! -f "$ROOT_DIR/format_ran.marker" ]
}

@test "format dispatches through the ws entry point" {
    # The other tests call ws-format.sh directly, so they'd stay green with
    # the dispatcher arm missing.
    write_adapter_format "./formatstub"
    run bash "$REPO_ROOT/scripts/ws" format yggdrasil --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"FORMAT_ARGS:--all"* ]]
    [ -f "$ROOT_DIR/format_ran.marker" ]
}

@test "format with no component prints usage and exits nonzero" {
    run_ws_format
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: ws format"* ]]
}

@test "format --help prints usage and exits 0" {
    run_ws_format --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws format"* ]]
}
