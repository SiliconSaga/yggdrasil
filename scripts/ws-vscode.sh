#!/usr/bin/env bash
# ws-vscode.sh — Generate a VS Code workspace file from cloned components
# ws:use-when generating the VS Code multi-root workspace file
#
# Usage:
#   ws-vscode.sh                   Generate yggdrasil.code-workspace
#
# Only includes component folders that are actually cloned locally.
# Re-run after cloning new components to update the workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"
OUTPUT="$ROOT_DIR/yggdrasil.code-workspace"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

if ! type -P yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

ECO="$(ws_resolve_ecosystem)"

# Build folder list: yggdrasil root first, then cloned components.
# `folders` stays a complete, well-formed JSON array on every iteration —
# each append round-trips through from_json rather than hand-editing
# brackets, so a future edit can't silently produce broken JSON.
folders='[{"path": "."}]'
# `// {}` guards the fresh-workspace case (null/missing components map).
while IFS= read -r name; do
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        # Name the offending key so a large catalog is diagnosable — control
        # characters stripped first, since an invalid key is exactly the one
        # string that must not be echoed to the terminal raw.
        safe_name="$(printf '%s' "$name" | tr -d '\000-\037\177')"
        echo "ERROR: Invalid component name '$safe_name' in ecosystem config; expected lowercase alphanumeric segments with hyphens or dots." >&2
        exit 1
    fi
    if [[ -d "$COMPONENTS_DIR/$name/.git" ]]; then
        folders="$(FOLDERS_JSON="$folders" COMPONENT_PATH="components/$name" \
            yq -n -o=json 'strenv(FOLDERS_JSON) | from_json + [{"path": strenv(COMPONENT_PATH)}]')"
    fi
done < <(yq -r '.components // {} | keys | .[]' "$ECO")

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
