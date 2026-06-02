#!/usr/bin/env bats
# Tests for the team-thalami hoard template: presence + scaffold.

load test_helper

setup() { init_workspace; }

@test "team-thalami template ships the required files" {
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/README.md" ]
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/TeamArcDashboard.md" ]
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/.ws-cadence.yaml" ]
    [ -f "$REPO_ROOT/templates/hoards/team-thalami/.gitignore" ]
}

@test "ws hoard help lists the team-thalami template" {
    run bash "$REPO_ROOT/scripts/ws-hoard.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"team-thalami"* ]]
}

@test "TeamArcDashboard is person-keyed (User column, no publish filter)" {
    local f="$REPO_ROOT/templates/hoards/team-thalami/TeamArcDashboard.md"
    grep -q 'choice(user, user, file.folder) AS "User"' "$f"
    grep -q 'option(User)' "$f"
    # Host retained as a secondary detail column
    grep -q 'AS "Host"' "$f"
}
