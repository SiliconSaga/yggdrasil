#!/usr/bin/env bats
load test_helper
setup() { setup_whoami; }

@test "whoami --set writes the session identity, then whoami shows it" {
    run_ws whoami --set "Codex GPT-5 <noreply@openai.com>"
    [ "$status" -eq 0 ]
    run_ws whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *"Codex GPT-5 <noreply@openai.com>"* ]]
    [[ "$output" == *"via session file"* ]]
}
@test "whoami --set accepts the split name + bare-email form (agent/hook-safe)" {
    run_ws whoami --set "Claude Opus 4.8" noreply@anthropic.com
    [ "$status" -eq 0 ]
    run_ws whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Opus 4.8 <noreply@anthropic.com>"* ]]
    [[ "$output" == *"via session file"* ]]
}
@test "whoami --set preserves shell-significant characters as data" {
    run_ws whoami --set 'Codex "Quoted" $Model' noreply@openai.com
    [ "$status" -eq 0 ]
    run_ws whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *'Codex "Quoted" $Model <noreply@openai.com>'* ]]
}
@test "whoami --set rejects an identity with no email" {
    run_ws whoami --set "Codex GPT-5"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must include an email"* ]]
}
@test "whoami --set rejects extra args (unquoted multi-word name)" {
    run_ws whoami --set Claude Opus 4.8 noreply@anthropic.com
    [ "$status" -ne 0 ]
    [[ "$output" == *"quote a multi-word name"* ]]
}
@test "whoami errors cleanly when no identity established" {
    run_ws whoami
    [ "$status" -ne 0 ]
    [[ "$output" == *"No commit identity for this session"* ]]
}
@test "whoami --help exits 0" {
    run_ws whoami --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws whoami"* ]]
}
@test "whoami with no session reports no agent session (not an error)" {
    run env WS_FOOTER_DISABLE=1 GDD_SESSION_ID="" bash "$WS_BIN" whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *"No agent session"* ]]
    [[ "$output" == *"--human"* ]]
}
