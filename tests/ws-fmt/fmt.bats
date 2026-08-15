#!/usr/bin/env bats

# Tests for `ws fmt`. It resolves commands.fmt from the active realm
# adapter, runs the formatter in the component directory, passes extra args
# through, propagates its exit status, and errors helpfully when no fmt
# command is configured.
#
# `fmt` writes and `lint` checks, so the check form of a formatter belongs
# in commands.lint — see the header of scripts/ws-fmt.sh.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "fmt refuses stale active-realm trust for workspace targets" {
    write_adapter_fmt "./fmtstub"
    FMT_CMD="./fmtstub --all" yq -i \
        '.commands.fmt = strenv(FMT_CMD)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_fmt yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [ ! -f "$ROOT_DIR/fmt_ran.marker" ]
}

@test "fmt runs the adapter's commands.fmt" {
    write_adapter_fmt "./fmtstub"
    run_ws_fmt yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"FMT_ARGS:"* ]]
}

@test "fmt passes extra args through to the formatter" {
    write_adapter_fmt "./fmtstub"
    run_ws_fmt yggdrasil --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"FMT_ARGS:--all"* ]]
}

@test "fmt runs in the component directory" {
    write_adapter_fmt "./fmtstub"
    run_ws_fmt yggdrasil
    [ "$status" -eq 0 ]
    # The stub touched its marker in cwd; it must land in the component dir.
    [ -f "$ROOT_DIR/fmt_ran.marker" ]
}

@test "fmt propagates a failing formatter" {
    # A formatter that cannot rewrite (unparseable source, read-only file)
    # must not be reported as success.
    write_adapter_fmt "./fmtstub-fail"
    run_ws_fmt yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"FMT_VIOLATIONS"* ]]
}

@test "fmt errors helpfully when no commands.fmt is configured" {
    # Adapter exists but declares only a lint command, no fmt.
    cat > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml" <<'EOF'
commands:
  lint: "true"
EOF
    approve_synthetic_realm
    run_ws_fmt yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"No fmt command configured"* ]]
}

@test "fmt rejects malformed adapter YAML as stale trust" {
    # An unterminated flow mapping cannot match the content that was approved.
    printf 'commands: {\n' > "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"
    run_ws_fmt yggdrasil
    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
}

@test "fmt with no component prints usage and exits nonzero" {
    run_ws_fmt
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: ws fmt"* ]]
}

@test "fmt --help prints usage and exits 0" {
    run_ws_fmt --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws fmt"* ]]
}
