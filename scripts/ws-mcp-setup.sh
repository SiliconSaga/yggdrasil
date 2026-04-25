#!/usr/bin/env bash
# ws-mcp-setup.sh — Generate .mcp.json for Claude Code from overlay mcp.servers declarations
#
# Usage:
#   ws-mcp-setup.sh [--dry-run] [--status]
#
#   --dry-run   Print what would be written without touching .mcp.json
#   --status    Show currently configured servers (reads existing .mcp.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/.mcp.json"

# shellcheck source=ws-overlay.sh
source "$SCRIPT_DIR/ws-overlay.sh"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

DRY_RUN=false
STATUS_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --status)  STATUS_ONLY=true ;;
    esac
done

# --status: show what's currently in .mcp.json
if [[ "$STATUS_ONLY" == "true" ]]; then
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        echo "No .mcp.json found. Run 'ws mcp-setup' to generate it."
        exit 0
    fi
    echo "Configured MCP servers (.mcp.json):"
    if command -v jq &>/dev/null; then
        jq -r '.mcpServers | to_entries[] | "  \(.key)  →  \(.value.url)"' "$OUTPUT_FILE"
    else
        yq -o=json '.mcpServers | to_entries[] | "  " + .key + "  →  " + .value.url' "$OUTPUT_FILE" 2>/dev/null \
            || cat "$OUTPUT_FILE"
    fi
    echo ""
    echo "Auth: run /mcp inside Claude Code to authenticate each server via browser OAuth."
    exit 0
fi

ECO="$(ws_resolve_ecosystem)"

# Check if any mcp.servers are declared
server_count="$(yq '.mcp.servers | length' "$ECO" 2>/dev/null || echo 0)"
if [[ "$server_count" -eq 0 || "$server_count" == "null" ]]; then
    echo "No mcp.servers declared in the active ecosystem config."
    echo "  Add an mcp.servers section to your overlay's ecosystem.yaml to use this command."
    exit 0
fi

# Build .mcp.json using yq transformation
# Claude Code HTTP format: {"mcpServers": {"name": {"type": "http", "url": "..."}}}
mcp_json="$(yq -o=json '{
  "mcpServers": (
    .mcp.servers | to_entries | map({
      "key": .key,
      "value": {"type": .value.transport, "url": .value.url}
    }) | from_entries
  )
}' "$ECO")"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "--- dry run: would write to $OUTPUT_FILE ---"
    echo "$mcp_json"
    echo "--- end dry run ---"
    exit 0
fi

echo "$mcp_json" > "$OUTPUT_FILE"

echo "Written: $OUTPUT_FILE"
echo ""
echo "Servers configured for Claude Code:"
for name in $(yq '.mcp.servers | keys | .[]' "$ECO"); do
    url="$(yq ".mcp.servers[\"$name\"].url" "$ECO")"
    echo "  $name  →  $url"
done
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load .mcp.json"
echo "  2. Run /mcp inside Claude Code to authenticate each server"
echo "     (Claude Code handles the browser OAuth flow — do not paste auth URLs manually)"
echo ""
echo "Cursor users: MaaS servers must be added to ~/.cursor/mcp.json manually."
echo "  See: overlays/overlay-nvidia-cis/AGENTS.md for the server list and URLs."
