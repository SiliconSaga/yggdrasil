#!/usr/bin/env bats

# Tests for `ws build`. It resolves commands.build from the active realm
# adapter, runs it in the component directory, passes extra args through,
# and errors helpfully when no build command is configured.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "build refuses stale active-realm trust for workspace targets" {
    write_adapter_build "./buildstub"
    BUILD_CMD="./buildstub --release" yq -i \
        '.commands.build = strenv(BUILD_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_build yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/build_ran.marker" ]
}

@test "build runs the adapter's commands.build" {
    write_adapter_build "./buildstub"
    run_ws_build yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"BUILD_ARGS:"* ]]
}

@test "build passes extra args through to the builder" {
    write_adapter_build "./buildstub"
    run_ws_build yggdrasil --release
    [ "$status" -eq 0 ]
    [[ "$output" == *"BUILD_ARGS:--release"* ]]
}

@test "build runs in the component directory" {
    write_adapter_build "./buildstub"
    run_ws_build yggdrasil
    [ "$status" -eq 0 ]
    # The stub touched its marker in cwd; it must land in the component dir.
    [ -f "$ROOT_DIR/build_ran.marker" ]
}

@test "build errors helpfully when no commands.build is configured" {
    # Adapter exists but declares only a test command, no build.
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<'EOF'
commands:
  test: "true"
EOF
    approve_synthetic_realm
    run_ws_build yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No build command configured"* ]]
}

@test "build rejects malformed adapter YAML as stale trust" {
    # An unterminated flow mapping cannot match the content that was approved.
    printf 'commands: {\n' > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    run_ws_build yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
}

@test "build rejects a whitespace-only commands.build without executing args" {
    # Empty-argv dispatch would execute the passthrough args as the command
    # inside a pre-allowed verb — the stub must never run.
    write_adapter_build "   "
    run_ws_build yggdrasil ./buildstub
    [ "$status" -ne 0 ]
    [[ "$output" == *"whitespace-only"* ]]
    [ ! -f "$ROOT_DIR/build_ran.marker" ]
}

@test "build with no component prints usage and exits nonzero" {
    run_ws_build
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: ws build"* ]]
}

@test "build --help prints usage and exits 0" {
    run_ws_build --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws build"* ]]
}
