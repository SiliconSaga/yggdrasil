#!/usr/bin/env bash
# ws-status.sh — Show Git status for all cloned components
# ws:use-when checking git state across every cloned component at a glance
#
# Usage:
#   ws-status.sh             Short status (branch, dirty flag, up to 10 changed files)
#   ws-status.sh --verbose   Full git status per component (all changed files)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

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
# `// {}` guards the fresh-workspace case: a missing or null components map
# must read as empty, not surface a yq "cannot get keys of !!null" error.
for name in $(yq '.components // {} | keys | .[]' "$ECO"); do
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

# Walk realms/ — directories with a .git/ subfolder. Disk-driven, not
# config-driven; we show all cloned realms regardless of active-realm
# selection so users get full workspace dirty-state visibility.
realms_dir="${REALMS_DIR:-$ROOT_DIR/realms}"
if [[ -d "$realms_dir" ]]; then
    for realm_path in "$realms_dir"/*/; do
        [[ -d "${realm_path}.git" ]] || continue
        realm_name="$(basename "$realm_path")"
        echo "=== $realm_name ==="
        print_repo_status "$realm_path"
        echo ""
    done
fi

# Walk hoards/ — same shape as realms walk.
hoards_dir="${HOARDS_DIR:-$ROOT_DIR/hoards}"
if [[ -d "$hoards_dir" ]]; then
    for hoard_path in "$hoards_dir"/*/; do
        [[ -d "${hoard_path}.git" ]] || continue
        hoard_name="$(basename "$hoard_path")"
        echo "=== $hoard_name ==="
        print_repo_status "$hoard_path"
        echo ""
    done
fi
