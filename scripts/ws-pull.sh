#!/usr/bin/env bash
# ws-pull.sh — Pull latest changes for cloned components, realms, and hoards
#
# Usage:
#   ws-pull.sh             Pull all cloned components/realms/hoards (skips dirty repos)
#   ws-pull.sh <name>      Pull a single component, realm, or hoard

set -euo pipefail

# Help short-circuit BEFORE any dependency check — fresh machines
# without yq still need to be able to read the help text.
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage:
  ws pull             Pull all cloned components, realms, and hoards (skips dirty repos)
  ws pull <name>      Pull a single component, realm, or hoard

Skips repos with an unclean working tree — commit or stash first.
Walks ecosystem-declared components plus on-disk realms/ and hoards/
(parallel to `ws status`).
HELP
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

ECO="$(ws_resolve_ecosystem)"

pull_repo() {
    local name="$1"
    local target="$2"

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
    # Single named arg — could be component, realm, or hoard.
    # ws_validate_component handles all three since PR #44 (sets COMPONENT_DIR).
    if ! ws_validate_component "$1"; then
        exit 1
    fi
    pull_repo "$1" "$COMPONENT_DIR"
else
    # No arg — walk all three families. Components are config-driven
    # (yq over ecosystem.yaml); realms and hoards are disk-driven
    # (any directory with a .git/ subfolder). Mirrors ws-status.sh.
    for name in $(yq '.components | keys | .[]' "$ECO"); do
        pull_repo "$name" "$COMPONENTS_DIR/$name"
    done

    realms_dir="${REALMS_DIR:-$ROOT_DIR/realms}"
    if [[ -d "$realms_dir" ]]; then
        for realm_path in "$realms_dir"/*/; do
            [[ -d "${realm_path}.git" ]] || continue
            pull_repo "$(basename "$realm_path")" "$realm_path"
        done
    fi

    hoards_dir="${HOARDS_DIR:-$ROOT_DIR/hoards}"
    if [[ -d "$hoards_dir" ]]; then
        for hoard_path in "$hoards_dir"/*/; do
            [[ -d "${hoard_path}.git" ]] || continue
            pull_repo "$(basename "$hoard_path")" "$hoard_path"
        done
    fi
fi

if [[ "$HAD_FAILURES" -ne 0 ]]; then
    echo ""
    echo "Some repos had conflicts. Resolve manually, then re-run."
    exit 1
fi
