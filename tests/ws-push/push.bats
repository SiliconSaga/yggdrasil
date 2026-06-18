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

@test "GitHub HTTPS push uses GH_TOKEN without credential helper prompts" {
    git -C "$REPO_DIR" remote set-url fork https://github.com/Example/repo.git
    install_git_push_spy
    export GH_TOKEN="ghp_testtoken"

    run_git_push main

    [ "$status" -eq 0 ]
    [[ "$output" == *"Using GH_TOKEN for HTTPS GitHub push auth"* ]]
    [[ "$output" == *"Pushing main"* ]]
    [ -f "$GIT_PUSH_SPY_LOG" ]
    expected="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_TERMINAL_PROMPT=0"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_KEY_0=credential.helper"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_VALUE_0="* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_KEY_1=http.https://github.com/.extraheader"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_VALUE_1=Authorization: Basic $expected"* ]]
}

@test "GitLab HTTPS push uses mapped gitTokens value without credential helper prompts" {
    git -C "$REPO_DIR" remote set-url fork https://gitlab-master.nvidia.com/gni-cis/gdd/rpraestholm-fork-group/yggdrasil.git
    cat > "$BATS_TEST_TMPDIR/ecosystem.yaml" <<'YAML'
defaults:
  gitTokens:
    gitlab-master.nvidia.com/gni-cis/gdd/rpraestholm-fork-group: GITLAB_FORK_TOKEN
identity: {}
components: {}
YAML
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/missing-local.yaml"
    export GITLAB_FORK_TOKEN="glpat_testtoken"
    export GITLAB_USER="rpraestholm"
    install_git_push_spy

    run_git_push main

    [ "$status" -eq 0 ]
    [[ "$output" == *"Using GITLAB_FORK_TOKEN for HTTPS GitLab push auth"* ]]
    [ -f "$GIT_PUSH_SPY_LOG" ]
    expected="$(printf '%s:%s' "$GITLAB_USER" "$GITLAB_FORK_TOKEN" | base64 | tr -d '\n')"
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_TERMINAL_PROMPT=0"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_KEY_0=credential.helper"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_VALUE_0="* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_KEY_1=http.https://gitlab-master.nvidia.com/.extraheader"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_VALUE_1=Authorization: Basic $expected"* ]]
}

@test "GitLab look-alike host gets NO GITLAB_TOKEN default (no credential leak)" {
    # A host that merely resembles GitLab must not harvest GITLAB_TOKEN via the
    # default fallback — only an explicit defaults.gitTokens mapping may send a
    # token there. With no mapping, no auth header is injected.
    git -C "$REPO_DIR" remote set-url fork https://gitlab-evil.example/attacker/repo.git
    cat > "$BATS_TEST_TMPDIR/ecosystem.yaml" <<'YAML'
defaults: {}
identity: {}
components: {}
YAML
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/missing-local.yaml"
    export GITLAB_TOKEN="glpat_secret"
    install_git_push_spy

    run_git_push main

    [ "$status" -eq 0 ]
    [[ "$output" != *"push auth"* ]]
    [ -f "$GIT_PUSH_SPY_LOG" ]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"extraheader"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"Authorization: Basic"* ]]
    # No non-interactive git config is injected either — not just the header.
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"GIT_TERMINAL_PROMPT=0"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"credential.helper"* ]]
}

@test "self-hosted gitlab.<domain> uses a mapped gitTokens value (explicit mapping)" {
    # gitlab.example.com is a self-hosted instance — it must get token auth when
    # an explicit defaults.gitTokens mapping exists (no GITLAB_TOKEN default).
    git -C "$REPO_DIR" remote set-url fork https://gitlab.example.com/group/repo.git
    cat > "$BATS_TEST_TMPDIR/ecosystem.yaml" <<'YAML'
defaults:
  gitTokens:
    gitlab.example.com/group: GITLAB_SELFHOSTED_TOKEN
identity: {}
components: {}
YAML
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/missing-local.yaml"
    export GITLAB_SELFHOSTED_TOKEN="glpat_selfhosted"
    export GITLAB_USER="ci-bot"
    install_git_push_spy

    run_git_push main

    [ "$status" -eq 0 ]
    [[ "$output" == *"Using GITLAB_SELFHOSTED_TOKEN for HTTPS GitLab push auth"* ]]
    [ -f "$GIT_PUSH_SPY_LOG" ]
    expected="$(printf '%s:%s' "$GITLAB_USER" "$GITLAB_SELFHOSTED_TOKEN" | base64 | tr -d '\n')"
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_KEY_1=http.https://gitlab.example.com/.extraheader"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_VALUE_1=Authorization: Basic $expected"* ]]
}
