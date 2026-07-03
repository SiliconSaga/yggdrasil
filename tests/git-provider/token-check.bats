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

@test "api probe returns rc 1 when the provider rejects the token" {
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "$STUB_DIR/gh"
    PATH="$STUB_DIR:$PATH"
    run gp_token_api_login github github.com badtoken
    [ "$status" -eq 1 ]
}

@test "api probe returns rc 2 for an unsupported provider" {
    run gp_token_api_login bitbucket bitbucket.org tok
    [ "$status" -eq 2 ]
}
