#!/usr/bin/env bash
# ws-list.sh — List all ecosystem components and their local status
#
# Usage:
#   ws-list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

printf "%-15s %-10s %-12s %-8s\n" "COMPONENT" "TIER" "CHART" "LOCAL"
printf "%-15s %-10s %-12s %-8s\n" "---------" "----" "-----" "-----"

for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
    tier=$(yq ".components.$name.tier" "$ECOSYSTEM")
    chart_version=$(yq ".components.$name.chartVersion" "$ECOSYSTEM")
    disabled=$(yq ".components.$name.disabled // false" "$ECOSYSTEM")

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
