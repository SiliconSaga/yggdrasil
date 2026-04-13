#!/usr/bin/env bash
# git-issue.sh — file an issue from a draft file
#
# Usage: ./scripts/git-issue.sh COMPONENT_DIR REMOTE TITLE LABEL BODYFILE
#   COMPONENT_DIR — path to the component git repo
#   REMOTE        — git remote name (e.g. 'SiliconSaga', 'MyGitLabGroup')
#                   The org/repo slug is resolved from the remote URL.
#   TITLE         — issue title
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
# Uses git-provider.sh for provider-agnostic issue creation.

set -euo pipefail

COMPONENT_DIR="${1:-}"
REMOTE="${2:-}"
TITLE="${3:-}"
LABEL="${4:-}"
BODYFILE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# Ensure clearinghouse directory exists
mkdir -p "$REPO_ROOT/.issues"


# Source provider dispatcher
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Source shared overlay/merge functions for ecosystem config
source "$SCRIPT_DIR/ws-overlay.sh"

# Validate arguments (REMOTE may be empty for auto-detection)
if [[ -z "$COMPONENT_DIR" || -z "$TITLE" || -z "$LABEL" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 COMPONENT_DIR [REMOTE] TITLE LABEL BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Resolve identity from merged ecosystem config
ECO=$(ws_resolve_ecosystem)
HUMAN_ACCOUNT=$(yq '.identity.human_account // ""' "$ECO" 2>/dev/null)
GDD_HOME=$(yq '.defaults.gddHome // "https://siliconsaga.github.io/yggdrasil/gdd/"' "$ECO" 2>/dev/null)
[[ "$GDD_HOME" == "null" || -z "$GDD_HOME" ]] && GDD_HOME="https://siliconsaga.github.io/yggdrasil/gdd/"

if [[ -z "$HUMAN_ACCOUNT" ]]; then
  echo "ERROR: identity.human_account not set in ecosystem config." >&2
  echo "  Set it in ecosystem.local.yaml (see ecosystem.local.yaml.example)." >&2
  exit 1
fi

# Enforce AI attribution line referencing the driving human
if ! head -n 1 "$BODYFILE" | grep -q '^> \*\*AI-assisted'; then
  echo "ERROR: body file is missing the AI attribution line." >&2
  echo "  First line must contain: > **AI-assisted issue.**" >&2
  exit 1
fi

# Substitute @HUMAN_ACCOUNT and @GDD_HOME placeholders in a temp copy of the body file
RESOLVED_BODY=$(mktemp)
trap 'rm -f "$RESOLVED_BODY" "$_RESOLVED_ECOSYSTEM" 2>/dev/null' EXIT
_ESC_HUMAN=$(printf '%s' "$HUMAN_ACCOUNT" | sed 's/[&|\\]/\\&/g')
_ESC_GDD_HOME=$(printf '%s' "$GDD_HOME" | sed 's/[&|\\]/\\&/g')
sed -e "s|@HUMAN_ACCOUNT|@${_ESC_HUMAN}|g" \
    -e "s|@GDD_HOME|${_ESC_GDD_HOME}|g" \
    "$BODYFILE" > "$RESOLVED_BODY"

# Resolve remote:
#   1 remote  → use it (any name)
#   N remotes + REMOTE hint → case-insensitive match
#   N remotes, no match → fail with clear error
mapfile -t _REMOTES < <(cd "$COMPONENT_DIR" && git remote)

REMOTE_NAME=""
if [[ ${#_REMOTES[@]} -eq 0 ]]; then
  echo "ERROR: No remotes configured in $COMPONENT_DIR." >&2
  exit 1
elif [[ ${#_REMOTES[@]} -eq 1 ]]; then
  REMOTE_NAME="${_REMOTES[0]}"
elif [[ -n "$REMOTE" ]]; then
  REMOTE_NAME=$(cd "$COMPONENT_DIR" && git remote | grep -i "^${REMOTE}$" | head -1 || true)
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$REMOTE' found in $COMPONENT_DIR." >&2
    echo "  Available remotes: ${_REMOTES[*]}" >&2
    exit 1
  fi
else
  echo "ERROR: Multiple remotes in $COMPONENT_DIR — specify which one." >&2
  echo "  Available remotes: ${_REMOTES[*]}" >&2
  echo "  Usage: ws issue <comp> <remote> <title> <label> <bodyfile>" >&2
  exit 1
fi
REMOTE_URL=$(cd "$COMPONENT_DIR" && git remote get-url "$REMOTE_NAME")

# Detect and load provider
gp_detect_and_load "$REMOTE_URL" "$ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$REMOTE_URL")

if [[ -z "$TARGET_SLUG" || "$TARGET_SLUG" != */* ]]; then
  echo "ERROR: Could not resolve org/repo from remote URL: $REMOTE_URL" >&2
  exit 1
fi

# Show a summary before filing
echo "Filing issue to $TARGET_SLUG (via remote '$REMOTE_NAME'):"
echo "  Title : $TITLE"
echo "  Label : $LABEL"
echo "  Author: @$HUMAN_ACCOUNT (via agent)"
echo "  Body  : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

gp_create_issue \
  --repo "$TARGET_SLUG" \
  --title "$TITLE" \
  --label "$LABEL" \
  --body-file "$RESOLVED_BODY"
