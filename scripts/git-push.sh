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
# Collect non-origin remotes, then decide:
#   1 remote  → use it (no ambiguity)
#   N remotes → use GIT_PUSH_REMOTE if it matches one (case-insensitive)
#   N remotes, no match → fail with clear error
REMOTES=()
for r in $(git remote); do
  if [[ "$(echo "$r" | tr '[:upper:]' '[:lower:]')" != "origin" ]]; then
    REMOTES+=("$r")
  fi
done

if [[ ${#REMOTES[@]} -eq 0 ]]; then
  echo "ERROR: No named remote found (only 'origin' exists)." >&2
  echo "  Name your remote after the org: git remote rename origin <orgname>" >&2
  exit 1
fi

REMOTE_NAME=""
if [[ ${#REMOTES[@]} -eq 1 ]]; then
  REMOTE_NAME="${REMOTES[0]}"
elif [[ -n "${GIT_PUSH_REMOTE:-}" ]]; then
  # Case-insensitive match against available remotes
  REMOTE_NAME=$(git remote | grep -i "^${GIT_PUSH_REMOTE}$" | head -1)
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$GIT_PUSH_REMOTE' (from identity.forkOrg)." >&2
    echo "  Available remotes: ${REMOTES[*]}" >&2
    echo "  Set identity.forkOrg in ecosystem.local.yaml or GIT_PUSH_REMOTE." >&2
    exit 1
  fi
else
  echo "ERROR: Multiple remotes found and no forkOrg configured to choose between them." >&2
  echo "  Available remotes: ${REMOTES[*]}" >&2
  echo "  Set identity.forkOrg in ecosystem.local.yaml or GIT_PUSH_REMOTE." >&2
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
