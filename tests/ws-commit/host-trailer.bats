#!/usr/bin/env bats

# `identity.commitHost` stamps which machine made a commit, as its own
# trailer. Opt-in by a config entry only: a host name is the kind of value
# that leaks, so nothing is stamped unless the operator wrote it down.

load test_helper

setup() {
    init_synthetic_repo
    echo "changed" >> "$REPO_DIR/test.md"
    BODYFILE="$REPO_DIR/.commits/change.md"
    mkdir -p "$REPO_DIR/.commits"
    write_bodyfile "$BODYFILE" "feat: a change" "test.md"
}

@test "no commitHost entry: no host trailer" {
    run bash "$WS_COMMIT_BIN" yggdrasil "$BODYFILE"
    [ "$status" -eq 0 ]
    run git -C "$REPO_DIR" log -1 --format=%B
    [[ "$output" == *"Co-Authored-By: Claude Opus 4.8"* ]]
    [[ "$output" != *"GDD-Host:"* ]]
}

@test "commitHost: true stamps this machine's hostname as a separate trailer" {
    printf 'identity:\n  human_account: testuser\n  commitHost: true\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_COMMIT_BIN" yggdrasil "$BODYFILE"
    [ "$status" -eq 0 ]
    run git -C "$REPO_DIR" log -1 --format=%B
    [[ "$output" == *"Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"* ]]
    [[ "$output" == *"GDD-Host: $(hostname)"* ]]
}

@test "commitHost: <label> stamps the label instead of the real hostname" {
    printf 'identity:\n  human_account: testuser\n  commitHost: lab-box\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_COMMIT_BIN" yggdrasil "$BODYFILE"
    [ "$status" -eq 0 ]
    run git -C "$REPO_DIR" log -1 --format=%B
    [[ "$output" == *"GDD-Host: lab-box"* ]]
    [[ "$output" != *"GDD-Host: $(hostname)"* ]]
}

@test "commitHost: false is the same as absent" {
    printf 'identity:\n  human_account: testuser\n  commitHost: false\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_COMMIT_BIN" yggdrasil "$BODYFILE"
    [ "$status" -eq 0 ]
    run git -C "$REPO_DIR" log -1 --format=%B
    [[ "$output" != *"GDD-Host:"* ]]
}
