#!/usr/bin/env bash
# ws-pull.sh — Pull latest changes for all cloned components
#
# Usage:
#   ws-pull.sh               Pull all cloned components (skips dirty repos)
#   ws-pull.sh <component>   Pull a single component

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

pull_component() {
    local name="$1"
    local target="$COMPONENTS_DIR/$name"

    if [[ ! -d "$target/.git" ]]; then
        echo "SKIP: $name (not cloned)"
        return 0
    fi

    local dirty
    dirty=$(git -C "$target" status --porcelain 2>/dev/null | head -1)
    if [[ -n "$dirty" ]]; then
        echo "SKIP: $name (dirty working tree — commit or stash first)"
        return 0
    fi

    local branch
    branch=$(git -C "$target" branch --show-current 2>/dev/null)
    if [[ -z "$branch" ]]; then
        echo "SKIP: $name (detached HEAD)"
        return 0
    fi

    # Check if upstream is configured
    if ! git -C "$target" rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
        echo "SKIP: $name (no upstream tracking branch)"
        return 0
    fi

    echo "PULL: $name ($branch)"
    if ! git -C "$target" pull --rebase 2>&1 | sed 's/^/  /'; then
        echo "  CONFLICT: aborting rebase — resolve manually in $target"
        git -C "$target" rebase --abort 2>/dev/null
        HAD_FAILURES=1
    fi
}

HAD_FAILURES=0

if [[ -n "${1:-}" ]]; then
    pull_component "$1"
else
    for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
        pull_component "$name"
    done
fi

if [[ "$HAD_FAILURES" -ne 0 ]]; then
    echo ""
    echo "Some components had conflicts. Resolve manually, then re-run."
    exit 1
fi
