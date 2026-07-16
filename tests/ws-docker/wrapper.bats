#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    DOCKER_WRAPPER="$REPO_ROOT/scripts/ws-docker.sh"
    STUB_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_DIR"

    cat > "$STUB_DIR/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TEST_UNAME:-Darwin}"
EOF
    cat > "$STUB_DIR/docker-stub" <<'EOF'
#!/usr/bin/env bash
printf 'MSYS_NO_PATHCONV=%s\n' "${MSYS_NO_PATHCONV-<unset>}"
printf 'ARG=%s\n' "$@"
EOF
    chmod +x "$STUB_DIR/uname" "$STUB_DIR/docker-stub"
}

run_docker_wrapper() {
    run env -u MSYS_NO_PATHCONV \
        PATH="$STUB_DIR:$PATH" \
        TEST_UNAME="$1" \
        DOCKER="$STUB_DIR/docker-stub" \
        bash "$DOCKER_WRAPPER" "${@:2}"
}

@test "Git Bash scopes MSYS path suppression to the docker process" {
    run_docker_wrapper MINGW64_NT-10.0 run --rm -v cache:/data image /opt/render

    [ "$status" -eq 0 ]
    [[ "$output" == *"MSYS_NO_PATHCONV=1"* ]]
    [[ "$output" == *"ARG=cache:/data"* ]]
    [[ "$output" == *"ARG=/opt/render"* ]]
}

@test "macOS and Linux leave MSYS path suppression unset" {
    run_docker_wrapper Darwin run --rm image

    [ "$status" -eq 0 ]
    [[ "$output" == *"MSYS_NO_PATHCONV=<unset>"* ]]
}

@test "docker arguments retain whitespace and container-absolute paths" {
    run_docker_wrapper MSYS_NT-10.0 run --label "display name" image "/opt/render output"

    [ "$status" -eq 0 ]
    [[ "$output" == *$'ARG=display name\n'* ]]
    [[ "$output" == *"ARG=/opt/render output"* ]]
}

@test "wrapper help does not invoke docker" {
    run env \
        PATH="$STUB_DIR:$PATH" \
        TEST_UNAME=MINGW64_NT-10.0 \
        DOCKER="$STUB_DIR/missing-docker" \
        bash "$DOCKER_WRAPPER" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws docker"* ]]
}

@test "docker help with a subcommand passes through" {
    run_docker_wrapper Darwin help run

    [ "$status" -eq 0 ]
    [[ "$output" == *$'ARG=help\nARG=run'* ]]
    [[ "$output" != *"Usage: ws docker"* ]]
}
