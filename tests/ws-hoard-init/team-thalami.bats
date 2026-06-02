#!/usr/bin/env bats
# Tests for the team-thalami hoard template: presence + scaffold.

load test_helper

setup() { init_workspace; }

@test "team-thalami template ships the required files" {
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/README.md" ]
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/.ws-cadence.yaml" ]
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/.gitignore" ]
}

@test "ws hoard help lists the team-thalami template" {
    run bash "$REPO_ROOT/scripts/ws-hoard.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"team-thalami"* ]]
}
