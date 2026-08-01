#!/usr/bin/env bash
# ws-clone-fork.sh — Fork-aware clone for ecosystem components
# ws:use-when fork-aware clone — ensures your personal fork exists then sets both remotes
#
# Usage: ws-clone-fork.sh <component>
#
# Ensures the user's personal fork of <component>'s source project exists,
# clones it to components/<name>/, wires up both remotes (fork and
# source), and syncs the local + fork main with the source project.
#
# Idempotent: re-running on an already-prepared clone re-syncs main
# and exits cleanly. The agent can call this any time without
# tracking whether the fork exists or is current.
#
# Per-component override (in ecosystem config):
#   components:
#     <name>:
#       repo: <source-project-url>
#       forkRepo: <fork-url>          # explicit fork URL (overrides derivation)
#
# Preferred per-developer fork home (in ecosystem config):
#   identity:
#     homes:
#       fork:
#         namespace: <host>/<group-path>  # e.g. gitlab.example.com/acme/gdd/alice

set -euo pipefail

# --- help short-circuit -----------------------------------------------------
for _arg in "$@"; do
    if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
        cat <<'HELP'
Usage: ws clone-fork <component>
       ws clone-fork --url <source-url> [--name <name>] --add-to-ecosystem

Prepare a ready-to-work fork-based clone of <component>:

  1. Ensure the user's fork-home copy exists in components.<name>.forkRepo
     or identity.homes.fork.namespace (creates it via API when the configured
     token can read the source project and create in the fork destination).
  2. Clone the fork into components/<component>/, with the initial remote
     named <forkRemote>.
  3. Add the source project as a second remote, named after the source
     project's parent group's leaf segment (or "upstream" if no leaf is sensible).
  4. Sync local main with the source project's main. Push synced main back to the
     fork so future clones start clean. Force-pushes never happen — if
     histories diverge, the script stops and asks the user to resolve.

Works against GitHub and GitLab sources: fork lookup/creation goes
through gh or glab per the detected provider (github.com/gitlab.com
auto-detect; self-hosted hosts map via defaults.gitProviders.<host>,
and unmapped hosts default to GitLab).

Token resolution is automatic: longest-prefix match on
defaults.gitTokens against the fork's namespace, falling back to the
provider default (GH_TOKEN on github.com, GITLAB_TOKEN on gitlab.com)
when no entry covers the target — same behavior as ws push. .env is
already sourced by the ws dispatcher, so no manual sourcing is needed.

Transport defaults to HTTPS with the .env token injected per-process
(no SSH keys, no credential-manager prompt — same mechanism as ws push).
Set defaults.forkTransport: ssh to use key-based SSH instead. HTTPS
auto-falls-back to SSH when no .env token covers the host (e.g. a
self-hosted GitLab on a non-gitlab.* domain). Both the SSH and HTTPS
remote URLs come from the provider's project-details API response
(provider-agnostic — no host-specific port handling here).

Idempotent: re-runs on an already-prepared clone simply re-sync main.

The --url form covers a source project not yet declared in the
ecosystem: it validates the URL, derives the component name from the
repo slug (override with --name), writes the components.<name> entry
to ecosystem.local.yaml (tier: supporting), then runs the normal
clone-fork flow — no separate `ws clone --url … --add-to-ecosystem`
step needed. --add-to-ecosystem is required with --url because a
fork-clone the ecosystem doesn't know about would leave every later
ws command unable to resolve the component. Declaring a component is
a trust decision, so this form prompts for human approval.

Cross-group forks (e.g. forking from one GitLab group into a fork
home that lives in another group) require one caller identity with
read access on the source project and project-create/fork rights on
the destination namespace. Access-token bot users cannot be invited
directly to unrelated groups (GitLab issue #355659), but a source
project/group can invite the fork-home group; the fork-group token can
then gain source-project read through that group membership. Group
service-account tokens follow the same capability rule: they work when
the service account can read the source project through public visibility,
same-hierarchy access, or GitLab project/group sharing to the fork-home
group. When the configured fork token cannot read the source project, this
script emits a one-click fork-via-UI URL and exits with code 2 ("manual
step needed"). Re-run after user interaction.
HELP
        exit 0
    fi
done

COMPONENT=""
CF_URL=""
CF_NAME=""
CF_ADD_ECO="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            shift
            CF_URL="${1:-}"
            if [[ -z "$CF_URL" ]]; then
                echo "ERROR: --url requires a value." >&2
                exit 1
            fi
            shift
            ;;
        --name)
            shift
            CF_NAME="${1:-}"
            if [[ -z "$CF_NAME" ]]; then
                echo "ERROR: --name requires a value." >&2
                exit 1
            fi
            shift
            ;;
        --add-to-ecosystem|--add-eco)
            CF_ADD_ECO="true"
            shift
            ;;
        -*)
            echo "ERROR: Unknown flag '$1' for ws clone-fork." >&2
            echo "  Run 'ws clone-fork --help' for usage." >&2
            exit 1
            ;;
        *)
            if [[ -n "$COMPONENT" ]]; then
                echo "ERROR: ws clone-fork takes a single component name (got '$COMPONENT' and '$1')." >&2
                exit 1
            fi
            COMPONENT="$1"
            shift
            ;;
    esac
