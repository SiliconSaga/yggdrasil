#!/usr/bin/env bash
# git-issue-edit.sh — update an existing issue's body, and its title when given
#
# Usage: git-issue-edit.sh COMPONENT_DIR REMOTE ISSUE_NUMBER BODYFILE [TITLE]
#
# Same reason as git-cr-edit.sh: substitution and the attribution check lived on the creation path only, so an edit through the raw provider CLI ran neither and failed silently, an unsubstituted placeholder being valid Markdown.
#
# Mirrors git-issue.sh's positional shape — it takes COMPONENT_DIR rather than running inside the component — instead of git-cr-edit.sh's flag-parsing shape.

set -euo pipefail

COMPONENT_DIR="${1:-}"
REMOTE="${2:-}"
ISSUE_NUMBER="${3:-}"
BODYFILE="${4:-}"
TITLE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"
source "$SCRIPT_DIR/ws-realm.sh"
# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"

if [[ -z "$COMPONENT_DIR" || -z "$ISSUE_NUMBER" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 COMPONENT_DIR [REMOTE] ISSUE_NUMBER BODYFILE [TITLE]" >&2
  exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: issue number must be numeric, got '$ISSUE_NUMBER'" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

ECO=$(ws_resolve_ecosystem)
AUTH_ECO=$(ws_resolve_local_ecosystem 2>/dev/null) || AUTH_ECO=""

# Attribution and placeholder resolution — the whole point of this script existing. See scripts/gdd-attribution.sh.
HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/issue.md" || exit 1
RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$HUMAN_ACCOUNT" "$GDD_HOME") || exit 1
trap 'rm -f "$RESOLVED_BODY" 2>/dev/null' EXIT
gdd_attribution_check_driver "$RESOLVED_BODY" "$HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$RESOLVED_BODY" || exit 1

# Plain read loop, not `mapfile`: that is a bash 4.0 builtin and macOS ships bash 3.2.57, where it does not exist. Same sweep as git-cr.sh and git-push.sh; this file arrived with #166 after the sweep was written, so it is caught here on the rebase.
_REMOTES=()
_remote_line=""
while IFS= read -r _remote_line || [[ -n "$_remote_line" ]]; do
  _REMOTES+=("$_remote_line")
done < <(cd "$COMPONENT_DIR" && git remote)
REMOTE_NAME=""
if [[ ${#_REMOTES[@]} -eq 0 ]]; then
  echo "ERROR: No remotes configured in $COMPONENT_DIR." >&2
  exit 1
elif [[ ${#_REMOTES[@]} -eq 1 ]]; then
  REMOTE_NAME="${_REMOTES[0]}"
elif [[ -n "$REMOTE" ]]; then
  REMOTE_NAME=$(cd "$COMPONENT_DIR" && git remote | grep -i "^${REMOTE}$" | head -1 || true)
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$REMOTE' found in $COMPONENT_DIR." >&2
    echo "  Available remotes: ${_REMOTES[*]}" >&2
    exit 1
  fi
else
  echo "ERROR: Multiple remotes in $COMPONENT_DIR — specify which one." >&2
  echo "  Available remotes: ${_REMOTES[*]}" >&2
  exit 1
fi

# Raw configured URL, not `git remote get-url` — see the same note in git-issue.sh and git-cr-remote.sh. Provider detection, token mapping and slug extraction are logical consumers; transport addresses the remote by name and still gets any insteadOf rewrite.
REMOTE_URL=$(cd "$COMPONENT_DIR" && git config --get-all "remote.$REMOTE_NAME.url" 2>/dev/null | head -n1) || true
if [[ -z "$REMOTE_URL" ]]; then
  echo "ERROR: remote '$REMOTE_NAME' has no configured URL." >&2
  exit 1
fi

gp_detect_and_load "$REMOTE_URL" "$ECO"
gp_set_token_for_url "$REMOTE_URL" "$AUTH_ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$REMOTE_URL")
if [[ -z "$TARGET_SLUG" || "$TARGET_SLUG" != */* ]]; then
  echo "ERROR: Could not resolve org/repo from remote URL: $REMOTE_URL" >&2
  exit 1
fi

echo "Updating issue #$ISSUE_NUMBER on $TARGET_SLUG (via remote '$REMOTE_NAME')"
if [[ -n "$TITLE" ]]; then
  echo "  Title: $TITLE"
fi
echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

if [[ -n "$TITLE" ]]; then
  gp_update_issue --repo "$TARGET_SLUG" --number "$ISSUE_NUMBER" --body-file "$RESOLVED_BODY" --title "$TITLE"
else
  gp_update_issue --repo "$TARGET_SLUG" --number "$ISSUE_NUMBER" --body-file "$RESOLVED_BODY"
fi

echo "✓ Issue updated: #$ISSUE_NUMBER on $TARGET_SLUG"
