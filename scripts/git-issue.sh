#!/usr/bin/env bash
# git-issue.sh — file an issue from a draft file
#
# Usage: ./scripts/git-issue.sh COMPONENT_DIR REMOTE TITLE LABEL BODYFILE
#   COMPONENT_DIR — path to the component git repo
#   REMOTE        — git remote name (e.g. 'SiliconSaga', 'MyGitLabGroup')
#                   The org/repo slug is resolved from the remote URL.
#   TITLE         — issue title
#   LABEL         — single label: bug | enhancement | documentation
#   BODYFILE      — path to the issue body markdown file
#
# The first line of the body file must contain an AI attribution line.
# The script reads identity.human_account from the merged ecosystem config
# and validates that the attribution references it.
#
# Draft files live in .issues/ (gitignored, created on first use).
# Copy templates/issue.md to .issues/<descriptive-name>.md to start a draft.
#
# Uses git-provider.sh for provider-agnostic issue creation.

set -euo pipefail

COMPONENT_DIR="${1:-}"
REMOTE="${2:-}"
TITLE="${3:-}"
LABEL="${4:-}"
BODYFILE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# Ensure clearinghouse directory exists
mkdir -p "$REPO_ROOT/.issues"


# Source provider dispatcher
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Source shared realm/merge functions for ecosystem config
source "$SCRIPT_DIR/ws-realm.sh"

# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"

