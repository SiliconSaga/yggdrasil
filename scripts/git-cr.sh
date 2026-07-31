#!/usr/bin/env bash
# git-cr.sh — open a change request (PR/MR) from the current branch
#
# Usage: git-cr.sh [--remote REMOTE] [--source-branch BRANCH] [--upstream] [--stale-base-ok] TITLE BODYFILE
#   --remote REMOTE — use this git remote as the fork/head remote.
#                     Defaults to GIT_CR_REMOTE, then identity.forkRemote.
#   --source-branch BRANCH — submit this local, remote-tracked branch instead
#                            of deriving the source branch from current HEAD.
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
_AUTH_ECO=""
if [[ -f "$SCRIPT_DIR/ws-realm.sh" ]]; then
  source "$SCRIPT_DIR/ws-realm.sh"
  _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
  _AUTH_ECO=$(ws_resolve_local_ecosystem 2>/dev/null) || _AUTH_ECO=""
fi

# Wrapper around gp_create_pr that captures the URL output and re-emits
# it with a prominent "CR ready:" line. The URL was easy to lose in the
# preceding "Opening CR..." chatter — this surfaces it as a dedicated
# line at the end so the operator (or a follow-up `ws review` call)
# can grab it at a glance.
_create_pr_with_prominent_url() {
  local rc=0
  local output
  # `output=$(...)` buffers stdout until gp_create_pr finishes
  # — the user sees nothing during the call, then the whole
  # captured text at once. That's a small UX regression vs
  # streaming, but the trade is letting us extract the URL
  # afterwards and emit a prominent line. Acceptable for a
  # CR-creation call that takes a couple of seconds; would
  # need a tee-style approach if it ever became long-running.
  output=$(gp_create_pr "$@") || rc=$?
  # Replay the captured output so existing downstream parsers /
  # log scrapers see the same text they would have seen without
  # the wrapper.
  printf '%s\n' "$output"
  if [[ $rc -eq 0 ]]; then
    # `grep -o ... | tail -1` returns nonzero if no match. Under
    # `set -euo pipefail`, that nonzero would propagate through the
    # pipe and fail the whole script — turning "PR succeeded but
    # output had no URL we recognized" into a false-positive
    # failure. The `|| true` neutralizes that; the `[[ -n "$url" ]]`
    # guard already skips the prominent line cleanly when no URL is
    # extracted.
    local url
    url=$(printf '%s\n' "$output" | grep -oE 'https?://[^[:space:]]+' | tail -1 || true)
    if [[ -n "$url" ]]; then
      echo ""
      echo "✓ CR ready: $url"
    fi
  fi
  return $rc
}

# Parse flags
UPSTREAM=""
CR_REMOTE="${GIT_CR_REMOTE:-}"
SOURCE_BRANCH="${GIT_CR_SOURCE_BRANCH:-}"
STALE_BASE_OK="${GIT_CR_STALE_BASE_OK:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream)
      UPSTREAM="1"
      shift
      ;;
    --stale-base-ok)
      STALE_BASE_OK="1"
      shift
      ;;
    --remote)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "ERROR: --remote requires a git remote name" >&2
        exit 1
      fi
      CR_REMOTE="$2"
      shift 2
      ;;
    --remote=*)
      CR_REMOTE="${1#--remote=}"
      if [[ -z "$CR_REMOTE" || "$CR_REMOTE" == -* ]]; then
        echo "ERROR: --remote requires a git remote name" >&2
        exit 1
      fi
      shift
      ;;
    --source-branch)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "ERROR: --source-branch requires a branch name" >&2
        exit 1
      fi
      SOURCE_BRANCH="$2"
      shift 2
      ;;
    --source-branch=*)
      SOURCE_BRANCH="${1#--source-branch=}"
      if [[ -z "$SOURCE_BRANCH" || "$SOURCE_BRANCH" == -* ]]; then
        echo "ERROR: --source-branch requires a branch name" >&2
        exit 1
      fi
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "ERROR: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

TITLE="${1:-}"
BODYFILE="${2:-}"

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Ensure .crs/ clearinghouse exists
mkdir -p "$REPO_ROOT/.crs"

