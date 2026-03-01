#!/usr/bin/env bash
# setup-branch-protection.sh — configure main branch protection on all SiliconSaga repos
#
# IMPORTANT: This is a one-time admin operation. The day-to-day agent PAT (.env)
# intentionally does NOT have Administration scope and will get a 403 here.
#
# Run this script as the org owner with a token that includes Administration scope:
#   GH_TOKEN=<admin-token> ./scripts/setup-branch-protection.sh
#
# Alternatively, set branch protection via GitHub web UI:
#   Settings → Branches → Add rule → Branch name: main
#   ✓ Require a pull request before merging (1 approval)
#   ✓ Dismiss stale pull request approvals when new commits are pushed
#   ✗ Do not allow bypassing the above settings  ← leave unchecked (admins can self-merge)
#   ✓ Allow force pushes → off
#   ✓ Allow deletions → off
#
# The web UI approach is recommended — it requires no additional token scope.
#
# What this sets on main for each repo:
#   - Pull request required before merging (1 approval)
#   - Dismiss stale reviews when new commits are pushed
#   - No force pushes
#   - No branch deletion
#   - Admins CAN bypass (enforce_admins: false) — allows self-merge until bot account is set up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "ERROR: GH_TOKEN not set." >&2
  echo "  This script requires an admin-scoped token, not the agent PAT." >&2
  echo "  Run: GH_TOKEN=<admin-token> $0" >&2
  echo "  Or use the GitHub web UI (see comments at top of this script)." >&2
  exit 1
fi

REPOS=(nordri nidavellir mimir yggdrasil vordu)
ORG="SiliconSaga"
BRANCH="main"

for REPO in "${REPOS[@]}"; do
  echo "Configuring $ORG/$REPO branch protection on '$BRANCH'..."

  gh api \
    --method PUT \
    "/repos/$ORG/$REPO/branches/$BRANCH/protection" \
    --field required_status_checks=null \
    --field enforce_admins=false \
    --field "required_pull_request_reviews[required_approving_review_count]=1" \
    --field "required_pull_request_reviews[dismiss_stale_reviews]=true" \
    --field restrictions=null \
    --field allow_force_pushes=false \
    --field allow_deletions=false \
    --silent \
    && echo "  ✓ $REPO" \
    || echo "  ✗ $REPO (failed — check token has admin scope)"

done

echo ""
echo "Done. Verify with: ./scripts/validate-agent-setup.sh"
