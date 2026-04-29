#!/usr/bin/env bash
# git-cr.sh — open a change request (PR/MR) from the current branch
#
# Usage: git-cr.sh [--upstream] TITLE BODYFILE
#   --upstream — target the upstream (non-fork) remote instead of the fork.
#                Creates a cross-fork CR: fork:branch → upstream:base.
#   TITLE     — CR title
#   BODYFILE  — path to markdown file containing the body
#
# Without --upstream, targets the fork remote using its default branch (via gp_default_branch).
# With --upstream, auto-detects the upstream remote and targets its default branch.
#
# Draft files live in .crs/ (gitignored, auto-created).
# Copy templates/change.md to .crs/<descriptive-name>.md to start a draft.
#
# Uses git-provider.sh for provider-agnostic CR creation.
# Run from the repo the branch belongs to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Source provider dispatcher
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Try to load ecosystem config for provider detection (optional — may not exist)
_ECO=""
if [[ -f "$SCRIPT_DIR/ws-realm.sh" ]]; then
  source "$SCRIPT_DIR/ws-realm.sh"
  _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
fi

# Wrapper around gp_create_pr that captures the URL output and re-emits
# it with a prominent "CR ready:" line. The URL was easy to lose in the
# preceding "Opening CR..." chatter — this surfaces it as a dedicated
# line at the end so the operator (or a follow-up `ws review` call)
# can grab it at a glance.
_create_pr_with_prominent_url() {
  local rc=0
  local output
  output=$(gp_create_pr "$@") || rc=$?
  # Stream the captured output unchanged so existing downstream
  # parsers / log scrapers keep working.
  printf '%s\n' "$output"
  if [[ $rc -eq 0 ]]; then
    local url
    url=$(printf '%s\n' "$output" | grep -oE 'https?://[^[:space:]]+' | tail -1)
    if [[ -n "$url" ]]; then
      echo ""
      echo "✓ CR ready: $url"
    fi
  fi
  return $rc
}

# Parse --upstream flag
UPSTREAM=""
if [[ "${1:-}" == "--upstream" ]]; then
  UPSTREAM="1"
  shift
fi

TITLE="${1:-}"
BODYFILE="${2:-}"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Ensure .crs/ clearinghouse exists
mkdir -p "$REPO_ROOT/.crs"

if [[ -z "$TITLE" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 [--upstream] TITLE BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Resolve @HUMAN_ACCOUNT, @GDD_HOME and enforce AI attribution line
_HUMAN_ACCOUNT=""
_GDD_HOME="https://siliconsaga.github.io/yggdrasil/gdd/"
if [[ -n "$_ECO" ]]; then
  _HUMAN_ACCOUNT=$(yq '.identity.human_account // ""' "$_ECO" 2>/dev/null)
  [[ "$_HUMAN_ACCOUNT" == "null" ]] && _HUMAN_ACCOUNT=""
  _GDD_HOME_RAW=$(yq '.defaults.gddHome // ""' "$_ECO" 2>/dev/null)
  [[ -n "$_GDD_HOME_RAW" && "$_GDD_HOME_RAW" != "null" ]] && _GDD_HOME="$_GDD_HOME_RAW"
fi
if [[ -z "$_HUMAN_ACCOUNT" ]]; then
  echo "ERROR: identity.human_account not set in ecosystem config." >&2
  echo "  Set it in ecosystem.local.yaml (see ecosystem.local.yaml.example)." >&2
  exit 1
fi
if ! head -n 1 "$BODYFILE" | grep -q '^> \*\*AI-assisted change proposal\.\*\*'; then
  echo "ERROR: body file is missing the AI attribution line." >&2
  echo "  First line must contain: > **AI-assisted change proposal.**" >&2
  exit 1
fi
_RESOLVED_BODY=$(mktemp)
trap 'rm -f "$_RESOLVED_BODY" 2>/dev/null' EXIT
_ESC_HUMAN=$(printf '%s' "$_HUMAN_ACCOUNT" | sed 's/[&|\\]/\\&/g')
_ESC_GDD_HOME=$(printf '%s' "$_GDD_HOME" | sed 's/[&|\\]/\\&/g')
sed -e "s|@HUMAN_ACCOUNT|@${_ESC_HUMAN}|g" \
    -e "s|@GDD_HOME|${_ESC_GDD_HOME}|g" \
    "$BODYFILE" > "$_RESOLVED_BODY"
BODYFILE="$_RESOLVED_BODY"

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || "$BRANCH" == "develop" ]]; then
  echo "ERROR: current branch is '$BRANCH' — check out a topic branch first" >&2
  exit 1
fi

# Find the fork remote.
# Single remote: use it. Multiple: match forkOrg. No match: fail.
mapfile -t _ALL_REMOTES < <(git remote)

