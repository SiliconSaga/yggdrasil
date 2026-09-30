#!/usr/bin/env bats

# git_auth_env_noninteractive shapes the ssh command a best-effort fetch runs
# under. The trap it guards: OpenSSH keeps the FIRST value it sees for an
# option, so a BatchMode=yes appended after a configured BatchMode=no does
# nothing, and the "advisory" fetch waits on a passphrase after all.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO"
    unset GIT_SSH_COMMAND
    source "$REPO_ROOT/scripts/git-auth.sh"
}

ssh_entry() {
    local entry
    for entry in "${GIT_AUTH_ENV[@]}"; do
        [[ "$entry" == GIT_SSH_COMMAND=* ]] && printf '%s\n' "${entry#GIT_SSH_COMMAND=}"
    done
}

@test "with nothing configured, plain ssh gets BatchMode" {
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(ssh_entry)" = "ssh -o BatchMode=yes" ]
}

@test "the prompt refusals are added alongside any token entries already present" {
    GIT_AUTH_ENV=("GIT_CONFIG_COUNT=1")
    git_auth_env_noninteractive "$REPO"

    [ "${GIT_AUTH_ENV[0]}" = "GIT_CONFIG_COUNT=1" ]
    [[ " ${GIT_AUTH_ENV[*]} " == *" GIT_TERMINAL_PROMPT=0 "* ]]
    [[ " ${GIT_AUTH_ENV[*]} " == *" GCM_INTERACTIVE=never "* ]]
}

@test "BatchMode=yes lands ahead of a configured BatchMode=no, keeping the identity" {
    git -C "$REPO" config core.sshCommand "ssh -o BatchMode=no -i /keys/id"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(ssh_entry)" = "ssh -o BatchMode=yes -o BatchMode=no -i /keys/id" ]
}

@test "GIT_SSH_COMMAND wins over core.sshCommand, as it does for git" {
    git -C "$REPO" config core.sshCommand "ssh -i /keys/from-config"
    export GIT_SSH_COMMAND="ssh -i /keys/from-env"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(ssh_entry)" = "ssh -o BatchMode=yes -i /keys/from-env" ]
}

@test "a quoted program path with spaces stays one word" {
    export GIT_SSH_COMMAND='"C:/Program Files/OpenSSH/ssh.exe" -i C:/keys/id'
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(ssh_entry)" = '"C:/Program Files/OpenSSH/ssh.exe" -o BatchMode=yes -i C:/keys/id' ]
}
