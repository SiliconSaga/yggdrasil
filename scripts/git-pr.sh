#!/usr/bin/env bash
# git-pr.sh — open a pull/merge request from the current branch
#
# Usage: git-pr.sh [--upstream] TITLE BODYFILE
#   --upstream — target the upstream (non-fork) remote instead of the fork.
#                Creates a cross-fork PR/MR: fork:branch → upstream:base.
#   TITLE     — PR/MR title
#   BODYFILE  — path to markdown file containing the body
#
# Without --upstream, targets the fork remote using its default branch (via gp_default_branch).
# With --upstream, auto-detects the upstream remote and targets its default branch.
#
# Draft files live in .prs/ (gitignored, auto-created).
# Copy .agent/pr-template.md to .prs/<descriptive-name>.md to start a draft.
#
# Uses git-provider.sh for provider-agnostic PR/MR creation.
# Run from the repo the branch belongs to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env for provider tokens (GH_TOKEN, GITLAB_TOKEN, etc.)
_ENV_FILE="$SCRIPT_DIR/../.env"
[[ -f "$_ENV_FILE" ]] && source "$_ENV_FILE"

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

# Find the fork remote.
# Single remote: use it. Multiple: match forkOrg. No match: fail.
mapfile -t _ALL_REMOTES < <(git remote)

FORK_REMOTE=""
if [[ ${#_ALL_REMOTES[@]} -eq 1 ]]; then
  FORK_REMOTE="${_ALL_REMOTES[0]}"
elif [[ -n "$_ECO" ]]; then
  _FORK_ORG=$(yq '.identity.forkOrg // ""' "$_ECO" 2>/dev/null)
  [[ "$_FORK_ORG" == "null" ]] && _FORK_ORG=""
  if [[ -n "$_FORK_ORG" ]]; then
    for _r in "${_ALL_REMOTES[@]}"; do
      if [[ "${_r,,}" == "${_FORK_ORG,,}" ]]; then
        FORK_REMOTE="$_r"
        break
      fi
    done
  fi
fi
if [[ -z "$FORK_REMOTE" ]]; then
  if [[ ${#_ALL_REMOTES[@]} -eq 0 ]]; then
    echo "ERROR: No remotes configured." >&2
  else
    echo "ERROR: Multiple remotes found — cannot determine fork remote." >&2
    echo "  Available remotes: ${_ALL_REMOTES[*]}" >&2
    echo "  Set identity.forkOrg in ecosystem.local.yaml." >&2
  fi
  exit 1
fi
FORK_URL=$(git remote get-url "$FORK_REMOTE" 2>/dev/null)

# Detect provider and load implementation
gp_detect_and_load "$FORK_URL" "$_ECO"
gp_check_cli

FORK_SLUG=$(gp_extract_slug "$FORK_URL")

if [[ -n "$UPSTREAM" ]]; then
  # Cross-fork PR: find the upstream (non-fork) remote
  UPSTREAM_REMOTES=()
  for remote in "${_ALL_REMOTES[@]}"; do
    if [[ "$remote" != "$FORK_REMOTE" ]]; then
      UPSTREAM_REMOTES+=("$remote")
    fi
  done
  if [[ ${#UPSTREAM_REMOTES[@]} -eq 0 ]]; then
    echo "ERROR: No upstream remote found (only '$FORK_REMOTE' exists)." >&2
    exit 1
  elif [[ ${#UPSTREAM_REMOTES[@]} -gt 1 ]]; then
    echo "ERROR: Multiple upstream remotes found: ${UPSTREAM_REMOTES[*]}" >&2
    echo "  Cannot determine which to target. Remove extra remotes or specify explicitly." >&2
    exit 1
  fi
  UPSTREAM_REMOTE="${UPSTREAM_REMOTES[0]}"
  UPSTREAM_URL=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null)

  # Verify both remotes use the same provider
  UPSTREAM_PROVIDER=$(gp_detect "$UPSTREAM_URL" "$_ECO" 2>/dev/null) || {
    echo "ERROR: Cannot detect provider for upstream remote '$UPSTREAM_REMOTE'." >&2
    exit 1
  }
  FORK_PROVIDER=$(gp_detect "$FORK_URL" "$_ECO" 2>/dev/null) || FORK_PROVIDER=""
  if [[ "$UPSTREAM_PROVIDER" != "$FORK_PROVIDER" ]]; then
    echo "ERROR: Cross-provider PR/MR creation is not supported." >&2
    echo "  Fork ($FORK_REMOTE): $FORK_PROVIDER" >&2
    echo "  Upstream ($UPSTREAM_REMOTE): $UPSTREAM_PROVIDER" >&2
    exit 1
  fi

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
    --fork-slug "$FORK_SLUG" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
else
  DEFAULT_BRANCH=$(gp_default_branch "$FORK_SLUG")

  echo "Opening PR/MR for $FORK_SLUG/$BRANCH → $DEFAULT_BRANCH"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gp_create_pr \
    --repo "$FORK_SLUG" \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
fi
