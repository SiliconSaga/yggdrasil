#!/usr/bin/env bats

# ws commit's side of the PII guard: every part of the commit that publishes is
# scanned, and a dry run reaches the same verdict the real run would.

load test_helper

setup() {
    init_synthetic_repo
}

@test "an address in the commit subject is refused" {
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: ask someone.new@newdomain.co.uk" "test.md" ""

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *"someone.new@newdomain.co.uk"* ]]
    [[ "$output" == *"re-run with --allow-pii"* ]]
}

@test "a dry run refuses what the real run would, without staging it" {
    # `git add --dry-run` stages nothing, so a guard reading the live index
    # passed the preview and failed the identical real invocation.
    echo "contact: someone.new@newdomain.co.uk" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" ""

    run_ws_commit --dry-run yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *"someone.new@newdomain.co.uk"* ]]
    run git -C "$REPO_DIR" diff --cached --quiet
    [ "$status" -eq 0 ]
}

@test "--allow-pii still lets a deliberate address through" {
    echo "contact: someone.new@newdomain.co.uk" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" ""

    run_ws_commit --allow-pii yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
}
