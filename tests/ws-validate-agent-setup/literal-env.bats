#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/workspace"
    BIN="$BATS_TEST_TMPDIR/bin"
    CALL_LOG="$BATS_TEST_TMPDIR/external-calls.log"
    GH_MARKER="$BATS_TEST_TMPDIR/gh-token-command-ran"
    ERRORS_MARKER="$BATS_TEST_TMPDIR/errors-command-ran"
    LOADER_MARKER="$BATS_TEST_TMPDIR/loader-local-command-ran"

    mkdir -p "$WORK/scripts" "$BIN"
    cp "$REPO_ROOT/scripts/validate-agent-setup.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"

    cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh' >> "$EXTERNAL_CALL_LOG"
for arg in "$@"; do
    printf ' <%s>' "$arg" >> "$EXTERNAL_CALL_LOG"
done
printf '\n' >> "$EXTERNAL_CALL_LOG"

if [[ "${GH_TOKEN-}" != "${EXPECTED_GH_TOKEN-}" ]]; then
    echo "unexpected GH_TOKEN value seen by gh" >&2
    exit 96
fi

if [[ "$#" -eq 2 && "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
fi

if [[ "$#" -eq 4 && "$1" == "api" && "$2" == "/user" && "$3" == "--jq" && "$4" == ".login" ]]; then
    echo "test-user"
    exit 0
fi

if [[ "$#" -eq 4 && "$1" == "api" && "$3" == "--jq" && "$4" == '[.permissions.push, .permissions.pull] | @csv' ]]; then
    case "$2" in
        /repos/SiliconSaga/nordri|/repos/SiliconSaga/nidavellir|/repos/SiliconSaga/mimir|/repos/SiliconSaga/yggdrasil|/repos/SiliconSaga/vordu)
            echo "true,true"
            exit 0
            ;;
    esac
fi

if [[ "$#" -eq 4 && "$1" == "api" && "$3" == "--jq" && "$4" == ".protected" ]]; then
    case "$2" in
        /repos/SiliconSaga/nordri/branches/main|/repos/SiliconSaga/nidavellir/branches/main|/repos/SiliconSaga/mimir/branches/main|/repos/SiliconSaga/yggdrasil/branches/main|/repos/SiliconSaga/vordu/branches/main)
            echo "true"
            exit 0
            ;;
    esac
fi

echo "unexpected gh invocation" >&2
exit 97
EOF

    cat > "$BIN/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >> "$EXTERNAL_CALL_LOG"
for arg in "$@"; do
    printf ' <%s>' "$arg" >> "$EXTERNAL_CALL_LOG"
done
printf '\n' >> "$EXTERNAL_CALL_LOG"

if [[ "$#" -eq 2 && "$1" == "config" && "$2" == "--list" ]]; then
    echo "credential.https://github.com.helper=!gh auth git-credential"
    exit 0
fi

echo "unexpected git invocation" >&2
exit 98
EOF

    chmod +x "$BIN/gh" "$BIN/git"
}

run_validator() {
    local expected_gh_token="$1"
    if [[ "$#" -eq 2 ]]; then
        run env -u GH_TOKEN REPO_ERRORS="$2" EXTERNAL_CALL_LOG="$CALL_LOG" EXPECTED_GH_TOKEN="$expected_gh_token" PATH="$BIN:$PATH" "$WORK/scripts/validate-agent-setup.sh"
    else
        run env -u GH_TOKEN EXTERNAL_CALL_LOG="$CALL_LOG" EXPECTED_GH_TOKEN="$expected_gh_token" PATH="$BIN:$PATH" "$WORK/scripts/validate-agent-setup.sh"
    fi
}

run_validator_with_environment_token() {
    local expected_gh_token="$1"
    run env GH_TOKEN="$expected_gh_token" EXTERNAL_CALL_LOG="$CALL_LOG" EXPECTED_GH_TOKEN="$expected_gh_token" PATH="$BIN:$PATH" "$WORK/scripts/validate-agent-setup.sh"
}

