#!/usr/bin/env bash
# git-cr-edit.sh — update an existing change request's body, and its title when given
#
# Usage: git-cr-edit.sh [--remote REMOTE] [--upstream] [--title TITLE] CR_NUMBER BODYFILE
#
# Exists because editing a description through raw `gh pr edit --body-file` runs neither the placeholder substitution nor the attribution check: both lived on the creation path only. yggdrasil#158 published a body reading "driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" for exactly that reason, and failed silently, because an unsubstituted placeholder is valid Markdown and nothing looks at a body after it is published.
#
# Deliberately does NOT run the creation preflights. The stale-base check, the source-branch verification and the changelog reminder are all statements about a branch being proposed for review; none is meaningful when only a description changes. The branch-is-not-main guard would be worse than useless here — it would refuse to fix a typo in a CR body because of which directory you happen to be standing in.
#
# Run from the repo the change request belongs to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"
# shellcheck source=git-cr-remote.sh
source "$SCRIPT_DIR/git-cr-remote.sh"

_ECO=""
_AUTH_ECO=""
if [[ -f "$SCRIPT_DIR/ws-realm.sh" ]]; then
  source "$SCRIPT_DIR/ws-realm.sh"
  _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
  _AUTH_ECO=$(ws_resolve_local_ecosystem 2>/dev/null) || _AUTH_ECO=""
fi

# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"

UPSTREAM=""
CR_REMOTE="${GIT_CR_REMOTE:-}"
TITLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) UPSTREAM="1"; shift ;;
    --remote)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "ERROR: --remote requires a git remote name" >&2
        exit 1
      fi
      CR_REMOTE="$2"; shift 2 ;;
    --remote=*)
      CR_REMOTE="${1#--remote=}"
      if [[ -z "$CR_REMOTE" || "$CR_REMOTE" == -* ]]; then
        echo "ERROR: --remote requires a git remote name" >&2
        exit 1
      fi
      shift ;;
    --title)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --title requires a title" >&2
        exit 1
      fi
      TITLE="$2"; shift 2 ;;
    --title=*)
      TITLE="${1#--title=}"
      if [[ -z "$TITLE" ]]; then
        echo "ERROR: --title requires a title" >&2
        exit 1
      fi
      shift ;;
    --) shift; break ;;
    -*) echo "ERROR: unknown option '$1'" >&2; exit 1 ;;
    *) break ;;
  esac
done

CR_NUMBER="${1:-}"
BODYFILE="${2:-}"

if [[ -z "$CR_NUMBER" || -z "$BODYFILE" || $# -ne 2 ]]; then
  echo "Usage: $0 [--remote REMOTE] [--upstream] [--title TITLE] CR_NUMBER BODYFILE" >&2
  echo "  See templates/change.md for a ready-to-copy bodyfile template." >&2
  exit 1
fi

if [[ ! "$CR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: CR number must be numeric, got '$CR_NUMBER'" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Attribution and placeholder resolution — the whole point of this script existing. See scripts/gdd-attribution.sh.
_HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
_GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/change.md" || exit 1
_RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$_HUMAN_ACCOUNT" "$_GDD_HOME") || exit 1
trap 'rm -f "$_RESOLVED_BODY" 2>/dev/null' EXIT
gdd_attribution_check_driver "$_RESOLVED_BODY" "$_HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$_RESOLVED_BODY" || exit 1

gdd_cr_resolve_fork_remote "$CR_REMOTE" "$_ECO" || exit 1

TARGET_URL="$FORK_URL"
TARGET_LABEL="$FORK_REMOTE"
if [[ -n "$UPSTREAM" ]]; then
  UPSTREAM_REMOTES=()
  for remote in "${GDD_CR_ALL_REMOTES[@]}"; do
    if [[ "$remote" != "$FORK_REMOTE" ]]; then
      UPSTREAM_REMOTES+=("$remote")
    fi
  done
  if [[ ${#UPSTREAM_REMOTES[@]} -eq 0 ]]; then
    echo "ERROR: No upstream remote found (only '$FORK_REMOTE' exists)." >&2
    exit 1
  elif [[ ${#UPSTREAM_REMOTES[@]} -gt 1 ]]; then
    _DEFAULT_UPSTREAM=""
    if [[ -n "$_ECO" ]]; then
      _DEFAULT_UPSTREAM=$(yq '.defaults.upstreamRemote // ""' "$_ECO" 2>/dev/null) || _DEFAULT_UPSTREAM=""
      [[ "$_DEFAULT_UPSTREAM" == "null" ]] && _DEFAULT_UPSTREAM=""
    fi
    if [[ -n "$_DEFAULT_UPSTREAM" ]] && printf '%s\n' "${UPSTREAM_REMOTES[@]}" | grep -qx "$_DEFAULT_UPSTREAM"; then
      UPSTREAM_REMOTES=("$_DEFAULT_UPSTREAM")
    else
      echo "ERROR: Multiple upstream remotes found: ${UPSTREAM_REMOTES[*]}" >&2
      echo "  Set defaults.upstreamRemote in your realm or ecosystem.local.yaml." >&2
      exit 1
    fi
  fi
  TARGET_LABEL="${UPSTREAM_REMOTES[0]}"
  # Raw config read for the same reason as FORK_URL in git-cr-remote.sh: every consumer here is logical, and transport addresses the remote by name.
  TARGET_URL=$(git config --get-all "remote.$TARGET_LABEL.url" 2>/dev/null | head -n1) || true
  if [[ -z "$TARGET_URL" ]]; then
    echo "ERROR: remote '$TARGET_LABEL' has no configured URL." >&2
    exit 1
  fi
fi

gp_detect_and_load "$TARGET_URL" "$_ECO"
gp_set_token_for_url "$TARGET_URL" "$_AUTH_ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$TARGET_URL")

echo "Updating CR #$CR_NUMBER on $TARGET_SLUG (via remote '$TARGET_LABEL')"
if [[ -n "$TITLE" ]]; then
  echo "  Title: $TITLE"
fi
echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

if [[ -n "$TITLE" ]]; then
  gp_update_pr --repo "$TARGET_SLUG" --number "$CR_NUMBER" --body-file "$_RESOLVED_BODY" --title "$TITLE"
else
  gp_update_pr --repo "$TARGET_SLUG" --number "$CR_NUMBER" --body-file "$_RESOLVED_BODY"
fi

echo "✓ CR updated: #$CR_NUMBER on $TARGET_SLUG"
