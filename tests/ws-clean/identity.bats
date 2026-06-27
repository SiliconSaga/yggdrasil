#!/usr/bin/env bats

# Tests for `ws clean`'s session-identity handling.
#
# Default: the whole .tmp/gdd-agent-sessions/ dir is spared — a finishing
# session running `ws clean` must not wipe a CONCURRENT session's identity
# (or future per-session settings). With --sessions, ended sessions' files
# are swept but the current session's is still spared. Unrelated .tmp/
# scratch is always swept.

load test_helper

setup() {
    init_clean_workspace
}

seed_sessions() {
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR=A <a@b.c>\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env"
    printf 'GDD_CO_AUTHOR=B <b@c.d>\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env"
    # A sibling top-level .tmp/ entry, unrelated to sessions — always swept.
    mkdir -p "$ROOT_DIR/.tmp/other-scratch"
    printf 'scratch\n' > "$ROOT_DIR/.tmp/other-scratch/file.txt"
}

@test "ws clean spares ALL session identities by default (protects concurrent sessions)" {
    export WS_CLEAN_MINE_THRESHOLD=1
    seed_sessions
    run env GDD_SESSION_ID=keep-me "$TIMEOUT_BIN" 10 bash "$WS_BIN" clean --force
    [ "$status" -eq 0 ]
    # Neither the current session's nor another session's identity is touched.
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env" ]
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env" ]
    # Unrelated scratch is still swept.
    [ ! -e "$ROOT_DIR/.tmp/other-scratch" ]
}

@test "ws clean --sessions-all sweeps ended sessions but spares the current one" {
    export WS_CLEAN_MINE_THRESHOLD=1
    seed_sessions
    run env GDD_SESSION_ID=keep-me "$TIMEOUT_BIN" 10 bash "$WS_BIN" clean --force --sessions-all
    [ "$status" -eq 0 ]
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env" ]
    [ ! -f "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env" ]
    [ ! -e "$ROOT_DIR/.tmp/other-scratch" ]
}

@test "ws clean --sessions spares ALL session files (no longer prunes ended sessions)" {
    export WS_CLEAN_MINE_THRESHOLD=1
    seed_sessions
    run env GDD_SESSION_ID=keep-me "$TIMEOUT_BIN" 10 bash "$WS_BIN" clean --force --sessions
    [ "$status" -eq 0 ]
    # --sessions is now a no-op for session pruning — both current and other
    # sessions' files must survive, just like the default.
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/keep-me.env" ]
    [ -f "$ROOT_DIR/.tmp/gdd-agent-sessions/other.env" ]
    [ ! -e "$ROOT_DIR/.tmp/other-scratch" ]
}
