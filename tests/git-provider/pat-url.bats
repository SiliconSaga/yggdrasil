#!/usr/bin/env bats

# gp_pat_create_url — builds a deep-link URL to create a provider personal
# access token with the scopes ws push / cr / review need pre-selected, so a
# newcomer lands on a page with the right boxes checked instead of guessing.
# Pure string logic; sourced and called directly.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    source "$REPO_ROOT/scripts/git-provider.sh"
}

@test "github link pre-selects the repo scope and URL-encodes the multi-word description" {
    # The description is a purpose label, not a repo name — a classic repo-scope
    # PAT is account-wide, so naming it after one repo would mislead.
    run gp_pat_create_url github github.com "GDD agent write token"
    [ "$status" -eq 0 ]
    [ "$output" = "https://github.com/settings/tokens/new?scopes=repo&description=GDD%20agent%20write%20token" ]
}

@test "github enterprise host is honored (not hardcoded to github.com)" {
    run gp_pat_create_url github github.example.com "GDD"
    [ "$output" = "https://github.example.com/settings/tokens/new?scopes=repo&description=GDD" ]
}

@test "gitlab link pre-selects api + write_repository scopes" {
    run gp_pat_create_url gitlab gitlab.com "GDD demo"
    [ "$output" = "https://gitlab.com/-/user_settings/personal_access_tokens?name=GDD%20demo&scopes=api,write_repository" ]
}

@test "unknown provider falls back to the host root" {
    run gp_pat_create_url bitbucket example.org "GDD"
    [ "$output" = "https://example.org" ]
}

@test "reserved characters in the description are percent-encoded, not left raw" {
    # A general deep-link builder must encode &, ?, #, +, space, etc. so they
    # can't be misread as query-string syntax.
    run gp_pat_create_url github github.com "a&b?c#d e+f"
    [ "$output" = "https://github.com/settings/tokens/new?scopes=repo&description=a%26b%3Fc%23d%20e%2Bf" ]
}