done

if [[ -z "$COMPONENT" && -z "$CF_URL" ]]; then
    echo "Usage: ws clone-fork <component>" >&2
    echo "       ws clone-fork --url <source-url> [--name <name>] --add-to-ecosystem" >&2
    echo "  Run 'ws clone-fork --help' for details." >&2
    exit 1
fi
if [[ -n "$COMPONENT" && -n "$CF_URL" ]]; then
    echo "ERROR: Pass a component name OR --url, not both." >&2
    exit 1
fi
if [[ -n "$CF_NAME" && -z "$CF_URL" ]]; then
    echo "ERROR: --name only applies with --url." >&2
    exit 1
fi
if [[ -n "$CF_URL" && "$CF_ADD_ECO" != "true" ]]; then
    echo "ERROR: --url requires --add-to-ecosystem." >&2
    echo "  A fork-clone the ecosystem doesn't declare would leave later ws commands" >&2
    echo "  unable to resolve the component. Re-run with --add-to-ecosystem, or declare" >&2
    echo "  the component in ecosystem config and use 'ws clone-fork <component>'." >&2
    exit 1
fi
if [[ -z "$CF_URL" && "$CF_ADD_ECO" == "true" ]]; then
    echo "ERROR: --add-to-ecosystem only applies with --url." >&2
    echo "  A plain 'ws clone-fork <component>' reads an EXISTING ecosystem entry;" >&2
    echo "  there is nothing to add. Use --url <source-url> to declare a new one." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# --- dependency checks ------------------------------------------------------
# Generic tools only here; the provider CLI (gh or glab) is checked after the
# source URL tells us which provider we're talking to.
for cmd in yq jq git; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required for ws clone-fork." >&2
        case "$cmd" in
            yq)   echo "  Install: https://github.com/mikefarah/yq" >&2 ;;
            jq)   echo "  Install: https://stedolan.github.io/jq/" >&2 ;;
        esac
        exit 1
    fi
done

ECO="$(ws_resolve_ecosystem)"

# --- URL mode: declare the component ----------------------------------------
# Runs AFTER ws_resolve_ecosystem so the realm-trust gate (inside the
# resolve) fires before anything is written — a trust failure must not
# leave a half-declared component behind. This run uses $CF_URL
# directly (the resolved merge predates the write); the entry is for
# future commands. Mirrors ws-clone.sh's yq shape and name derivation.
if [[ -n "$CF_URL" ]]; then
    git_remote_validate "$CF_URL" remote
    if [[ -z "$CF_NAME" ]]; then
        CF_NAME=$(echo "$CF_URL" | sed 's|.*/||; s|\.git$||' | tr '[:upper:]' '[:lower:]')
    fi
    if [[ -z "$CF_NAME" ]] || ! ws_component_name_is_valid "$CF_NAME"; then
        echo "ERROR: Cannot derive a valid component name from URL: $CF_URL" >&2
        echo "  Use --name <name> (lowercase, alphanumeric, hyphens, dots)." >&2
        exit 1
    fi
    EXISTING_REPO=$(COMP="$CF_NAME" yq '.components[strenv(COMP)].repo // ""' "$ECO" 2>/dev/null)
    [[ "$EXISTING_REPO" == "null" ]] && EXISTING_REPO=""
    if [[ -n "$EXISTING_REPO" ]]; then
        if [[ "$EXISTING_REPO" == "$CF_URL" ]]; then
            echo "Component '$CF_NAME' is already declared with this repo — continuing without changes."
        else
            echo "ERROR: Component '$CF_NAME' is already declared with a different repo:" >&2
            echo "    declared: $EXISTING_REPO" >&2
            echo "    --url:    $CF_URL" >&2
            echo "  Use --name <other-name> for a separate component, or fix the existing entry." >&2
            exit 1
        fi
    else
        LOCAL_CONFIG="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
        if [[ ! -f "$LOCAL_CONFIG" ]]; then
            # Deliberately NOT seeded from ecosystem.local.yaml.example (ws-clone
            # does): the example's uncommented identity placeholders would
            # deep-merge over the realm's real values and turn the clear
            # "identity.forkRemote is not set" error below into a fork remote
            # silently named after a placeholder.
            printf '{}\n' > "$LOCAL_CONFIG"
        fi
        COMPONENT_NAME="$CF_NAME" REPO_URL="$CF_URL" \
            yq -i '
                .components[strenv(COMPONENT_NAME)].tier = "supporting" |
                .components[strenv(COMPONENT_NAME)].repo = strenv(REPO_URL)
            ' "$LOCAL_CONFIG"
        echo "ADDED: $CF_NAME to $LOCAL_CONFIG (tier: supporting, repo: $CF_URL)"
    fi
    COMPONENT="$CF_NAME"
