# Shared helpers for ws-audit-permissions bats tests.
#
# Each test gets a fresh isolated workspace under $BATS_TEST_TMPDIR
# with synthetic settings.json files at each of the three scopes.
# Tests invoke ws-audit-permissions.sh directly with $HOME and
# $ROOT_DIR pointing into the sandbox so the audit doesn't read
# the real workspace's permission configs.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
AUDIT_BIN="$REPO_ROOT/scripts/ws-audit-permissions.sh"

# Set up an isolated workspace.
#
# After this returns:
#   $WORK           — workspace root
#   $WORK/.claude/  — workspace settings dir
#   $HOME           — sandbox user dir ($WORK/_home)
#   ROOT_DIR        — exported = $WORK
init_audit_env() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/.claude"
    mkdir -p "$WORK/_home/.claude"
    export HOME="$WORK/_home"
    export ROOT_DIR="$WORK"
}

# Write a settings.json at the given scope (user / project /
# project-local) with the given permissions.allow patterns (passed
# newline-separated).
write_settings() {
    local scope="$1"
    local entries="$2"
    local file
    case "$scope" in
        user)          file="$HOME/.claude/settings.json" ;;
        project)       file="$WORK/.claude/settings.json" ;;
        project-local) file="$WORK/.claude/settings.local.json" ;;
        *) echo "ERROR: unknown scope '$scope'" >&2; return 1 ;;
    esac
    {
        echo "{"
        echo "  \"permissions\": {"
        echo "    \"allow\": ["
        local first=true
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            if $first; then first=false; else echo ","; fi
            printf '      "%s"' "$entry"
        done <<< "$entries"
        echo ""
        echo "    ]"
        echo "  }"
        echo "}"
    } > "$file"
}

run_audit() {
    run bash "$AUDIT_BIN" "$@"
}
