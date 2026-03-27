#!/usr/bin/env bash
# ws-clone.sh — Clone one or all ecosystem components into components/
#
# Usage:
#   ws-clone.sh <component>    Clone a single component
#   ws-clone.sh --all          Clone all non-disabled components
#
# Components are cloned into components/<component-name>/ as independent
# Git repos. If the directory already exists, it is skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source shared overlay/merge functions
# shellcheck source=ws-lib.sh
source "$SCRIPT_DIR/ws-lib.sh"

# Source .env if present (for GH_TOKEN)
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

ECO="$(ws_resolve_ecosystem)"

clone_component() {
    local name="$1"
    local target="$COMPONENTS_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        echo "SKIP: $name (already cloned at $target)"
        return 0
    fi

    local disabled
    disabled=$(yq ".components.$name.disabled // false" "$ECO")
    if [[ "$disabled" == "true" ]]; then
        echo "SKIP: $name (disabled)"
        return 0
    fi

    local git_org
    git_org=$(yq '.defaults.gitOrg' "$ECO")
    local repo_url="$git_org/$name.git"

    echo "CLONE: $name -> $target"
    git clone "$repo_url" "$target"
}

if [[ "${1:-}" == "--all" ]]; then
    # Safety check: no components declared
    comp_count=$(yq '.components | length' "$ECO" 2>/dev/null || echo 0)
    if [[ "$comp_count" -eq 0 ]]; then
        echo "No components declared." >&2
        echo "  Run 'ws overlay init' to get started, or 'ws overlay <url>' for your community." >&2
        exit 1
    fi
    for name in $(yq '.components | keys | .[]' "$ECO"); do
        clone_component "$name"
    done
elif [[ -n "${1:-}" ]]; then
    if [[ "$(yq ".components.${1} // \"missing\"" "$ECO")" == "missing" ]]; then
        echo "ERROR: '$1' is not declared in ecosystem config." >&2
        exit 1
    fi
    clone_component "$1"
else
    echo "Usage: ws-clone.sh <component> | --all" >&2
    exit 1
fi
