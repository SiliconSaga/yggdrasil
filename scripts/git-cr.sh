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

# Provider CLI output is untrusted terminal input. Keep ordinary text, tabs,
# and newlines intact while removing C0 controls that could ring bells, rewrite
# the current line, or introduce terminal escape sequences.
# Strip whole terminal control strings before deleting their control bytes, so
# a hidden payload cannot become ordinary text. The pre-iconv pass also treats
# standalone C1 bytes as controls while preserving strictly valid UTF-8.
_strip_terminal_sequences() {
  local recognize_raw_c1="${1:-false}"
  local state="normal" osc_string="false" char="" reprocess="false"
  local pending_index=0 pending_count=0 utf8_remaining=0 utf8_position=0 i=0
  local LC_ALL=C
  local esc=$'\033' bel=$'\007' c2=$'\302' backslash=$'\\'
  local e0=$'\340' ed=$'\355' f0=$'\360' f4=$'\364'
  local cont_min=$'\200' cont_max=$'\277'
  local utf8_second_min="$cont_min" utf8_second_max="$cont_max"
  local raw_dcs=$'\220' raw_sos=$'\230' raw_csi=$'\233' raw_st=$'\234'
  local raw_osc=$'\235' raw_pm=$'\236' raw_apc=$'\237'
  local -a pending=() utf8_chars=()

  while true; do
    if [[ "$pending_index" -lt "$pending_count" ]]; then
      char="${pending[$pending_index]}"
      pending_index=$((pending_index + 1))
    else
      pending=()
      pending_index=0
      pending_count=0
      char=""
      if IFS= read -r -n 1 char; then
        :
      elif [[ -n "$char" ]]; then
        :
      else
        break
      fi
      [[ -n "$char" ]] || char=$'\n'
    fi

    reprocess="true"
    while [[ "$reprocess" == "true" ]]; do
      reprocess="false"
      case "$state" in
        normal)
          if [[ "$recognize_raw_c1" == "true" && "$char" > "$c2" && "$char" < "$e0" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=1
            utf8_position=2
            utf8_second_min="$cont_min"
            utf8_second_max="$cont_max"
          elif [[ "$recognize_raw_c1" == "true" && "$char" == "$e0" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=2
            utf8_position=2
            utf8_second_min=$'\240'
            utf8_second_max="$cont_max"
          elif [[ "$recognize_raw_c1" == "true" && "$char" > "$e0" && "$char" < "$ed" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=2
            utf8_position=2
            utf8_second_min="$cont_min"
            utf8_second_max="$cont_max"
          elif [[ "$recognize_raw_c1" == "true" && "$char" == "$ed" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=2
            utf8_position=2
            utf8_second_min="$cont_min"
            utf8_second_max=$'\237'
          elif [[ "$recognize_raw_c1" == "true" && "$char" > "$ed" && "$char" < "$f0" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=2
            utf8_position=2
            utf8_second_min="$cont_min"
            utf8_second_max="$cont_max"
          elif [[ "$recognize_raw_c1" == "true" && "$char" == "$f0" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=3
            utf8_position=2
            utf8_second_min=$'\220'
            utf8_second_max="$cont_max"
          elif [[ "$recognize_raw_c1" == "true" && "$char" > "$f0" && "$char" < "$f4" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=3
            utf8_position=2
            utf8_second_min="$cont_min"
            utf8_second_max="$cont_max"
          elif [[ "$recognize_raw_c1" == "true" && "$char" == "$f4" ]]; then
            state="utf8"
            utf8_chars=("$char")
            utf8_remaining=3
            utf8_position=2
            utf8_second_min="$cont_min"
            utf8_second_max=$'\217'
          else
            case "$char" in
              "$esc") state="esc" ;;
              "$c2") state="c2" ;;
              "$raw_csi")
                if [[ "$recognize_raw_c1" == "true" ]]; then state="csi"; else printf '%s' "$char"; fi
                ;;
              "$raw_dcs"|"$raw_sos"|"$raw_osc"|"$raw_pm"|"$raw_apc")
                if [[ "$recognize_raw_c1" == "true" ]]; then
                  state="string"
                  if [[ "$char" == "$raw_osc" ]]; then osc_string="true"; else osc_string="false"; fi
                else
                  printf '%s' "$char"
                fi
                ;;
              "$raw_st")
                [[ "$recognize_raw_c1" == "true" ]] || printf '%s' "$char"
                ;;
              *) printf '%s' "$char" ;;
            esac
          fi
          ;;
        esc)
          state="normal"
          case "$char" in
            '[') state="csi" ;;
            ']') state="string"; osc_string="true" ;;
            'P'|'X'|'^'|'_') state="string"; osc_string="false" ;;
            "$backslash") ;;
            *) reprocess="true" ;;
          esac
          ;;
        c2)
          state="normal"
          case "$char" in
            "$raw_csi") state="csi" ;;
            "$raw_dcs"|"$raw_sos"|"$raw_osc"|"$raw_pm"|"$raw_apc")
              state="string"
              if [[ "$char" == "$raw_osc" ]]; then osc_string="true"; else osc_string="false"; fi
              ;;
            "$raw_st") ;;
            *) printf '%s' "$c2"; reprocess="true" ;;
          esac
          ;;
        csi)
          case "$char" in
            "$esc") state="esc" ;;
            "$c2") state="c2" ;;
            "$raw_csi")
              [[ "$recognize_raw_c1" == "true" ]] && state="csi"
              ;;
            "$raw_dcs"|"$raw_sos"|"$raw_osc"|"$raw_pm"|"$raw_apc")
              if [[ "$recognize_raw_c1" == "true" ]]; then
                state="string"
                if [[ "$char" == "$raw_osc" ]]; then osc_string="true"; else osc_string="false"; fi
              fi
              ;;
            "$raw_st")
              [[ "$recognize_raw_c1" == "true" ]] && state="normal"
              ;;
            [@-~]) state="normal" ;;
          esac
          ;;
        string)
          if [[ "$osc_string" == "true" && "$char" == "$bel" ]]; then
            state="normal"
          elif [[ "$char" == "$esc" ]]; then
            state="string_esc"
          elif [[ "$char" == "$c2" ]]; then
            state="string_c2"
          elif [[ "$recognize_raw_c1" == "true" && "$char" == "$raw_st" ]]; then
            state="normal"
          fi
          ;;
        string_esc)
          if [[ "$char" == "$backslash" ]]; then
            state="normal"
          else
            state="string"
            reprocess="true"
          fi
          ;;
        string_c2)
          if [[ "$char" == "$raw_st" ]]; then
            state="normal"
          else
            state="string"
            reprocess="true"
          fi
          ;;
        utf8)
          if { [[ "$utf8_position" -eq 2 ]] &&
                { [[ "$char" < "$utf8_second_min" ]] || [[ "$char" > "$utf8_second_max" ]]; }; } ||
              { [[ "$utf8_position" -ne 2 ]] &&
                { [[ "$char" < "$cont_min" ]] || [[ "$char" > "$cont_max" ]]; }; }; then
            pending=()
            pending_count=0
            for ((i = 1; i < ${#utf8_chars[@]}; i++)); do
              pending[$pending_count]="${utf8_chars[$i]}"
              pending_count=$((pending_count + 1))
            done
            pending[$pending_count]="$char"
            pending_count=$((pending_count + 1))
            pending_index=0
            state="normal"
          else
            utf8_chars[${#utf8_chars[@]}]="$char"
            utf8_remaining=$((utf8_remaining - 1))
            utf8_position=$((utf8_position + 1))
            if [[ "$utf8_remaining" -eq 0 ]]; then
              printf '%s' "${utf8_chars[@]}"
              state="normal"
            fi
          fi
          ;;
      esac
    done
  done
}

_sanitize_provider_text() {
  local provider_text="" sequence_stripped="" utf8_text=""
  provider_text="$(LC_ALL=C sed -e '')" || return 1
  sequence_stripped="$(printf '%s' "$provider_text" | _strip_terminal_sequences true)" || return 1
  # Invalid standalone bytes, including raw 8-bit C1 controls, are discarded
  # without corrupting valid UTF-8 text whose continuation bytes overlap that
  # range. C0 controls and DEL then drop byte-wise; UTF-8-encoded C1 controls
  # (U+0080–U+009F, e.g. the CSI code point U+009B) are the 0xC2 0x80–0x9F
  # sequences — strip those as pairs so legit multibyte text (whose
  # continuation bytes share the 0x80–0x9F range) is untouched.
  if command -v iconv >/dev/null 2>&1 &&
      utf8_text="$(printf '%s' "$sequence_stripped" | LC_ALL=C iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)"; then
    sequence_stripped="$(printf '%s' "$utf8_text" | _strip_terminal_sequences false)" || return 1
    printf '%s' "$sequence_stripped" |
      LC_ALL=C tr -d '\000-\010\013-\037\177' |
      LC_ALL=C sed -e $'s/\xc2[\x80-\x9f]//g'
    return
  fi

  # iconv is optional. Its conservative fallback keeps the provider's ASCII
  # URL and diagnostics while dropping every byte that could be malformed
  # UTF-8 or an 8-bit terminal control.
  printf '%s' "$sequence_stripped" | LC_ALL=C tr -d '\000-\010\013-\037\177-\377'
}

# Wrapper around gp_create_pr that captures the URL output and re-emits
# it with a prominent "CR ready:" line. The URL was easy to lose in the
# preceding "Opening CR..." chatter — this surfaces it as a dedicated
# line at the end so the operator (or a follow-up `ws review` call)
# can grab it at a glance.
_create_pr_with_prominent_url() (
  local fork_host="$1"
  shift
  local rc=0
  local capture_dir="" output="" error_output=""
  local sanitized_output="" sanitized_error=""
  capture_dir=$(mktemp -d "${TMPDIR:-/tmp}/ws-cr-provider-output.XXXXXX") || {
    echo "ERROR: Could not create a provider-output capture directory." >&2
    return 1
  }
  trap 'rm -rf "$capture_dir"' EXIT
  trap 'exit 1' HUP INT TERM

  # Buffer both streams until gp_create_pr finishes. That's a small UX
  # regression versus streaming, but it lets us neutralize untrusted provider
  # text and extract the URL. A tee-style sanitizer would be warranted if CR
  # creation ever became long-running.
  if gp_create_pr "$@" >"$capture_dir/stdout" 2>"$capture_dir/stderr"; then
    rc=0
  else
    rc=$?
  fi
  output=$(<"$capture_dir/stdout")
  error_output=$(<"$capture_dir/stderr")
  if ! sanitized_output=$(printf '%s' "$output" | _sanitize_provider_text); then
    echo "WARNING: Provider stdout could not be sanitized and was not replayed." >&2
    return $rc
  fi
  # Replay independently validated stdout before handling stderr. A failure in
  # one provider stream must not suppress safe diagnostics or the created URL
  # from the other stream.
  printf '%s\n' "$sanitized_output"
  if ! sanitized_error=$(printf '%s' "$error_output" | _sanitize_provider_text); then
    echo "WARNING: Provider stderr could not be sanitized and was not replayed." >&2
  elif [[ -n "$sanitized_error" ]]; then
    printf '%s\n' "$sanitized_error" >&2
  fi
  if [[ $rc -eq 0 ]]; then
    local authority candidate candidate_host url=""
    while IFS= read -r candidate; do
      candidate=$(printf '%s' "$candidate" | LC_ALL=C sed -e $'s/[])}.,;:!?\'">]*$//') || continue
      authority="${candidate#https://}"
      authority="${authority%%/*}"
      [[ -n "$authority" && "$authority" != *"@"* ]] || continue
      candidate_host=$(git_remote_host "$candidate" 2>/dev/null) || continue
      if [[ "$candidate_host" == "$fork_host" ]]; then
        url="$candidate"
      fi
    done < <(printf '%s\n' "$sanitized_output" | grep -oE 'https://[^[:space:]]+' || true)
    if [[ -n "$url" ]]; then
      echo ""
      echo "✓ CR ready: $url"
    fi
  fi
  return $rc
)

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
FORK_HOST=$(git_remote_host "$FORK_URL") || {
  echo "ERROR: Cannot determine host for fork remote '$FORK_REMOTE'." >&2
  exit 1
}

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
  REMOTE_LS_OUTPUT=$(git_auth_run git ls-remote --exit-code "$FORK_REMOTE" "refs/heads/$BRANCH") || _LS_STATUS=$?
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
# ref absent, other nonzero = transport/auth failure. Both fail closed before
# handing an ambiguous base to the provider.
# A change worth reviewing is usually a change worth recording, and the moment
# to write the entry is now — `[Unreleased]` only becomes the next release's
# section if something was accumulated into it. Reconstructing a release's worth
# of entries afterwards means re-reading merged PRs to recover what each change
# meant, with the reasoning already cold; the person opening the CR still knows.
#
# Advisory, never blocking: plenty of branches correctly have no entry (internal
# refactors, test-only work, typo fixes), and only repositories that actually
# keep a changelog are nudged at all. Read-only and best-effort — if the base
# ref cannot be resolved, say nothing rather than guess.
changelog_reminder() {
  local remote="$1" base_branch="$2" root="" base_ref=""
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ -f "$root/CHANGELOG.md" ]] || return 0
  if git rev-parse --verify --quiet "refs/remotes/$remote/$base_branch" >/dev/null 2>&1; then
    base_ref="$remote/$base_branch"
  elif git rev-parse --verify --quiet "refs/heads/$base_branch" >/dev/null 2>&1; then
    base_ref="$base_branch"
  else
    return 0
  fi
  [[ -z "$(git diff --name-only "$base_ref...HEAD" -- CHANGELOG.md 2>/dev/null)" ]] || return 0
  echo "NOTE: this branch does not touch CHANGELOG.md."
  echo "  If someone using this repo would notice the change, add an entry under [Unreleased]"
  echo "  before merging — entries left for release time have to be reconstructed from PRs."
  echo ""
}

check_base_branch_fresh() {
  local remote="$1" remote_url="$2" base_branch="$3"
  [[ "$STALE_BASE_OK" == "1" ]] && return 0
  declare -a GIT_AUTH_ENV=()
  local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
  git_auth_env_for_url "$remote_url"
  local _bs=0 _out _tip
  _out=$(git_auth_run git ls-remote --exit-code "$remote" "refs/heads/$base_branch") || _bs=$?
  if [[ "$_bs" -eq 2 ]]; then
    echo "ERROR: target branch '$base_branch' is not known on remote '$remote'." >&2
    echo "  Check the repository default branch and remote selection, then retry." >&2
    echo "  If the detected default branch is intentionally absent here, --stale-base-ok skips this preflight." >&2
    exit 1
  elif [[ "$_bs" -ne 0 ]]; then
    echo "ERROR: could not verify target branch '$base_branch' on '$remote' — git ls-remote failed (see above); check connectivity and auth." >&2
    exit 1
  fi
  _tip="${_out%%[[:space:]]*}"
  if ! git cat-file -e "${_tip}^{commit}" 2>/dev/null; then
    git_auth_run git fetch --quiet "$remote" "refs/heads/$base_branch" || {
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
  changelog_reminder "$UPSTREAM_REMOTE" "$UPSTREAM_DEFAULT"

  echo "Opening cross-fork CR: $FORK_SLUG:$BRANCH → $UPSTREAM_SLUG:$UPSTREAM_DEFAULT"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  # glab ≥1.65 with --head POSTs to the fork project — switch to fork write token
  gp_set_token_for_url "$FORK_URL" "$_AUTH_ECO"

  _create_pr_with_prominent_url "$FORK_HOST" \
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
  changelog_reminder "$FORK_REMOTE" "$DEFAULT_BRANCH"

  echo "Opening CR for $FORK_SLUG/$BRANCH → $DEFAULT_BRANCH"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  _create_pr_with_prominent_url "$FORK_HOST" \
    --repo "$FORK_SLUG" \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
fi
