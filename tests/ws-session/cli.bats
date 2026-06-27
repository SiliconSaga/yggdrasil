#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"; mkdir -p "$ROOT_DIR/.tmp"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
    export GDD_SESSION_ID="cli-test"
}
run_ws() { run env WS_FOOTER_DISABLE=1 bash "$WS_BIN" "$@"; }

@test "ws session set then get round-trips" {
    run_ws session set GDD_STANCE flow
    [ "$status" -eq 0 ]
    run_ws session get GDD_STANCE
    [ "$status" -eq 0 ]
    [ "$output" = "flow" ]
}

@test "ws session get prints the value with a trailing newline" {
    run_ws session set GDD_STANCE flow
    # Append a marker so bats' trailing-newline stripping doesn't hide the
    # newline under test — the value must end with \n so the ws footer / the
    # next shell prompt doesn't butt up against it.
    run bash -c "bash '$WS_BIN' session get GDD_STANCE; printf MARK"
    [ "$output" = $'flow\nMARK' ]
}

@test "ws session show lists all keys" {
    run_ws session set GDD_STANCE flow
    run_ws session set GDD_ROLE developer
    run_ws session show
    [[ "$output" == *"GDD_STANCE=flow"* ]]
    [[ "$output" == *"GDD_ROLE=developer"* ]]
}

@test "ws session with an unknown subcommand errors" {
    run_ws session frobnicate
    [ "$status" -ne 0 ]
}
