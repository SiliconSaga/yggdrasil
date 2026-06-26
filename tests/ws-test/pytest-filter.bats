#!/usr/bin/env bats

# Tests for ws-test's pytest-adapter filter handling. A positional selector
# that names an existing path or nodeid is passed through positionally (so
# pytest collects just that target — and a partial suite still runs when
# unrelated modules have collection errors). Anything else becomes a -k
# keyword filter. Non-pytest, non-Gradle adapters still reject filters.

load test_helper

setup() {
    setup_synthetic_realm
}

@test "pytest adapter: an existing path filter is passed positionally" {
    write_adapter_test "./pytest"
    touch "$ROOT_DIR/tests/foo.py"
    run_ws_test yggdrasil tests/foo.py
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:tests/foo.py"* ]]
    [[ "$output" != *"-k"* ]]
}

@test "pytest adapter: a nodeid (path::test) is passed positionally" {
    write_adapter_test "./pytest"
    touch "$ROOT_DIR/tests/foo.py"
    run_ws_test yggdrasil "tests/foo.py::test_bar"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:tests/foo.py::test_bar"* ]]
    [[ "$output" != *"-k"* ]]
}

@test "pytest adapter: a non-path keyword becomes a -k filter" {
    write_adapter_test "./pytest"
    run_ws_test yggdrasil some_keyword
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:-k some_keyword"* ]]
}

@test "pytest adapter: no filter runs the base command" {
    write_adapter_test "./pytest"
    run_ws_test yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:"* ]]
    [[ "$output" != *"-k"* ]]
}

@test "pytest adapter: flags pass through alongside a path filter" {
    write_adapter_test "./pytest"
    touch "$ROOT_DIR/tests/foo.py"
    run_ws_test yggdrasil tests/foo.py -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:tests/foo.py -v"* ]]
}

@test "unittest adapter: a non-path keyword becomes a -k filter" {
    write_adapter_test "./python -m unittest discover"
    run_ws_test yggdrasil some_keyword
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:[-m][unittest][discover][-k][some_keyword]"* ]]
}

@test "unittest-like wrapper adapter rejects positional filters" {
    cat > "$ROOT_DIR/unittest-wrapper" <<'EOF'
#!/usr/bin/env bash
echo "WRAPPER:$*"
EOF
    chmod +x "$ROOT_DIR/unittest-wrapper"
    write_adapter_test "./unittest-wrapper"
    run_ws_test yggdrasil some_keyword
    [ "$status" -ne 0 ]
    [[ "$output" == *"not Gradle, pytest, or unittest"* ]]
    [[ "$output" != *"WRAPPER:"* ]]
}

@test "unittest adapter preserves quoted filter as one argv element" {
    write_adapter_test "./python -m unittest discover"
    run_ws_test yggdrasil "some keyword"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:[-m][unittest][discover][-k][some\\ keyword]"* ]]
}

@test "non-pytest, non-unittest, non-Gradle adapter still rejects a positional filter" {
    write_adapter_test "true"
    run_ws_test yggdrasil somefilter
    [ "$status" -ne 0 ]
    [[ "$output" == *"not Gradle, pytest, or unittest"* ]]
}
