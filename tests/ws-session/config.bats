#!/usr/bin/env bats
load test_helper

setup() { setup_session_env; }

@test "session_set then session_get round-trips one key" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = "flow" ]
}

@test "session_set preserves sibling keys (no clobber)" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_session_set GDD_ROLE developer; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = "flow" ]
}

@test "session_set updates an existing key in place" {
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_session_set GDD_STANCE quick; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = "quick" ]
}

@test "identity and stance coexist in the same file" {
    run_session 'GDD_SESSION_ID=s1 ws_write_session_identity "Claude Opus 4.8 <noreply@anthropic.com>"; GDD_SESSION_ID=s1 ws_session_set GDD_STANCE flow; GDD_SESSION_ID=s1 ws_resolve_co_author ""'
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Opus 4.8 <noreply@anthropic.com>" ]
}

@test "session_set value is data, not shell" {
    # The shell evaluates "$(echo pwn)" to "pwn" before calling ws_session_set;
    # the function stores and returns it as-is (no further eval). The
    # data-not-sourced contract is separately verified by session.bats
    # "read identity file treats shell syntax as data".
    run_session 'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE "$(echo pwn)"; GDD_SESSION_ID=s1 ws_session_get GDD_STANCE'
    [ "$status" -eq 0 ]
    [ "$output" = 'pwn' ]
}

@test "session_set rejects a newline in the value" {
    run_session $'GDD_SESSION_ID=s1 ws_session_set GDD_STANCE "fl\now"'
    [ "$status" -ne 0 ]
}
