#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    REMOTE_LIB="$REPO_ROOT/scripts/git-remote.sh"
}

run_validator() {
    run bash -c 'source "$1"; git_remote_validate "$2" "${3:-remote}" "${4:-}"' \
        _ "$REMOTE_LIB" "$1" "${2:-remote}" "${3:-}"
}

@test "remote validator accepts HTTPS Git URLs" {
    run_validator "https://gitlab.example.com/team/project.git"

    [ "$status" -eq 0 ]
}

@test "remote validator accepts ssh scheme Git URLs" {
    run_validator "ssh://git@gitlab.example.com:2222/team/project.git"

    [ "$status" -eq 0 ]
}

@test "remote validator accepts scp-like Git URLs" {
    run_validator "git@gitlab.example.com:team/project.git"

    [ "$status" -eq 0 ]
}

@test "remote validator rejects option-like values" {
    run_validator "--upload-pack=sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"option-like"* ]]
}

@test "remote validator rejects Git remote helpers" {
    run_validator "ext::sh -c id"

    [ "$status" -ne 0 ]
    [[ "$output" == *"remote helper"* ]]
}

@test "remote validator rejects control characters" {
    run_validator $'https://gitlab.example.com/team/project.git\n--upload-pack=sh'

    [ "$status" -ne 0 ]
    [[ "$output" == *"control character"* ]]
}

@test "remote validator rejects insecure HTTP" {
    run_validator "http://gitlab.example.com/team/project.git"

    [ "$status" -ne 0 ]
    [[ "$output" == *"HTTPS or SSH"* ]]
}

@test "remote validator rejects local paths in remote mode" {
    run_validator "$BATS_TEST_TMPDIR/repo.git"

    [ "$status" -ne 0 ]
    [[ "$output" == *"HTTPS or SSH"* ]]
}

@test "remote validator accepts local paths only in local mode" {
    mkdir -p "$BATS_TEST_TMPDIR/repo.git"

    run_validator "$BATS_TEST_TMPDIR/repo.git" local

    [ "$status" -eq 0 ]
}

@test "remote validator accepts file URLs only in local mode" {
    mkdir -p "$BATS_TEST_TMPDIR/repo.git"

    run_validator "file://$BATS_TEST_TMPDIR/repo.git" local

    [ "$status" -eq 0 ]
}

@test "remote validator enforces an expected provider host" {
    run_validator "https://evil.example/team/project.git" remote "gitlab.example.com"

    [ "$status" -ne 0 ]
    [[ "$output" == *"expected host 'gitlab.example.com'"* ]]
}

@test "remote validator redacts embedded credentials from errors" {
    run_validator "http://oauth2:super-secret@gitlab.example.com/team/project.git"

    [ "$status" -ne 0 ]
    [[ "$output" != *"super-secret"* ]]
    [[ "$output" == *"[redacted]"* ]]
}

@test "remote host extraction normalizes supported URL forms" {
    run bash -c 'source "$1"; git_remote_host "$2"' \
        _ "$REMOTE_LIB" "ssh://git@GitLab.Example.com:2222/team/project.git"

    [ "$status" -eq 0 ]
    [ "$output" = "gitlab.example.com" ]
}

@test "remote host extraction preserves bracketed IPv6 literals" {
    run bash -c 'source "$1"; git_remote_host "$2"' \
        _ "$REMOTE_LIB" "ssh://git@[::1]:2222/team/project.git"

    [ "$status" -eq 0 ]
    [ "$output" = "::1" ]
}
