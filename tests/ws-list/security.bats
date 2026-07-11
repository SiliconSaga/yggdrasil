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

@test "ws list preserves a complete component key without word splitting" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  "odd key":
    tier: supporting
    chartVersion: 1.2.3
YAML

    run bash "$WORK/scripts/ws-list.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"odd key"*"supporting"*"1.2.3"* ]]
}

@test "ws list treats yq-shaped component keys as literal data" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  secret: must-not-be-selected
components:
  'probe"] | .defaults.secret | ["x':
    tier: literal-tier
    chartVersion: literal-chart
YAML

    run bash "$WORK/scripts/ws-list.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *'probe"] | .defaults.secret | ["x'* ]]
    [[ "$output" == *"literal-tier"*"literal-chart"* ]]
    [[ "$output" != *"must-not-be-selected"* ]]
}

@test "component writes use strenv rather than expression interpolation" {
    run grep -F 'yq -i ".components.\"$name\".repo = \"$repo_url\""' "$REPO_ROOT/scripts/ws-component.sh"

    [ "$status" -ne 0 ]
    run grep -F 'COMPONENT_NAME="$name" REPO_URL="$repo_url"' "$REPO_ROOT/scripts/ws-component.sh"
    [ "$status" -eq 0 ]
}

@test "workspace component iteration does not word-split yq output" {
    run rg -n 'for name in \$\(yq' "$REPO_ROOT/scripts"

    [ "$status" -ne 0 ]
}
