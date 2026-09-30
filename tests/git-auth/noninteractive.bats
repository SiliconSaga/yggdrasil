#!/usr/bin/env bats

# git_auth_env_noninteractive shapes the environment a best-effort fetch runs
# under. The traps it guards: OpenSSH keeps the FIRST value it sees for an
# option, so a BatchMode=yes appended after a configured BatchMode=no does
# nothing; a wrapper ahead of ssh must not receive ssh's options; and on the
# tokenless path nothing else blanks the credential helper, so a custom one can
# still raise a dialog.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# The options forced onto every ssh invocation, in the order they are added.
FORCED='-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2'

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO"
    unset GIT_SSH_COMMAND
    source "$REPO_ROOT/scripts/git-auth.sh"
}

env_value() {
    local entry
    for entry in "${GIT_AUTH_ENV[@]}"; do
        [[ "$entry" == "$1="* ]] && printf '%s\n' "${entry#"$1"=}"
    done
}

@test "with nothing configured, plain ssh gets the forced options" {
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "ssh $FORCED" ]
}

@test "the prompt refusals and stall bounds are all present" {
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_TERMINAL_PROMPT)" = "0" ]
    [ "$(env_value GCM_INTERACTIVE)" = "never" ]
    [ "$(env_value GIT_CONFIG_KEY_1)" = "http.lowSpeedLimit" ]
    [ "$(env_value GIT_CONFIG_VALUE_1)" = "1" ]
    [ "$(env_value GIT_CONFIG_KEY_2)" = "http.lowSpeedTime" ]
    [ "$(env_value GIT_CONFIG_VALUE_2)" = "30" ]
}

@test "the tokenless path blanks the credential helper" {
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_CONFIG_COUNT)" = "3" ]
    [ "$(env_value GIT_CONFIG_KEY_0)" = "credential.helper" ]
    [ "$(env_value GIT_CONFIG_VALUE_0)" = "" ]
}

@test "config entries queue after a token's, keeping its extraheader" {
    # What git_auth_env_for_url leaves behind when a token resolves.
    GIT_AUTH_ENV=(
        "GIT_TERMINAL_PROMPT=0"
        "GIT_CONFIG_COUNT=2"
        "GIT_CONFIG_KEY_0=credential.helper"
        "GIT_CONFIG_VALUE_0="
        "GIT_CONFIG_KEY_1=http.https://github.com/.extraheader"
        "GIT_CONFIG_VALUE_1=Authorization: Basic secret"
    )
    git_auth_env_noninteractive "$REPO"

    # The later COUNT wins at export time and covers every index below it.
    [ "$(env_value GIT_CONFIG_COUNT | tail -1)" = "5" ]
    [ "$(env_value GIT_CONFIG_KEY_1)" = "http.https://github.com/.extraheader" ]
    [ "$(env_value GIT_CONFIG_KEY_2)" = "credential.helper" ]
    [ "$(env_value GIT_CONFIG_KEY_4)" = "http.lowSpeedTime" ]
}

@test "BatchMode=yes lands ahead of a configured BatchMode=no, keeping the identity" {
    git -C "$REPO" config core.sshCommand "ssh -o BatchMode=no -i /keys/id"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "ssh $FORCED -o BatchMode=no -i /keys/id" ]
}

@test "GIT_SSH_COMMAND wins over core.sshCommand, as it does for git" {
    git -C "$REPO" config core.sshCommand "ssh -i /keys/from-config"
    export GIT_SSH_COMMAND="ssh -i /keys/from-env"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "ssh $FORCED -i /keys/from-env" ]
}

@test "a wrapper ahead of ssh keeps its prefix and the options land on ssh" {
    export GIT_SSH_COMMAND="env FOO=bar ssh -i /keys/id"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "env FOO=bar ssh $FORCED -i /keys/id" ]
}

@test "a quoted ssh path behind a wrapper receives the forced options" {
    export GIT_SSH_COMMAND='env FOO=bar "/usr/bin/ssh" -i /keys/id'
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "env FOO=bar \"/usr/bin/ssh\" $FORCED -i /keys/id" ]
}

@test "a quoted wrapper assignment before ssh keeps its value intact" {
    export GIT_SSH_COMMAND='env SSH_AUTH_SOCK="/tmp/ssh agent.sock" ssh -i /keys/id'
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "env SSH_AUTH_SOCK=\"/tmp/ssh agent.sock\" ssh $FORCED -i /keys/id" ]
}

@test "an absolute ssh path is recognised as the ssh word" {
    export GIT_SSH_COMMAND="/usr/bin/ssh -i /keys/id"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "/usr/bin/ssh $FORCED -i /keys/id" ]
}

@test "an unrecognised program is treated as the ssh word" {
    export GIT_SSH_COMMAND="ssh-wrapper -i /keys/id"
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "ssh-wrapper $FORCED -i /keys/id" ]
}

@test "a quoted program path with spaces stays one word" {
    export GIT_SSH_COMMAND='"C:/Program Files/OpenSSH/ssh.exe" -i C:/keys/id'
    GIT_AUTH_ENV=()
    git_auth_env_noninteractive "$REPO"

    [ "$(env_value GIT_SSH_COMMAND)" = "\"C:/Program Files/OpenSSH/ssh.exe\" $FORCED -i C:/keys/id" ]
}
