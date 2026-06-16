# Shared helpers for ws-commit bats tests.
#
# Each test gets an isolated synthetic git repo under $BATS_TEST_TMPDIR
# that ws-commit.sh treats as the "yggdrasil" component (which
# ws_resolve_target maps to $ROOT_DIR by special-case). Setting
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
#                 ws_resolve_ecosystem succeeds. Identity now resolves
#                 from the per-session file (see GDD_SESSION_ID below),
#                 not from the ecosystem config.
init_synthetic_repo() {
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO_DIR"

    echo "hello" > "$REPO_DIR/test.md"
    git -C "$REPO_DIR" add test.md
    git -C "$REPO_DIR" -c user.name=seed -c user.email=seed@local \
        commit -q -m "seed commit"

    export ROOT_DIR="$REPO_DIR"

    # Deterministic session identity for resolution (Task 2). GDD_SESSION_ID
    # wins over any inherited CLAUDE_CODE_SESSION_ID, so tests are hermetic.
    export GDD_SESSION_ID="ws-commit-test"
    # Also drop any inherited inline GDD_CO_AUTHOR so a value in the outer
    # shell can't masquerade as the rung-1 inline override and skew tests.
    unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID GDD_CO_AUTHOR
    mkdir -p "$REPO_DIR/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR="Claude Opus 4.8 <noreply@anthropic.com>"\n' \
        > "$REPO_DIR/.tmp/gdd-agent-sessions/ws-commit-test.env"

    # Minimal ecosystem stubs. Trailer-builder calls ws_resolve_ecosystem;
    # that function expects an ecosystem.yaml-like file to exist.
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    # `components` is a mapping in the real schema (scripts do
    # `yq '.components | keys | .[]'` and `.components.<name>.repo`).
    # Use `{}` here even though ws-commit doesn't traverse it — keeps
    # the stub schema-faithful so a future refactor that DOES read
    # .components fails loudly rather than mysteriously.
    cat > "$ECOSYSTEM" <<'YAML'
identity: {}
components: {}
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
