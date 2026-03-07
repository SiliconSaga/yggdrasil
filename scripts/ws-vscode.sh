#!/usr/bin/env bash
# ws-vscode.sh — Generate a VS Code workspace file from cloned components
#
# Usage:
#   ws-vscode.sh                   Generate yggdrasil.code-workspace
#
# Only includes component folders that are actually cloned locally.
# Re-run after cloning new components to update the workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"
OUTPUT="$ROOT_DIR/yggdrasil.code-workspace"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

# Build folder list: yggdrasil root first, then cloned components
folders='[{"path": "."}'
for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
    if [[ -d "$COMPONENTS_DIR/$name/.git" ]]; then
        folders="$folders, {\"path\": \"components/$name\"}"
    fi
done
folders="$folders]"

# Write workspace file
echo "{" > "$OUTPUT"
echo "  \"folders\": $folders," >> "$OUTPUT"
echo '  "settings": {}' >> "$OUTPUT"
echo "}" >> "$OUTPUT"

# Pretty-print if yq can handle JSON
if yq --output-format=json '.' "$OUTPUT" > /dev/null 2>&1; then
    yq --output-format=json --prettyPrint '.' "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
fi

echo "Generated: $OUTPUT"
echo "Open in VS Code: code $OUTPUT"
