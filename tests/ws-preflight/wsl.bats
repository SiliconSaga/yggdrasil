#!/usr/bin/env bats

# From PowerShell, `bash` resolves to WSL, and WSL reports itself as Linux. A
# Windows user who typed `bash scripts/ws preflight` was told to apt-install
# every tool into a distro the workspace never runs from. GDD on Windows means
# Git Bash, so preflight has to say that rather than hand out Linux hints.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/ws-preflight.sh"

@test "preflight recognises WSL from its distro variable and points at Git Bash" {
    run env WSL_DISTRO_NAME=Ubuntu bash "$PREFLIGHT" --soft

    [[ "$output" == *"(OS: wsl)"* ]]
    [[ "$output" == *"This is WSL"* ]]
    [[ "$output" == *"Git Bash"* ]]
    [[ "$output" != *"sudo apt install"* ]]
}

@test "preflight says nothing about WSL when it is not WSL" {
    # The kernel string is the other signal, and it cannot be unset from a
    # test; on a real WSL host this case has nothing to assert.
    if [[ -r /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        skip "running on WSL — the kernel string itself identifies it"
    fi
    run env -u WSL_DISTRO_NAME bash "$PREFLIGHT" --soft

    [[ "$output" != *"This is WSL"* ]]
}
