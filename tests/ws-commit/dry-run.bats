#!/usr/bin/env bats

# Tests for `ws commit --dry-run`. The flag should:
#   - validate the bodyfile (message + add: paths)
#   - report what would be staged via `git add --dry-run`
#   - print the full commit message that WOULD land
#   - exit 0 successfully
#   - leave the index unchanged
#   - leave HEAD unchanged
#   - leave the working tree unchanged

load test_helper

setup() {
    init_synthetic_repo
}

@test "--dry-run on a clean modification: succeeds, previews, no commit" {
    echo "modified" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: dry-run smoke" \
        "test.md" \
        "Body explanation goes here."

    head_before="$(git -C "$REPO_DIR" rev-parse HEAD)"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" == *"test: dry-run smoke"* ]]
    [[ "$output" == *"Body explanation goes here."* ]]
    [[ "$output" == *"No changes were made"* ]]

    # HEAD did not move
    head_after="$(git -C "$REPO_DIR" rev-parse HEAD)"
    [ "$head_before" = "$head_after" ]

    # Nothing was staged
    git -C "$REPO_DIR" diff --cached --quiet
}

@test "--dry-run accepts the flag before the bodyfile (positional-flexible)" {
    echo "more" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: flag position" "test.md"

    # Flag is second positional, bodyfile is third — positional-friendly form.
    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
}

@test "--dry-run accepts the flag after the bodyfile" {
    echo "more" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: flag at end" "test.md"

    # Flag appears LAST — the arg parser strips it regardless of position.
    run_ws_commit yggdrasil "$BATS_TEST_TMPDIR/body.md" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
}

@test "--dry-run fails when a listed add path doesn't exist" {
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: bad path" "does-not-exist.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"file not found"* ]]
    # HEAD still didn't move (the early-validation exits before commit)
    # — nothing to do here; the assertion above is sufficient since
    # status != 0 already means commit wasn't reached.
}

@test "--dry-run still works when there are no pre-staged changes" {
    # No modifications to test.md, no pre-staging. The real-commit path
    # would error with "no staged changes"; --dry-run must skip that
    # check because it intentionally doesn't stage anything.
    echo "fresh content" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: no pre-staging" "test.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    # Index still clean
    git -C "$REPO_DIR" diff --cached --quiet
}

@test "--dry-run preserves working-tree modifications" {
    # The user's local edits to test.md should still be present after
    # the dry-run — the script must not stash, reset, or otherwise
    # munge what's on disk.
    echo "user-edit-line-1" >> "$REPO_DIR/test.md"
    echo "user-edit-line-2" >> "$REPO_DIR/test.md"
    before="$(cat "$REPO_DIR/test.md")"

    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: preserve worktree" "test.md"
    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    after="$(cat "$REPO_DIR/test.md")"
    [ "$before" = "$after" ]
}

@test "--dry-run prints the Co-Authored-By trailer in the preview" {
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: trailer visible" "test.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Co-Authored-By:"* ]]
}

@test "real (non-dry-run) commit still works against the synthetic repo" {
    # Regression guard: my dry-run plumbing shouldn't have broken the
    # normal commit path. Same fixture, same bodyfile, no flag.
    echo "real" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: real commit" "test.md"

    head_before="$(git -C "$REPO_DIR" rev-parse HEAD)"
    run_ws_commit yggdrasil "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    head_after="$(git -C "$REPO_DIR" rev-parse HEAD)"
    [ "$head_before" != "$head_after" ]
    # The new commit message matches the bodyfile
    last_msg="$(git -C "$REPO_DIR" log -1 --format='%s')"
    [ "$last_msg" = "test: real commit" ]
}
