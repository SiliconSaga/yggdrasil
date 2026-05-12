# Shared helpers for ws-commit bats tests.
#
# Each test gets an isolated synthetic git repo under $BATS_TEST_TMPDIR
# that ws-commit.sh treats as the "yggdrasil" component (which
# ws_validate_component maps to $ROOT_DIR by special-case). Setting
# ROOT_DIR to the synthetic repo path keeps the validation
# short-circuited without faking an ecosystem.yaml entry.
#
# Tests invoke ws-commit.sh directly (not the `ws` wrapper) so the
# env-var overrides propagate cleanly.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_COMMIT_BIN="$REPO_ROOT/scripts/ws-commit.sh"

# Build a fresh synthetic git repo with one seed commit and one tracked
# file (test.md). Caller can then modify files / write bodyfiles that
# reference them.
#
# After this returns:
#   $REPO_DIR   — path to the synthetic repo
#   $ROOT_DIR   — same path, exported so ws-commit.sh's "yggdrasil"
#                 component lookup resolves COMPONENT_DIR to it
#   $ECOSYSTEM, $ECOSYSTEM_LOCAL — minimal stubs so
#                 ws_resolve_ecosystem succeeds for the trailer-build
#                 step. No identity.co_authored_by entry → trailer
#                 falls through to the dynamic CLAUDE_MODEL default.
init_synthetic_repo() {
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO_DIR"

    echo "hello" > "$REPO_DIR/test.md"
    git -C "$REPO_DIR" add test.md
    git -C "$REPO_DIR" -c user.name=seed -c user.email=seed@local \
        commit -q -m "seed commit"

    export ROOT_DIR="$REPO_DIR"

    # Minimal ecosystem stubs. Trailer-builder calls ws_resolve_ecosystem;
    # that function expects an ecosystem.yaml-like file to exist.
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    cat > "$ECOSYSTEM" <<'YAML'
identity: {}
components: []
YAML
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/ecosystem.local.yaml"
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML
}

# Write a bodyfile at $1 with $2 as the message subject, $3 as a
# newline-separated `add:` list, $4 as optional body content.
write_bodyfile() {
    local path="$1"
    local message="$2"
    local add="$3"
    local body="${4:-}"

    {
        echo "---"
        echo "message: \"$message\""
        echo ""
        if [[ -n "$add" ]]; then
            echo "add:"
            while IFS= read -r f; do
                [[ -n "$f" ]] && echo "  - $f"
            done <<< "$add"
        fi
        echo "---"
        echo ""
        echo "$body"
    } > "$path"
}

# Invoke ws-commit.sh with the test env propagated.
run_ws_commit() {
    run bash "$WS_COMMIT_BIN" "$@"
}