FORK_REMOTE=""
if [[ ${#_ALL_REMOTES[@]} -eq 1 ]]; then
  FORK_REMOTE="${_ALL_REMOTES[0]}"
elif [[ -n "$_ECO" ]]; then
  _FORK_ORG=$(yq '.identity.forkOrg // ""' "$_ECO" 2>/dev/null)
  [[ "$_FORK_ORG" == "null" ]] && _FORK_ORG=""
  if [[ -n "$_FORK_ORG" ]]; then
    for _r in "${_ALL_REMOTES[@]}"; do
      if [[ "${_r,,}" == "${_FORK_ORG,,}" ]]; then
        FORK_REMOTE="$_r"
        break
      fi
    done
  fi
fi
if [[ -z "$FORK_REMOTE" ]]; then
  if [[ ${#_ALL_REMOTES[@]} -eq 0 ]]; then
    echo "ERROR: No remotes configured." >&2
  else
    echo "ERROR: Multiple remotes found — cannot determine fork remote." >&2
    echo "  Available remotes: ${_ALL_REMOTES[*]}" >&2
    echo "  Set identity.forkOrg in ecosystem.local.yaml." >&2
  fi
  exit 1
fi
FORK_URL=$(git remote get-url "$FORK_REMOTE" 2>/dev/null)

# Detect provider and load implementation; set token before auth check
gp_detect_and_load "$FORK_URL" "$_ECO"
gp_set_token_for_url "$FORK_URL" "$_ECO"
gp_check_cli

FORK_SLUG=$(gp_extract_slug "$FORK_URL")

if [[ -n "$UPSTREAM" ]]; then
  # Cross-fork CR: find the upstream (non-fork) remote
  UPSTREAM_REMOTES=()
  for remote in "${_ALL_REMOTES[@]}"; do
    if [[ "$remote" != "$FORK_REMOTE" ]]; then
      UPSTREAM_REMOTES+=("$remote")
    fi
  done
  if [[ ${#UPSTREAM_REMOTES[@]} -eq 0 ]]; then
    echo "ERROR: No upstream remote found (only '$FORK_REMOTE' exists)." >&2
    exit 1
  elif [[ ${#UPSTREAM_REMOTES[@]} -gt 1 ]]; then
    # Multiple candidates — use defaults.upstreamRemote from ecosystem config as tiebreaker
    _DEFAULT_UPSTREAM=""
    if [[ -n "$_ECO" ]]; then
      _DEFAULT_UPSTREAM=$(yq '.defaults.upstreamRemote // ""' "$_ECO" 2>/dev/null)
      [[ "$_DEFAULT_UPSTREAM" == "null" ]] && _DEFAULT_UPSTREAM=""
    fi
    if [[ -n "$_DEFAULT_UPSTREAM" ]] && printf '%s\n' "${UPSTREAM_REMOTES[@]}" | grep -qx "$_DEFAULT_UPSTREAM"; then
      UPSTREAM_REMOTES=("$_DEFAULT_UPSTREAM")
    else
      echo "ERROR: Multiple upstream remotes found: ${UPSTREAM_REMOTES[*]}" >&2
      echo "  Set defaults.upstreamRemote in your realm or ecosystem.local.yaml." >&2
      [[ -n "$_DEFAULT_UPSTREAM" ]] && echo "  (configured value '$_DEFAULT_UPSTREAM' not found in remotes)" >&2
      exit 1
    fi
  fi
  UPSTREAM_REMOTE="${UPSTREAM_REMOTES[0]}"
  UPSTREAM_URL=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null)

  # Verify both remotes use the same provider
  UPSTREAM_PROVIDER=$(gp_detect "$UPSTREAM_URL" "$_ECO" 2>/dev/null) || {
    echo "ERROR: Cannot detect provider for upstream remote '$UPSTREAM_REMOTE'." >&2
    exit 1
  }
  FORK_PROVIDER=$(gp_detect "$FORK_URL" "$_ECO" 2>/dev/null) || FORK_PROVIDER=""
  if [[ "$UPSTREAM_PROVIDER" != "$FORK_PROVIDER" ]]; then
    echo "ERROR: Cross-provider CR creation is not supported." >&2
    echo "  Fork ($FORK_REMOTE): $FORK_PROVIDER" >&2
    echo "  Upstream ($UPSTREAM_REMOTE): $UPSTREAM_PROVIDER" >&2
    exit 1
  fi

  UPSTREAM_SLUG=$(gp_extract_slug "$UPSTREAM_URL")

  # Reporter token needed to read upstream default branch
  gp_set_token_for_url "$UPSTREAM_URL" "$_ECO"
  UPSTREAM_DEFAULT=$(gp_default_branch "$UPSTREAM_SLUG")

  echo "Opening cross-fork CR: $FORK_SLUG:$BRANCH → $UPSTREAM_SLUG:$UPSTREAM_DEFAULT"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  # glab ≥1.65 with --head POSTs to the fork project — switch to fork write token
  gp_set_token_for_url "$FORK_URL" "$_ECO"

  _create_pr_with_prominent_url \
    --repo "$UPSTREAM_SLUG" \
    --base "$UPSTREAM_DEFAULT" \
    --head "$BRANCH" \
    --fork-slug "$FORK_SLUG" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
else
  # Use the token appropriate for the fork target
  gp_set_token_for_url "$FORK_URL" "$_ECO"

  DEFAULT_BRANCH=$(gp_default_branch "$FORK_SLUG")

  echo "Opening CR for $FORK_SLUG/$BRANCH → $DEFAULT_BRANCH"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  _create_pr_with_prominent_url \
    --repo "$FORK_SLUG" \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
fi
