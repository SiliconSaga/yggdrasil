#!/usr/bin/env bash
# ws-status.sh — Show Git status for all cloned components
#
# Usage:
#   ws-status.sh             Short status (branch, dirty flag, up to 10 changed files)
#   ws-status.sh --verbose   Full git status per component (all changed files)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# shellcheck source=ws-overlay.sh
source "$SCRIPT_DIR/ws-overlay.sh"

VERBOSE="${1:-}"
DEFAULT_LIMIT=10

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

ECO="$(ws_resolve_ecosystem)"

# Print status for a repo at the given path.
# Outputs: branch line + (if dirty) up to $DEFAULT_LIMIT file lines (or all with --verbose).
print_repo_status() {
    local path="$1"
    local branch
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "detached")

    local status_lines
    status_lines=$(git -C "$path" status --porcelain 2>/dev/null || true)
    local dirty_count=0
    if [[ -n "$status_lines" ]]; then
        # BSD `wc` (macOS) pads output with leading spaces — trim to avoid
        # " (dirty —        5 file(s))" on some platforms.
        dirty_count=$(printf '%s\n' "$status_lines" | wc -l | tr -d '[:space:]')
    fi

    if [[ "$dirty_count" -gt 0 ]]; then
        echo "  branch: $branch  (dirty — $dirty_count file(s))"
    else
        echo "  branch: $branch"
    fi

    if [[ "$dirty_count" -eq 0 ]]; then
        return
    fi

    if [[ "$VERBOSE" == "--verbose" ]]; then
        printf '%s\n' "$status_lines" | sed 's/^/  /'
    else
        printf '%s\n' "$status_lines" | head -n "$DEFAULT_LIMIT" | sed 's/^/  /'
        if [[ "$dirty_count" -gt "$DEFAULT_LIMIT" ]]; then
            echo "  ... and $((dirty_count - DEFAULT_LIMIT)) more (run with --verbose to see all)"
        fi
    fi
}

# Status of yggdrasil itself
echo "=== yggdrasil ==="
print_repo_status "$ROOT_DIR"
echo ""

# Status of each component
for name in $(yq '.components | keys | .[]' "$ECO"); do
    target="$COMPONENTS_DIR/$name"
    if [[ ! -d "$target/.git" ]]; then
        echo "=== $name === (not cloned)"
        echo ""
        continue
    fi

    echo "=== $name ==="
    print_repo_status "$target"
    echo ""
done
