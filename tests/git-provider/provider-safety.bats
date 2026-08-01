#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO_ROOT/scripts/git-provider.sh"
    source "$REPO_ROOT/scripts/git-auth.sh"
}

@test "HTTPS normalization never treats an at-sign in the path as userinfo" {
    run git_auth_normalize_url "https://attacker.example/x@gitlab.mycorp.com/team/widget.git"

    [ "$status" -eq 0 ]
    [ "$output" = "attacker.example/x@gitlab.mycorp.com/team/widget" ]
}

@test "provider token routing does not cross an at-sign in the URL path" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-at-path.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitTokens:
    gitlab.mycorp.com/team: GITLAB_CORPORATE_TOKEN
YAML
    export GITLAB_CORPORATE_TOKEN="corporate-secret"
    unset GITLAB_TOKEN

    gp_set_token_for_url "https://attacker.example/x@gitlab.mycorp.com/team/widget.git" "$eco"

    [ "${GITLAB_TOKEN:-}" = "" ]
}

@test "provider selection pins GitHub Enterprise API calls to the remote host" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-ghe.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitProviders:
    ghe.example.com: github
YAML
    unset GH_HOST

    gp_detect_and_load "https://ghe.example.com/team/widget.git" "$eco"

    [ "$GH_HOST" = "ghe.example.com" ]
}

@test "provider selection does not carry an ambient GitLab token to another host" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-hosts.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitProviders:
    trusted.example.com: gitlab
    other.example.com: gitlab
YAML

    run env \
        GITLAB_HOST="trusted.example.com" \
        GITLAB_TOKEN="ambient-secret" \
        bash -c 'source "$1/scripts/git-provider.sh"; gp_detect_and_load "https://other.example.com/team/project.git" "$2"; printf "%s|%s" "$GITLAB_HOST" "${GITLAB_TOKEN-unset}"' _ "$REPO_ROOT" "$eco"

    [ "$status" -eq 0 ]
    [ "$output" = "other.example.com|unset" ]
}

@test "provider selection restores an ambient GitLab token for its paired host" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-hosts.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitProviders:
    trusted.example.com: gitlab
    other.example.com: gitlab
YAML

    run env \
        GITLAB_HOST="trusted.example.com" \
        GITLAB_TOKEN="ambient-secret" \
        bash -c 'source "$1/scripts/git-provider.sh"; gp_detect_and_load "https://other.example.com/team/project.git" "$2"; gp_detect_and_load "https://trusted.example.com/team/project.git" "$2"; printf "%s|%s" "$GITLAB_HOST" "${GITLAB_TOKEN-unset}"' _ "$REPO_ROOT" "$eco"

    [ "$status" -eq 0 ]
    [ "$output" = "trusted.example.com|ambient-secret" ]
}

@test "provider selection does not carry an ambient GitHub token to another host" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-hosts.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitProviders:
    github.com: github
    ghe.example.com: github
YAML

    run env \
        GH_HOST="github.com" \
        GH_TOKEN="ambient-secret" \
        bash -c 'source "$1/scripts/git-provider.sh"; gp_detect_and_load "https://ghe.example.com/team/project.git" "$2"; printf "%s|%s" "$GH_HOST" "${GH_TOKEN-unset}"' _ "$REPO_ROOT" "$eco"

    [ "$status" -eq 0 ]
    [ "$output" = "ghe.example.com|unset" ]
}

@test "local token mapping overrides an ambient token bound to another host" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-hosts.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitProviders:
    trusted.example.com: gitlab
    other.example.com: gitlab
  gitTokens:
    other.example.com/team: GITLAB_OTHER_TOKEN
YAML

    run env \
        GITLAB_HOST="trusted.example.com" \
        GITLAB_TOKEN="ambient-secret" \
        GITLAB_OTHER_TOKEN="scoped-secret" \
        bash -c 'source "$1/scripts/git-provider.sh"; gp_detect_and_load "https://other.example.com/team/project.git" "$2"; gp_set_token_for_url "https://other.example.com/team/project.git" "$2"; printf "%s|%s" "$GITLAB_HOST" "$GITLAB_TOKEN"' _ "$REPO_ROOT" "$eco"

    [ "$status" -eq 0 ]
    [ "$output" = "other.example.com|scoped-secret" ]
}

