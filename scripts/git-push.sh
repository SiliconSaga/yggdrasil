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
source "$SCRIPT_DIR/../.env"

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
REPO=$(git remote get-url siliconsaga 2>/dev/null | sed 's|.*/||; s|\.git$||')

echo "Pushing $REPO/$BRANCH → siliconsaga"
git push siliconsaga "$BRANCH"
