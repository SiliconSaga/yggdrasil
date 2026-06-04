#!/usr/bin/env bats

# ws commit --help documents model attribution + the sub-agent inline rule.
#
# --help needs no synthetic repo, so we don't call init_synthetic_repo here —
# but we load the shared helper for $WS_COMMIT_BIN (matches dry-run.bats).

load test_helper

@test "ws commit --help mentions CLAUDE_MODEL and the .env default" {
    run bash "$WS_COMMIT_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLAUDE_MODEL"* ]]
    [[ "$output" == *".env"* ]]
}

@test "ws commit --help explains the sub-agent inline override" {
    run bash "$WS_COMMIT_BIN" --help
    [ "$status" -eq 0 ]
    # Case-insensitive, but Bash 3.2-safe (macOS /bin/bash predates the
    # ${var,,} downcase): the help uses "SUB-AGENTS:" as a heading and
    # "sub-agents" in prose, so downcase via tr and match either without
    # depending on which case wins.
    local lower
    lower="$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')"
    [[ "$lower" == *"sub-agent"* ]]
}
