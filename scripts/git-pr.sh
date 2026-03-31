#!/usr/bin/env bash
# git-pr.sh — open a pull request from the current branch
#
# Usage: git-pr.sh [--upstream] TITLE BODYFILE
#   --upstream — target the upstream (non-SiliconSaga) remote instead of the fork.
#                Creates a cross-fork PR: SiliconSaga:branch → upstream:base.
#   TITLE     — PR title, e.g. 'feat: add topic branch workflow scripts'
#   BODYFILE  — path to markdown file containing the PR body
#
# Without --upstream, targets the SiliconSaga fork repo with --base main.
# With --upstream, auto-detects the upstream remote and targets its default branch.
#
# Draft files live in .prs/ (gitignored, auto-created).
# Copy .agent/pr-template.md to .prs/<descriptive-name>.md to start a draft.
#
# Sources .env automatically. Run from the repo the branch belongs to.

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

# Parse --upstream flag
UPSTREAM=""
if [[ "${1:-}" == "--upstream" ]]; then
  UPSTREAM="1"
  shift
fi

TITLE="${1:-}"
BODYFILE="${2:-}"

# Find the SiliconSaga remote (case-insensitive)
FORK_REMOTE=$(git remote | grep -i '^siliconsaga$' | head -1)
if [[ -z "$FORK_REMOTE" ]]; then
  echo "ERROR: No 'siliconsaga' remote found (checked case-insensitive)." >&2
  echo "  Available remotes: $(git remote | tr '\n' ' ')" >&2
  exit 1
fi
FORK_REPO=$(git remote get-url "$FORK_REMOTE" 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||')

BRANCH=$(git rev-parse --abbrev-ref HEAD)
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Ensure .prs/ clearinghouse exists
mkdir -p "$REPO_ROOT/.prs"

if [[ -z "$TITLE" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 [--upstream] TITLE BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || "$BRANCH" == "develop" ]]; then
  echo "ERROR: current branch is '$BRANCH' — check out a topic branch first" >&2
  exit 1
fi

if [[ -n "$UPSTREAM" ]]; then
  # Cross-fork PR: find the upstream (non-SiliconSaga) remote
  UPSTREAM_REMOTE=""
  for remote in $(git remote); do
    if [[ "$(echo "$remote" | tr '[:upper:]' '[:lower:]')" != "siliconsaga" ]]; then
      UPSTREAM_REMOTE="$remote"
      break
    fi
  done
  if [[ -z "$UPSTREAM_REMOTE" ]]; then
    echo "ERROR: No upstream remote found (only SiliconSaga exists)." >&2
    exit 1
  fi
  UPSTREAM_REPO=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||')

  # Detect the default branch of the upstream repo
  UPSTREAM_DEFAULT=$(gh api "repos/$UPSTREAM_REPO" --jq '.default_branch' 2>/dev/null || echo "main")

  echo "Opening cross-fork PR: $FORK_REPO:$BRANCH → $UPSTREAM_REPO:$UPSTREAM_DEFAULT"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gh pr create \
    --repo "$UPSTREAM_REPO" \
    --base "$UPSTREAM_DEFAULT" \
    --head "SiliconSaga:$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
else
  echo "Opening PR for $FORK_REPO/$BRANCH → main"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gh pr create \
    --repo "$FORK_REPO" \
    --base main \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
fi
