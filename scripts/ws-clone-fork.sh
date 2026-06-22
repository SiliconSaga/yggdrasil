#!/usr/bin/env bash
# ws-clone-fork.sh — Fork-aware clone for ecosystem components
# ws:use-when fork-aware clone — ensures your personal fork exists then sets both remotes
#
# Usage: ws-clone-fork.sh <component>
#
# Ensures the user's personal fork of <component>'s upstream exists,
# clones it to components/<name>/, wires up both remotes (fork and
# upstream), and syncs the local + fork main with upstream.
#
# Idempotent: re-running on an already-prepared clone re-syncs main
# and exits cleanly. The agent can call this any time without
# tracking whether the fork exists or is current.
#
# Per-component override (in ecosystem config):
#   components:
#     <name>:
#       repo: <upstream-url>
#       forkRepo: <fork-url>          # explicit fork URL (overrides derivation)
#
# Realm-level convention (defaults.forkConvention):
#   nested  — insert forkOrg before the repo name (default; e.g.
#             acme/team/<repo> + forkOrg=alice → acme/team/alice/<repo>)
#   flat    — replace the first segment with forkOrg (GitHub-style:
#             org/<repo> + forkOrg=alice → alice/<repo>)

set -euo pipefail

# --- help short-circuit -----------------------------------------------------
for _arg in "$@"; do
    if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
        cat <<'HELP'
Usage: ws clone-fork <component>

Prepare a ready-to-work fork-based clone of <component>:

  1. Ensure the user's personal fork exists in identity.forkOrg (creates it
     via API if missing).
  2. Clone the fork (SSH) into components/<component>/, with origin renamed
     to <forkOrg>.
  3. Add the upstream as a second remote, named after the upstream group's
     leaf segment (or "upstream" if no leaf is sensible).
  4. Sync local main with upstream main. Push synced main back to the
     fork so future clones start clean. Force-pushes never happen — if
     histories diverge, the script stops and asks the user to resolve.

Token resolution is automatic: longest-prefix match on
defaults.gitTokens against the fork's namespace. .env is already
sourced by the ws dispatcher, so no manual sourcing is needed.

Transport defaults to HTTPS with the .env token injected per-process
(no SSH keys, no credential-manager prompt — same mechanism as ws push).
Set defaults.forkTransport: ssh to use key-based SSH instead. HTTPS
auto-falls-back to SSH when no .env token covers the host (e.g. a
self-hosted GitLab on a non-gitlab.* domain). Both the SSH and HTTPS
remote URLs come from the provider's project-details API response
(provider-agnostic — no host-specific port handling here).

Idempotent: re-runs on an already-prepared clone simply re-sync main.

Cross-group forks (e.g. forking from one GitLab group into a fork
home that lives in another group) hit a GitLab API limitation: the
fork API requires one caller identity with both Reporter+ on source
and Maintainer+ on destination, and bot users created by access
tokens cannot be cross-invited (Gitlab issue #355659). When the script
detects this case it emits a one-click fork-via-UI URL and exits with
code 2 ("manual step needed"). Re-run after user interaction.
HELP
        exit 0
    fi
done

if [[ $# -lt 1 ]]; then
    echo "Usage: ws clone-fork <component>" >&2
    echo "  Run 'ws clone-fork --help' for details." >&2
    exit 1
fi

COMPONENT="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

# --- dependency checks ------------------------------------------------------
for cmd in yq jq git glab; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required for ws clone-fork." >&2
        case "$cmd" in
            yq)   echo "  Install: https://github.com/mikefarah/yq" >&2 ;;
            jq)   echo "  Install: https://stedolan.github.io/jq/" >&2 ;;
            glab) echo "  Install: https://gitlab.com/gitlab-org/cli" >&2 ;;
        esac
        exit 1
    fi
done

ECO="$(ws_resolve_ecosystem)"

# Scratch file for capturing glab stderr. Workspace convention is
# .tmp/ over /tmp — Git Bash maps /tmp to an unpredictable location
# on Windows. .tmp/ is gitignored. Per-PID suffix avoids collisions;
# each `2>` redirect truncates, so the file is reused safely and the
# inline `rm -f` calls clean it up after each consumer.
ERR_TMP="$ROOT_DIR/.tmp/ws-clone-fork-err.$$"
mkdir -p "$ROOT_DIR/.tmp"

