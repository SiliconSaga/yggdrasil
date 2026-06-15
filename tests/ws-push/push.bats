#!/usr/bin/env bats

load test_helper

setup() {
    init_push_repo
}

@test "pushes an explicit local tag as a tag ref" {
    git -C "$REPO_DIR" tag v0.1.0

    run_git_push v0.1.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushing tag v0.1.0"* ]]
    remote_ref_exists refs/tags/v0.1.0
    [ "$(git -C "$REPO_DIR" rev-parse refs/tags/v0.1.0)" = "$(remote_ref_sha refs/tags/v0.1.0)" ]
}

@test "pushing a tag does not create an upstream branch" {
    git -C "$REPO_DIR" tag v0.2.0

    run_git_push v0.2.0

    [ "$status" -eq 0 ]
    ! remote_ref_exists refs/heads/v0.2.0
}

@test "keeps explicit branch push upstream behavior" {
    git -C "$REPO_DIR" switch -q -c feature/tag-support
    echo "change" >> "$REPO_DIR/file.txt"
    git -C "$REPO_DIR" add file.txt
    git -C "$REPO_DIR" commit -q -m "feature work"

    run_git_push feature/tag-support

    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushing feature/tag-support"* ]]
    remote_ref_exists refs/heads/feature/tag-support
    [ "$(git -C "$REPO_DIR" rev-parse --abbrev-ref --symbolic-full-name feature/tag-support@{upstream})" = "fork/feature/tag-support" ]
}

@test "refuses an explicit name that is both a local branch and local tag" {
    git -C "$REPO_DIR" switch -q -c release
    git -C "$REPO_DIR" tag release

    run_git_push release

    [ "$status" -ne 0 ]
    [[ "$output" == *"ambiguous"* ]]
    [[ "$output" == *"refs/heads/release"* ]]
    [[ "$output" == *"refs/tags/release"* ]]
}

@test "refuses force-pushing tags" {
    git -C "$REPO_DIR" tag v0.3.0

    run_git_push --force v0.3.0

    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing to force-push tag v0.3.0"* ]]
}
