#!/usr/bin/env bats

# Tests for `ws lint`. It resolves commands.lint from the active realm
# adapter, runs it in the component directory, passes extra args through,
# and errors helpfully when no lint command is configured.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "lint refuses stale active-realm trust for workspace targets" {
    write_adapter_lint "./lintstub"
    LINT_CMD="./lintstub --changed" yq -i \
        '.commands.lint = strenv(LINT_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_lint yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/lint_ran.marker" ]
}

@test "lint runs the adapter's commands.lint" {
    write_adapter_lint "./lintstub"
    run_ws_lint yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"LINT_ARGS:"* ]]
}

@test "lint passes extra args through to the linter" {
    write_adapter_lint "./lintstub"
    run_ws_lint yggdrasil --fix
    [ "$status" -eq 0 ]
    [[ "$output" == *"LINT_ARGS:--fix"* ]]
}

@test "lint runs in the component directory" {
    write_adapter_lint "./lintstub"
    run_ws_lint yggdrasil
    [ "$status" -eq 0 ]
    # The stub touched its marker in cwd; it must land in the component dir.
    [ -f "$ROOT_DIR/lint_ran.marker" ]
}

@test "lint errors helpfully when no commands.lint is configured" {
    # Adapter exists but declares only a test command, no lint.
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<'EOF'
commands:
  test: "true"
EOF
    approve_synthetic_realm
    run_ws_lint yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No lint command configured"* ]]
}

@test "lint rejects malformed adapter YAML as stale trust" {
    # An unterminated flow mapping cannot match the content that was approved.
    printf 'commands: {\n' > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    run_ws_lint yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
}

@test "lint --help prints usage and exits 0" {
    run_ws_lint --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws lint"* ]]
}
