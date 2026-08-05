#!/usr/bin/env bash
# validate-agent-setup.sh — verify agent tooling prerequisites are correctly configured
#
# Run at the start of any session where agent will push code or file issues:
#   ./scripts/validate-agent-setup.sh
#
# Checks:
#   1. GH_TOKEN set and gh authenticated
#   2. git credential helper wired to gh (git push will work)
#   3. All five repos reachable with push permission
#   4. Branch protection enabled on main for each repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -z "${GH_TOKEN:-}" && -f "$ENV_FILE" ]]; then
  ws_load_env "$ENV_FILE"
  ENV_FILE="$SCRIPT_DIR/../.env"
  GH_TOKEN_LOAD_SOURCE="dotenv"
else
  GH_TOKEN_LOAD_SOURCE="environment"
fi

# Prevent MSYS / Git Bash from converting /api-style paths to C:/… filesystem paths
export MSYS_NO_PATHCONV=1

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
  if [[ "$GH_TOKEN_LOAD_SOURCE" == "dotenv" ]]; then
    echo "  $FAIL GH_TOKEN missing or empty after loading $ENV_FILE"
  else
    echo "  $FAIL GH_TOKEN not set and $ENV_FILE not found"
  fi
  echo ""
  echo "Cannot continue without a nonempty GH_TOKEN. Set it in the environment or .env."
  exit 1
fi

if [[ "$GH_TOKEN_LOAD_SOURCE" == "dotenv" ]]; then
  echo "  $WARN GH_TOKEN loaded from .env as literal assignment data for this validation run"
else
  echo "  $PASS GH_TOKEN set in environment"
fi

if gh auth status &>/dev/null; then
  echo "  $PASS gh authenticated"
else
  echo "  $FAIL gh not authenticated (is GH_TOKEN valid?)"
  ERRORS=$((ERRORS + 1))
  echo ""
  echo "Cannot continue without a valid token. Fix auth first."
  exit 1
fi

gh_login=$(gh api /user --jq .login 2>/dev/null || echo "")
if [[ -n "$gh_login" ]]; then
  echo "  $PASS authenticated as: $gh_login"
else
  echo "  $FAIL could not retrieve GitHub username"
  echo "       Add 'Account (read)' permission to the token (fine-grained PATs need it)."
  ERRORS=$((ERRORS + 1))
  echo ""
  echo "Cannot continue without a confirmed identity. Fix auth first."
  exit 1
fi

# ── 2. git URL rewrite and credential helper ─────────────────────────────────
echo ""
echo "[ git credentials ]"

# GitKraken adds url."git@github.com:".insteadOf=https://github.com/ to ~/.gitconfig,
# rewriting all HTTPS remotes to SSH. Agent push scripts bypass this by using an
# explicit https://x-access-token:$GH_TOKEN@github.com/... URL which doesn't match
# the insteadOf prefix. GitKraken continues to use SSH via its own ssh-agent.
if git config --list | grep -q 'url.*insteadOf.*github'; then
  echo "  $WARN SSH insteadOf rewrite active (GitKraken). Agent scripts use token URL to bypass."
fi

if git config --list | grep -q 'credential.https://github.com.helper.*gh auth'; then
  echo "  $PASS gh credential helper configured for github.com (used by gh CLI, not git push)"
else
  echo "  $WARN gh credential helper not set — run: gh auth setup-git (optional; gh CLI may still work via GH_TOKEN)"
fi

# ── 3. Repo access ───────────────────────────────────────────────────────────
echo ""
echo "[ repo access ]"

REPOS=(nordri nidavellir mimir yggdrasil vordu)
ORG="SiliconSaga"

REPO_ERRORS=0
for REPO in "${REPOS[@]}"; do
  PERMS=$(gh api "/repos/$ORG/$REPO" --jq '[.permissions.push, .permissions.pull] | @csv' 2>/dev/null || echo "false,false")
  CAN_PUSH=$(echo "$PERMS" | cut -d, -f1)
  if [[ "$CAN_PUSH" == "true" ]]; then
    echo "  $PASS $ORG/$REPO (push)"
  else
    echo "  $FAIL $ORG/$REPO (no push — check token scopes)"
    ERRORS=$((ERRORS + 1))
    REPO_ERRORS=$((REPO_ERRORS + 1))
  fi
done

if [[ $REPO_ERRORS -eq ${#REPOS[@]} ]]; then
  echo ""
  echo "All repos inaccessible — token likely lacks Contents permission or is not scoped to $ORG."
  echo "Skipping branch protection checks."
  echo ""
  echo "$ERRORS check(s) failed. Resolve before pushing code."
  exit 1
fi

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
