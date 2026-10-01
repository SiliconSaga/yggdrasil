#!/usr/bin/env bats

# The bash watchdog that stands in for coreutils `timeout` on a stock Mac.
# Forced on here so a Linux runner covers it; the three properties the
# helpers rely on are that it is a real executable (reachable through `env`
# and `bash -c`, not only as a shell function), that the wrapped command
# keeps the caller's stdin, and that expiry reports 124 the way coreutils does.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    unset TIMEOUT_BIN
    export WS_TEST_FORCE_TIMEOUT_FALLBACK=1
    # shellcheck source=../timeout_helper.bash
    source "$REPO_ROOT/tests/timeout_helper.bash"
}

@test "the fallback is an executable file, not a function" {
    [ -x "$TIMEOUT_BIN" ]
    run env "$TIMEOUT_BIN" 5 true
    [ "$status" -eq 0 ]
}

@test "the wrapped command keeps the caller's stdin" {
    run "$TIMEOUT_BIN" 5 cat <<< "payload intact"
    [ "$status" -eq 0 ]
    [ "$output" = "payload intact" ]
}

@test "a command that outlives its budget is killed and reports 124" {
    run "$TIMEOUT_BIN" 1 sleep 10
    [ "$status" -eq 124 ]
}

@test "a command's own exit status passes through" {
    run "$TIMEOUT_BIN" 5 bash -c 'exit 7'
    [ "$status" -eq 7 ]
}