fi

# Scratch file for capturing provider-CLI stderr. Workspace convention is
# .tmp/ over /tmp — Git Bash maps /tmp to an unpredictable location
# on Windows. .tmp/ is gitignored. Per-PID suffix avoids collisions;
# each `2>` redirect truncates, so the file is reused safely and the
# inline `rm -f` calls clean it up after each consumer.
ERR_TMP="$ROOT_DIR/.tmp/ws-clone-fork-err.$$"
mkdir -p "$ROOT_DIR/.tmp"

# --- read component config --------------------------------------------------
# URL mode uses the given URL directly — the merged config was resolved
# before the declaration write, so a lookup there would miss the new entry.
if [[ -n "$CF_URL" ]]; then
    UPSTREAM_URL="$CF_URL"
else
    UPSTREAM_URL=$(COMP="$COMPONENT" yq '.components[strenv(COMP)].repo // ""' "$ECO" 2>/dev/null)
    if [[ -z "$UPSTREAM_URL" || "$UPSTREAM_URL" == "null" ]]; then
        echo "ERROR: Component '$COMPONENT' is not declared in ecosystem config." >&2
        echo "  Declare-and-clone in one step: ws clone-fork --url <source-url> --add-to-ecosystem" >&2
        echo "  Or add it to ecosystem.local.yaml under 'components:' first:" >&2
        echo "    components:" >&2
        echo "      $COMPONENT:" >&2
        echo "        tier: supporting" >&2
        echo "        repo: <source-project-git-url>" >&2
        exit 1
    fi
fi
git_remote_validate "$UPSTREAM_URL" remote

# Per-component fork override (full URL)
FORK_REPO_OVERRIDE=$(COMP="$COMPONENT" yq '.components[strenv(COMP)].forkRepo // ""' "$ECO" 2>/dev/null)
[[ "$FORK_REPO_OVERRIDE" == "null" ]] && FORK_REPO_OVERRIDE=""

FORK_HOME_NAMESPACE=$(yq '.identity.homes.fork.namespace // ""' "$ECO" 2>/dev/null)
[[ "$FORK_HOME_NAMESPACE" == "null" ]] && FORK_HOME_NAMESPACE=""

FORK_REMOTE=$(yq '.identity.forkRemote // ""' "$ECO" 2>/dev/null)
[[ "$FORK_REMOTE" == "null" ]] && FORK_REMOTE=""
if [[ -z "$FORK_REMOTE" ]]; then
    echo "ERROR: identity.forkRemote is not set in ecosystem config." >&2
    echo "  Add 'identity.forkRemote: <your-fork-remote-name>' to ecosystem.local.yaml." >&2
    exit 1
fi

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