# Validate arguments (REMOTE may be empty for auto-detection)
if [[ -z "$COMPONENT_DIR" || -z "$TITLE" || -z "$LABEL" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 COMPONENT_DIR [REMOTE] TITLE LABEL BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Attribution and placeholder resolution — see scripts/gdd-attribution.sh. ECO is still read here because gp_detect_and_load below needs it.
ECO=$(ws_resolve_ecosystem)
HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/issue.md" || exit 1
RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$HUMAN_ACCOUNT" "$GDD_HOME") || exit 1
trap 'rm -f "$RESOLVED_BODY" "$_RESOLVED_ECOSYSTEM" 2>/dev/null' EXIT
gdd_attribution_check_driver "$RESOLVED_BODY" "$HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$RESOLVED_BODY" || exit 1

# Resolve remote:
#   1 remote  → use it (any name)
#   N remotes + REMOTE hint → case-insensitive match
#   N remotes, no match → fail with clear error
# Plain read loop, not `mapfile`: that is a bash 4.0 builtin and macOS ships
# bash 3.2.57 (frozen in 2007 over the GPLv3 relicense), where it does not
# exist at all. See the matching note in git-push.sh.
_REMOTES=()
_line=""
while IFS= read -r _line || [[ -n "$_line" ]]; do
  _REMOTES+=("$_line")
done < <(cd "$COMPONENT_DIR" && git remote)

REMOTE_NAME=""
if [[ ${#_REMOTES[@]} -eq 0 ]]; then
  echo "ERROR: No remotes configured in $COMPONENT_DIR." >&2
  exit 1
elif [[ ${#_REMOTES[@]} -eq 1 ]]; then
  REMOTE_NAME="${_REMOTES[0]}"
elif [[ -n "$REMOTE" ]]; then
  # -F -x: same fix as git-issue-edit.sh. Review flagged only that file because only
  # it was in the diff, but this copy carried the identical regex injection — a
  # `$REMOTE` containing BRE metacharacters could select a different remote than the
  # one named, and here that chooses which repository the issue is filed against.
  REMOTE_NAME=$(cd "$COMPONENT_DIR" && git remote | LC_ALL=C grep -F -i -x -- "$REMOTE" | head -1 || true)
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$REMOTE' found in $COMPONENT_DIR." >&2
    echo "  Available remotes: ${_REMOTES[*]}" >&2
    exit 1
  fi
else
  echo "ERROR: Multiple remotes in $COMPONENT_DIR — specify which one." >&2
  echo "  Available remotes: ${_REMOTES[*]}" >&2
  echo "  Usage: ws issue <comp> <remote> <title> <label> <bodyfile>" >&2
  exit 1
fi
# Read the remote's RAW configured URL (not `git remote get-url`, which applies url.insteadOf rewrites): every consumer below is logical — provider detection, token mapping, slug extraction — and should see the canonical URL the operator configured. Transport operations address the remote by NAME, so git still applies any insteadOf rewrite where it belongs. Take the FIRST url entry, which is the one git fetches from on a multi-URL remote, while --get would return the LAST. Same reasoning, and the same spelling, as git-cr.sh; reading the rewritten URL here made provider detection fail on a repo where `ws cr` worked.
REMOTE_URL=$(cd "$COMPONENT_DIR" && git config --get-all "remote.$REMOTE_NAME.url" 2>/dev/null | head -n1) || true
if [[ -z "$REMOTE_URL" ]]; then
  echo "ERROR: remote '$REMOTE_NAME' has no configured URL." >&2
  exit 1
fi

# Detect and load provider
gp_detect_and_load "$REMOTE_URL" "$ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$REMOTE_URL")

if [[ -z "$TARGET_SLUG" || "$TARGET_SLUG" != */* ]]; then
  echo "ERROR: Could not resolve org/repo from remote URL: $REMOTE_URL" >&2
  exit 1
fi

# Show a summary before filing
echo "Filing issue to $TARGET_SLUG (via remote '$REMOTE_NAME'):"
echo "  Title : $TITLE"
echo "  Label : $LABEL"
echo "  Author: @$HUMAN_ACCOUNT (via agent)"
echo "  Body  : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

# Capture rather than stream so a disabled-issues refusal can be recognized and answered. Provider CLIs write their error body to STDOUT, not stderr, and exit non-zero — so judge by exit status and keep both streams.
_ISSUE_OUTPUT=$(mktemp)
_ISSUE_STATUS=0
gp_create_issue \
  --repo "$TARGET_SLUG" \
  --title "$TITLE" \
  --label "$LABEL" \
  --body-file "$RESOLVED_BODY" >"$_ISSUE_OUTPUT" 2>&1 || _ISSUE_STATUS=$?
cat "$_ISSUE_OUTPUT"

if [[ "$_ISSUE_STATUS" -ne 0 ]]; then
  # A fork starts with issues DISABLED on GitHub, and nobody chooses that — it is inherited silently by anything ws clone-fork produced. The bare provider error names the state and not the way out, and the improvised way out is to post the finding as a PR comment instead, which is how an unattributed comment reached a public repo. Naming the three real options here is the cheaper half of preventing that.
  if grep -qiE 'disabled issues|issues are disabled|issues.*disabled' "$_ISSUE_OUTPUT"; then
    echo "" >&2
    echo "Issues are disabled on $TARGET_SLUG, so there is nowhere to file this." >&2
    # The match is provider-agnostic because both providers phrase it similarly, but the remediation is not — pointing a GitLab user at GitHub's repo settings and a `has_issues` field they do not have is worse than saying nothing. Step 1 is therefore provider-specific; steps 2 and 3 hold either way.
    case "${_GP_LOADED_PROVIDER:-}" in
      github)
        echo "  A GitHub fork starts with issues disabled — a component from 'ws clone-fork' inherits that without anyone choosing it." >&2
        echo "  Three ways forward, in the order usually wanted:" >&2
        echo "    1. Enable issues on the fork: Settings → General → Features → Issues (or 'ws gh api -X PATCH repos/$TARGET_SLUG -F has_issues=true')." >&2
        ;;
      gitlab)
        echo "  Three ways forward, in the order usually wanted:" >&2
        echo "    1. Enable issues on the project: Settings → General → Visibility, project features, permissions → Issues." >&2
        ;;
      *)
        echo "  Three ways forward, in the order usually wanted:" >&2
        echo "    1. Enable issues on the project in its provider settings." >&2
        ;;
    esac
    echo "    2. File it upstream instead: 'ws issue <comp> <upstream-remote> \"<title>\" <label> <bodyfile>'." >&2
    echo "    3. Carry the finding in the change-request body, if it belongs to work already under review." >&2
    echo "  Don't post it as a bare provider comment — that path attaches no attribution." >&2
  fi
  rm -f "$_ISSUE_OUTPUT"
  exit "$_ISSUE_STATUS"
fi
rm -f "$_ISSUE_OUTPUT"
