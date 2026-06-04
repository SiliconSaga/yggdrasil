#!/usr/bin/env bats

# Tests for `ws lint`. It resolves commands.lint from the active realm
# adapter, runs it in the component directory, passes extra args through,
# and errors helpfully when no lint command is configured.

load test_helper

setup() {
    setup_synthetic_realm
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
    run_ws_lint yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No lint command configured"* ]]
}

@test "lint falls through gracefully when the adapter YAML is malformed" {
    # An unterminated flow mapping makes yq exit non-zero. Without the
    # guarded substitution, `set -euo pipefail` would abort here before the
    # "No lint command configured" guidance — regression test for that.
    printf 'commands: {\n' > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    run_ws_lint yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No lint command configured"* ]]
}

@test "lint --help prints usage and exits 0" {
    run_ws_lint --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws lint"* ]]
}