parse_fork_home_namespace() {
    local raw="$1"
    local default_host="$2"
    local host path first

    raw="${raw%/}"
    if [[ "$raw" =~ ^https?://([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
    elif [[ "$raw" == *"://"* ]]; then
        echo "ERROR: Cannot parse identity.homes.fork.namespace: $raw" >&2
        return 1
    elif [[ "$raw" == "$default_host/"* ]]; then
        host="$default_host"
        path="${raw#"$default_host/"}"
    elif [[ "$raw" == */* ]]; then
        first="${raw%%/*}"
        if [[ "$first" == *.* || "$first" == *:* ]]; then
            host="$first"
            path="${raw#*/}"
        else
            host="$default_host"
            path="$raw"
        fi
    else
        host="$default_host"
        path="$raw"
    fi

    path="${path#/}"
    path="${path%/}"
    path="${path%.git}"
    if [[ -z "$path" || "$path" == "." ]]; then
        echo "ERROR: identity.homes.fork.namespace must include a namespace path." >&2
        return 1
    fi

    echo "$host" "$path"
}

read -r UPSTREAM_HOST UPSTREAM_PATH < <(parse_git_url "$UPSTREAM_URL")

# --- provider detection -------------------------------------------------------
# github.com / gitlab.com auto-detect; other hosts resolve via
# defaults.gitProviders.<host> or defaults.gitProvider. When nothing matches,
# default to gitlab — every pre-parity clone-fork target was GitLab, so an
# unmapped self-hosted host keeps its historical behavior instead of erroring.
PROVIDER="$(gp_detect "$UPSTREAM_URL" "$ECO" 2>/dev/null || true)"
[[ -z "$PROVIDER" ]] && PROVIDER="gitlab"
case "$PROVIDER" in
    github) PROVIDER_CLI="gh" ;;
    gitlab) PROVIDER_CLI="glab" ;;
    *)
        echo "ERROR: ws clone-fork supports the github and gitlab providers (got '$PROVIDER' for $UPSTREAM_HOST)." >&2
        echo "  Check defaults.gitProviders.$UPSTREAM_HOST / defaults.gitProvider in ecosystem config." >&2
        exit 1
        ;;
esac
if ! command -v "$PROVIDER_CLI" &>/dev/null; then
    echo "ERROR: $PROVIDER_CLI is required for ws clone-fork on a $PROVIDER source." >&2
    case "$PROVIDER_CLI" in
        gh)   echo "  Install: https://cli.github.com/" >&2 ;;
        glab) echo "  Install: https://gitlab.com/gitlab-org/cli" >&2 ;;
    esac
    exit 1
fi

UPSTREAM_LEAF_GROUP="$(dirname "$UPSTREAM_PATH")"        # e.g. "acme/team"
UPSTREAM_REPO_NAME="$(basename "$UPSTREAM_PATH")"        # e.g. "widget"
# Remote name for upstream: last segment of the parent group, or "upstream" if path is flat.
if [[ "$UPSTREAM_LEAF_GROUP" == "." || -z "$UPSTREAM_LEAF_GROUP" ]]; then
    UPSTREAM_REMOTE_NAME="upstream"
else
    UPSTREAM_REMOTE_NAME="$(basename "$UPSTREAM_LEAF_GROUP")"
fi
# The fork remote is named after $FORK_REMOTE. If the upstream group's
# leaf segment happens to equal $FORK_REMOTE, the two `git remote add`
# calls would collide. Use "upstream" as the preferred fallback.
if [[ "$UPSTREAM_REMOTE_NAME" == "$FORK_REMOTE" ]]; then
    UPSTREAM_REMOTE_NAME="upstream"
fi

# --- derive fork path -------------------------------------------------------
if [[ -n "$FORK_REPO_OVERRIDE" ]]; then
    read -r _FORK_HOST FORK_PATH < <(parse_git_url "$FORK_REPO_OVERRIDE")
    if [[ "$_FORK_HOST" != "$UPSTREAM_HOST" ]]; then
        echo "ERROR: forkRepo host ($_FORK_HOST) differs from source host ($UPSTREAM_HOST). Cross-host forks are not supported by this script." >&2
        exit 1
    fi
elif [[ -n "$FORK_HOME_NAMESPACE" ]]; then
    read -r _FORK_HOST FORK_NAMESPACE < <(parse_fork_home_namespace "$FORK_HOME_NAMESPACE" "$UPSTREAM_HOST")
    if [[ "$_FORK_HOST" != "$UPSTREAM_HOST" ]]; then
        echo "ERROR: identity.homes.fork.namespace host ($_FORK_HOST) differs from source host ($UPSTREAM_HOST). Cross-host forks are not supported by this script." >&2
        exit 1
    fi
    FORK_PATH="${FORK_NAMESPACE}/${UPSTREAM_REPO_NAME}"
else
    echo "ERROR: identity.homes.fork.namespace is not set in ecosystem config." >&2
    echo "  Add 'identity.homes.fork.namespace: <host>/<group-path>' to ecosystem.local.yaml," >&2
    echo "  or set components.$COMPONENT.forkRepo for an exact one-off fork URL." >&2
    exit 1
fi

FORK_NAMESPACE="$(dirname "$FORK_PATH")"  # destination namespace for project creation
FORK_REPO_NAME="$(basename "$FORK_PATH")"

