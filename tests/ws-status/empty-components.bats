#!/usr/bin/env bats
# A fresh workspace has no components cloned and often no components map at
# all in its ecosystem config. The component walk in ws status / ws list must
# treat a null/missing map as empty instead of surfacing a yq error — this is
# first-run noise on the exact commands a newcomer is told are safe to run.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/realms" "$WORK/hoards"

    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/missing-local.yaml"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
}

@test "ws status stays quiet when the ecosystem has no components key" {
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
YAML

    run bash "$REPO_ROOT/scripts/ws-status.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *"cannot get keys"* ]]
    [[ "$output" != *"Error:"* ]]
    [[ "$output" == *"=== yggdrasil ==="* ]]
}

@test "ws status stays quiet when components is explicitly null" {
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
components:
YAML

    run bash "$REPO_ROOT/scripts/ws-status.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *"cannot get keys"* ]]
    [[ "$output" != *"Error:"* ]]
}

@test "ws list stays quiet when the ecosystem has no components key" {
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
YAML

    run bash "$REPO_ROOT/scripts/ws-list.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *"cannot get keys"* ]]
    [[ "$output" != *"Error:"* ]]
}

@test "ws status rejects a traversal-shaped component key" {
    cat > "$ECOSYSTEM" <<'YAML'
components:
  ../outside:
    repo: https://example.test/outside.git
YAML

    run bash "$REPO_ROOT/scripts/ws-status.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component name"* ]]
    [[ "$output" != *"../outside"* ]]
}
