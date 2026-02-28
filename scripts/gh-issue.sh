#!/usr/bin/env bash
# gh-issue.sh — file a GitHub issue from a draft file
#
# Usage: ./scripts/gh-issue.sh REPO TITLE LABEL BODYFILE
#   REPO      — repo name only, e.g. 'mimir' (owner is always SiliconSaga)
#   TITLE     — issue title, e.g. 'fix: remove hardcoded storageClassName'
#   LABEL     — single label: bug | enhancement | documentation
#   BODYFILE  — path to markdown file containing the issue body
#
# Example:
#   ./scripts/gh-issue.sh mimir "fix: remove storageClassName" bug .issue-draft.md

set -euo pipefail

REPO="${1:-}"
TITLE="${2:-}"
LABEL="${3:-}"
BODYFILE="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

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
if [[ -z "$REPO" || -z "$TITLE" || -z "$LABEL" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 REPO TITLE LABEL BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Enforce AI attribution line
if ! grep -q 'AI-generated issue' "$BODYFILE"; then
  echo "ERROR: body file is missing the required AI attribution line." >&2
  echo "  First line must contain: > **AI-generated issue.**" >&2
  exit 1
fi

# Show a summary before filing
echo "Filing issue to SiliconSaga/$REPO:"
echo "  Title : $TITLE"
echo "  Label : $LABEL"
echo "  Body  : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

gh issue create \
  --repo "SiliconSaga/$REPO" \
  --title "$TITLE" \
  --label "$LABEL" \
  --body-file "$BODYFILE"