# --- token resolution (longest-prefix match) --------------------------------
# Token-walk lives in ws-realm.sh as `ws_resolve_token_var`. We pass the
# full "host/path" target (which the shared helper expects).

# Load .env before resolving tokens — the default-fallback below needs the
# token *values* visible, not just the var names. (ws dispatcher already
# sources .env, but ws-clone-fork.sh may be invoked directly.)
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ws_load_env "$ROOT_DIR/.env"

# Default-token fallback for the canonical hosts only — the same posture as
# git-auth.sh: gitlab-lookalike.example must never receive GITLAB_TOKEN via a
# default; only an explicit defaults.gitTokens mapping sends a token there.
DEFAULT_TOKEN_VAR=""
case "$UPSTREAM_HOST" in
    github.com) DEFAULT_TOKEN_VAR="GH_TOKEN" ;;
    gitlab.com) DEFAULT_TOKEN_VAR="GITLAB_TOKEN" ;;
esac

# An explicit gitTokens mapping always wins — even when its var is unset, in
# which case require_token reports exactly which var to fill. The provider
# default only covers targets with NO mapping; silently substituting it for a
# mapped-but-unset var could run fork creation under the wrong identity.
# (Deliberately stricter than git_auth_resolve_token's read-path fallback.)
resolve_token_var_with_default() {
    local target="$1"
    local var
    var=$(ws_resolve_token_var "$target")
    [[ "$var" == "null" ]] && var=""
    if [[ -n "$var" ]]; then
        echo "$var"
        return
    fi
    if [[ -n "$DEFAULT_TOKEN_VAR" && -n "${!DEFAULT_TOKEN_VAR:-}" ]]; then
        echo "$DEFAULT_TOKEN_VAR"
        return
    fi
    echo "$var"
}

UPSTREAM_TOKEN_VAR=$(resolve_token_var_with_default "$UPSTREAM_HOST/$UPSTREAM_PATH")
FORK_TOKEN_VAR=$(resolve_token_var_with_default "$UPSTREAM_HOST/$FORK_PATH")

require_token() {
    local var="$1"
    local purpose="$2"
    if [[ -z "$var" || "$var" == "null" ]]; then
        echo "ERROR: No gitTokens entry covers '$purpose' on $UPSTREAM_HOST." >&2
        echo "  Add an entry to defaults.gitTokens in ecosystem.local.yaml." >&2
        if [[ -n "$DEFAULT_TOKEN_VAR" ]]; then
            echo "  (Or set the $UPSTREAM_HOST default \$$DEFAULT_TOKEN_VAR in .env — no mapping needed.)" >&2
        fi
        exit 1
    fi
    local val="${!var:-}"
    if [[ -z "$val" ]]; then
        echo "ERROR: Env var \$$var is not set (needed for $purpose)." >&2
        echo "  Add 'export $var=<token>' to .env, then re-run." >&2
        exit 1
    fi
}

require_token "$UPSTREAM_TOKEN_VAR" "source-project read"
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
# --hostname is pinned to the source-project host explicitly. Without it,
# glab picks the instance from its own config or the cwd's git remote
# — which for a script targeting a specific upstream could silently
# hit the wrong GitLab (e.g. gitlab.com instead of a corporate one).
api_call() {
    local token_var="$1"; shift
    local token="${!token_var}"
    GITLAB_TOKEN="$token" glab api --hostname "$UPSTREAM_HOST" "$@"
}

# GitHub counterpart. GH_HOST pins the instance the same way --hostname does
# for glab. Paths carry no leading slash — Git Bash's MSYS layer rewrites
# /repos/... as a Windows filesystem path.
gh_api() {
    local token_var="$1"; shift
    local token="${!token_var}"
    GH_TOKEN="$token" GH_HOST="$UPSTREAM_HOST" gh api "$@"
}

# Provider-neutral project lookup. Emits GitLab-shaped JSON either way — the
# GitHub response is normalized to the field names the rest of this script
# already consumes (ssh_url_to_repo / http_url_to_repo / web_url /
# import_status), so everything downstream of the API layer stays provider-
# agnostic. GitHub has no import_status; an existing repo reads "finished",
# and a not-yet-materialized fork fails the fetch (the poll loop's retry case).
api_project() {
    local token_var="$1" path="$2"
    if [[ "$PROVIDER" == "github" ]]; then
        gh_api "$token_var" "repos/$path" \
            | jq '{id, default_branch, ssh_url_to_repo: .ssh_url, http_url_to_repo: .clone_url, web_url: .html_url, import_status: "finished"}'
    else
        api_call "$token_var" "projects/$(urlencode "$path")"
    fi
}

