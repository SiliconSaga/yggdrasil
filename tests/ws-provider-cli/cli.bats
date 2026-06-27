#!/usr/bin/env bats
# ws gh / ws glab — provider-CLI passthrough wrappers that make the workspace
# .env token available without a mid-session `source .env`, and never fall
# through to an interactive login or leak the token to the transcript.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK/bin"
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
    # Stub gh/glab: echo the args and whether the provider token is present,
    # but NEVER echo the token value (the wrapper must not leak it either).
    cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "GH_ARGS: $*"
# Mirror the wrapper contract: GH_TOKEN or GITHUB_TOKEN counts as authenticated.
[[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]] && echo "GH_TOKEN_PRESENT" || echo "GH_TOKEN_ABSENT"
EOF
    cat > "$WORK/bin/glab" <<'EOF'
#!/usr/bin/env bash
echo "GLAB_ARGS: $*"
[[ -n "${GITLAB_TOKEN:-}" ]] && echo "GITLAB_TOKEN_PRESENT" || echo "GITLAB_TOKEN_ABSENT"
EOF
    chmod +x "$WORK/bin/gh" "$WORK/bin/glab"
}
# Clear any provider tokens inherited from the runner's environment (the full
# `ws test` run sources the real workspace .env, which exports GH_TOKEN) so each
# test controls the token state entirely via the $WORK/.env it writes.
run_ws() { run env -u GH_TOKEN -u GITHUB_TOKEN -u GITLAB_TOKEN -u GITLAB_HOST WS_FOOTER_DISABLE=1 ROOT_DIR="$WORK" PATH="$WORK/bin:$PATH" bash "$WS_BIN" "$@"; }

@test "ws gh execs gh with args and the .env token present, without leaking it" {
    printf 'export GH_TOKEN=secret-gh-tok\n' > "$WORK/.env"
    run_ws gh pr list --limit 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_ARGS: pr list --limit 1"* ]]
    [[ "$output" == *"GH_TOKEN_PRESENT"* ]]
    [[ "$output" != *"secret-gh-tok"* ]]
}
@test "ws gh without a token errors and does NOT exec gh" {
    printf '\n' > "$WORK/.env"
    run_ws gh pr list
    [ "$status" -ne 0 ]
    [[ "$output" != *"GH_ARGS:"* ]]
    [[ "$output" == *"GH_TOKEN"* ]]
}
@test "ws gh works with GITHUB_TOKEN when GH_TOKEN is absent" {
    printf 'export GITHUB_TOKEN=secret-gh-tok\n' > "$WORK/.env"
    run_ws gh pr list --limit 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_ARGS: pr list --limit 1"* ]]
    [[ "$output" == *"GH_TOKEN_PRESENT"* ]]
    [[ "$output" != *"secret-gh-tok"* ]]
}
@test "ws gh --help passes through to gh without requiring a token" {
    printf '\n' > "$WORK/.env"
    run_ws gh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_ARGS: --help"* ]]
}
@test "ws gh <cmd> --help passes through without requiring a token" {
    printf '\n' > "$WORK/.env"
    run_ws gh pr --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_ARGS: pr --help"* ]]
}
@test "ws gh -h (short form) passes through without requiring a token" {
    printf '\n' > "$WORK/.env"
    run_ws gh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_ARGS: -h"* ]]
}
@test "ws gh passes a subcommand --help through to gh (not the wrapper)" {
    printf 'export GH_TOKEN=t\n' > "$WORK/.env"
    run_ws gh pr --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"GH_ARGS: pr --help"* ]]
}
@test "ws glab execs glab with args and the .env token present, without leaking it" {
    printf 'export GITLAB_TOKEN=secret-gl-tok\n' > "$WORK/.env"
    run_ws glab mr list
    [ "$status" -eq 0 ]
    [[ "$output" == *"GLAB_ARGS: mr list"* ]]
    [[ "$output" == *"GITLAB_TOKEN_PRESENT"* ]]
    [[ "$output" != *"secret-gl-tok"* ]]
}
@test "ws glab without a token errors and does NOT exec glab" {
    printf '\n' > "$WORK/.env"
    run_ws glab mr list
    [ "$status" -ne 0 ]
    [[ "$output" != *"GLAB_ARGS:"* ]]
    [[ "$output" == *"GITLAB_TOKEN"* ]]
}
@test "ws glab --help passes through to glab without requiring a token" {
    printf '\n' > "$WORK/.env"
    run_ws glab --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"GLAB_ARGS: --help"* ]]
}
@test "ws glab -h (short form) passes through without requiring a token" {
    printf '\n' > "$WORK/.env"
    run_ws glab -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"GLAB_ARGS: -h"* ]]
}
