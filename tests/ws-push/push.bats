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

@test "pushes an exact branch ref when its short name has revision meaning" {
    git -C "$REPO_DIR" branch @ HEAD
    branch_sha="$(git -C "$REPO_DIR" rev-parse refs/heads/@)"
    printf 'new head\n' >> "$REPO_DIR/file.txt"
    git -C "$REPO_DIR" add file.txt
    git -C "$REPO_DIR" commit -q -m "advance current branch"

    run_git_push @

    [ "$status" -eq 0 ]
    remote_ref_exists refs/heads/@
    [ "$(remote_ref_sha refs/heads/@)" = "$branch_sha" ]
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

@test "refuses a fully qualified branch target before push safeguards" {
    run_git_push --force refs/heads/main

    [ "$status" -ne 0 ]
    [[ "$output" == *"must name an exact local branch or tag"* ]]
    ! remote_ref_exists refs/heads/main
}

@test "refuses a refspec target" {
    run_git_push main:refs/heads/release

    [ "$status" -ne 0 ]
    [[ "$output" == *"refspecs and fully qualified refs are not accepted"* ]]
    ! remote_ref_exists refs/heads/release
}

@test "refuses an unknown short target before invoking git push" {
    run_git_push missing

    [ "$status" -ne 0 ]
    [[ "$output" == *"must name an exact local branch or tag"* ]]
    [[ "$output" != *"src refspec missing does not match any"* ]]
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

@test "token push clears an inherited editor GIT_ASKPASS instead of hanging on it" {
    # Regression: GIT_TERMINAL_PROMPT=0 closes only the *terminal* prompt. git
    # consults an askpass helper first, and VS Code and Cursor both export
    # GIT_ASKPASS into every integrated-terminal shell. That helper waits on a
    # GUI dialog nobody answers in an agent session, so an expired token made
    # this path hang forever instead of failing fast. Both vars must reach git
    # cleared — git prefers GIT_ASKPASS but falls back to SSH_ASKPASS.
    git -C "$REPO_DIR" remote set-url fork https://github.com/Example/repo.git
    export GIT_ASKPASS="/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh"
    export SSH_ASKPASS="/usr/lib/ssh/ssh-askpass"
    install_git_push_spy
    export GH_TOKEN="ghp_testtoken"

    run_git_push main

    [ "$status" -eq 0 ]
    [ -f "$GIT_PUSH_SPY_LOG" ]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_TERMINAL_PROMPT=0"* ]]
    # Cleared to empty, not merely absent, and not the inherited path.
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_ASKPASS="$'\n'* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"SSH_ASKPASS="$'\n'* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"askpass.sh"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"ssh-askpass"* ]]
}

@test "GitLab HTTPS push uses mapped gitTokens value without credential helper prompts" {
    git -C "$REPO_DIR" remote set-url fork https://gitlab.example.com/acme/forks/alice/yggdrasil.git
    cat > "$BATS_TEST_TMPDIR/ecosystem.yaml" <<'YAML'
defaults:
  gitTokens:
    gitlab.example.com/acme/forks/alice: GITLAB_FORK_TOKEN
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
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_KEY_1=http.https://gitlab.example.com/.extraheader"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_CONFIG_VALUE_1=Authorization: Basic $expected"* ]]
}

@test "tokenless push clears the editor askpass but keeps git's terminal prompt" {
    # The tokenless path (SSH, unmapped host) is a plain git call and populates
    # no GIT_AUTH_ENV, so it was the one route still exposed to the editor's GUI
    # askpass — a real `ws hoard` clone of an unmapped project hung on exactly
    # this. git_auth_run now clears askpass for every call, token or not.
    #
    # GIT_TERMINAL_PROMPT must stay UNSET here: killing the GUI while leaving
    # the terminal prompt intact is what lets a human still authenticate
    # interactively, while an agent with no tty fails fast instead of hanging.
    git -C "$REPO_DIR" remote set-url fork https://gitlab-evil.example/attacker/repo.git
    cat > "$BATS_TEST_TMPDIR/ecosystem.yaml" <<'YAML'
defaults: {}
identity: {}
components: {}
YAML
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/missing-local.yaml"
    export GIT_ASKPASS="/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh"
    export SSH_ASKPASS="/usr/lib/ssh/ssh-askpass"
    install_git_push_spy

    run_git_push main

    [ "$status" -eq 0 ]
    [ -f "$GIT_PUSH_SPY_LOG" ]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"GIT_ASKPASS="$'\n'* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" == *"SSH_ASKPASS="$'\n'* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"askpass.sh"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"ssh-askpass"* ]]
    # No token resolved, so no non-interactive git config rides along.
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"GIT_TERMINAL_PROMPT=0"* ]]
    [[ "$(cat "$GIT_PUSH_SPY_LOG")" != *"extraheader"* ]]
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