# Emit a one-click helper for the cross-group fork case and exit 2.
emit_cross_group_helper() {
    if [[ "$PROVIDER" == "github" ]]; then
        echo "" >&2
        echo "  Cross-group fork detected — manual step needed." >&2
        echo "" >&2
        echo "  Your fork-home token (\$$FORK_TOKEN_VAR) has rights on '$FORK_NAMESPACE'" >&2
        echo "  but no read access on source repo '$UPSTREAM_PATH' (private, or the" >&2
        echo "  token's scope/installation doesn't cover it). GitHub's fork flow needs" >&2
        echo "  one identity with read on the source and fork rights on the destination." >&2
        echo "" >&2
        echo "  Click here to fork in the GitHub UI (pick '$FORK_NAMESPACE' as the owner):" >&2
        echo "" >&2
        echo "    https://$UPSTREAM_HOST/$UPSTREAM_PATH/fork" >&2
        echo "" >&2
        echo "  Once the fork exists, re-run:" >&2
        echo "    ws clone-fork $COMPONENT" >&2
        echo "" >&2
        return
    fi

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
    echo "  '$FORK_NAMESPACE' but no read access on source project '$UPSTREAM_PATH'." >&2
    echo "  GitLab's fork API needs one identity with both rights." >&2
    echo "" >&2
    echo "  This can be automated by giving the fork token source-project read" >&2
    echo "  through public visibility, same-hierarchy access, or GitLab" >&2
    echo "  project/group sharing to the fork-home group. Access-token bot users" >&2
    echo "  cannot be invited directly to unrelated groups." >&2
    echo "" >&2
    echo "  Click here to fork in the GitLab UI:" >&2
    echo "" >&2
    echo "    $fork_url" >&2
    echo "" >&2
    echo "  In the fork form:" >&2
    echo "    Destination namespace: $FORK_NAMESPACE" >&2
    echo "    Project slug:          $UPSTREAM_REPO_NAME (default)" >&2
    echo "    Visibility:            match source project (default)" >&2
    echo "" >&2
    echo "  Once GitLab finishes the import (usually <1 minute), re-run:" >&2
    echo "    ws clone-fork $COMPONENT" >&2
    echo "" >&2
}

source_probe_denied() {
    local message="$1"
    # GitLab commonly hides private projects as 404 when the caller lacks
    # read access; some versions return 403. Those map to the cross-group
    # helper. Transport/tool/auth failures should surface as normal errors.
    [[ "$message" =~ (^|[^0-9])(403|404)([^0-9]|$) ]] && return 0
    [[ "$message" =~ [Nn]ot[[:space:]]+[Ff]ound ]] && return 0
    [[ "$message" =~ [Ff]orbidden ]] && return 0
    return 1
}

# --- ensure fork exists -----------------------------------------------------
echo "[ ws clone-fork: $COMPONENT ]"
echo "  Source   : $UPSTREAM_PATH on $UPSTREAM_HOST"
echo "  Fork     : $FORK_PATH"

