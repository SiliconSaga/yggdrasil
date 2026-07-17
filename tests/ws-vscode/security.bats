#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$WORK/scripts" "$WORK/components" "$WORK/realms" "$WORK/hoards"
    cp "$REPO_ROOT/scripts/ws-vscode.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
}

@test "vscode rejects a component key that escapes the components directory" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  ../outside:
    repo: https://example.com/outside.git
YAML
    mkdir -p "$WORK/outside/.git"

    run bash "$WORK/scripts/ws-vscode.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component name"* ]]
    [[ "$output" != *"../outside"* ]]
    [ ! -e "$WORK/yggdrasil.code-workspace" ]
}

@test "vscode emits a valid workspace for a safe cloned component" {
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  safe.component:
    repo: https://example.com/safe.git
YAML
    mkdir -p "$WORK/components/safe.component/.git"

    run bash "$WORK/scripts/ws-vscode.sh"

    [ "$status" -eq 0 ]
    run yq -r '.folders[].path' "$WORK/yggdrasil.code-workspace"
    [ "$status" -eq 0 ]
    [[ "$output" == *"components/safe.component"* ]]
}
