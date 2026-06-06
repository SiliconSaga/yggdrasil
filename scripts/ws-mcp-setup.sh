#!/usr/bin/env bash
# ws-mcp-setup.sh — Generate .mcp.json for Claude Code from realm mcp.servers declarations
# ws:use-when:mcp-setup generating .mcp.json from realm mcp.servers declarations
# ws:use-when:mcp-status checking which MCP servers are currently configured
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

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi
# Disambiguate Mike Farah's Go yq (required) from python-yq (kislyuk/yq).
# Both install as `yq`; python-yq fails on every Mike Farah-specific call.
if ! yq --version 2>&1 | grep -qE 'mikefarah|version v([4-9]|[1-9][0-9]+)\.'; then
    echo "ERROR: yq v4+ from Mike Farah is required (found: $(yq --version 2>&1))." >&2
    echo "  Install from: https://github.com/mikefarah/yq" >&2
    exit 1
fi

DRY_RUN=false
STATUS_ONLY=false

usage() {
    sed -n '/^# Usage:$/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --status)  STATUS_ONLY=true ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument '$arg'." >&2
            usage >&2
            exit 2
            ;;
    esac
done

# --status: show what's currently in .mcp.json
if [[ "$STATUS_ONLY" == "true" ]]; then
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        echo "No .mcp.json found. Run 'ws mcp-setup' to generate it."
        exit 0
    fi
    echo "Configured MCP servers (.mcp.json):"
    # Default mcpServers to an empty object so a hand-edited file with a
    # missing or null mcpServers key prints a friendly message instead of
    # failing under set -e.
    if command -v jq &>/dev/null; then
        server_lines="$(jq -r '(.mcpServers // {}) | to_entries[] | "  \(.key)  →  \(.value.url)"' "$OUTPUT_FILE")"
    else
        server_lines="$(yq -p=json -r '.mcpServers // {} | to_entries | .[] | "  " + .key + "  →  " + .value.url' "$OUTPUT_FILE")"
    fi
    if [[ -z "$server_lines" ]]; then
        echo "  (none configured)"
    else
        echo "$server_lines"
    fi
    echo ""
    echo "Auth: run /mcp inside Claude Code to authenticate each server via browser OAuth."
    exit 0
fi

ECO="$(ws_resolve_ecosystem)"

# Check if any mcp.servers are declared. // {} coerces missing/null to an
# empty map so length always returns a non-negative integer.
server_count="$(yq '.mcp.servers // {} | length' "$ECO" 2>/dev/null || echo 0)"
if [[ ! "$server_count" =~ ^[0-9]+$ || "$server_count" -eq 0 ]]; then
    echo "No mcp.servers declared in the active ecosystem config."
    echo "  Add an mcp.servers section to your realm's ecosystem.yaml to use this command."
    exit 0
fi

# Validate each server has the required url and transport fields before
# generating .mcp.json. Catches misconfigurations up front instead of
# letting them produce a .mcp.json with null values that Claude Code rejects.
missing_fields="$(yq -r '
  .mcp.servers
  | to_entries
  | map(select(.value.url == null or .value.transport == null) | .key)
  | join(", ")
' "$ECO")"
if [[ -n "$missing_fields" && "$missing_fields" != "null" ]]; then
    echo "ERROR: mcp.servers entries missing required fields (url and/or transport): $missing_fields" >&2
    echo "  Each server must declare both 'url' and 'transport' (e.g. transport: http)." >&2
    exit 1
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

# Atomic write: stage to a temp file in the same directory, then mv into
# place. Avoids leaving a truncated .mcp.json if the script is interrupted.
tmp_file="$(mktemp "${OUTPUT_FILE}.XXXXXX")"
echo "$mcp_json" > "$tmp_file"
mv -f "$tmp_file" "$OUTPUT_FILE"

echo "Written: $OUTPUT_FILE"
echo ""
echo "Servers configured for Claude Code:"
# Single yq call avoids shell word-splitting and quote-injection that
# could occur if a server name ever contained spaces or quote characters.
yq -r '.mcp.servers | to_entries | .[] | "  " + .key + "  →  " + .value.url' "$ECO"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load .mcp.json"
echo "  2. Run /mcp inside Claude Code to authenticate each server"
echo "     (Claude Code handles the browser OAuth flow — do not paste auth URLs manually)"
echo ""
echo "Cursor users: MaaS servers must be added to ~/.cursor/mcp.json manually."
mcp_doc="$(yq '.mcp.doc // ""' "$ECO" 2>/dev/null || echo "")"
active_realm="$(ws_detect_realm 2>/dev/null || true)"
if [[ -n "$mcp_doc" && "$mcp_doc" != "null" && -n "$active_realm" ]]; then
    echo "  See: realms/$active_realm/$mcp_doc for the server list and URLs."
fi
