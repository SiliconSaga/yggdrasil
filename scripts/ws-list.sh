#!/usr/bin/env bash
# ws-list.sh — List all ecosystem components and their local status
#
# Usage:
#   ws-list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source shared overlay/merge functions
# shellcheck source=ws-lib.sh
source "$SCRIPT_DIR/ws-lib.sh"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

ECO="$(ws_resolve_ecosystem)"

# Show active overlay
active_overlay="$(ws_detect_overlay)"
if [[ -n "$active_overlay" ]]; then
    echo "Overlay: $active_overlay"
    echo ""
fi

# Safety check: no components declared
comp_count=$(yq '.components | length' "$ECO" 2>/dev/null || echo 0)
if [[ "$comp_count" -eq 0 ]]; then
    echo "No components declared."
    echo "  Run 'ws overlay init' to get started, or 'ws overlay <url>' for your community."
    exit 0
fi

printf "%-15s %-10s %-12s %-8s\n" "COMPONENT" "TIER" "CHART" "LOCAL"
printf "%-15s %-10s %-12s %-8s\n" "---------" "----" "-----" "-----"

for name in $(yq '.components | keys | .[]' "$ECO"); do
    tier=$(yq ".components.$name.tier" "$ECO")
    chart_version=$(yq ".components.$name.chartVersion" "$ECO")
    disabled=$(yq ".components.$name.disabled // false" "$ECO")

    if [[ -d "$COMPONENTS_DIR/$name/.git" ]]; then
        local_status="yes"
    else
        local_status="-"
    fi

    if [[ "$disabled" == "true" ]]; then
        local_status="disabled"
    fi

    printf "%-15s %-10s %-12s %-8s\n" "$name" "$tier" "$chart_version" "$local_status"
done
