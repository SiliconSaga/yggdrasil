#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ENV_LIB="$REPO_ROOT/scripts/ws-env.sh"
}

@test "ws_load_env loads supported assignments as literal data" {
    local env_file="$BATS_TEST_TMPDIR/.env"
    local marker="$BATS_TEST_TMPDIR/command-ran"
    cat > "$env_file" <<EOF
# comments and blank lines are ignored

export GH_TOKEN=ghp_example
GITLAB_HOST=gitlab.example.com
DOUBLE_QUOTED="value with spaces"
SINGLE_QUOTED='another value'
WITH_EQUALS=left=right
INERT_COMMAND='\$(touch $marker)'
EOF

    source "$ENV_LIB"
    ws_load_env "$env_file"

    [ "$GH_TOKEN" = "ghp_example" ]
    [ "$GITLAB_HOST" = "gitlab.example.com" ]
    [ "$DOUBLE_QUOTED" = "value with spaces" ]
    [ "$SINGLE_QUOTED" = "another value" ]
    [ "$WITH_EQUALS" = "left=right" ]
    [ "$INERT_COMMAND" = "\$(touch $marker)" ]
    [ ! -e "$marker" ]
}

@test "ws_load_env rejects malformed shell content without executing it" {
    local env_file="$BATS_TEST_TMPDIR/.env"
    local marker="$BATS_TEST_TMPDIR/command-ran"
    cat > "$env_file" <<EOF
SAFE_VALUE=loaded
touch $marker
EOF

    source "$ENV_LIB"
    run ws_load_env "$env_file"

    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid .env line 2"* ]]
    [ ! -e "$marker" ]
}

@test "workspace scripts use the literal loader instead of sourcing .env" {
    local file
    for file in \
        scripts/ws \
        scripts/ws-test.sh \
        scripts/ws-lint.sh \
        scripts/ws-commit.sh \
        scripts/ws-clone-fork.sh; do
        run rg --fixed-strings 'source "$ROOT_DIR/.env"' "$REPO_ROOT/$file"
        [ "$status" -ne 0 ]
    done
}
