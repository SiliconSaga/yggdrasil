#!/usr/bin/env bash
# git-push.sh — push a branch to the siliconsaga remote
#
# Usage: git-push.sh [branch]
#   branch — branch to push (default: current branch)
#
# Sources .env automatically. Run from any workspace repo directory.
#
# Example:
#   /Users/cervator/dev/git_ws/yggdrasil/scripts/git-push.sh
#   /Users/cervator/dev/git_ws/yggdrasil/scripts/git-push.sh feat/my-feature

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

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
REPO=$(git remote get-url siliconsaga 2>/dev/null | sed 's|.*/||; s|\.git$||')

# Push via explicit HTTPS URL to bypass any global url.insteadOf SSH rewrite
# (GitKraken sets url."git@github.com:".insteadOf=https://github.com/ in ~/.gitconfig,
#  which redirects all https:// remotes to SSH — the embedded-token URL avoids this.)
PUSH_URL="https://x-access-token:${GH_TOKEN}@github.com/SiliconSaga/${REPO}.git"

echo "Pushing $REPO/$BRANCH → siliconsaga (HTTPS)"
git push "$PUSH_URL" "$BRANCH"
