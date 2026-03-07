#!/usr/bin/env bash
# ws-status.sh — Show Git status for all cloned components
#
# Usage:
#   ws-status.sh             Short status (branch + dirty flag)
#   ws-status.sh --verbose   Full git status per component

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

VERBOSE="${1:-}"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

# Status of yggdrasil itself
echo "=== yggdrasil ==="
branch=$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || echo "detached")
dirty=$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null | head -1)
echo "  branch: $branch${dirty:+  (dirty)}"
if [[ "$VERBOSE" == "--verbose" ]]; then
    git -C "$ROOT_DIR" status --short 2>/dev/null | sed 's/^/  /'
fi
echo ""

# Status of each component
for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
    target="$COMPONENTS_DIR/$name"
    if [[ ! -d "$target/.git" ]]; then
        echo "=== $name === (not cloned)"
        echo ""
        continue
    fi

    echo "=== $name ==="
    branch=$(git -C "$target" branch --show-current 2>/dev/null || echo "detached")
    dirty=$(git -C "$target" status --porcelain 2>/dev/null | head -1)
    echo "  branch: $branch${dirty:+  (dirty)}"

    if [[ "$VERBOSE" == "--verbose" ]]; then
        git -C "$target" status --short 2>/dev/null | sed 's/^/  /'
    fi
    echo ""
done
