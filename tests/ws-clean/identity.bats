#!/usr/bin/env bats

# Tests for `ws clean`'s session-identity carve-out.
#
# Invariant: after `ws clean`, the CURRENT session's identity file
# (.tmp/gdd-agent-sessions/<current-session-id>.env) still exists, while a
# DIFFERENT session's file under the same dir is removed. Cleaning your own
# session would break your own next commit; other sessions' files are clutter.

load test_helper

setup() {
    init_clean_workspace
}

@test "ws clean spares the current session's identity, sweeps others" {
    export WS_CLEAN_MINE_THRESHOLD=1
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR="A <a@b.c>"\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env"
    printf 'GDD_CO_AUTHOR="B <b@c.d>"\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env"
    # A sibling top-level .tmp/ entry, unrelated to sessions: must still be
    # wholesale-removed (pins that the carve-out only spares `keep`, not all
    # of .tmp/).
    mkdir -p "$ROOT_DIR/.tmp/other-scratch"
    printf 'scratch\n' > "$ROOT_DIR/.tmp/other-scratch/file.txt"
    run env GDD_SESSION_ID=keep-me "$TIMEOUT_BIN" 10 bash "$WS_BIN" clean --force
    [ "$status" -eq 0 ]
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env" ]
    [ ! -f "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env" ]
    [ ! -e "$ROOT_DIR/.tmp/other-scratch" ]
    # The tally reflects what was actually removed: the spared sessions dir
    # is not counted as cleaned (2 top-level .tmp/ entries, 1 spared).
    [[ "$output" == *"Cleaned 1 draft file(s) total."* ]]
}
