#!/usr/bin/env bats

# gp_token_is_placeholder + gp_token_api_login — the offline placeholder check
# and the best-effort validity probe behind `ws diagnose`'s token coverage.
# Sourced directly; the probe's provider CLI is stubbed so no network is hit.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    source "$REPO_ROOT/scripts/git-provider.sh"
    STUB_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_DIR"
}

@test "placeholder check matches the shipped GitHub sample token" {
    run gp_token_is_placeholder "ghp_xxxxxxxxxxxx"
    [ "$status" -eq 0 ]
}

@test "placeholder check matches the shipped GitLab sample token" {
    run gp_token_is_placeholder "glpat-xxxxxxxxxxxx"
    [ "$status" -eq 0 ]
}

@test "placeholder check rejects a real-looking token" {
    # Obviously-fake value that still has the ghp_+length shape but won't trip
    # secret scanners (it's all zeros).
    run gp_token_is_placeholder "ghp_0000000000000000000000000000000000" # gitleaks:allow
    [ "$status" -ne 0 ]
}

@test "placeholder check rejects empty" {
    run gp_token_is_placeholder ""
    [ "$status" -ne 0 ]
}

@test "api probe echoes the login when the provider accepts the token" {
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
echo "octocat"
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"
    run gp_token_api_login github github.com sometoken
    [ "$status" -eq 0 ]
    [ "$output" = "octocat" ]
}

@test "api probe extracts the GitLab username when the provider accepts the token" {
    cat > "$STUB_DIR/glab" <<'SH'
#!/usr/bin/env bash
printf '{"username":"gitlab-user"}\n'
SH
    chmod +x "$STUB_DIR/glab"
    PATH="$STUB_DIR:$PATH"

    run gp_token_api_login gitlab gitlab.example.com sometoken

    [ "$status" -eq 0 ]
    [ "$output" = "gitlab-user" ]
}

@test "api probe returns rc 1 when the provider rejects the token" {
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
echo 'gh: Bad credentials (HTTP 401)' >&2
exit 1
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"
    run gp_token_api_login github github.com badtoken
    [ "$status" -eq 1 ]
}

@test "api error classifier distinguishes auth not-found transport and unknown failures" {
    run gp_api_error_classify 1 "gh: Bad credentials (HTTP 401)"
    [ "$status" -eq 0 ]
    [ "$output" = "auth" ]

    run gp_api_error_classify 1 "glab: GET /api/v4/user: 403 Forbidden"
    [ "$status" -eq 0 ]
    [ "$output" = "auth" ]

    run gp_api_error_classify 1 "gh: Not Found (HTTP 404)"
    [ "$status" -eq 0 ]
    [ "$output" = "not_found" ]

    run gp_api_error_classify 1 "dial tcp: lookup api.github.com: no such host"
    [ "$status" -eq 0 ]
    [ "$output" = "transport" ]

    run gp_api_error_classify 1 "provider failed for an unrecognized reason"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "api probe returns an indeterminate reason for network failures" {
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
echo 'Post "https://api.github.com/user": dial tcp: lookup api.github.com: no such host' >&2
exit 1
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"

    run gp_token_api_login github github.com sometoken

    [ "$status" -eq 3 ]
    [[ "$output" == *"no such host"* ]]
}

@test "api probe treats unknown CLI failures as indeterminate" {
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
echo 'provider failed for an unrecognized reason' >&2
exit 1
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"

    run gp_token_api_login github github.com sometoken

    [ "$status" -eq 3 ]
    [[ "$output" == *"unrecognized reason"* ]]
}

@test "api probe redacts a credential repeated by provider diagnostics" {
    local fake_token="fake-provider-token"
    cat > "$STUB_DIR/gh" <<SH
#!/usr/bin/env bash
echo 'request rejected for $fake_token' >&2
exit 1
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"

    run gp_token_api_login github github.com "$fake_token"

    [ "$status" -eq 3 ]
    [[ "$output" == *"[redacted]"* ]]
    [[ "$output" != *"$fake_token"* ]]
}

@test "api probe reports timeout exits as transport failures" {
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
exit 124
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"

    run gp_token_api_login github github.com sometoken

    [ "$status" -eq 3 ]
    [[ "$output" == *"timed out"* ]]
}

@test "api probe returns rc 2 for an unsupported provider" {
    run gp_token_api_login bitbucket bitbucket.org tok
    [ "$status" -eq 2 ]
}
