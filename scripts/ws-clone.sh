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
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source .env if present (for GH_TOKEN)
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

clone_component() {
    local name="$1"
    local target="$COMPONENTS_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        echo "SKIP: $name (already cloned at $target)"
        return 0
    fi

    local disabled
    disabled=$(yq ".components.$name.disabled // false" "$ECOSYSTEM")
    if [[ "$disabled" == "true" ]]; then
        echo "SKIP: $name (disabled in ecosystem.yaml)"
        return 0
    fi

    local git_org
    git_org=$(yq '.defaults.gitOrg' "$ECOSYSTEM")
    local repo_url="$git_org/$name.git"

    echo "CLONE: $name -> $target"
    git clone "$repo_url" "$target"
}

if [[ "${1:-}" == "--all" ]]; then
    for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
        clone_component "$name"
    done
elif [[ -n "${1:-}" ]]; then
    # Validate component exists in manifest
    if [[ "$(yq ".components.${1} // \"missing\"" "$ECOSYSTEM")" == "missing" ]]; then
        echo "ERROR: '$1' is not declared in ecosystem.yaml" >&2
        exit 1
    fi
    clone_component "$1"
else
    echo "Usage: ws-clone.sh <component> | --all" >&2
    exit 1
fi