# --- read component config --------------------------------------------------
UPSTREAM_URL=$(COMP="$COMPONENT" yq '.components[strenv(COMP)].repo // ""' "$ECO" 2>/dev/null)
if [[ -z "$UPSTREAM_URL" || "$UPSTREAM_URL" == "null" ]]; then
    echo "ERROR: Component '$COMPONENT' is not declared in ecosystem config." >&2
    echo "  Add it to ecosystem.local.yaml under 'components:' first." >&2
    echo "  Example:" >&2
    echo "    components:" >&2
    echo "      $COMPONENT:" >&2
    echo "        tier: supporting" >&2
    echo "        repo: <upstream-git-url>" >&2
    exit 1
fi

# Per-component fork override (full URL)
FORK_REPO_OVERRIDE=$(COMP="$COMPONENT" yq '.components[strenv(COMP)].forkRepo // ""' "$ECO" 2>/dev/null)
[[ "$FORK_REPO_OVERRIDE" == "null" ]] && FORK_REPO_OVERRIDE=""

FORK_ORG=$(yq '.identity.forkOrg // ""' "$ECO" 2>/dev/null)
[[ "$FORK_ORG" == "null" ]] && FORK_ORG=""
if [[ -z "$FORK_ORG" ]]; then
    echo "ERROR: identity.forkOrg is not set in ecosystem config." >&2
    echo "  Add 'identity.forkOrg: <your-fork-namespace>' to ecosystem.local.yaml." >&2
    exit 1
fi

FORK_CONVENTION=$(yq '.defaults.forkConvention // "nested"' "$ECO" 2>/dev/null)
[[ "$FORK_CONVENTION" == "null" ]] && FORK_CONVENTION="nested"

# Transport for the fork/upstream remotes. https (default) injects the .env
# token per-process — no SSH keys, no credential-manager prompt — the same
# mechanism as ws push/clone (see git-auth.sh). ssh keeps key-based transport.
# https auto-falls-back to ssh when no .env token covers the host (e.g.
# self-hosted GitLab on a non-gitlab.* domain), so SSH-key users don't regress.
FORK_TRANSPORT=$(yq '.defaults.forkTransport // "https"' "$ECO" 2>/dev/null)
[[ "$FORK_TRANSPORT" == "null" || -z "$FORK_TRANSPORT" ]] && FORK_TRANSPORT="https"
case "$FORK_TRANSPORT" in
    https|ssh) ;;
    *) echo "ERROR: Unknown defaults.forkTransport '$FORK_TRANSPORT'. Use 'https' or 'ssh'." >&2; exit 1 ;;
esac

