#!/usr/bin/env bash
# gh-issue.sh — file a GitHub issue from a draft file
#
# Usage: ./scripts/gh-issue.sh COMPONENT_DIR REMOTE TITLE LABEL BODYFILE
#   COMPONENT_DIR — path to the component git repo
#   REMOTE        — git remote name (e.g. 'SiliconSaga', 'MovingBlocks')
#                   The org/repo is resolved from the remote URL.
#   TITLE         — issue title, e.g. 'fix: remove hardcoded storageClassName'
#   LABEL         — single label: bug | enhancement | documentation
#   BODYFILE      — path to the issue body markdown file
#
# The first line of the body file must contain an AI attribution line.
# The script reads identity.human_account from the merged ecosystem config
# and validates that the attribution references it.
#
# Draft files live in .issues/ (gitignored, created on first use).
# Copy .agent/issue-template.md to .issues/<descriptive-name>.md to start a draft.
#
# Example:
#   ./scripts/gh-issue.sh components/terasology MovingBlocks \
#     "fix: overlapping NUIManagers" enhancement .issues/nui-overlap.md

set -euo pipefail

COMPONENT_DIR="${1:-}"
REMOTE="${2:-}"
TITLE="${3:-}"
LABEL="${4:-}"
BODYFILE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
ENV_FILE="$REPO_ROOT/.env"

# Ensure clearinghouse directory exists
mkdir -p "$REPO_ROOT/.issues"

# Load GH_TOKEN if not already set
if [[ -z "${GH_TOKEN:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
  else
    echo "ERROR: GH_TOKEN not set and $ENV_FILE not found" >&2
    exit 1
  fi
fi

# Validate arguments
if [[ -z "$COMPONENT_DIR" || -z "$REMOTE" || -z "$TITLE" || -z "$LABEL" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 COMPONENT_DIR REMOTE TITLE LABEL BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Resolve identity from merged ecosystem config
source "$SCRIPT_DIR/ws-overlay.sh"
ECO=$(ws_resolve_ecosystem)
HUMAN_ACCOUNT=$(yq '.identity.human_account // ""' "$ECO" 2>/dev/null)

if [[ -z "$HUMAN_ACCOUNT" ]]; then
  echo "ERROR: identity.human_account not set in ecosystem config." >&2
  echo "  Set it in ecosystem.local.yaml (see ecosystem.local.yaml.example)." >&2
  exit 1
fi

# Enforce AI attribution line referencing the driving human
if ! grep -q 'AI-assisted issue' "$BODYFILE"; then
  echo "ERROR: body file is missing the AI attribution line." >&2
  echo "  First line must contain: > **AI-assisted issue.**" >&2
  exit 1
fi

# Resolve org/repo from the remote URL (case-insensitive remote lookup)
REMOTE_NAME=$(cd "$COMPONENT_DIR" && git remote | grep -i "^${REMOTE}$" | head -1)
if [[ -z "$REMOTE_NAME" ]]; then
  echo "ERROR: No remote matching '$REMOTE' found in $COMPONENT_DIR." >&2
  echo "  Available remotes: $(cd "$COMPONENT_DIR" && git remote | tr '\n' ' ')" >&2
  exit 1
fi
REMOTE_URL=$(cd "$COMPONENT_DIR" && git remote get-url "$REMOTE_NAME")
# Extract org/repo from HTTPS or SSH URL
TARGET_REPO=$(echo "$REMOTE_URL" | sed 's|.*github.com[:/]||; s|\.git$||')

if [[ -z "$TARGET_REPO" || "$TARGET_REPO" != */* ]]; then
  echo "ERROR: Could not resolve org/repo from remote URL: $REMOTE_URL" >&2
  exit 1
fi

# Show a summary before filing
echo "Filing issue to $TARGET_REPO (via remote '$REMOTE_NAME'):"
echo "  Title : $TITLE"
echo "  Label : $LABEL"
echo "  Author: @$HUMAN_ACCOUNT (via agent)"
echo "  Body  : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

gh issue create \
  --repo "$TARGET_REPO" \
  --title "$TITLE" \
  --label "$LABEL" \
  --body-file "$BODYFILE"
