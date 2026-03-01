#!/usr/bin/env bash
# git-pr.sh — open a pull request from the current branch to main
#
# Usage: git-pr.sh TITLE BODYFILE
#   TITLE    — PR title, e.g. 'feat: add topic branch workflow scripts'
#   BODYFILE — path to markdown file containing the PR body
#
# Draft files live in .prs/ (gitignored, auto-created).
# Copy .agent/pr-template.md to .prs/<descriptive-name>.md to start a draft.
#
# Sources .env automatically. Run from the repo the branch belongs to.
#
# Example:
#   cp .agent/pr-template.md .prs/git-workflow-scripts.md
#   # ... fill in content ...
#   /Users/cervator/dev/git_ws/yggdrasil/scripts/git-pr.sh \
#     "feat: add git workflow scripts" .prs/git-workflow-scripts.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -z "${GH_TOKEN:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
  else
    echo "ERROR: GH_TOKEN not set and $ENV_FILE not found" >&2
    echo "  Create it from .env.example or set GH_TOKEN in your environment." >&2
    exit 1
  fi
fi

TITLE="${1:-}"
BODYFILE="${2:-}"

REPO=$(git remote get-url siliconsaga 2>/dev/null | sed 's|.*/||; s|\.git$||')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Ensure .prs/ clearinghouse exists
mkdir -p "$REPO_ROOT/.prs"

if [[ -z "$TITLE" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 TITLE BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

if [[ "$BRANCH" == "main" ]]; then
  echo "ERROR: current branch is 'main' — check out a topic branch first" >&2
  exit 1
fi

echo "Opening PR for $REPO/$BRANCH → main"
echo "  Title: $TITLE"
echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

gh pr create \
  --repo "SiliconSaga/$REPO" \
  --base main \
  --head "$BRANCH" \
  --title "$TITLE" \
  --body-file "$BODYFILE"