assert_successful_external_calls() {
    local expected_log="$BATS_TEST_TMPDIR/expected-external-calls.log"
    cat > "$expected_log" <<'EOF'
gh <auth> <status>
gh <api> </user> <--jq> <.login>
git <config> <--list>
git <config> <--list>
gh <api> </repos/SiliconSaga/nordri> <--jq> <[.permissions.push, .permissions.pull] | @csv>
gh <api> </repos/SiliconSaga/nidavellir> <--jq> <[.permissions.push, .permissions.pull] | @csv>
gh <api> </repos/SiliconSaga/mimir> <--jq> <[.permissions.push, .permissions.pull] | @csv>
gh <api> </repos/SiliconSaga/yggdrasil> <--jq> <[.permissions.push, .permissions.pull] | @csv>
gh <api> </repos/SiliconSaga/vordu> <--jq> <[.permissions.push, .permissions.pull] | @csv>
gh <api> </repos/SiliconSaga/nordri/branches/main> <--jq> <.protected>
gh <api> </repos/SiliconSaga/nidavellir/branches/main> <--jq> <.protected>
gh <api> </repos/SiliconSaga/mimir/branches/main> <--jq> <.protected>
gh <api> </repos/SiliconSaga/yggdrasil/branches/main> <--jq> <.protected>
gh <api> </repos/SiliconSaga/vordu/branches/main> <--jq> <.protected>
EOF
    diff -u "$expected_log" "$CALL_LOG"
}

@test "validate-agent-setup overwrites validator state loaded from literal .env data" {
    local expected_gh_token="\$(touch $GH_MARKER)"
    cat > "$WORK/.env" <<EOF
GH_TOKEN=$expected_gh_token
ERRORS=REPO_ERRORS[\$(touch $ERRORS_MARKER)0]
EOF

    run_validator "$expected_gh_token"

    if [[ "$status" -ne 0 ]]; then
        echo "$output"
    fi
    [ ! -e "$GH_MARKER" ]
    [ ! -e "$ERRORS_MARKER" ]
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_TOKEN loaded from .env as literal assignment data for this validation run"* ]]
    assert_successful_external_calls
}

@test "validate-agent-setup keeps loader-local names literal across .env lines" {
    local expected_gh_token="token"
    cat > "$WORK/.env" <<EOF
line_number=REPO_ERRORS[\$(touch $LOADER_MARKER)0]
GH_TOKEN=$expected_gh_token
EOF

    run_validator "$expected_gh_token" "0"

    [ ! -e "$LOADER_MARKER" ]
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_TOKEN loaded from .env as literal assignment data for this validation run"* ]]
    assert_successful_external_calls
}

@test "validate-agent-setup exits before external commands when GH_TOKEN is missing" {
    run_validator ""

    [ "$status" -ne 0 ]
    [[ "$output" == *"GH_TOKEN not set and $WORK/scripts/../.env not found"* ]]
    [ ! -e "$CALL_LOG" ]
}

@test "validate-agent-setup exits before external commands when .env has an empty GH_TOKEN" {
    cat > "$WORK/.env" <<'EOF'
ENV_FILE=/attacker-controlled
GH_TOKEN=
EOF

    run_validator ""

    [ "$status" -ne 0 ]
    [[ "$output" == *"GH_TOKEN missing or empty after loading $WORK/scripts/../.env"* ]]
    [[ "$output" != *"/attacker-controlled"* ]]
    [ ! -e "$CALL_LOG" ]
}

@test "validate-agent-setup exits before external commands when .env is malformed" {
    echo "this is not an assignment" > "$WORK/.env"

    run_validator ""

    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid .env line 1"* ]]
    [ ! -e "$CALL_LOG" ]
}

@test "validate-agent-setup gives a valid environment token precedence over hostile .env" {
    local expected_gh_token="ambient-literal-token"
    cat > "$WORK/.env" <<EOF
line_number=REPO_ERRORS[\$(touch $LOADER_MARKER)0]
this is not an assignment
GH_TOKEN=file-token
EOF

    run_validator_with_environment_token "$expected_gh_token"

    [ "$status" -eq 0 ]
    [ ! -e "$LOADER_MARKER" ]
    [[ "$output" == *"GH_TOKEN set in environment"* ]]
    [[ "$output" != *"GH_TOKEN loaded from .env"* ]]
    assert_successful_external_calls
}