echo ""
echo "  Step 1: check fork exists..."
FORK_DETAILS=""
if FORK_DETAILS=$(api_project "$FORK_TOKEN_VAR" "$FORK_PATH" 2>/dev/null); then
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
    fork_probe_result=""
    if ! fork_probe_result=$(api_project "$FORK_TOKEN_VAR" "$UPSTREAM_PATH" 2>"$ERR_TMP"); then
        fork_probe_error="$(cat "$ERR_TMP" 2>/dev/null || true)"
        rm -f "$ERR_TMP"
        fork_probe_message="${fork_probe_error}${fork_probe_result}"
        if source_probe_denied "$fork_probe_message"; then
            emit_cross_group_helper
            exit 2
        fi
        echo "ERROR: Fork token failed while probing source-project access." >&2
        [[ -n "$fork_probe_error" ]] && printf '%s\n' "$fork_probe_error" >&2
        [[ -n "$fork_probe_result" ]] && printf '%s\n' "$fork_probe_result" >&2
        exit 1
    fi
    rm -f "$ERR_TMP"

    if [[ "$PROVIDER" == "github" ]]; then
        # `gh repo fork` takes the destination org via --org; forking into the
        # token's own account must OMIT it (gh rejects --org naming a user).
        # Compare the fork-home namespace against the token's login to decide.
        fork_login=$(gh_api "$FORK_TOKEN_VAR" user 2>/dev/null | jq -r '.login // empty' || true)
        fork_login_lc=$(printf '%s' "$fork_login" | tr '[:upper:]' '[:lower:]')
        fork_namespace_lc=$(printf '%s' "$FORK_NAMESPACE" | tr '[:upper:]' '[:lower:]')
        fork_args=("$UPSTREAM_PATH" --clone=false)
        if [[ -n "$fork_namespace_lc" && "$fork_namespace_lc" != "$fork_login_lc" ]]; then
            fork_args+=(--org "$FORK_NAMESPACE")
        fi
        if ! GH_TOKEN="${!FORK_TOKEN_VAR}" GH_HOST="$UPSTREAM_HOST" gh repo fork "${fork_args[@]}" 2>"$ERR_TMP"; then
            echo "ERROR: Fork creation failed." >&2
            cat "$ERR_TMP" >&2
            rm -f "$ERR_TMP"
            exit 1
        fi
        rm -f "$ERR_TMP"
        FORK_DETAILS=""
    else
        # Get upstream project ID (needed for the GitLab fork API)
        local_upstream_details=""
        if ! local_upstream_details=$(api_project "$UPSTREAM_TOKEN_VAR" "$UPSTREAM_PATH" 2>"$ERR_TMP"); then
            echo "ERROR: Failed to fetch source project details." >&2
            cat "$ERR_TMP" >&2; rm -f "$ERR_TMP"
            exit 1
        fi
        rm -f "$ERR_TMP"
        UPSTREAM_ID=$(echo "$local_upstream_details" | jq -r '.id')
        if [[ -z "$UPSTREAM_ID" || "$UPSTREAM_ID" == "null" ]]; then
            echo "ERROR: Could not determine source project ID." >&2
            echo "$local_upstream_details" | head -20 >&2
            exit 1
        fi

        # POST /projects/:id/fork with namespace_path. When forkRepo gives the
        # fork a different slug, pass it explicitly so creation and polling use
        # the same project path.
        fork_create_result=""
        fork_create_err="$ERR_TMP"
        fork_create_args=(-X POST -f "namespace_path=$FORK_NAMESPACE")
        if [[ "$FORK_REPO_NAME" != "$UPSTREAM_REPO_NAME" ]]; then
            fork_create_args+=(-f "name=$FORK_REPO_NAME" -f "path=$FORK_REPO_NAME")
        fi
        if ! fork_create_result=$(api_call "$FORK_TOKEN_VAR" "projects/$UPSTREAM_ID/fork" "${fork_create_args[@]}" 2>"$fork_create_err"); then
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
    fi

    # Poll until the fork is fetchable and (GitLab) import_status reaches
    # "finished" — a GitHub fork has no import phase, so its first successful
    # fetch reads "finished" via the api_project normalization. Default is
    # 10 × 2s = 20s, which covers normal-size repos; heavier upstreams may
    # need more. WS_CLONE_FORK_POLL_ITERATIONS overrides the count without a
    # code change. A non-positive or non-numeric value falls back to 10.
    poll_max="${WS_CLONE_FORK_POLL_ITERATIONS:-10}"
    [[ "$poll_max" =~ ^[1-9][0-9]*$ ]] || poll_max=10
    echo "         Fork created; waiting for it to become available..."
    for ((i = 1; i <= poll_max; i++)); do
        sleep 2
        status_json=$(api_project "$FORK_TOKEN_VAR" "$FORK_PATH" 2>/dev/null || echo '{}')
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
    if ! local_upstream_details=$(api_project "$UPSTREAM_TOKEN_VAR" "$UPSTREAM_PATH" 2>"$ERR_TMP"); then
        echo "ERROR: Failed to fetch source project details." >&2
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

# Provider API payloads are untrusted input. Before any clone or remote sink,
# require the selected source and fork URLs to use a supported Git transport
# and to remain on the provider host derived from the configured source URL.
git_remote_validate "$FORK_REMOTE_URL" remote "$UPSTREAM_HOST"
git_remote_validate "$UPSTREAM_REMOTE_URL" remote "$UPSTREAM_HOST"

# --- clone or repair local checkout -----------------------------------------
TARGET="$COMPONENTS_DIR/$COMPONENT"
echo ""
echo "  Step 2: prepare local clone at $TARGET ..."

