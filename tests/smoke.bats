#!/usr/bin/env bats

# Smoke tests for the yggdrasil shell-test pipeline.
#
# These exist solely to prove that bats is wired up and that
# `bash scripts/ws test yggdrasil` discovers and runs *.bats files
# in the workspace tests/ directory. Real test coverage lives in
# topic-specific files alongside this one (Phase A.3 onward).

@test "bats is wired up and can run a trivial assertion" {
    run echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "ws CLI is on disk and prints help" {
    run bash "${BATS_TEST_DIRNAME}/../scripts/ws" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
