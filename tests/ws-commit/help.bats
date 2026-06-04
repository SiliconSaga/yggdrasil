#!/usr/bin/env bats

# ws commit --help documents model attribution + the sub-agent inline rule.

setup() {
    ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "ws commit --help mentions CLAUDE_MODEL and the .env default" {
    run bash "$ROOT_DIR/scripts/ws-commit.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLAUDE_MODEL"* ]]
    [[ "$output" == *".env"* ]]
}

@test "ws commit --help explains the sub-agent inline override" {
    run bash "$ROOT_DIR/scripts/ws-commit.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"sub-agent"* ]]
}