if [[ -z "$TITLE" || -z "$BODYFILE" || $# -ne 2 ]]; then
  echo "Usage: $0 [--remote REMOTE] [--source-branch BRANCH] [--upstream] [--stale-base-ok] TITLE BODYFILE" >&2
  echo "  See templates/change.md for a ready-to-copy bodyfile template. CR bodyfiles conventionally live in .crs/." >&2
  exit 1
fi

EXPLICIT_SOURCE_BRANCH=""
if [[ -n "$SOURCE_BRANCH" ]]; then
  if ! git check-ref-format --branch "$SOURCE_BRANCH" >/dev/null 2>&1; then
    echo "ERROR: invalid source branch '$SOURCE_BRANCH'." >&2
    exit 1
  fi
  if ! git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH"; then
    echo "ERROR: source branch '$SOURCE_BRANCH' does not exist locally." >&2
    exit 1
  fi
  BRANCH="$SOURCE_BRANCH"
  EXPLICIT_SOURCE_BRANCH="1"
else
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
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
# Explicit override: match it. Single remote: use it. Multiple: match forkRemote. No match: fail.
mapfile -t _ALL_REMOTES < <(git remote)

FORK_REMOTE=""
if [[ -n "$CR_REMOTE" ]]; then
  for _r in "${_ALL_REMOTES[@]}"; do
    if [[ "${_r,,}" == "${CR_REMOTE,,}" ]]; then
      FORK_REMOTE="$_r"
      break
    fi
  done
  if [[ -z "$FORK_REMOTE" ]]; then
    echo "ERROR: No remote matching '$CR_REMOTE' (from --remote/GIT_CR_REMOTE)." >&2
    echo "  Available remotes: ${_ALL_REMOTES[*]:-(none)}" >&2
    exit 1
  fi
elif [[ ${#_ALL_REMOTES[@]} -eq 1 ]]; then
  FORK_REMOTE="${_ALL_REMOTES[0]}"
elif [[ -n "$_ECO" ]]; then
  _FORK_REMOTE=$(yq '.identity.forkRemote // ""' "$_ECO" 2>/dev/null)
  [[ "$_FORK_REMOTE" == "null" ]] && _FORK_REMOTE=""
  if [[ -n "$_FORK_REMOTE" ]]; then
    for _r in "${_ALL_REMOTES[@]}"; do
      if [[ "${_r,,}" == "${_FORK_REMOTE,,}" ]]; then
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
    echo "  Set identity.forkRemote in ecosystem.local.yaml." >&2
  fi
  exit 1
fi
# Read the remote's RAW configured URL (not `git remote get-url`, which
# applies url.insteadOf rewrites): every consumer below is logical — provider
# detection, token mapping, slug/host extraction — and should see the
# canonical URL the operator configured. Transport operations address the
# remote by NAME, so git still applies any insteadOf rewrite where it belongs.
# Take the FIRST url entry (--get-all | head): that is the URL git fetches
# from on a multi-URL remote, while --get would return the LAST — letting
# provider detection disagree with the remote git actually talks to.
FORK_URL=$(git config --get-all "remote.$FORK_REMOTE.url" 2>/dev/null | head -n1) || true
if [[ -z "$FORK_URL" ]]; then
  echo "ERROR: remote '$FORK_REMOTE' has no configured URL." >&2
  exit 1
fi

if [[ -n "$EXPLICIT_SOURCE_BRANCH" ]]; then
  LOCAL_BRANCH_TIP=$(git rev-parse "refs/heads/$BRANCH")
  # Live-verify the selected branch against the remote it will be reviewed
  # from. Comparing against the last-fetched tracking ref is not enough — a
  # stale fetch could equal the local tip while the real remote branch has
  # moved, opening a review for code other than what the operator selected.
  # Auth-env injection mirrors git-push.sh so private forks resolve without
  # a credential-helper prompt.
  declare -a GIT_AUTH_ENV=()
  GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
  git_auth_env_for_url "$FORK_URL"
  # Let ls-remote's stderr flow through and branch on its exit code — 2 means
  # the remote answered and the ref is absent, anything else is a transport or
  # auth failure. Collapsing both into "push the branch" would send an operator
  # with an expired token off to debug the wrong problem.
  _LS_STATUS=0
  REMOTE_LS_OUTPUT=$(env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git ls-remote --exit-code "$FORK_REMOTE" "refs/heads/$BRANCH") || _LS_STATUS=$?
  if [[ "$_LS_STATUS" -eq 2 ]]; then
    echo "ERROR: source branch '$BRANCH' is not known on remote '$FORK_REMOTE'." >&2
    echo "  Push the branch to '$FORK_REMOTE' before creating the CR." >&2
    exit 1
  elif [[ "$_LS_STATUS" -ne 0 ]]; then
    echo "ERROR: could not verify '$BRANCH' against remote '$FORK_REMOTE' — git ls-remote failed (see above); check connectivity and auth." >&2
    exit 1
  fi
  REMOTE_BRANCH_TIP="${REMOTE_LS_OUTPUT%%[[:space:]]*}"
  if [[ "$LOCAL_BRANCH_TIP" != "$REMOTE_BRANCH_TIP" ]]; then
    echo "ERROR: source branch '$BRANCH' does not match remote '$FORK_REMOTE'." >&2
    echo "  Push the local branch or fetch and reconcile the remote branch before creating the CR." >&2
    exit 1
  fi
fi

# Stale-base preflight. With multiple contributors, the target branch's tip
# routinely moves between branching and CR time — the bots then review a
# stale diff and conflicts surface only after the CR opens. Verify the live
# base tip is contained in the source branch before creating; a moved base
# fails with a rebase pointer. --stale-base-ok (or GIT_CR_STALE_BASE_OK=1)
# skips the check for deliberate cases like stacked CRs. Same exit-code
# discipline as the source-branch verification above: ls-remote exit 2 =
# ref absent (let CR creation surface the provider's own error), other
# nonzero = transport/auth failure.
check_base_branch_fresh() {
  local remote="$1" remote_url="$2" base_branch="$3"
  [[ "$STALE_BASE_OK" == "1" ]] && return 0
  declare -a GIT_AUTH_ENV=()
  local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
  git_auth_env_for_url "$remote_url"
  local _bs=0 _out _tip
  _out=$(env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git ls-remote --exit-code "$remote" "refs/heads/$base_branch") || _bs=$?
  if [[ "$_bs" -eq 2 ]]; then
    return 0
  elif [[ "$_bs" -ne 0 ]]; then
    echo "ERROR: could not verify target branch '$base_branch' on '$remote' — git ls-remote failed (see above); check connectivity and auth." >&2
    exit 1
  fi
  _tip="${_out%%[[:space:]]*}"
  if ! git cat-file -e "${_tip}^{commit}" 2>/dev/null; then
    env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git fetch --quiet "$remote" "refs/heads/$base_branch" || {
      echo "ERROR: could not fetch target branch '$base_branch' from '$remote' for the stale-base check." >&2
      exit 1
    }
  fi
  if ! git merge-base --is-ancestor "$_tip" "refs/heads/$BRANCH"; then
    echo "ERROR: target branch '$base_branch' on '$remote' has moved — tip ${_tip:0:12} is not contained in '$BRANCH'." >&2
    echo "  Rebase first (git fetch $remote && git rebase $remote/$base_branch, or ws pull), re-push, then re-run ws cr." >&2
    echo "  Submitting against the moved base deliberately (e.g. a stacked CR)? Re-run with --stale-base-ok." >&2
    exit 1
  fi
}

# Detect provider and load implementation; set token before auth check
gp_detect_and_load "$FORK_URL" "$_ECO"
gp_set_token_for_url "$FORK_URL" "$_AUTH_ECO"
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
  # Raw config read for the same reason as FORK_URL above: every consumer is
  # logical (provider detect, host compare, token mapping) and must see the
  # canonical configured URL, not a url.insteadOf rewrite. Transport addresses
  # the remote by NAME, so git still applies rewrites where they belong.
  UPSTREAM_URL=$(git config --get-all "remote.$UPSTREAM_REMOTE.url" 2>/dev/null | head -n1) || true

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

  # Provider tokens are host-bound. The supported fork flow keeps both
  # remotes on one host; refusing a hand-wired cross-host layout is safer than
  # swapping to the upstream token while the provider CLI remains pinned to
  # the fork host.
  FORK_HOST=$(git_remote_host "$FORK_URL") || {
    echo "ERROR: Cannot determine host for fork remote '$FORK_REMOTE'." >&2
    exit 1
  }
  UPSTREAM_HOST=$(git_remote_host "$UPSTREAM_URL") || {
    echo "ERROR: Cannot determine host for upstream remote '$UPSTREAM_REMOTE'." >&2
    exit 1
  }
  if [[ "$UPSTREAM_HOST" != "$FORK_HOST" ]]; then
    echo "ERROR: Cross-host CR creation is not supported because provider credentials are host-bound." >&2
    echo "  Fork ($FORK_REMOTE): $FORK_HOST" >&2
    echo "  Upstream ($UPSTREAM_REMOTE): $UPSTREAM_HOST" >&2
    echo "  Use same-host fork/upstream remotes or create the CR manually with host-specific credentials." >&2
    exit 1
  fi

  UPSTREAM_SLUG=$(gp_extract_slug "$UPSTREAM_URL")

  # Reporter token needed to read upstream default branch
  gp_set_token_for_url "$UPSTREAM_URL" "$_AUTH_ECO"
  UPSTREAM_DEFAULT=$(gp_default_branch "$UPSTREAM_SLUG")

  check_base_branch_fresh "$UPSTREAM_REMOTE" "$UPSTREAM_URL" "$UPSTREAM_DEFAULT"

  echo "Opening cross-fork CR: $FORK_SLUG:$BRANCH → $UPSTREAM_SLUG:$UPSTREAM_DEFAULT"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  # glab ≥1.65 with --head POSTs to the fork project — switch to fork write token
  gp_set_token_for_url "$FORK_URL" "$_AUTH_ECO"

  _create_pr_with_prominent_url \
    --repo "$UPSTREAM_SLUG" \
    --base "$UPSTREAM_DEFAULT" \
    --head "$BRANCH" \
    --fork-slug "$FORK_SLUG" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
else
  # Use the token appropriate for the fork target
  gp_set_token_for_url "$FORK_URL" "$_AUTH_ECO"

  DEFAULT_BRANCH=$(gp_default_branch "$FORK_SLUG")

  check_base_branch_fresh "$FORK_REMOTE" "$FORK_URL" "$DEFAULT_BRANCH"

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
