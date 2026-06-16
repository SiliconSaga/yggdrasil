#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GLAB_LOG="$BATS_TEST_TMPDIR/glab.args"
    BODYFILE="$BATS_TEST_TMPDIR/body.md"
    echo "body text" > "$BODYFILE"

    # shellcheck source=../../scripts/providers/gitlab.sh
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
}

glab() {
    printf '%s\n' "$*" > "$GLAB_LOG"
}

@test "same-project GitLab MR pins the source project with --head" {
    run gp_create_pr \
        --repo "example-group/forked-project" \
        --base "main" \
        --head "feature/source-project" \
        --title "fix: pin MR source project" \
        --body-file "$BODYFILE"

    [ "$status" -eq 0 ]
    [[ "$(cat "$GLAB_LOG")" == *"--repo example-group/forked-project"* ]]
    [[ "$(cat "$GLAB_LOG")" == *"--source-branch feature/source-project"* ]]
    [[ "$(cat "$GLAB_LOG")" == *"--head example-group/forked-project"* ]]
}

@test "cross-fork GitLab MR keeps the fork slug as --head" {
    run gp_create_pr \
        --repo "upstream-group/project" \
        --base "main" \
        --head "feature/source-project" \
        --fork-slug "example-group/forked-project" \
        --title "fix: pin MR source project" \
        --body-file "$BODYFILE"

    [ "$status" -eq 0 ]
    [[ "$(cat "$GLAB_LOG")" == *"--repo upstream-group/project"* ]]
    [[ "$(cat "$GLAB_LOG")" == *"--source-branch feature/source-project"* ]]
    [[ "$(cat "$GLAB_LOG")" == *"--head example-group/forked-project"* ]]
}
