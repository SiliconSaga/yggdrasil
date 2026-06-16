#!/usr/bin/env bats
load test_helper
setup() { setup_session_env; }

@test "session id precedence: GDD_SESSION_ID wins" {
    run_session 'GDD_SESSION_ID=g CLAUDE_CODE_SESSION_ID=c CODEX_THREAD_ID=x ws_resolve_session_id'
    [ "$output" = "g" ]
}
@test "session id precedence: CLAUDE before CODEX" {
    run_session 'CLAUDE_CODE_SESSION_ID=c CODEX_THREAD_ID=x ws_resolve_session_id'
    [ "$output" = "c" ]
}
@test "session id: CODEX when only it is set" {
    run_session 'CODEX_THREAD_ID=x ws_resolve_session_id'
    [ "$output" = "x" ]
}
@test "session id: empty when none set" {
    run_session 'ws_resolve_session_id'
    [ -z "$output" ]
}
@test "identity path: under .tmp/gdd-agent-sessions keyed by id" {
    run_session 'GDD_SESSION_ID=abc ws_session_identity_path'
    [[ "$output" == *"/.tmp/gdd-agent-sessions/abc.env" ]]
}
@test "identity path: sanitizes special chars in the session id" {
    run_session 'GDD_SESSION_ID="abc/def 1" ws_session_identity_path'
    [[ "$output" == *"/.tmp/gdd-agent-sessions/abc_def_1.env" ]]
}
@test "write + resolve round-trips via the session file" {
    run_session 'GDD_SESSION_ID=s1 ws_write_session_identity "Claude Opus 4.8 <noreply@anthropic.com>"; GDD_SESSION_ID=s1 ws_resolve_co_author ""'
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Opus 4.8 <noreply@anthropic.com>" ]
}
@test "resolve: agent session with no file hard-errors" {
    run_session 'GDD_SESSION_ID=s1 ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}
@test "resolve: no session errors (no silent fallback; guides to --human)" {
    run_session 'ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity resolved"* ]]
    [[ "$output" == *"--human"* ]]
}
@test "resolve: a GDD_CO_AUTHOR in the env is never consulted (no session → still errors)" {
    run_session 'GDD_CO_AUTHOR="Drifty <x@y.z>" ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity resolved"* ]]
}
@test "resolve: a GDD_CO_AUTHOR in the env is never consulted (agent session, no file → error)" {
    run_session 'GDD_SESSION_ID=s1 GDD_CO_AUTHOR="Drifty <x@y.z>" ws_resolve_co_author ""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}
@test "resolve: --co-author-file reads the named identity file" {
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR="Sub Codex <noreply@openai.com>"\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/parent--sub.env"
    run_session 'ws_resolve_co_author "parent--sub"'
    [ "$status" -eq 0 ]
    [ "$output" = "Sub Codex <noreply@openai.com>" ]
}
@test "resolve: --co-author-file wins over the current session file" {
    mkdir -p "$ROOT_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR="Sub Codex <noreply@openai.com>"\n' > "$ROOT_DIR/.tmp/gdd-agent-sessions/parent--sub.env"
    run_session 'GDD_SESSION_ID=parent ws_write_session_identity "Parent Claude <noreply@anthropic.com>"; GDD_SESSION_ID=parent ws_resolve_co_author "parent--sub"'
    [ "$status" -eq 0 ]
    [ "$output" = "Sub Codex <noreply@openai.com>" ]
}
@test "resolve: --co-author-file naming a missing file errors" {
    run_session 'GDD_SESSION_ID=s1 ws_resolve_co_author "nope"'
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing or sets no GDD_CO_AUTHOR"* ]]
}
@test "identity path: a name resolves under the agent-sessions dir" {
    run_session 'ws_session_identity_path_for "parent--sub"'
    [[ "$output" == *"/.tmp/gdd-agent-sessions/parent--sub.env" ]]
}