@test "provider token probe does not invoke external env with the credential" {
    local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
    local env_record="$BATS_TEST_TMPDIR/env-argv"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/env" <<'BASH'
#!/bin/bash
printf '%s\n' "$@" > "$ENV_RECORD"
exec /usr/bin/env "$@"
BASH
    cat > "$fake_bin/gh" <<'BASH'
#!/bin/bash
printf '%s\n' "probe-user"
BASH
    chmod +x "$fake_bin/env" "$fake_bin/gh"
    export ENV_RECORD="$env_record"
    PATH="$fake_bin:$PATH"

    run gp_token_api_login github github.example.com probe-secret

    [ "$status" -eq 0 ]
    [ "$output" = "probe-user" ]
    [ ! -e "$env_record" ]
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

@test "gp_set_token_for_url exports mapped GitHub credentials to GH_TOKEN" {
    local eco="$BATS_TEST_TMPDIR/ecosystem-github.yaml"
    cat > "$eco" <<'YAML'
defaults:
  gitProviders:
    github.example.com: github
  gitTokens:
    github.example.com/team/project: GITHUB_TEAM_TOKEN
YAML

    export GITHUB_TEAM_TOKEN="ghp_example"
    unset GH_TOKEN GITLAB_TOKEN

    gp_set_token_for_url "https://github.example.com/team/project.git" "$eco"

    [ "$GH_TOKEN" = "ghp_example" ]
    [ "${GITLAB_TOKEN:-}" = "" ]
}

@test "local token selection retains the provider detected from merged config" {
    local provider_eco="$BATS_TEST_TMPDIR/ecosystem-provider.yaml"
    local auth_eco="$BATS_TEST_TMPDIR/ecosystem-auth.yaml"
    cat > "$provider_eco" <<'YAML'
defaults:
  gitProviders:
    code.example.com: gitlab
YAML
    cat > "$auth_eco" <<'YAML'
defaults:
  gitTokens:
    code.example.com/team: GITHUB_SHARED_TOKEN
YAML

    export GITHUB_SHARED_TOKEN="shared-secret"
    unset GH_TOKEN GITLAB_TOKEN

    gp_detect_and_load "https://code.example.com/team/project.git" "$provider_eco"
    gp_set_token_for_url "https://code.example.com/team/project.git" "$auth_eco"

    [ "$GITLAB_TOKEN" = "shared-secret" ]
    [ "${GH_TOKEN:-}" = "" ]
}

@test "realm-only gitTokens mappings cannot authorize credential attachment" {
    local work="$BATS_TEST_TMPDIR/work"
    mkdir -p "$work/realms/realm-untrusted"
    cat > "$work/ecosystem.yaml" <<'YAML'
defaults: {}
components: {}
YAML
    cat > "$work/ecosystem.local.yaml" <<'YAML'
realm: realm-untrusted
YAML
    cat > "$work/realms/realm-untrusted/ecosystem.yaml" <<'YAML'
defaults:
  gitTokens:
    evil.example/group: GITLAB_TOKEN
components: {}
YAML

    run env \
        ROOT_DIR="$work" \
        ECOSYSTEM="$work/ecosystem.yaml" \
        ECOSYSTEM_LOCAL="$work/ecosystem.local.yaml" \
        REALMS_DIR="$work/realms" \
        bash -c 'source "$1/scripts/ws-realm.sh"; ws_resolve_token_var "evil.example/group/repo"' _ "$REPO_ROOT"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "local gitTokens mappings remain authoritative" {
    local work="$BATS_TEST_TMPDIR/work"
    mkdir -p "$work/realms/realm-selected"
    printf 'defaults: {}\ncomponents: {}\n' > "$work/ecosystem.yaml"
    cat > "$work/ecosystem.local.yaml" <<'YAML'
realm: realm-selected
defaults:
  gitTokens:
    gitlab.example.com/group: GITLAB_LOCAL_TOKEN
YAML
    printf 'components: {}\n' > "$work/realms/realm-selected/ecosystem.yaml"

    run env \
        ROOT_DIR="$work" \
        ECOSYSTEM="$work/ecosystem.yaml" \
        ECOSYSTEM_LOCAL="$work/ecosystem.local.yaml" \
        REALMS_DIR="$work/realms" \
        bash -c 'source "$1/scripts/ws-realm.sh"; ws_resolve_token_var "gitlab.example.com/group/repo"' _ "$REPO_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = "GITLAB_LOCAL_TOKEN" ]
}
