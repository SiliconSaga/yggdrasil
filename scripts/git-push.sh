#!/usr/bin/env bash
# git-push.sh — push a branch to the siliconsaga remote
#
# Usage: git-push.sh [--force] [branch]
#   --force — force push (for rebased branches). Refuses to force-push main/master.
#   branch  — branch to push (default: current branch)
#
# Sources .env automatically. Run from any workspace repo directory.
#
# Example:
#   /Users/cervator/dev/git_ws/yggdrasil/scripts/git-push.sh
#   /Users/cervator/dev/git_ws/yggdrasil/scripts/git-push.sh feat/my-feature
#   /Users/cervator/dev/git_ws/yggdrasil/scripts/git-push.sh --force feat/my-feature

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

# Parse --force flag
FORCE=""
if [[ "${1:-}" == "--force" ]]; then
  FORCE="--force"
  shift
fi

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

# Find the SiliconSaga remote (case-insensitive)
REMOTE_NAME=$(git remote | grep -i '^siliconsaga$' | head -1)
if [[ -z "$REMOTE_NAME" ]]; then
  echo "ERROR: No 'siliconsaga' remote found (checked case-insensitive)." >&2
  echo "  Available remotes: $(git remote | tr '\n' ' ')" >&2
  exit 1
fi
REPO=$(git remote get-url "$REMOTE_NAME" 2>/dev/null | sed 's|.*/||; s|\.git$||')

# Safety: refuse to force-push main or master
if [[ -n "$FORCE" ]] && [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Refusing to force-push to $BRANCH. This is almost certainly a mistake." >&2
  exit 1
fi

# Push via explicit HTTPS URL to bypass any global url.insteadOf SSH rewrite
# (GitKraken sets url."git@github.com:".insteadOf=https://github.com/ in ~/.gitconfig,
#  which redirects all https:// remotes to SSH — the embedded-token URL avoids this.)
PUSH_URL="https://x-access-token:${GH_TOKEN}@github.com/SiliconSaga/${REPO}.git"

if [[ -n "$FORCE" ]]; then
  echo "Force pushing $REPO/$BRANCH → siliconsaga (HTTPS)"
  git push --force "$PUSH_URL" "$BRANCH"
else
  echo "Pushing $REPO/$BRANCH → siliconsaga (HTTPS)"
  git push "$PUSH_URL" "$BRANCH"
fi
