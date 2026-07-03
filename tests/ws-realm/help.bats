#!/usr/bin/env bats

# `ws realm init --help` must print usage and return, NOT start cloning the
# template realm. Regression for the dispatcher dropping args before
# ws_realm_init (so --help fell through and ran the command).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

@test "ws realm init --help prints usage and does not run" {
    run bash "$WS_BIN" realm init --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws realm init"* ]]
}

@test "ws realm init -h prints usage too" {
    run bash "$WS_BIN" realm init -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws realm init"* ]]
}
