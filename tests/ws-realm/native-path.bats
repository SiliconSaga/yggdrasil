#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    STUB_DIR="$BATS_TEST_TMPDIR/bin"
    export ROOT_DIR="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$STUB_DIR" "$ROOT_DIR"

    cat > "$STUB_DIR/cygpath" <<'EOF'
#!/usr/bin/env bash
shift 2
printf 'NATIVE:%s' "$1"
EOF
    cat > "$STUB_DIR/yq" <<'EOF'
#!/usr/bin/env bash
printf 'YQ_ARG=%s\n' "$@"
EOF
    chmod +x "$STUB_DIR/cygpath" "$STUB_DIR/yq"
    export PATH="$STUB_DIR:$PATH"
}

@test "yq converts an absolute file operand and preserves flags and expression" {
    local config="$BATS_TEST_TMPDIR/ecosystem.yaml"
    : > "$config"

    run env REPO_ROOT="$REPO_ROOT" CONFIG="$config" ROOT_DIR="$ROOT_DIR" PATH="$PATH" bash -c 'source "$REPO_ROOT/scripts/ws-realm.sh"; yq -r '\''.components'\'' "$CONFIG"'

    [ "$status" -eq 0 ]
    [[ "$output" == *$'YQ_ARG=-r\n'* ]]
    [[ "$output" == *$'YQ_ARG=.components\n'* ]]
    [[ "$output" == *"YQ_ARG=NATIVE:$config"* ]]
}

@test "yq does not convert an expression that happens to name a relative file" {
    local config="$BATS_TEST_TMPDIR/ecosystem.yaml"
    : > "$config"
    : > "$ROOT_DIR/ecosystem.yaml"

    # The expression deliberately names an existing relative file. Existence alone must not make a relative expression into a native file operand.
    run env REPO_ROOT="$REPO_ROOT" CONFIG="$config" ROOT_DIR="$ROOT_DIR" PATH="$PATH" bash -c 'cd "$ROOT_DIR" || exit 1; source "$REPO_ROOT/scripts/ws-realm.sh"; yq '\''ecosystem.yaml'\'' "$CONFIG"'

    [ "$status" -eq 0 ]
    [[ "$output" == *$'YQ_ARG=ecosystem.yaml\n'* ]]
    [[ "$output" != *"YQ_ARG=NATIVE:ecosystem.yaml"* ]]
    [[ "$output" == *"YQ_ARG=NATIVE:$config"* ]]
}

@test "scripts probe the real yq binary instead of the exported wrapper function" {
    run rg -n 'command -v yq' "$REPO_ROOT/scripts"

    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "ws_native_path converts a relative body-file path for native CLIs" {
    run env REPO_ROOT="$REPO_ROOT" ROOT_DIR="$ROOT_DIR" PATH="$PATH" bash -c 'source "$REPO_ROOT/scripts/ws-realm.sh"; ws_native_path .crs/change.md'

    [ "$status" -eq 0 ]
    [ "$output" = "NATIVE:.crs/change.md" ]
}
