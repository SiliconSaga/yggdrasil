#!/usr/bin/env bash
# ws-list.sh — List all ecosystem components and their local status
# ws:use-when surveying what's declared in the ecosystem (clones, tiers, repos)
#
# Usage:
#   ws-list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source shared realm/merge functions
# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

ECO="$(ws_resolve_ecosystem)"

# Show active realm
active_realm="$(ws_detect_realm)"
if [[ -n "$active_realm" ]]; then
    echo "Realm: $active_realm"
    echo ""
fi

# Safety check: no components declared
comp_count=$(yq '.components | length' "$ECO" 2>/dev/null || echo 0)
if [[ "$comp_count" -eq 0 ]]; then
    echo "No components declared."
    echo "  Run 'ws realm init' to get started, or 'ws realm <url>' for your community."
    exit 0
fi

printf "%-15s %-10s %-12s %-8s\n" "COMPONENT" "TIER" "CHART" "LOCAL"
printf "%-15s %-10s %-12s %-8s\n" "---------" "----" "-----" "-----"

while IFS= read -r name; do
    tier=$(COMPONENT_NAME="$name" yq '.components[strenv(COMPONENT_NAME)].tier // ""' "$ECO")
    chart_version=$(COMPONENT_NAME="$name" yq '.components[strenv(COMPONENT_NAME)].chartVersion // ""' "$ECO")
    disabled=$(COMPONENT_NAME="$name" yq '.components[strenv(COMPONENT_NAME)].disabled // false' "$ECO")

    if [[ -d "$COMPONENTS_DIR/$name/.git" ]]; then
        local_status="yes"
    else
        local_status="-"
    fi

    if [[ "$disabled" == "true" ]]; then
        local_status="disabled"
    fi

    printf "%-15s %-10s %-12s %-8s\n" "$name" "$tier" "$chart_version" "$local_status"
done < <(yq -r '.components | keys | .[]' "$ECO")
