#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO_ROOT/scripts/git-provider.sh"
}

@test "gp_load rejects provider names that escape the providers directory" {
    local fake_scripts="$BATS_TEST_TMPDIR/scripts"
    mkdir -p "$fake_scripts/providers"
    cat > "$fake_scripts/evil.sh" <<'BASH'
export GP_EVIL_PROVIDER_SOURCED=1
BASH

    _GP_SCRIPT_DIR="$fake_scripts"

    run gp_load "../evil"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid provider name"* ]]
    [ "${GP_EVIL_PROVIDER_SOURCED:-}" = "" ]
}

@test "gp_set_token_for_url rejects invalid gitTokens env var names" {
    local eco="$BATS_TEST_TMPDIR/ecosystem.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitTokens:
    gitlab.example.com/team/project: BAD-NAME
YAML

    unset GITLAB_TOKEN

    run gp_set_token_for_url "https://gitlab.example.com/team/project.git" "$eco"

    [ "$status" -ne 0 ]
    [[ "$output" == *"not an allowed provider-token variable"* ]]
    [ "${GITLAB_TOKEN:-}" = "" ]
}

@test "gp_set_token_for_url rejects unrelated environment variables" {
    local eco="$BATS_TEST_TMPDIR/ecosystem.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitTokens:
    gitlab.example.com/team/project: AWS_SECRET_ACCESS_KEY
YAML

    export AWS_SECRET_ACCESS_KEY="not-a-git-token"
    unset GITLAB_TOKEN

    run gp_set_token_for_url "https://gitlab.example.com/team/project.git" "$eco"

    [ "$status" -ne 0 ]
    [[ "$output" == *"not an allowed provider-token variable"* ]]
    [ "${GITLAB_TOKEN:-}" = "" ]
}

@test "gp_set_token_for_url accepts scoped GitLab token variables" {
    local eco="$BATS_TEST_TMPDIR/ecosystem.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitTokens:
    gitlab.example.com/team/project: GITLAB_TEAM_REPORTER
YAML

    export GITLAB_TEAM_REPORTER="glpat-example"
    unset GITLAB_TOKEN

    gp_set_token_for_url "https://gitlab.example.com/team/project.git" "$eco"

    [ "$GITLAB_TOKEN" = "glpat-example" ]
}
