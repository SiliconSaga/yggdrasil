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

@test "expiry reports 124 even when the command traps TERM and exits otherwise" {
    # git-cr.sh and ws-test.sh install TERM traps; inferring expiry from a
    # 143 exit would report their timeouts as ordinary failures.
    run "$TIMEOUT_BIN" 1 bash -c 'trap "exit 7" TERM; sleep 10 & wait'
    [ "$status" -eq 124 ]
}

@test "a command that finishes early returns at once, with no sleeper left behind" {
    # bats waits for every process holding its output descriptor, so a
    # watchdog sleep that outlived the command would stall `run` for the
    # whole budget. Wall-clock bounds it: 5s budget, must return in under 3.
    local started=$SECONDS
    run "$TIMEOUT_BIN" 5 true
    [ "$status" -eq 0 ]
    [ $((SECONDS - started)) -lt 3 ]
}

@test "expiry terminates the wrapped command's children too" {
    # The hang the wrapper exists to catch is a `bash ws …` whose child
    # (a git fetch, say) never returns; killing only the shell would leave
    # that child running and the runner waiting on it.
    [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]] && skip "process groups are not reliably signalled under MSYS"
    local pidfile="$BATS_TEST_TMPDIR/grandchild.pid"
    run "$TIMEOUT_BIN" 1 bash -c "sleep 30 & echo \$! > '$pidfile'; wait"
    [ "$status" -eq 124 ]
    local grandchild
    grandchild=$(cat "$pidfile")
    sleep 1
    ! kill -0 "$grandchild" 2>/dev/null
}
