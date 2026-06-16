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
@test "whoami --set rejects an identity with no email" {
    run_ws whoami --set "Codex GPT-5"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must include an email"* ]]
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
