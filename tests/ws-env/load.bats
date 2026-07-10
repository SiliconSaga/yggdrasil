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
EMPTY=
INERT_COMMAND='\$(touch $marker)'
EOF

    source "$ENV_LIB"
    ws_load_env "$env_file"

    [ "$GH_TOKEN" = "ghp_example" ]
    [ "$GITLAB_HOST" = "gitlab.example.com" ]
    [ "$DOUBLE_QUOTED" = "value with spaces" ]
    [ "$SINGLE_QUOTED" = "another value" ]
    [ "$WITH_EQUALS" = "left=right" ]
    [ "$EMPTY" = "" ]
    [ "$INERT_COMMAND" = "\$(touch $marker)" ]
    [ ! -e "$marker" ]
}

@test "ws_load_env rejects command-environment variables" {
    local env_file="$BATS_TEST_TMPDIR/.env"
    cat > "$env_file" <<'EOF'
PATH=/tmp/untrusted-bin
EOF

    source "$ENV_LIB"
    run ws_load_env "$env_file"

    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to set reserved variable 'PATH'"* ]]
}

@test "ws_load_env rejects Git execution and configuration variables" {
    source "$ENV_LIB"
    local key
    for key in \
        GIT_CONFIG_COUNT \
        GIT_CONFIG_KEY_0 \
        GIT_SSH_COMMAND \
        GIT_SSH \
        GIT_ASKPASS \
        SSH_ASKPASS \
        GIT_EXEC_PATH \
        GIT_EXTERNAL_DIFF \
        GIT_PROXY_COMMAND \
        HOME \
        CDPATH; do
        local env_file="$BATS_TEST_TMPDIR/$key.env"
        printf '%s=%s\n' "$key" "attacker-controlled" > "$env_file"

        run ws_load_env "$env_file"

        [ "$status" -ne 0 ]
        [[ "$output" == *"refusing to set reserved variable '$key'"* ]]
    done
}

@test "ws_load_env still accepts provider token variables" {
    local env_file="$BATS_TEST_TMPDIR/provider.env"
    printf 'GITLAB_TOKEN=glpat-example\n' > "$env_file"

    source "$ENV_LIB"
    ws_load_env "$env_file"

    [ "$GITLAB_TOKEN" = "glpat-example" ]
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
        run grep -Fq 'source "$ROOT_DIR/.env"' "$REPO_ROOT/$file"
        [ "$status" -ne 0 ]
    done
}
