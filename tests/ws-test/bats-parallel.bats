#!/usr/bin/env bats

# Tests for optional Bats parallel-backend routing. The synthetic runner only
# prints its argv; backend stubs prove the execution contract independently.

load test_helper

setup() {
    setup_synthetic_realm
    export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FAKE_BIN" "$ROOT_DIR/tests/vendor/bats-core/bin"
    export PATH="$FAKE_BIN:$PATH"

    cat > "$ROOT_DIR/tests/vendor/bats-core/bin/bats" <<'EOF'
#!/usr/bin/env bash
printf 'BATS_ARG=<%s>\n' "$@"
EOF
    chmod +x "$ROOT_DIR/tests/vendor/bats-core/bin/bats"

    printf '#!/usr/bin/env bats\n@test "one" { true; }\n' > "$ROOT_DIR/tests/one.bats"
    printf '#!/usr/bin/env bats\n@test "two" { true; }\n' > "$ROOT_DIR/tests/two.bats"

    write_incompatible_backend rush
    write_incompatible_backend parallel
}

write_incompatible_backend() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
exit 64
EOF
    chmod +x "$FAKE_BIN/$name"
}

write_compatible_backend() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" != "--keep-order" || "$2" != "--jobs" || "$3" != "1" || "$4" != "--" || "$5" != 'printf "verified:%s\n" "{}"' ]]; then
    exit 64
fi
IFS= read -r input
printf 'verified:%s\n' "$input"
EOF
    chmod +x "$FAKE_BIN/$name"
}

write_passthrough_backend() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
IFS= read -r input
printf '%s\n' "$input"
EOF
    chmod +x "$FAKE_BIN/$name"
}

write_invalid_cpu_probes() {
    cat > "$FAKE_BIN/nproc" <<'EOF'
#!/usr/bin/env bash
printf 'many\n'
EOF
    chmod +x "$FAKE_BIN/nproc"

    cat > "$FAKE_BIN/sysctl" <<'EOF'
#!/usr/bin/env bash
printf '0\n'
EOF
    chmod +x "$FAKE_BIN/sysctl"
}

@test "bats runner stays serial when same-name backends are incompatible" {
    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" != *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name>"* ]]
}

@test "bats runner rejects a backend that ignores the supplied command" {
    write_passthrough_backend rush

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" != *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name>"* ]]
}

@test "bats runner prefers a compatible rush backend" {
    write_compatible_backend rush
    write_compatible_backend parallel

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" == *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
}

@test "bats runner falls back to compatible GNU parallel" {
    write_compatible_backend parallel

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<parallel>'* ]]
}

@test "bats runner selects rush for an explicit job count" {
    write_compatible_backend rush

    run_ws_test yggdrasil -j 2

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<-j>\nBATS_ARG=<2>'* ]]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
}

@test "bats runner normalizes an equals-form job count" {
    write_compatible_backend rush

    run_ws_test yggdrasil --jobs=2

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--jobs>\nBATS_ARG=<2>'* ]]
    [[ "$output" != *"BATS_ARG=<--jobs=2>"* ]]
}

@test "bats runner preserves an explicit equals-form backend" {
    run_ws_test yggdrasil --parallel-binary-name=custom

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<custom>'* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name=custom>"* ]]
    [[ "$output" != *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
}

@test "bats runner consumes a split-form backend value" {
    run_ws_test yggdrasil --parallel-binary-name custom

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<custom>'* ]]
    [[ "$output" != *"BATS_ARG=<--filter>"* ]]
}

@test "bats runner falls back to four jobs when CPU probes are invalid" {
    write_compatible_backend rush
    write_invalid_cpu_probes

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--jobs>\nBATS_ARG=<4>'* ]]
}

@test "bats runner leaves an automatic single-file run serial" {
    write_compatible_backend rush

    run_ws_test yggdrasil tests/one.bats

    [ "$status" -eq 0 ]
    [[ "$output" != *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name>"* ]]
}

@test "bats runner parallelizes a directory containing multiple test files" {
    write_compatible_backend rush

    run_ws_test yggdrasil tests

    [ "$status" -eq 0 ]
    [[ "$output" == *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
}