# --- parse upstream URL -----------------------------------------------------
# Returns host and path (no .git suffix). Path is e.g. "acme/team/widget".
parse_git_url() {
    local url="$1"
    local host path
    if [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
    elif [[ "$url" =~ ^ssh://[^@]+@([^/:]+)(:[0-9]+)?/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[3]}"
    elif [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
    else
        echo "ERROR: Cannot parse git URL: $url" >&2
        return 1
    fi
    path="${path%.git}"
    echo "$host" "$path"
}

read -r UPSTREAM_HOST UPSTREAM_PATH < <(parse_git_url "$UPSTREAM_URL")
UPSTREAM_LEAF_GROUP="$(dirname "$UPSTREAM_PATH")"        # e.g. "acme/team"
UPSTREAM_REPO_NAME="$(basename "$UPSTREAM_PATH")"        # e.g. "widget"
# Remote name for upstream: last segment of the parent group, or "upstream" if path is flat.
if [[ "$UPSTREAM_LEAF_GROUP" == "." || -z "$UPSTREAM_LEAF_GROUP" ]]; then
    UPSTREAM_REMOTE_NAME="upstream"
else
    UPSTREAM_REMOTE_NAME="$(basename "$UPSTREAM_LEAF_GROUP")"
fi
# The fork remote is named after $FORK_ORG. If the upstream group's
# leaf segment happens to equal $FORK_ORG, the two `git remote add`
# calls would collide — the second clobbers or fails. Fall back to
# the literal "upstream" so the two remotes always have distinct names.
if [[ "$UPSTREAM_REMOTE_NAME" == "$FORK_ORG" ]]; then
    UPSTREAM_REMOTE_NAME="upstream"
fi

# --- derive fork path -------------------------------------------------------
if [[ -n "$FORK_REPO_OVERRIDE" ]]; then
    read -r _FORK_HOST FORK_PATH < <(parse_git_url "$FORK_REPO_OVERRIDE")
    if [[ "$_FORK_HOST" != "$UPSTREAM_HOST" ]]; then
        echo "ERROR: forkRepo host ($_FORK_HOST) differs from upstream host ($UPSTREAM_HOST). Cross-host forks are not supported by this script." >&2
        exit 1
    fi
else
    case "$FORK_CONVENTION" in
        nested)
            FORK_PATH="${UPSTREAM_LEAF_GROUP}/${FORK_ORG}/${UPSTREAM_REPO_NAME}"
            ;;
        flat)
            FORK_PATH="${FORK_ORG}/${UPSTREAM_REPO_NAME}"
            ;;
        *)
            echo "ERROR: Unknown forkConvention '$FORK_CONVENTION'. Use 'nested' or 'flat'." >&2
            exit 1
            ;;
    esac
fi

FORK_NAMESPACE="$(dirname "$FORK_PATH")"  # destination namespace for project creation

# --- token resolution (longest-prefix match) --------------------------------
# Token-walk lives in ws-realm.sh as `ws_resolve_token_var`. We pass the
# full "host/path" target (which the shared helper expects).

UPSTREAM_TOKEN_VAR=$(ws_resolve_token_var "$UPSTREAM_HOST/$UPSTREAM_PATH")
FORK_TOKEN_VAR=$(ws_resolve_token_var "$UPSTREAM_HOST/$FORK_PATH")

# Helper: source .env from workspace root if a needed var isn't loaded.
# (ws dispatcher already sources .env, but ws-clone-fork.sh may be invoked
# directly. Belt-and-suspenders.)
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env" 2>/dev/null || true

require_token() {
    local var="$1"
    local purpose="$2"
    if [[ -z "$var" || "$var" == "null" ]]; then
        echo "ERROR: No gitTokens entry covers '$purpose' on $UPSTREAM_HOST." >&2
        echo "  Add an entry to defaults.gitTokens in ecosystem.local.yaml." >&2
        exit 1
    fi
    local val="${!var:-}"
    if [[ -z "$val" ]]; then
        echo "ERROR: Env var \$$var is not set (needed for $purpose)." >&2
        echo "  Add 'export $var=<token>' to .env, then re-run." >&2
        exit 1
    fi
}

require_token "$UPSTREAM_TOKEN_VAR" "upstream read"
require_token "$FORK_TOKEN_VAR"     "fork write/create"

# --- helpers: API + URL encoding -------------------------------------------
urlencode() {
    # Lightweight URL-encoder for path components (jq is faster than printf).
    printf '%s' "$1" | jq -sRr @uri
}

# Call glab api with a specific token (via GITLAB_TOKEN env override).
# Returns stdout-only on success (callers capture); stderr passes through
# so glab's "new version available" notices don't pollute the JSON.
# Callers that want the error body on failure capture stderr to a file
# at the call site (see $ERR_TMP usage below).
#
# --hostname is pinned to the upstream host explicitly. Without it,
# glab picks the instance from its own config or the cwd's git remote
# — which for a script targeting a specific upstream could silently
# hit the wrong GitLab (e.g. gitlab.com instead of a corporate one).
api_call() {
    local token_var="$1"; shift
    local token="${!token_var}"
    GITLAB_TOKEN="$token" glab api --hostname "$UPSTREAM_HOST" "$@"
}

# Emit a one-click helper for the cross-group fork case and exit 2.
emit_cross_group_helper() {
    local fork_url="https://$UPSTREAM_HOST/$UPSTREAM_PATH/-/forks/new"

    # Best-effort: look up destination namespace ID for URL pre-fill.
    # GitLab versions vary in whether ?namespace_id=<id> actually pre-fills
    # the fork-form dropdown — include it anyway; harmless if ignored,
    # saves a click on versions that honor it.
    local ns_id="" ns_encoded ns_details
    ns_encoded=$(urlencode "$FORK_NAMESPACE")
    if ns_details=$(api_call "$FORK_TOKEN_VAR" "namespaces/$ns_encoded" 2>/dev/null); then
        ns_id=$(echo "$ns_details" | jq -r '.id // empty')
    fi
    if [[ -n "$ns_id" ]]; then
        fork_url="${fork_url}?namespace_id=${ns_id}"
    fi

    echo "" >&2
    echo "  Cross-group fork detected — manual step needed." >&2
    echo "" >&2
    echo "  Your fork-home token (\$$FORK_TOKEN_VAR) has write access on" >&2
    echo "  '$FORK_NAMESPACE' but no read access on '$UPSTREAM_PATH'. GitLab's" >&2
    echo "  fork API needs one identity with both rights, and bot users created" >&2
    echo "  by access tokens cannot be cross-invited to other groups" >&2
    echo "" >&2
    echo "  Click here to fork in the GitLab UI:" >&2
    echo "" >&2
    echo "    $fork_url" >&2
    echo "" >&2
    echo "  In the fork form:" >&2
    echo "    Destination namespace: $FORK_NAMESPACE" >&2
    echo "    Project slug:          $UPSTREAM_REPO_NAME (default)" >&2
    echo "    Visibility:            match upstream (default)" >&2
    echo "" >&2
    echo "  Once GitLab finishes the import (usually <1 minute), re-run:" >&2
    echo "    ws clone-fork $COMPONENT" >&2
    echo "" >&2
}

# --- ensure fork exists -----------------------------------------------------
echo "[ ws clone-fork: $COMPONENT ]"
echo "  Upstream : $UPSTREAM_PATH on $UPSTREAM_HOST"
echo "  Fork     : $FORK_PATH"

UPSTREAM_ENCODED="$(urlencode "$UPSTREAM_PATH")"
FORK_ENCODED="$(urlencode "$FORK_PATH")"

echo ""
echo "  Step 1: check fork exists..."
FORK_DETAILS=""
if FORK_DETAILS=$(api_call "$FORK_TOKEN_VAR" "projects/$FORK_ENCODED" 2>/dev/null); then
    if echo "$FORK_DETAILS" | jq -e '.id' &>/dev/null; then
        echo "         ✓ fork exists ($(echo "$FORK_DETAILS" | jq -r '.web_url'))"
    else
        FORK_DETAILS=""
    fi
else
    # glab api returns non-zero on HTTP error but still writes the error body
    # to stdout; the command-substitution assignment captures it. Clear it
    # so the "fork does not exist — creating" branch below can fire.
    FORK_DETAILS=""
fi

if [[ -z "$FORK_DETAILS" ]]; then
    echo "         ✗ fork does not exist — creating..."

    # Probe: can FORK_TOKEN see upstream? GitLab's fork API requires one
    # caller identity with rights on both source (read) and destination
    # (create). When upstream and destination are in different groups,
    # FORK_TOKEN typically has create on destination but no read on source.
    # Detect this up front and surface a UI-fork helper rather than letting
    # the API call fail with a cryptic 404.
    if ! api_call "$FORK_TOKEN_VAR" "projects/$UPSTREAM_ENCODED" >/dev/null 2>&1; then
        emit_cross_group_helper
        exit 2
    fi

    # Get upstream project ID (needed for fork API)
    local_upstream_details=""
    if ! local_upstream_details=$(api_call "$UPSTREAM_TOKEN_VAR" "projects/$UPSTREAM_ENCODED" 2>"$ERR_TMP"); then
        echo "ERROR: Failed to fetch upstream project details." >&2
        cat "$ERR_TMP" >&2; rm -f "$ERR_TMP"
        exit 1
    fi
    rm -f "$ERR_TMP"
    UPSTREAM_ID=$(echo "$local_upstream_details" | jq -r '.id')
    if [[ -z "$UPSTREAM_ID" || "$UPSTREAM_ID" == "null" ]]; then
        echo "ERROR: Could not determine upstream project ID." >&2
        echo "$local_upstream_details" | head -20 >&2
        exit 1
    fi

    # POST /projects/:id/fork with namespace_path
    fork_create_result=""
    fork_create_err="$ERR_TMP"
    if ! fork_create_result=$(api_call "$FORK_TOKEN_VAR" "projects/$UPSTREAM_ID/fork" -X POST -f "namespace_path=$FORK_NAMESPACE" 2>"$fork_create_err"); then
        echo "ERROR: Fork creation failed." >&2
        cat "$fork_create_err" >&2
        # Common failure: token lacks Maintainer role on the destination group.
        if grep -qi "not allowed to import" "$fork_create_err"; then
            echo "" >&2
            echo "  GitLab error 'not allowed to import projects' usually means the token's role" >&2
            echo "  on '$FORK_NAMESPACE' is too low (Developer is insufficient; need Maintainer)." >&2
            echo "  Regenerate the token at the destination group with Maintainer+ role and 'api' scope." >&2
        fi
        rm -f "$fork_create_err"
        exit 1
    fi
    rm -f "$fork_create_err"
    FORK_DETAILS="$fork_create_result"

    # Poll import_status until "finished". Default is 10 × 2s = 20s,
    # which covers normal-size repos; heavier upstreams may need more.
    # WS_CLONE_FORK_POLL_ITERATIONS overrides the count without a code
    # change. A non-positive or non-numeric value falls back to 10.
    poll_max="${WS_CLONE_FORK_POLL_ITERATIONS:-10}"
    [[ "$poll_max" =~ ^[1-9][0-9]*$ ]] || poll_max=10
    echo "         Fork created; waiting for import to finish..."
    for ((i = 1; i <= poll_max; i++)); do
        sleep 2
        status_json=$(api_call "$FORK_TOKEN_VAR" "projects/$FORK_ENCODED" 2>/dev/null || echo '{}')
        status=$(echo "$status_json" | jq -r '.import_status // "unknown"')
        echo "         attempt $i/$poll_max: import_status = $status"
        if [[ "$status" == "finished" ]]; then
            FORK_DETAILS="$status_json"
            break
        elif [[ "$status" == "failed" ]]; then
            echo "ERROR: Fork import failed on the GitLab side." >&2
            echo "$status_json" | jq '.import_error // .' >&2
            exit 1
        fi
    done
    if [[ "$status" != "finished" ]]; then
        echo "ERROR: Fork import did not finish after $((poll_max * 2))s." >&2
        echo "  Re-run ws clone-fork — the import may complete in the background." >&2
        echo "  For a consistently slow upstream, raise WS_CLONE_FORK_POLL_ITERATIONS." >&2
        exit 1
    fi
fi

# Need upstream details too (for remote URLs + default branch). Re-fetch if
# we didn't already capture them during fork creation.
if [[ -z "${local_upstream_details:-}" ]]; then
    if ! local_upstream_details=$(api_call "$UPSTREAM_TOKEN_VAR" "projects/$UPSTREAM_ENCODED" 2>"$ERR_TMP"); then
        echo "ERROR: Failed to fetch upstream project details." >&2
        cat "$ERR_TMP" >&2; rm -f "$ERR_TMP"
        exit 1
    fi
    rm -f "$ERR_TMP"
fi

# The provider API returns both ssh_url_to_repo and http_url_to_repo. Pick the
# remote URLs per FORK_TRANSPORT, auto-falling-back to ssh when https can't be
# token-covered for this host (so self-hosted/keys-only setups keep working).
FORK_SSH_URL=$(echo "$FORK_DETAILS" | jq -r '.ssh_url_to_repo')
UPSTREAM_SSH_URL=$(echo "$local_upstream_details" | jq -r '.ssh_url_to_repo')
FORK_HTTP_URL=$(echo "$FORK_DETAILS" | jq -r '.http_url_to_repo')
UPSTREAM_HTTP_URL=$(echo "$local_upstream_details" | jq -r '.http_url_to_repo')

FORK_REMOTE_URL="$FORK_SSH_URL"
UPSTREAM_REMOTE_URL="$UPSTREAM_SSH_URL"
if [[ "$FORK_TRANSPORT" == "https" ]]; then
    if [[ -n "$FORK_HTTP_URL" && "$FORK_HTTP_URL" != "null" ]]; then
        GIT_AUTH_ENV=()
        git_auth_env_for_url "$FORK_HTTP_URL"
        if [[ ${#GIT_AUTH_ENV[@]} -gt 0 ]]; then
            FORK_REMOTE_URL="$FORK_HTTP_URL"
            UPSTREAM_REMOTE_URL="$UPSTREAM_HTTP_URL"
            echo "  Transport: https (token-injected, no credential-manager prompt)"
        else
            echo "  Transport: ssh (https injection unavailable for $UPSTREAM_HOST — no covering .env token, or host not injectable)"
        fi
    else
        echo "  Transport: ssh (provider returned no http_url_to_repo)"
    fi
else
    echo "  Transport: ssh"
fi

# --- clone or repair local checkout -----------------------------------------
TARGET="$COMPONENTS_DIR/$COMPONENT"
echo ""
echo "  Step 2: prepare local clone at $TARGET ..."

# A leftover directory at $TARGET that is NOT a usable git clone
# blocks the clone step below. Only auto-remove it when it is
# genuinely EMPTY (e.g., an empty stub left by an IDE file-watcher).
# A non-empty directory without a .git — the user's own work parked
# under components/, or a half-broken clone — must NOT be rm -rf'd.
# Stop and let the user decide rather than risk silent data loss.
if [[ -d "$TARGET" && ! -d "$TARGET/.git" ]]; then
    if [[ -z "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
        rmdir "$TARGET"
    else
        echo "ERROR: $TARGET exists, is not empty, and is not a git clone." >&2
        echo "  Refusing to delete it — it may contain untracked work." >&2
        echo "  Move or remove it yourself, then re-run ws clone-fork." >&2
        exit 1
    fi
fi

if [[ -d "$TARGET/.git" ]]; then
    # Pre-existing real clone — verify remotes and proceed
    echo "         ✓ clone already present; verifying remotes"

    # Fork remote: ensure it's named correctly and points at the fork remote
    # URL for the chosen transport. Re-running after a transport change
    # migrates the stored remote (e.g. ssh → https) idempotently.
    if git -C "$TARGET" remote get-url "$FORK_ORG" &>/dev/null; then
        existing_url=$(git -C "$TARGET" remote get-url "$FORK_ORG")
        if [[ "$existing_url" != "$FORK_REMOTE_URL" ]]; then
            git -C "$TARGET" remote set-url "$FORK_ORG" "$FORK_REMOTE_URL"
            echo "         updated fork remote URL"
        fi
    else
        # Maybe origin still points at fork — rename it if so
        if git -C "$TARGET" remote get-url origin &>/dev/null; then
            existing_origin=$(git -C "$TARGET" remote get-url origin)
            if [[ "$existing_origin" == "$FORK_REMOTE_URL" ]]; then
                git -C "$TARGET" remote rename origin "$FORK_ORG"
                echo "         renamed origin → $FORK_ORG"
            else
                git -C "$TARGET" remote add "$FORK_ORG" "$FORK_REMOTE_URL"
                echo "         added fork remote: $FORK_ORG"
            fi
        else
            git -C "$TARGET" remote add "$FORK_ORG" "$FORK_REMOTE_URL"
            echo "         added fork remote: $FORK_ORG"
        fi
    fi

    # Upstream remote
    if git -C "$TARGET" remote get-url "$UPSTREAM_REMOTE_NAME" &>/dev/null; then
        existing_up=$(git -C "$TARGET" remote get-url "$UPSTREAM_REMOTE_NAME")
        if [[ "$existing_up" != "$UPSTREAM_REMOTE_URL" ]]; then
            git -C "$TARGET" remote set-url "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
            echo "         updated upstream remote URL"
        fi
    else
        git -C "$TARGET" remote add "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
        echo "         added upstream remote: $UPSTREAM_REMOTE_NAME"
    fi
else
    # Fresh clone from fork
    echo "         CLONE: $FORK_REMOTE_URL → $TARGET (origin: $FORK_ORG)"
    GIT_AUTH_ENV=()
    git_auth_env_for_url "$FORK_REMOTE_URL"
    env "${GIT_AUTH_ENV[@]}" git clone --origin "$FORK_ORG" "$FORK_REMOTE_URL" "$TARGET"
    git -C "$TARGET" remote add "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
fi

# --- sync main with upstream ------------------------------------------------
echo ""
echo "  Step 3: sync local + fork main with upstream ..."

GIT_AUTH_ENV=()
git_auth_env_for_url "$UPSTREAM_REMOTE_URL"
env "${GIT_AUTH_ENV[@]}" git -C "$TARGET" fetch "$UPSTREAM_REMOTE_NAME" --quiet

# Determine the upstream default branch (might be "main" or "master")
DEFAULT_BRANCH=$(echo "$local_upstream_details" | jq -r '.default_branch // "main"')
[[ -z "$DEFAULT_BRANCH" || "$DEFAULT_BRANCH" == "null" ]] && DEFAULT_BRANCH="main"

# Ensure local default branch exists and is checked out
if ! git -C "$TARGET" rev-parse --verify "$DEFAULT_BRANCH" &>/dev/null; then
    git -C "$TARGET" checkout -B "$DEFAULT_BRANCH" "$UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH"
    echo "         created local $DEFAULT_BRANCH from $UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH"
else
    current=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)
    if [[ "$current" != "$DEFAULT_BRANCH" ]]; then
        # Don't yank the user out of an in-progress release branch silently
        if [[ "$current" == release/* ]]; then
            echo "         current branch is '$current' (release in progress); leaving it alone, syncing main in the background"
            # Compute sync action without checkout
            read -r ahead behind < <(git -C "$TARGET" rev-list --left-right --count "$DEFAULT_BRANCH...$UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH")
            if [[ "$behind" -gt 0 && "$ahead" -eq 0 ]]; then
                git -C "$TARGET" update-ref "refs/heads/$DEFAULT_BRANCH" "$UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH"
                echo "         fast-forwarded $DEFAULT_BRANCH ref to upstream (without checkout)"
            elif [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
                echo "ERROR: Local $DEFAULT_BRANCH has diverged from $UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH ($ahead ahead, $behind behind)." >&2
                echo "  Resolve manually before re-running ws clone-fork." >&2
                exit 1
            fi
        else
            git -C "$TARGET" checkout "$DEFAULT_BRANCH"
        fi
    fi
fi

# If we're on default branch now, do the visible ahead/behind compute + merge
if [[ "$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)" == "$DEFAULT_BRANCH" ]]; then
    read -r ahead behind < <(git -C "$TARGET" rev-list --left-right --count "$DEFAULT_BRANCH...$UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH")
    if [[ "$behind" -eq 0 ]]; then
        echo "         ✓ local $DEFAULT_BRANCH is up to date (ahead: $ahead, behind: 0)"
    elif [[ "$ahead" -eq 0 ]]; then
        echo "         local $DEFAULT_BRANCH is behind by $behind — fast-forwarding"
        git -C "$TARGET" merge --ff-only "$UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH"
    else
        echo "ERROR: Local $DEFAULT_BRANCH has diverged from $UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH ($ahead ahead, $behind behind)." >&2
        echo "  This script will not force-push or rebase. Resolve manually:" >&2
        echo "    - inspect the local commits with: git -C $TARGET log $UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH..$DEFAULT_BRANCH" >&2
        echo "    - either push those commits upstream as their own MRs, or discard them with a hard reset" >&2
        exit 1
    fi
fi

# --- push synced main to fork (always, never force) -------------------------
# Use GIT_SSH_COMMAND if a non-default key is configured? Not in v1.
echo ""
echo "  Step 4: push synced $DEFAULT_BRANCH to fork ..."
# Push the local default branch ref to fork's same branch.
# Use refspec form to avoid checkout dependency. Regular push (no --force).
#
# Capture the push result explicitly rather than `git push | sed`.
# In a pipeline, the `if` tests the LAST stage (sed), not git —
# `pipefail` currently propagates git's failure so the test is
# correct today, but relying on that for an if-condition pipeline is
# subtle and a future edit could silently break it. Capture output
# and status, then stream the output and branch on the real status.
GIT_AUTH_ENV=()
git_auth_env_for_url "$FORK_REMOTE_URL"
if push_output=$(env "${GIT_AUTH_ENV[@]}" git -C "$TARGET" push "$FORK_ORG" "refs/heads/$DEFAULT_BRANCH:refs/heads/$DEFAULT_BRANCH" 2>&1); then
    push_ok=true
else
    push_ok=false
fi
printf '%s\n' "$push_output" | sed 's/^/         /'
if $push_ok; then
    echo "         ✓ fork $DEFAULT_BRANCH now matches upstream"
else
    echo "         (push to fork $DEFAULT_BRANCH did not fast-forward — leaving fork main as is; clone retry will sync on next run)"
    # Don't fail the whole run on this; the local checkout is good.
fi

# --- summary ----------------------------------------------------------------
echo ""
echo "  Ready:"
echo "    $TARGET"
echo "    remotes: $FORK_ORG (fork), $UPSTREAM_REMOTE_NAME (upstream)"
echo "    $DEFAULT_BRANCH: synced with $UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH"
