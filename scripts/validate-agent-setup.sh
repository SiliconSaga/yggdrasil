#!/usr/bin/env bash
# validate-agent-setup.sh — verify agent tooling prerequisites are correctly configured
#
# Run at the start of any session where agent will push code or file issues:
#   source .env && ./scripts/validate-agent-setup.sh
#
# Checks:
#   1. GH_TOKEN set and gh authenticated
#   2. git credential helper wired to gh (git push will work)
#   3. All five repos reachable with push permission
#   4. Branch protection enabled on main for each repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
PASS="✓"
FAIL="✗"
WARN="⚠"
ERRORS=0

check() {
  local label="$1"; shift
  if "$@" &>/dev/null; then
    echo "  $PASS $label"
  else
    echo "  $FAIL $label"
    ERRORS=$((ERRORS + 1))
  fi
}

# ── 1. GH_TOKEN and auth ─────────────────────────────────────────────────────
echo "[ gh auth ]"

if [[ -z "${GH_TOKEN:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo "  $WARN GH_TOKEN loaded from .env (not in environment — add 'source .env' to shell profile)"
  else
    echo "  $FAIL GH_TOKEN not set and $ENV_FILE not found"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  $PASS GH_TOKEN set in environment"
fi

check "gh authenticated" gh auth status

GH_USER=$(gh api /user --jq .login 2>/dev/null || echo "unknown")
echo "  $PASS authenticated as: $GH_USER"

# ── 2. git credential helper ─────────────────────────────────────────────────
echo ""
echo "[ git credentials ]"

if git config --list | grep -q 'credential.https://github.com.helper.*gh auth'; then
  echo "  $PASS gh credential helper configured for github.com"
else
  echo "  $FAIL gh credential helper not set — run: gh auth setup-git"
  ERRORS=$((ERRORS + 1))
fi

# ── 3. Repo access ───────────────────────────────────────────────────────────
echo ""
echo "[ repo access ]"

REPOS=(nordri nidavellir mimir yggdrasil vordu)
ORG="SiliconSaga"

for REPO in "${REPOS[@]}"; do
  PERMS=$(gh api "/repos/$ORG/$REPO" --jq '[.permissions.push, .permissions.pull] | @csv' 2>/dev/null || echo "false,false")
  CAN_PUSH=$(echo "$PERMS" | cut -d, -f1)
  if [[ "$CAN_PUSH" == "true" ]]; then
    echo "  $PASS $ORG/$REPO (push)"
  else
    echo "  $FAIL $ORG/$REPO (no push — check token scopes)"
    ERRORS=$((ERRORS + 1))
  fi
done

# ── 4. Branch protection ─────────────────────────────────────────────────────
echo ""
echo "[ branch protection ]"

for REPO in "${REPOS[@]}"; do
  PROTECTED=$(gh api "/repos/$ORG/$REPO/branches/main" --jq '.protected' 2>/dev/null || echo "false")
  if [[ "$PROTECTED" == "true" ]]; then
    echo "  $PASS $ORG/$REPO main is protected"
  else
    echo "  $WARN $ORG/$REPO main is NOT protected — run: ./scripts/setup-branch-protection.sh"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "All checks passed. Agent is ready to push and file issues."
else
  echo "$ERRORS check(s) failed. Resolve before pushing code."
  exit 1
fi
