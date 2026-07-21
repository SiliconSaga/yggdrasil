#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

    # shellcheck source=../../scripts/providers/gitlab.sh
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
}

glab() {
    [ "${1:-}" = "api" ] || return 2
    [ "${2:-}" = "projects/example-group%2Fproject" ] || return 2

    case "${GLAB_RESPONSE_MODE:-}" in
        valid)
            printf '%s\n' '{"default_branch":"trunk"}'
            ;;
        failure)
            echo "404 Project Not Found" >&2
            return 1
            ;;
        malformed)
            printf '%s\n' '{'
            ;;
        null)
            printf '%s\n' '{"default_branch":null}'
            ;;
        *)
            return 2
            ;;
    esac
}

@test "GitLab default-branch lookup returns a non-empty branch" {
    export GLAB_RESPONSE_MODE=valid

    run gp_default_branch "example-group/project"

    [ "$status" -eq 0 ]
    [ "$output" = "trunk" ]
}

@test "GitLab default-branch lookup propagates an API failure" {
    export GLAB_RESPONSE_MODE=failure

    run gp_default_branch "example-group/project"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot determine the default branch for GitLab project 'example-group/project'"* ]]
}

@test "GitLab default-branch lookup rejects malformed JSON" {
    export GLAB_RESPONSE_MODE=malformed

    run gp_default_branch "example-group/project"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot determine the default branch for GitLab project 'example-group/project'"* ]]
}

@test "GitLab default-branch lookup rejects null" {
    export GLAB_RESPONSE_MODE=null

    run gp_default_branch "example-group/project"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot determine the default branch for GitLab project 'example-group/project'"* ]]
}
