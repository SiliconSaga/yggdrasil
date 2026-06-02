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

@test "ws hoard init team-thalami scaffolds files without machine seeding" {
    run bash "$WS_HOARD_BIN" init team-thalami --name team-thalami-cfr
    [ "$status" -eq 0 ]
    [ -f "$HOARDS_DIR/team-thalami-cfr/TeamArcDashboard.md" ]
    [ -f "$HOARDS_DIR/team-thalami-cfr/README.md" ]
    [ -d "$HOARDS_DIR/team-thalami-cfr/.git" ]
    # No per-machine thalamus file is seeded for this flavor
    run bash -c "compgen -G '$HOARDS_DIR/team-thalami-cfr/*-thalamus.md'"
    [ "$status" -ne 0 ]
}

@test "thalamus seed documents published/user/vault fields" {
    local t="$REPO_ROOT/templates/thalamus.md"
    grep -q '^user: null' "$t"
    grep -q '^vault: null' "$t"
    grep -q 'published (true.*flag' "$t"
}

@test "personal ArcDashboard schema documents published + vault" {
    local d="$REPO_ROOT/templates/hoards/thalami/ArcDashboard.md"
    grep -q '# published: true' "$d"
    grep -q '# vault: <path>' "$d"
}

@test "personal ArcDashboard prepends a conditional team icon" {
    local d="$REPO_ROOT/templates/hoards/thalami/ArcDashboard.md"
    grep -qF 'choice(arc.published = true, "📡 ", "") + choice(arc.status = "active",' "$d"
}
