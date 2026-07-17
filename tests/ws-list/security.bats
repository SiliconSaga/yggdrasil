#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$WORK/scripts" "$WORK/components" "$WORK/realms"
    cp "$REPO_ROOT/scripts/ws-list.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"
}

@test "ws list rejects component keys outside the shared name grammar" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  "odd key":
    tier: supporting
    chartVersion: 1.2.3
YAML

    run bash "$WORK/scripts/ws-list.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component name"* ]]
    [[ "$output" != *"odd key"* ]]
}

@test "ws list rejects yq-shaped component keys without exposing unrelated values" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  secret: must-not-be-selected
components:
  'probe"] | .defaults.secret | ["x':
    tier: literal-tier
    chartVersion: literal-chart
YAML

    run bash "$WORK/scripts/ws-list.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component name"* ]]
    [[ "$output" != *'probe"] | .defaults.secret | ["x'* ]]
    [[ "$output" != *"must-not-be-selected"* ]]
}

@test "component writes use strenv rather than expression interpolation" {
    run grep -F 'yq -i ".components.\"$name\".repo = \"$repo_url\""' "$REPO_ROOT/scripts/ws-component.sh"

    [ "$status" -ne 0 ]
    run grep -F 'COMPONENT_NAME="$name" REPO_URL="$repo_url"' "$REPO_ROOT/scripts/ws-component.sh"
    [ "$status" -eq 0 ]
}

@test "workspace component iteration does not word-split yq output" {
    # grep, not rg: on an rg-less machine `run rg` would fail with
    # command-not-found (also nonzero) and this test would pass vacuously.
    run grep -rF 'for name in $(yq' "$REPO_ROOT/scripts"

    [ "$status" -eq 1 ]
}
