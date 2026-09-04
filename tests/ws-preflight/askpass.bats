#!/usr/bin/env bats

# An editor-injected GUI askpass turns a git credential failure into a silent,
# unbounded hang: git consults askpass BEFORE the terminal, so GIT_TERMINAL_PROMPT=0
# never gets a say, and the helper blocks on a dialog nobody answers in an agent
# session. `ws` clears it for its own git calls (see git_auth_run), but raw git in
# the same shell stays exposed and the durable fix is an editor setting the
# workspace cannot change — so preflight names it. Advisory: never changes exit code.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/ws-preflight.sh"

run_preflight() {
    run env "$@" bash "$PREFLIGHT"
}

@test "preflight flags a Cursor-injected GIT_ASKPASS" {
    run_preflight \
        "GIT_ASKPASS=/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh"

    [[ "$output" == *"GIT_ASKPASS points at an editor's GUI askpass helper"* ]]
    [[ "$output" == *"git.terminalAuthentication"* ]]
}

@test "preflight flags a VS Code-injected GIT_ASKPASS" {
    run_preflight \
        "GIT_ASKPASS=/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/git/dist/askpass.sh"

    [[ "$output" == *"GIT_ASKPASS points at an editor's GUI askpass helper"* ]]
}

@test "preflight flags an inherited SSH_ASKPASS too" {
    # git falls back to SSH_ASKPASS when GIT_ASKPASS is unset, so it is the same hazard.
    run_preflight \
        "GIT_ASKPASS=" \
        "SSH_ASKPASS=/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh"

    [[ "$output" == *"SSH_ASKPASS points at an editor's GUI askpass helper"* ]]
}

@test "preflight stays quiet for a deliberate headless askpass" {
    # A non-GUI helper is a legitimate setup and must not nag.
    run_preflight "GIT_ASKPASS=/usr/local/bin/my-keyring-askpass" "SSH_ASKPASS="

    [[ "$output" == *"no GUI askpass helper inherited"* ]]
    [[ "$output" != *"points at an editor's GUI askpass helper"* ]]
}

@test "preflight reports a clean environment when no askpass is set" {
    run_preflight "GIT_ASKPASS=" "SSH_ASKPASS="

    [[ "$output" == *"Environment:"* ]]
    [[ "$output" == *"no GUI askpass helper inherited"* ]]
}

@test "the askpass advisory never changes the exit code" {
    # Everything else on this host passes, so a flagged askpass must still exit 0.
    run_preflight \
        "GIT_ASKPASS=/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh"

    [[ "$output" == *"points at an editor's GUI askpass helper"* ]]
    [ "$status" -eq 0 ]
}