select_available_source_remote_name() {
    local target="$1"
    local base="$2"
    local source_url="$3"
    local candidate="$base"
    local suffix=2
    local existing_url
    while existing_url=$(git -C "$target" remote get-url "$candidate" 2>/dev/null); do
        if [[ "$existing_url" == "$source_url" ]]; then
            echo "$candidate"
            return 0
        fi
        candidate="${base}-${suffix}"
        suffix=$((suffix + 1))
    done
    echo "$candidate"
}

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
    if git -C "$TARGET" remote get-url "$FORK_REMOTE" &>/dev/null; then
        existing_url=$(git -C "$TARGET" remote get-url "$FORK_REMOTE")
        if [[ "$existing_url" != "$FORK_REMOTE_URL" ]]; then
            git -C "$TARGET" remote set-url "$FORK_REMOTE" "$FORK_REMOTE_URL"
            echo "         updated fork remote URL"
        fi
    else
        # Maybe origin still points at fork — rename it if so
        if git -C "$TARGET" remote get-url origin &>/dev/null; then
            existing_origin=$(git -C "$TARGET" remote get-url origin)
            if [[ "$existing_origin" == "$FORK_REMOTE_URL" ]]; then
                git -C "$TARGET" remote rename origin "$FORK_REMOTE"
                echo "         renamed origin → $FORK_REMOTE"
            else
                git -C "$TARGET" remote add "$FORK_REMOTE" "$FORK_REMOTE_URL"
                echo "         added fork remote: $FORK_REMOTE"
            fi
        else
            git -C "$TARGET" remote add "$FORK_REMOTE" "$FORK_REMOTE_URL"
            echo "         added fork remote: $FORK_REMOTE"
        fi
    fi

    selected_upstream_remote_name=$(select_available_source_remote_name "$TARGET" "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL")
    if [[ "$selected_upstream_remote_name" != "$UPSTREAM_REMOTE_NAME" ]]; then
        echo "         source remote '$UPSTREAM_REMOTE_NAME' already points elsewhere; using '$selected_upstream_remote_name'"
        UPSTREAM_REMOTE_NAME="$selected_upstream_remote_name"
    fi

    # Upstream remote
    if git -C "$TARGET" remote get-url "$UPSTREAM_REMOTE_NAME" &>/dev/null; then
        existing_up=$(git -C "$TARGET" remote get-url "$UPSTREAM_REMOTE_NAME")
        if [[ "$existing_up" != "$UPSTREAM_REMOTE_URL" ]]; then
            git -C "$TARGET" remote set-url "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
            echo "         updated source remote URL"
        fi
    else
        git -C "$TARGET" remote add "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
        echo "         added source remote: $UPSTREAM_REMOTE_NAME"
    fi
else
    # Fresh clone from fork
    echo "         CLONE: $FORK_REMOTE_URL → $TARGET (remote: $FORK_REMOTE)"
    GIT_AUTH_ENV=()
    git_auth_env_for_url "$FORK_REMOTE_URL"
    git_auth_run git clone --origin "$FORK_REMOTE" -- "$FORK_REMOTE_URL" "$TARGET"
    git -C "$TARGET" remote add "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
fi

# --- sync main with upstream ------------------------------------------------
echo ""
echo "  Step 3: sync local + fork main with source project ..."

GIT_AUTH_ENV=()
git_auth_env_for_url "$UPSTREAM_REMOTE_URL"
git_auth_run git -C "$TARGET" fetch "$UPSTREAM_REMOTE_NAME" --quiet

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
                echo "         fast-forwarded $DEFAULT_BRANCH ref to source project (without checkout)"
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
        echo "    - either push those commits to the source project as their own MRs, or discard them with a hard reset" >&2
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
if push_output=$(git_auth_run git -C "$TARGET" push "$FORK_REMOTE" "refs/heads/$DEFAULT_BRANCH:refs/heads/$DEFAULT_BRANCH" 2>&1); then
    push_ok=true
else
    push_ok=false
fi
printf '%s\n' "$push_output" | sed 's/^/         /'
if $push_ok; then
    echo "         ✓ fork $DEFAULT_BRANCH now matches source project"
else
    echo "         (push to fork $DEFAULT_BRANCH did not fast-forward — leaving fork main as is; clone retry will sync on next run)"
    # Don't fail the whole run on this; the local checkout is good.
fi

# --- summary ----------------------------------------------------------------
echo ""
echo "  Ready:"
echo "    $TARGET"
echo "    remotes: $FORK_REMOTE (fork), $UPSTREAM_REMOTE_NAME (source)"
echo "    $DEFAULT_BRANCH: synced with $UPSTREAM_REMOTE_NAME/$DEFAULT_BRANCH"
