#!/usr/bin/env bash
# setup-branch-protection.sh — configure main branch protection on all SiliconSaga repos
#
# Requires admin permission on each repo. Run with a token that has repo admin scope,
# or as the org owner via: source .env && ./scripts/setup-branch-protection.sh
#
# What this sets on main for each repo:
#   - Pull request required before merging (1 approval)
#   - Dismiss stale reviews when new commits are pushed
#   - No force pushes
#   - No branch deletion
#   - Admins are NOT exempt (enforce_admins: true) — use bypass sparingly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -z "${GH_TOKEN:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
  else
    echo "ERROR: GH_TOKEN not set and $ENV_FILE not found" >&2
    exit 1
  fi
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
    --field enforce_admins=true \
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
