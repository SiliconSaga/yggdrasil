#!/usr/bin/env bats

# Tests for commands.testFilter — the opt-in escape hatch for adapters whose
# filter syntax ws-test cannot infer. A make target, an npm script or a shell
# wrapper has no convention to detect, so the adapter declares its own and
# marks where the selector goes with `{}`.
#
# Opt-in matters. Quietly dropping an unusable filter and running the whole
# suite would report a green full run as though the single test asked for had
# passed, which is the worst of the three possible behaviours.

load test_helper

setup() {
    setup_synthetic_realm

    # Stub `make` that echoes the args it received, so the tests can assert
    # exactly what ws-test invoked rather than that it exited zero.
    cat > "$ROOT_DIR/make" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/make"
}

@test "testFilter substitutes the selector at the placeholder" {
    write_adapter_test_filter "./make test" "./make test-one NAME={}"
    run_ws_test yggdrasil facets
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:test-one NAME=facets"* ]]
}

@test "testFilter is ignored when no selector is given" {
    # The plain command still runs the whole suite. Declaring a filter must not
    # change what `ws test <comp>` with no arguments does.
    write_adapter_test_filter "./make test" "./make test-one NAME={}"
    run_ws_test yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:test"* ]]
    [[ "$output" != *"test-one"* ]]
}

@test "a filter is still refused when the adapter declares no testFilter" {
    # Unchanged behaviour for adapters that have not opted in, and the error
    # now names the way to opt in.
    write_adapter_test "./make test"
    run_ws_test yggdrasil facets
    [ "$status" -ne 0 ]
    [[ "$output" == *"commands.testFilter"* ]]
    [[ "$output" != *"ARGS:"* ]]
}

@test "a testFilter without a placeholder is refused rather than silently unfiltered" {
    # THE ONE THAT MATTERS. Running the command as-is would drop the selector
    # and pass the full suite, which reads as "the test you asked for passed".
    write_adapter_test_filter "./make test" "./make test-one"
    run_ws_test yggdrasil facets
    [ "$status" -ne 0 ]
    [[ "$output" == *"no {} placeholder"* ]]
    [[ "$output" != *"ARGS:"* ]]
}

@test "multiple keyword selectors are refused rather than silently dropping one" {
    write_adapter_test_filter "./make test" "./make test-one NAME={}"
    run_ws_test yggdrasil facets outcome
    [ "$status" -ne 0 ]
    [[ "$output" != *"ARGS:"* ]]
}

@test "runner flags after the selector are passed through" {
    write_adapter_test_filter "./make test" "./make test-one NAME={}"
    run_ws_test yggdrasil facets --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:test-one NAME=facets --verbose"* ]]
}
