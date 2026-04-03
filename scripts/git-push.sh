#!/usr/bin/env bash
# git-push.sh — push a branch to a named remote
#
# Usage: git-push.sh [--force] [branch]
#   --force — force push (for rebased branches). Refuses to force-push main/master.
#   branch  — branch to push (default: current branch)
#
# Auth is handled by the system credential helper (credential.helper=manager
# on Windows, osxkeychain on macOS, or gh/glab auth). No token needed here.
#
# The target remote is detected by finding a non-origin remote whose name
# matches the org (case-insensitive). Override by setting GIT_PUSH_REMOTE.

set -euo pipefail

# Parse --force flag
FORCE=""
if [[ "${1:-}" == "--force" ]]; then
  FORCE="--force"
  shift
fi

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

# Find the push remote.
# If GIT_PUSH_REMOTE is set, use that. Otherwise, pick the first remote
# that isn't literally "origin" (our convention: remotes are named after orgs).
if [[ -n "${GIT_PUSH_REMOTE:-}" ]]; then
  # Case-insensitive match against available remotes
  REMOTE_NAME=$(git remote | grep -i "^${GIT_PUSH_REMOTE}$" | head -1)
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$GIT_PUSH_REMOTE' found." >&2
    echo "  Available remotes: $(git remote | tr '\n' ' ')" >&2
    exit 1
  fi
else
  REMOTE_NAME=""
  for r in $(git remote); do
    if [[ "$(echo "$r" | tr '[:upper:]' '[:lower:]')" != "origin" ]]; then
      REMOTE_NAME="$r"
      break
    fi
  done
fi

if [[ -z "$REMOTE_NAME" ]]; then
  echo "ERROR: No named remote found (only 'origin' exists)." >&2
  echo "  Name your remote after the org: git remote rename origin <orgname>" >&2
  echo "  Or set GIT_PUSH_REMOTE=<remote-name>." >&2
  echo "  Available remotes: $(git remote | tr '\n' ' ')" >&2
  exit 1
fi

REMOTE_URL=$(git remote get-url "$REMOTE_NAME" 2>/dev/null || echo "")
ORG_REPO=$(echo "$REMOTE_URL" | sed 's|.*[:/]\([^/]*/[^/]*\)$|\1|; s|\.git$||')

# Safety: refuse to force-push main or master
if [[ -n "$FORCE" ]] && [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Refusing to force-push to $BRANCH. This is almost certainly a mistake." >&2
  exit 1
fi

if [[ -n "$FORCE" ]]; then
  echo "Force pushing $BRANCH → $REMOTE_NAME ($ORG_REPO)"
  git push --force "$REMOTE_NAME" "$BRANCH"
else
  echo "Pushing $BRANCH → $REMOTE_NAME ($ORG_REPO)"
  git push "$REMOTE_NAME" "$BRANCH"
fi
