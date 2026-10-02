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

@test "adapter execution refuses stale active-realm trust for workspace targets" {
    write_adapter_test "./pytest"
    ADAPTER_TEST="./pytest -q" yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm-test/adapters/yggdrasil.yaml"

    run_ws_test yggdrasil

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [[ "$output" != *"ARGS:"* ]]
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

@test "detected python runner: a project venv's own pytest is used when uv does not own the project" {
    # No adapter, a pyproject.toml, no uv.lock, and a .venv with pytest in it:
    # `uv run` there is the wrong tool, and the one on disk is right.
    printf '[project]\nname = "demo"\n' > "$ROOT_DIR/pyproject.toml"
    mkdir -p "$ROOT_DIR/.venv/bin"
    printf '#!/usr/bin/env bash\necho "VENV_PYTEST:$*"\n' > "$ROOT_DIR/.venv/bin/pytest"
    chmod +x "$ROOT_DIR/.venv/bin/pytest"
    run_ws_test yggdrasil some_keyword
    [ "$status" -eq 0 ]
    [[ "$output" == *"VENV_PYTEST:-k some_keyword"* ]]
}

@test "detected python runner: uv.lock means uv owns the project, venv or not" {
    printf '[project]\nname = "demo"\n' > "$ROOT_DIR/pyproject.toml"
    : > "$ROOT_DIR/uv.lock"
    mkdir -p "$ROOT_DIR/.venv/bin" "$ROOT_DIR/bin"
    printf '#!/usr/bin/env bash\necho "VENV_PYTEST:$*"\n' > "$ROOT_DIR/.venv/bin/pytest"
    chmod +x "$ROOT_DIR/.venv/bin/pytest"
    printf '#!/usr/bin/env bash\necho "UV:$*"\n' > "$ROOT_DIR/bin/uv"
    chmod +x "$ROOT_DIR/bin/uv"
    run env "PATH=$ROOT_DIR/bin:$PATH" bash "$WS_TEST_BIN" yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"UV:run pytest"* ]]
    [[ "$output" != *"VENV_PYTEST"* ]]
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

@test "pytest adapter: multiple existing path filters are passed positionally" {
    write_adapter_test "./pytest"
    touch "$ROOT_DIR/tests/foo.py" "$ROOT_DIR/tests/bar.py"
    run_ws_test yggdrasil tests/foo.py tests/bar.py
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:tests/foo.py tests/bar.py"* ]]
    [[ "$output" != *"-k"* ]]
}

@test "bats runner: multiple existing path filters select those files" {
    ln -s "$REPO_ROOT/tests/vendor" "$ROOT_DIR/tests/vendor"
    cat > "$ROOT_DIR/tests/one.bats" <<'EOF'
#!/usr/bin/env bats
@test "one selected" {
  true
}
EOF
    cat > "$ROOT_DIR/tests/two.bats" <<'EOF'
#!/usr/bin/env bats
@test "two selected" {
  true
}
EOF
    cat > "$ROOT_DIR/tests/unselected.bats" <<'EOF'
#!/usr/bin/env bats
@test "unselected failure" {
  false
}
EOF

    run_ws_test yggdrasil tests/one.bats tests/two.bats

    [ "$status" -eq 0 ]
    [[ "$output" == *"one selected"* ]]
    [[ "$output" == *"two selected"* ]]
    [[ "$output" != *"unselected failure"* ]]
}

@test "bats runner: --filter keeps its value instead of reading it as a second selector" {
    ln -s "$REPO_ROOT/tests/vendor" "$ROOT_DIR/tests/vendor"
    cat > "$ROOT_DIR/tests/one.bats" <<'EOF'
#!/usr/bin/env bats
@test "wanted case" {
  true
}
@test "other case" {
  false
}
EOF

    run_ws_test yggdrasil tests/one.bats --filter "wanted"

    [ "$status" -eq 0 ]
    [[ "$output" == *"wanted case"* ]]
    [[ "$output" != *"other case"* ]]
}

@test "bats runner: more than six path filters are accepted" {
    ln -s "$REPO_ROOT/tests/vendor" "$ROOT_DIR/tests/vendor"
    selected=()
    for name in one two three four five six seven; do
        selected+=("tests/$name.bats")
        cat > "$ROOT_DIR/tests/$name.bats" <<EOF
#!/usr/bin/env bats
@test "$name selected" {
  true
}
EOF
    done

    run_ws_test yggdrasil "${selected[@]}"

    [ "$status" -eq 0 ]
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

@test "unittest adapter rejects multiple keyword filters with runner-neutral guidance" {
    write_adapter_test "./python -m unittest discover"
    run_ws_test yggdrasil alpha beta
    [ "$status" -ne 0 ]
    [[ "$output" == *"Multiple positional selectors for unittest are not supported in this form"* ]]
    [[ "$output" == *"Pass one keyword expression, or use the runner's native selector flag explicitly"* ]]
    [[ "$output" != *"must be existing paths or nodeids"* ]]
}

@test "non-pytest, non-unittest, non-Gradle adapter still rejects a positional filter" {
    write_adapter_test "true"
    run_ws_test yggdrasil somefilter
    [ "$status" -ne 0 ]
    [[ "$output" == *"not Gradle, pytest, or unittest"* ]]
}
