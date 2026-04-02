#!/usr/bin/env bash
# git-pr.sh — open a pull/merge request from the current branch
#
# Usage: git-pr.sh [--upstream] TITLE BODYFILE
#   --upstream — target the upstream (non-fork) remote instead of the fork.
#                Creates a cross-fork PR/MR: fork:branch → upstream:base.
#   TITLE     — PR/MR title
#   BODYFILE  — path to markdown file containing the body
#
# Without --upstream, targets the fork remote with --base main.
# With --upstream, auto-detects the upstream remote and targets its default branch.
#
# Draft files live in .prs/ (gitignored, auto-created).
# Copy .agent/pr-template.md to .prs/<descriptive-name>.md to start a draft.
#
# Uses git-provider.sh for provider-agnostic PR/MR creation.
# Run from the repo the branch belongs to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source provider dispatcher
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Try to load ecosystem config for provider detection (optional — may not exist)
_ECO=""
if [[ -f "$SCRIPT_DIR/ws-overlay.sh" ]]; then
  source "$SCRIPT_DIR/ws-overlay.sh"
  _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
fi

# Parse --upstream flag
UPSTREAM=""
if [[ "${1:-}" == "--upstream" ]]; then
  UPSTREAM="1"
  shift
fi

TITLE="${1:-}"
BODYFILE="${2:-}"

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

# Find the fork remote (first non-origin remote)
FORK_REMOTE=""
for r in $(git remote); do
  if [[ "$(echo "$r" | tr '[:upper:]' '[:lower:]')" != "origin" ]]; then
    FORK_REMOTE="$r"
    break
  fi
done
if [[ -z "$FORK_REMOTE" ]]; then
  echo "ERROR: No named remote found (only 'origin' exists)." >&2
  echo "  Name your remote after the org: git remote rename origin <orgname>" >&2
  exit 1
fi
FORK_URL=$(git remote get-url "$FORK_REMOTE" 2>/dev/null)

# Detect provider and load implementation
gp_detect_and_load "$FORK_URL" "$_ECO"
gp_check_cli

FORK_SLUG=$(gp_extract_slug "$FORK_URL")
FORK_ORG="${FORK_SLUG%%/*}"

if [[ -n "$UPSTREAM" ]]; then
  # Cross-fork PR: find the upstream (non-fork) remote
  UPSTREAM_REMOTE=""
  for remote in $(git remote); do
    if [[ "$remote" != "$FORK_REMOTE" ]]; then
      UPSTREAM_REMOTE="$remote"
      break
    fi
  done
  if [[ -z "$UPSTREAM_REMOTE" ]]; then
    echo "ERROR: No upstream remote found (only '$FORK_REMOTE' exists)." >&2
    exit 1
  fi
  UPSTREAM_URL=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null)
  UPSTREAM_SLUG=$(gp_extract_slug "$UPSTREAM_URL")

  UPSTREAM_DEFAULT=$(gp_default_branch "$UPSTREAM_SLUG")

  echo "Opening cross-fork PR/MR: $FORK_SLUG:$BRANCH → $UPSTREAM_SLUG:$UPSTREAM_DEFAULT"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gp_create_pr \
    --repo "$UPSTREAM_SLUG" \
    --base "$UPSTREAM_DEFAULT" \
    --head "$BRANCH" \
    --fork-org "$FORK_ORG" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
else
  echo "Opening PR/MR for $FORK_SLUG/$BRANCH → main"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gp_create_pr \
    --repo "$FORK_SLUG" \
    --base main \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
fi
