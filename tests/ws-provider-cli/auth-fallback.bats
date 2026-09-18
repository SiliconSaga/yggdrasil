#!/usr/bin/env bats

# `ws gh` / `ws glab` inject the workspace .env token. With no token in the
# environment they fall back to the CLI's own stored login for the target host,
# checked with a host-scoped `auth status` so a stale account on an unrelated
# host cannot block a valid one — and refuse with a pointer at both fixes when
# neither is available.
#
# A stub gh/glab on PATH records the args it received and answers `auth status`
# from STUB_AUTH_OK, so the tests assert the exact call the wrapper made rather
# than anything about a real login.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export WS_FOOTER_DISABLE=1
    unset GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN GH_HOST GITLAB_HOST
    # The dispatcher sources $ROOT_DIR/.env before dispatching, which would
    # reinject the developer's real token; point it at a root that has none.
    export ROOT_DIR="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT_DIR"
    export STUB_LOG="$BATS_TEST_TMPDIR/calls"
    local stubs="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stubs"
    local cli
    for cli in gh glab; do
        cat > "$stubs/$cli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    [[ "${STUB_AUTH_OK:-0}" == "1" ]]
    exit $?
fi
echo "RAN:$*"
EOF
        chmod +x "$stubs/$cli"
    done
    export PATH="$stubs:$PATH"
}

@test "ws gh with a token skips the stored-login check" {
    GH_TOKEN=test-token run bash "$WS_BIN" gh pr list
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN:pr list"* ]]
    ! grep -q "auth status" "$STUB_LOG"
}

@test "ws gh with no token uses a valid stored login, scoped to github.com" {
    STUB_AUTH_OK=1 run bash "$WS_BIN" gh pr list
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN:pr list"* ]]
    grep -qF "auth status --hostname github.com" "$STUB_LOG"
}

@test "ws gh scopes the stored-login check to GH_HOST when set" {
    GH_HOST=github.example.com STUB_AUTH_OK=1 run bash "$WS_BIN" gh pr list
    [ "$status" -eq 0 ]
    grep -qF "auth status --hostname github.example.com" "$STUB_LOG"
}

@test "ws gh refuses with both fixes named when neither token nor login exists" {
    STUB_AUTH_OK=0 run bash "$WS_BIN" gh pr list
    [ "$status" -ne 0 ]
    [[ "$output" == *"no GitHub token"* ]]
    [[ "$output" == *"no valid stored login for github.com"* ]]
    [[ "$output" == *"gh auth login"* ]]
    [[ "$output" != *"RAN:"* ]]
}

@test "ws glab with a token skips the stored-login check" {
    GITLAB_TOKEN=test-token run bash "$WS_BIN" glab mr list
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN:mr list"* ]]
    ! grep -q "auth status" "$STUB_LOG"
}

@test "ws glab with no token uses a valid stored login, scoped to GITLAB_HOST" {
    GITLAB_HOST=gitlab.example.com STUB_AUTH_OK=1 run bash "$WS_BIN" glab mr list
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN:mr list"* ]]
    grep -qF "auth status --hostname gitlab.example.com" "$STUB_LOG"
}

@test "ws glab refuses when neither token nor login exists" {
    STUB_AUTH_OK=0 run bash "$WS_BIN" glab mr list
    [ "$status" -ne 0 ]
    [[ "$output" == *"no GitLab token"* ]]
    [[ "$output" == *"no valid stored login for gitlab.com"* ]]
    [[ "$output" != *"RAN:"* ]]
}
