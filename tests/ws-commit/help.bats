#!/usr/bin/env bats

# ws commit --help documents model attribution + the sub-agent inline rule.
#
# --help needs no synthetic repo, so we don't call init_synthetic_repo here —
# but we load the shared helper for $WS_COMMIT_BIN (matches dry-run.bats).

load test_helper

@test "ws commit --help explains per-session resolution and the --human / no-trailer paths" {
    run bash "$WS_COMMIT_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"first match wins"* ]]
    [[ "$output" == *"--human"* ]]
    [[ "$output" == *"no trailer"* ]]
}

@test "ws commit --help shows the email-shaped identity example" {
    run bash "$WS_COMMIT_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Codex GPT-5 <noreply@openai.com>"* ]]
}

@test "ws commit --help explains the sub-agent --co-author-file path" {
    run bash "$WS_COMMIT_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--co-author-file"* ]]
    # Case-insensitive, Bash 3.2-safe (macOS /bin/bash predates ${var,,}).
    local lower
    lower="$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')"
    [[ "$lower" == *"sub-agent"* ]]
}
