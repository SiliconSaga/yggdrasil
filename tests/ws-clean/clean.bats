#!/usr/bin/env bats

# Tests for `ws clean` and its mining-threshold push-back.
#
# Behavior under test:
#   - below WS_CLEAN_MINE_THRESHOLD and no --force → hold off, delete
#     nothing (scratch files survive to be mined by housekeeping)
#   - below threshold WITH --force → clean anyway
#   - at/above threshold → clean without --force
#   - empty scratch dirs → "nothing to clean"
#   - counts span all scratch dirs incl. .tmp
#   - env override + invalid-value fallback
#   - arg handling: --help, unknown flag

load test_helper

setup() {
    init_clean_workspace
}

@test "below threshold without --force: holds off and deletes nothing" {
    export WS_CLEAN_MINE_THRESHOLD=5
    make_drafts .commits 2
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Holding off"* ]]
    [[ "$output" == *"threshold of 5"* ]]
    [[ "$output" == *"ws clean --force"* ]]
    # Nothing deleted
    [ "$(count_scratch)" -eq 2 ]
}

@test "below threshold with --force: cleans" {
    export WS_CLEAN_MINE_THRESHOLD=5
    make_drafts .commits 2
    run_ws clean --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned 2 draft file(s) total."* ]]
    [ "$(count_scratch)" -eq 0 ]
}

@test "force clean handles paths with spaces" {
    export WS_CLEAN_MINE_THRESHOLD=1
    printf 'x\n' > "$ROOT_DIR/.commits/with space.md"
    run_ws clean --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned 1 draft file(s) total."* ]]
    [ ! -e "$ROOT_DIR/.commits/with space.md" ]
    [ "$(count_scratch)" -eq 0 ]
}

@test "newline scratch names cannot delete a relative directory in the caller cwd" {
    mkdir -p "$WORK/protected"
    printf 'keep\n' > "$WORK/protected/file"
    printf 'scratch\n' > "$WORK/.tmp/"$'scratch\nprotected'
    cd "$WORK"
    run_ws clean --force
    [ "$status" -eq 0 ]
    [ -f "$WORK/protected/file" ]
    [ ! -e "$WORK/.tmp/"$'scratch\nprotected' ]
    [[ "$output" == *"Cleaned 1 draft file(s) total."* ]]
}

@test "newlines in draft filenames cannot inflate the mining threshold" {
    export WS_CLEAN_MINE_THRESHOLD=3
    printf 'draft\n' > "$WORK/.commits/"$'one\ntwo\nthree.md'
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"only 1 scratch file(s)"* ]]
    [ -f "$WORK/.commits/"$'one\ntwo\nthree.md' ]
    run_ws clean --force
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/.commits/"$'one\ntwo\nthree.md' ]
}

@test "symlinked draft directories cannot clean files outside the workspace" {
    local outside="$BATS_TEST_TMPDIR/outside"
    mkdir -p "$outside"
    printf 'keep\n' > "$outside/keep.md"
    rmdir "$WORK/.crs"
    ln -s "$outside" "$WORK/.crs"
    [ -L "$WORK/.crs" ] || skip "symlinks are unavailable on this filesystem"
    run_ws clean --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"symlinked draft directory"* ]]
    [ -f "$outside/keep.md" ]
}

@test "at/above threshold without --force: cleans" {
    export WS_CLEAN_MINE_THRESHOLD=2
    make_drafts .commits 2
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned 2 draft file(s) total."* ]]
    [[ "$output" != *"Holding off"* ]]
    [ "$(count_scratch)" -eq 0 ]
}

@test "no scratch files: reports nothing to clean" {
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"(no draft files to clean)"* ]]
}

@test "count spans all scratch dirs including .tmp" {
    export WS_CLEAN_MINE_THRESHOLD=100
    make_drafts .commits 2
    make_drafts .crs 1
    make_drafts .outputs 3
    printf 'scratch\n' > "$ROOT_DIR/.tmp/leftover.txt"
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Holding off"* ]]
    # 2 + 1 + 3 + 1 = 7
    [[ "$output" == *"only 7 scratch file(s)"* ]]
    [[ "$output" == *".commits/"* ]]
    [[ "$output" == *".outputs/"* ]]
    [[ "$output" == *".tmp/"* ]]
    [ "$(count_scratch)" -eq 7 ]
}

@test "env threshold of 1: a single file cleans without --force" {
    export WS_CLEAN_MINE_THRESHOLD=1
    make_drafts .crs 1
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned 1 draft file(s) total."* ]]
    [ "$(count_scratch)" -eq 0 ]
}

@test "invalid WS_CLEAN_MINE_THRESHOLD falls back to 50 with a warning" {
    export WS_CLEAN_MINE_THRESHOLD=abc
    make_drafts .commits 1
    run_ws clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a non-negative integer"* ]]
    # 1 < 50 fallback → holds off, nothing deleted
    [[ "$output" == *"Holding off"* ]]
    [ "$(count_scratch)" -eq 1 ]
}

@test "--help prints usage and exits 0" {
    run_ws clean --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws clean [--force]"* ]]
}

@test "unknown flag errors with usage (exit 1)" {
    run_ws clean --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: ws clean [--force]"* ]]
}
