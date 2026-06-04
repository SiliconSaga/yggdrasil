#!/usr/bin/env bats
load test_helper

setup() { init_publish_workspace; }

@test "ws thalami help lists the publish subcommand" {
    run bash "$WS_THALAMI_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"publish"* ]]
}
