#!/usr/bin/env bats

# Tests for optional Bats parallel-backend routing. The synthetic runner only
# prints its argv; backend stubs prove the execution contract independently.

load test_helper
bats_require_minimum_version 1.5.0

setup() {
    setup_synthetic_realm
    export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    export REAL_FIND="$(type -P find)"
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

teardown() {
    local child_pid=""
    if [[ -n "${TERM_IGNORING_CHILD_PID_FILE:-}" && -s "$TERM_IGNORING_CHILD_PID_FILE" ]]; then
        child_pid="$(<"$TERM_IGNORING_CHILD_PID_FILE")"
        rm -f -- "$TERM_IGNORING_CHILD_PID_FILE"
        TERM_IGNORING_CHILD_PID_FILE=""
        if [[ "$child_pid" =~ ^[1-9][0-9]*$ ]]; then
            kill -KILL "$child_pid" 2>/dev/null || true
        fi
    fi
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
if [[ "$#" -ne 9 || "$1" != "--keep-order" || "$2" != "--jobs" || "$3" != "1" || "$4" != "--" || "$5" != ":" || "$6" != "&&" || "$7" != "printf" || "$8" != "verified:%s" || "$9" != "{}" ]]; then
    exit 64
fi
IFS= read -r input
printf 'verified:%s' "$input"
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

write_slow_compatible_backend() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
if [[ "$#" -ne 9 || "$1" != "--keep-order" || "$2" != "--jobs" || "$3" != "1" || "$4" != "--" || "$5" != ":" || "$6" != "&&" || "$7" != "printf" || "$8" != "verified:%s" || "$9" != "{}" ]]; then
    exit 64
fi
IFS= read -r input
sleep 5
printf 'verified:%s' "$input"
EOF
    chmod +x "$FAKE_BIN/$name"
}

write_briefly_delayed_compatible_backend() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
if [[ "$#" -ne 9 || "$1" != "--keep-order" || "$2" != "--jobs" || "$3" != "1" || "$4" != "--" || "$5" != ":" || "$6" != "&&" || "$7" != "printf" || "$8" != "verified:%s" || "$9" != "{}" ]]; then
    exit 64
fi
IFS= read -r input
sleep 1
printf 'verified:%s' "$input"
EOF
    chmod +x "$FAKE_BIN/$name"
}

write_term_ignoring_child_backend() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
if [[ "$#" -ne 9 || "$1" != "--keep-order" || "$2" != "--jobs" || "$3" != "1" || "$4" != "--" || "$5" != ":" || "$6" != "&&" || "$7" != "printf" || "$8" != "verified:%s" || "$9" != "{}" ]]; then
    exit 64
fi
IFS= read -r input
(
    trap '' TERM
    sleep 5
) &
child_pid=$!
printf '%s\n' "$child_pid" > "$TERM_IGNORING_CHILD_PID_FILE"
trap 'exit 143' TERM
wait "$child_pid"
printf 'verified:%s' "$input"
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

write_lock_helper() {
    local name="$1"
    cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$FAKE_BIN/$name"
}

hide_lock_helpers() {
    type() {
        if [[ "${1:-}" == "-P" ]]; then
            case "${2:-}" in
                flock|shlock) return 1 ;;
            esac
        fi
        builtin type "$@"
    }
    export -f type
}

write_noisy_recursive_find() {
    cat > "$FAKE_BIN/find" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-L" && -L "${2:-}/ws-bats-self-loop" ]]; then
    printf 'recursive-find-diagnostic: %s\n' "${2:-}/ws-bats-self-loop" >&2
fi
exec "$REAL_FIND" "$@"
EOF
    chmod +x "$FAKE_BIN/find"
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

@test "bats runner rejects a compatible backend that exceeds the probe budget" {
    write_slow_compatible_backend rush
    write_lock_helper shlock

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" != *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name>"* ]]
}

@test "bats runner tolerates brief backend probe scheduling delays" {
    write_briefly_delayed_compatible_backend rush

    run_ws_test yggdrasil -j 2

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
}

@test "bats backend watchdog kills a TERM-ignoring ordinary descendant" {
    export TERM_IGNORING_CHILD_PID_FILE="$BATS_TEST_TMPDIR/term-ignoring-child.pid"
    write_term_ignoring_child_backend rush

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [ -s "$TERM_IGNORING_CHILD_PID_FILE" ]
    child_pid="$(<"$TERM_IGNORING_CHILD_PID_FILE")"
    attempts=0
    while kill -0 "$child_pid" 2>/dev/null && [[ "$attempts" -lt 20 ]]; do
        sleep 0.05
        attempts=$((attempts + 1))
    done
    ! kill -0 "$child_pid" 2>/dev/null
}

@test "bats runner stays serial when automatic parallelism has no lock helper" {
    write_compatible_backend rush
    hide_lock_helpers

    run_ws_test yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" != *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name>"* ]]
}

@test "bats runner auto-selects a compatible backend with empty args under system Bash" {
    write_compatible_backend rush
    write_lock_helper shlock

    run /bin/bash "$WS_TEST_BIN" yggdrasil

    [ "$status" -eq 0 ]
    [[ "$output" == *"BATS_ARG=<--jobs>"* ]]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
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
    hide_lock_helpers

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
    hide_lock_helpers

    run_ws_test yggdrasil --parallel-binary-name=custom

    [ "$status" -eq 0 ]
    [[ "$output" == *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<custom>'* ]]
    [[ "$output" != *"BATS_ARG=<--parallel-binary-name=custom>"* ]]
    [[ "$output" != *$'BATS_ARG=<--parallel-binary-name>\nBATS_ARG=<rush>'* ]]
}

@test "bats runner consumes a split-form backend value" {
    hide_lock_helpers

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

@test "bats recursive file counting suppresses symlink-loop diagnostics" {
    write_compatible_backend rush
    ln -s . "$ROOT_DIR/tests/ws-bats-self-loop"
    write_noisy_recursive_find

    run --separate-stderr bash "$WS_TEST_BIN" yggdrasil --recursive tests

    [ "$status" -eq 0 ]
    [[ "$stderr" != *"ws-bats-self-loop"* ]]
}
