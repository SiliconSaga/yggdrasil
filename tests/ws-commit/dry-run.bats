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

@test "--dry-run fails when a remove: path can't be staged" {
    # Bodyfile lists a remove: path that doesn't exist on disk and
    # isn't tracked either — `git rm --dry-run` errors. In real
    # commit mode this would have been a warning, but for dry-run
    # the whole point is "would this commit succeed?" — surfacing
    # a non-zero exit is the correct preview.
    cat > "$BATS_TEST_TMPDIR/body.md" <<'EOF'
---
message: "test: dry-run with bad remove"
add:
  - test.md
remove:
  - this-file-does-not-exist.md
---

Body.
EOF
    echo "modified" >> "$REPO_DIR/test.md"

    head_before="$(git -C "$REPO_DIR" rev-parse HEAD)"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: could not stage removal"* ]]
    # HEAD didn't move, index unchanged
    [ "$(git -C "$REPO_DIR" rev-parse HEAD)" = "$head_before" ]
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

@test "--dry-run succeeds when index is pre-staged even with no bodyfile adds" {
    # Regression: dry-run used to fail whenever `would_stage_any=0`,
    # but that ignored the legitimate case of an operator who
    # manually staged something via `git add` BEFORE invoking
    # `ws commit --dry-run`. Real-mode would happily commit the
    # pre-staged content; dry-run should mirror that.
    #
    # Set up: pre-stage a modification, then write a bodyfile with
    # an empty add: list. Dry-run should accept the index as the
    # source of staged changes.
    echo "pre-staged-edit" >> "$REPO_DIR/test.md"
    git -C "$REPO_DIR" add test.md
    # Bodyfile with no add: entries — message only.
    cat > "$BATS_TEST_TMPDIR/body.md" <<'EOF'
---
message: "test: pre-staged via manual git add"
---

Body.
EOF

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" == *"test: pre-staged via manual git add"* ]]
}

@test "--dry-run fails when add: lists only unchanged files (fidelity with real-mode)" {
    # Real-mode catches "no staged changes" after the add: loop runs
    # against unchanged files (git add produces nothing, the cached-
    # diff check fires). Dry-run used to skip that check entirely
    # and report a successful preview anyway — false positive that
    # the user would only discover by trying the real commit.
    #
    # Fix: track whether `git add --dry-run -A` produced any output
    # (silent on unchanged paths) and fail dry-run if nothing would
    # be staged.
    #
    # test.md is committed at "hello"; bodyfile lists it without
    # any modification, so the add would no-op.
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: dry-run of unchanged" "test.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"no stageable changes"* ]] \
        || [[ "$output" == *"No staged changes"* ]]
}

@test "--dry-run handles tracked-deleted file in add: list via git add -A" {
    # Bodyfile validation accepts a tracked-but-deleted path in
    # add: (the user deleted from disk and listed in add: meaning
    # "stage the deletion this way"). Previously the underlying
    # `git add <path>` errored with "pathspec did not match any
    # files" because plain git-add doesn't stage deletions by path —
    # `-A` does. Under `set -e` that error aborted the dry-run
    # preview before the user saw what else was in the bodyfile.
    #
    # The fix is `git add -A "$f"` (and the same for --dry-run).
    # This test exercises the dry-run path with a tracked-deleted
    # entry and expects it to succeed.
    rm "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: deletion via add:" "test.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    # Working tree still has test.md deleted (dry-run doesn't restore)
    [ ! -e "$REPO_DIR/test.md" ]
}

@test "--dry-run does not create .commits/ directory on a fresh clone" {
    # Regression: dry-run's contract is "DO NOT touch the index, working
    # tree, or git history." Earlier versions ran an unconditional
    # `mkdir -p $ROOT_DIR/.commits` before the dry_run branch, which
    # created an untracked directory on disk during a preview — a
    # working-tree change a user might be surprised by on a brand-new
    # clone. The fix gates the mkdir behind `if ! $dry_run`. The
    # synthetic repo here doesn't pre-create .commits/, so its
    # absence after the dry-run proves the gate works.
    [ ! -e "$REPO_DIR/.commits" ]
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: no mkdir in dry-run" "test.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [ ! -e "$REPO_DIR/.commits" ]
}

@test "--dry-run prints the Co-Authored-By trailer in the preview" {
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: trailer visible" "test.md"

    run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Co-Authored-By:"* ]]
}

@test "--dry-run uses GDD_CO_AUTHOR as a full agent-neutral trailer identity" {
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: generic co-author" "test.md"

    GDD_CO_AUTHOR="Codex GPT-5 <noreply@openai.com>" \
        run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Co-Authored-By: Codex GPT-5 <noreply@openai.com>"* ]]
    [[ "$output" != *"Co-Authored-By: Claude"* ]]
}

@test "GDD_CO_AUTHOR without an email is rejected" {
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: missing email" "test.md"

    GDD_CO_AUTHOR="Codex GPT-5" \
        run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"must include an email in angle brackets"* ]]
}

@test "GDD_CO_AUTHOR with junk (no @) in the brackets is rejected" {
    # The old check only verified < and > were present; an email-shaped
    # token (with @) is now required so '<not an email>' no longer passes.
    echo "x" >> "$REPO_DIR/test.md"
    write_bodyfile "$BATS_TEST_TMPDIR/body.md" \
        "test: junk identity" "test.md"

    GDD_CO_AUTHOR="Codex GPT-5 <not an email>" \
        run_ws_commit yggdrasil --dry-run "$BATS_TEST_TMPDIR/body.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"must include an email in angle brackets"* ]]
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
