#!/usr/bin/env bash
# ws-clone.sh — Clone ecosystem components or arbitrary repos into components/
# ws:use-when materializing a component locally from its declared remote
#
# Usage:
#   ws-clone.sh <component>                          Clone a declared component
#   ws-clone.sh --all                                Clone all non-disabled components
#   ws-clone.sh --url <git-url> [--name <name>] [--add-to-ecosystem]
#                                                    Clone an arbitrary repo
#     --name               Override the component directory name (default: derived from URL)
#     --add-to-ecosystem   Add the component to ecosystem.local.yaml as trusted
#     --add-eco            Compatibility alias for --add-to-ecosystem
#
# Components are cloned into components/<component-name>/ as independent
# Git repos. If the directory already exists, it is skipped.

set -euo pipefail

# Help short-circuit BEFORE any dependency check — fresh machines
# without yq still need to be able to read the help text. Detect
# --help/-h ANYWHERE in args so `ws clone <component> --help` and
# `ws clone --url <url> --help` both work, matching the style used
# by ws push / ws actions / ws pull.
for _arg in "$@"; do
    if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
        cat <<'HELP'
Usage:
  ws clone <component>                          Clone a declared ecosystem component
  ws clone --all                                Clone all non-disabled components
  ws clone --url <git-url> [--name <name>] [--add-to-ecosystem]
                                                Clone an arbitrary repo
    --name               Override the component directory name (default: derived from URL)
    --add-to-ecosystem   Add the component to ecosystem.local.yaml as trusted
    --add-eco            Compatibility alias for --add-to-ecosystem

Components are cloned into components/<component-name>/ as independent
Git repos. If the directory already exists, it is skipped.
HELP
        exit 0
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source shared realm/merge functions
# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"


if ! type -P yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

# Extract org name from a Git URL for use as the remote name.
# e.g., https://github.com/MovingBlocks/repo.git        -> MovingBlocks
#       git@github.com:SiliconSaga/repo.git              -> SiliconSaga
#       https://gitlab.com/MyOrg/repo.git                -> MyOrg
#       https://gitlab.example.com/group/subgroup/repo   -> subgroup
remote_name_from_url() {
    local url="$1"
    local path=""

    if [[ "$url" =~ ^https?://[^/]+(/.+)$ ]]; then
        path="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^git@[^:]+:(.+)$ ]]; then
        path="/${BASH_REMATCH[1]}"
    else
        echo "origin"
        return
    fi

    # Strip leading slash, credentials, and .git suffix; split on /
    path="${path#/}"
    path="${path%.git}"
    path="${path%%@*}"   # defensive: truncate if @ appears in path portion
    IFS='/' read -ra parts <<< "$path"

    # Use the second-to-last segment (the immediate group/org before the repo name).
    # For flat orgs (github.com/Org/repo) this is the org.
    # For nested groups (gitlab.com/group/subgroup/repo) this is the subgroup.
    local n=${#parts[@]}
    if [[ $n -ge 2 ]]; then
        echo "${parts[$((n-2))]}"
    elif [[ $n -eq 1 ]]; then
        echo "${parts[0]}"
    else
        echo "origin"
    fi
}

# Redact credentials from a URL for safe logging.
# e.g., https://user:token@github.com/... -> https://***@github.com/...
redact_url() {
    echo "$1" | sed 's|://[^@]*@|://***@|'
}

# Normalize a validated remote for repository-identity comparisons. This is
# deliberately separate from git_auth_normalize_url: credential routing may
# ignore SSH details that are material when deciding whether two URLs name the
# same repository. The conventional `git` SSH user and protocol-default ports
# are transport details; other usernames and non-default ports are retained.
repository_identity_from_url() {
    local url="$1" scheme="" rest="" authority="" hostport=""
    local user="" host="" port="" path="" suffix=""

    case "$url" in
        https://*|ssh://*)
            scheme="${url%%://*}"
            rest="${url#*://}"
            authority="${rest%%/*}"
            path="${rest#*/}"
            hostport="$authority"
            if [[ "$scheme" == "ssh" && "$hostport" == *@* ]]; then
                user="${hostport%%@*}"
                hostport="${hostport#*@}"
            elif [[ "$scheme" == "https" && "$hostport" == *@* ]]; then
                # HTTPS userinfo is credentials, never repository identity.
                # Unreachable in practice — git_remote_validate refuses
                # embedded-credential URLs before any identity comparison —
                # but stripped here so this helper stays standalone-correct.
                hostport="${hostport#*@}"
            fi
            if [[ "$hostport" == \[*\]* ]]; then
                host="${hostport#\[}"
                host="${host%%\]*}"
                suffix="${hostport#*\]}"
                [[ "$suffix" == :* ]] && port="${suffix#:}"
            elif [[ "$hostport" == *:* ]]; then
                host="${hostport%%:*}"
                port="${hostport#*:}"
            else
                host="$hostport"
            fi
            if [[ ( "$scheme" == "https" && "$port" == "443" ) || ( "$scheme" == "ssh" && "$port" == "22" ) ]]; then
                port=""
            fi
            ;;
        *)
            if [[ "$url" =~ ^([^@/:]+@)?([^@/:]+):(.+)$ ]]; then
                user="${BASH_REMATCH[1]%@}"
                host="${BASH_REMATCH[2]}"
                path="${BASH_REMATCH[3]}"
                scheme="ssh"
            else
                printf 'local:%s\n' "$url"
                return 0
            fi
            ;;
    esac

    host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    [[ "$host" == *:* ]] && host="[$host]"
    path="${path#/}"
    while [[ "$path" == */ ]]; do
        path="${path%/}"
    done
    path="${path%.git}"
    [[ "$user" == "git" ]] && user=""
    [[ -n "$user" ]] && user="${user}@"
    [[ -n "$port" ]] && port=":${port}"
    printf 'repo:%s%s%s/%s\n' "$user" "$host" "$port" "$path"
}

# Explicit clones need declarations from authorities whose trust is current.
# Root and operator-local config are always available; realm declarations join
# the comparison only while the selected realm's approval still matches.
explicit_clone_ecosystem() {
    local active_realm trust_state
    active_realm="$(ws_detect_realm)"
    if [[ -n "$active_realm" ]]; then
        trust_state="$(ws_realm_trust_state "$active_realm")"
        if [[ "$trust_state" == "current" ]]; then
            ws_resolve_ecosystem
            return
        fi
    fi
    ws_resolve_local_ecosystem
}

clone_component() {
    local name="$1"
    local eco="$2"

    # Validate component name (same pattern as ws_resolve_target)
    if ! ws_component_name_is_valid "$name"; then
        echo "SKIP: $name (invalid component name)"
        return 0
    fi

    local target="$COMPONENTS_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        echo "SKIP: $name (already cloned at $target)"
        return 0
    fi

    local disabled
    disabled=$(COMPONENT_NAME="$name" yq '.components[strenv(COMPONENT_NAME)].disabled // false' "$eco")
    if [[ "$disabled" == "true" ]]; then
        echo "SKIP: $name (disabled)"
        return 0
    fi

    # Prefer explicit repo URL if set, otherwise build from gitOrg
    local repo_url
    repo_url=$(COMPONENT_NAME="$name" yq '.components[strenv(COMPONENT_NAME)].repo // ""' "$eco")
    if [[ -z "$repo_url" || "$repo_url" == "null" ]]; then
        local git_org
        git_org=$(yq '.defaults.gitOrg // ""' "$eco")
        git_org="${git_org%/}"
        if [[ -z "$git_org" || "$git_org" == "null" ]]; then
            echo "ERROR: No repo URL or defaults.gitOrg set for '$name'." >&2
            return 1
        fi
        repo_url="$git_org/$name.git"
    fi

    local remote
    remote=$(remote_name_from_url "$repo_url")

    git_remote_validate "$repo_url" remote

    echo "CLONE: $name -> $target (remote: $remote)"
    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    git_auth_env_for_url "$repo_url"
    git_auth_run git clone --filter=blob:none --origin "$remote" -- "$repo_url" "$target"
}

clone_url() {
    local url="$1"
    local name="$2"
    local add_eco="$3"

    git_remote_validate "$url" local

    # Derive name from URL if not specified, lowercased
    if [[ -z "$name" ]]; then
        name=$(echo "$url" | sed 's|.*/||; s|\.git$||' | tr '[:upper:]' '[:lower:]')
    fi

    # Validate derived name against the safe component pattern
    if [[ -z "$name" ]]; then
        echo "ERROR: Could not derive component name from URL: $url" >&2
        echo "  Use --name <name> to specify one." >&2
        exit 1
    fi
    if ! ws_component_name_is_valid "$name"; then
        echo "ERROR: Derived name '$name' is not a valid component name." >&2
        echo "  Use --name <name> to specify a valid one (lowercase, alphanumeric, hyphens, dots)." >&2
        exit 1
    fi

    # An explicit URL clone must not occupy the identity of a component that
    # the merged ecosystem already declares. Protocol-equivalent URLs compare
    # by normalized host/path so the declared HTTPS repo can still be cloned
    # over SSH; a different repo must use a unique name.
    local eco component_declared declared_repo git_org declared_norm requested_norm
    eco="$(explicit_clone_ecosystem)"
    component_declared=$(COMPONENT_NAME="$name" yq -r '.components[strenv(COMPONENT_NAME)] != null' "$eco")
    if [[ "$component_declared" == "true" ]]; then
        declared_repo=$(COMPONENT_NAME="$name" yq -r '.components[strenv(COMPONENT_NAME)].repo // ""' "$eco")
        if [[ -z "$declared_repo" ]]; then
            git_org=$(yq -r '.defaults.gitOrg // ""' "$eco")
            [[ -n "$git_org" ]] && declared_repo="${git_org%/}/$name.git"
        fi
        if [[ -z "$declared_repo" ]]; then
            echo "ERROR: '$name' is a declared component without a repository URL." >&2
            echo "  Configure its repository and use 'ws clone $name', or choose a unique --name." >&2
            exit 1
        fi
        git_remote_validate "$declared_repo" remote
        declared_norm="$(repository_identity_from_url "$declared_repo")"
        requested_norm="$(repository_identity_from_url "$url")"
        if [[ "$declared_norm" != "$requested_norm" ]]; then
            echo "ERROR: '$name' is a declared component for a different repository." >&2
            echo "  Use 'ws clone $name' for the declared component or choose a unique --name." >&2
            exit 1
        fi
    fi

    local target="$COMPONENTS_DIR/$name"
    local safe_url
    safe_url=$(redact_url "$url")

    if [[ -d "$target/.git" ]]; then
        echo "SKIP: $name (already cloned at $target)"
    else
        local remote
        remote=$(remote_name_from_url "$url")

        echo "CLONE: $safe_url -> $target (remote: $remote)"
        local -a GIT_AUTH_ENV=()
        local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
        git_auth_env_for_url "$url"
        git_auth_run git clone --filter=blob:none --origin "$remote" -- "$url" "$target"
    fi

    if [[ "$add_eco" == "true" ]]; then
        local local_config="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"

        # Ensure ecosystem.local.yaml exists — copy from example template if available
        if [[ ! -f "$local_config" ]]; then
            local example="$ROOT_DIR/ecosystem.local.yaml.example"
            if [[ -f "$example" ]]; then
                cp "$example" "$local_config"
                echo "Created ecosystem.local.yaml from example template."
            else
                echo "identity:" > "$local_config"
            fi
        fi

        # Canonicalize local paths before storing (portable fallback for macOS)
        local stored_url="$url"
        if [[ ! "$url" =~ ^(git@|https?://) ]]; then
            if command -v realpath &>/dev/null; then
                stored_url=$(realpath "$url")
            else
                stored_url=$(cd "$(dirname "$url")" && pwd)/$(basename "$url")
            fi
            # Pin the stored form on Git Bash: MSYS env conversion rewrites a
            # POSIX /c/… value when the native yq spawns, so without an
            # explicit choice the recorded form is platform-accidental.
            # ws_native_path yields the C:/… mixed form both git and native
            # tools accept; on POSIX hosts it is a no-op.
            stored_url=$(ws_native_path "$stored_url")
        fi

        # Add component entry with repo URL for future re-cloning (use strenv for safe interpolation)
        COMPONENT_NAME="$name" REPO_URL="$stored_url" \
            yq -i '
                .components[strenv(COMPONENT_NAME)].tier = "supporting" |
                .components[strenv(COMPONENT_NAME)].repo = strenv(REPO_URL)
            ' "$local_config"
        echo "ADDED: $name to ecosystem.local.yaml (tier: supporting, repo: $safe_url)"
        echo "  Edit $local_config to adjust tier or add config."
    else
        echo ""
        echo "NOTE: $name is not in the ecosystem config."
        echo "  Use 'ws clone --url <url> --add-to-ecosystem' to add it, or add manually."
        echo "  Without ecosystem config, ws commands won't recognize this component."
    fi
}

# Parse arguments
URL=""
NAME=""
ADD_ECO="false"

# Check for --url mode
if [[ "${1:-}" == "--url" ]]; then
    shift
    URL="${1:-}"
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                shift
                NAME="${1:-}"
                if [[ -z "$NAME" ]]; then
                    echo "ERROR: --name requires a value" >&2
                    exit 1
                fi
                ;;
            --add-to-ecosystem|--add-eco) ADD_ECO="true" ;;
            *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$URL" ]]; then
        echo "Usage: ws-clone.sh --url <git-url> [--name <name>] [--add-to-ecosystem]" >&2
        exit 1
    fi

    clone_url "$URL" "$NAME" "$ADD_ECO"
elif [[ "${1:-}" == "--all" ]]; then
    ECO="$(ws_resolve_ecosystem)"
    ws_validate_component_keys "$ECO" || exit 1
    comp_count=$(yq '.components | length' "$ECO" 2>/dev/null || echo 0)
    if [[ "$comp_count" -eq 0 ]]; then
        echo "No components declared." >&2
        echo "  Run 'ws realm init' to get started, or 'ws realm <url>' for your community." >&2
        exit 1
    fi
    while IFS= read -r name; do
        clone_component "$name" "$ECO"
    done < <(yq -r '.components | keys | .[]' "$ECO")
elif [[ -n "${1:-}" ]]; then
    ECO="$(ws_resolve_ecosystem)"
    if [[ "$(COMPONENT_NAME="$1" yq '.components[strenv(COMPONENT_NAME)] // "missing"' "$ECO")" == "missing" ]]; then
        echo "ERROR: '$1' is not declared in ecosystem config." >&2
        echo "  Use 'ws clone --url <git-url>' for repos not in the ecosystem." >&2
        exit 1
    fi
    clone_component "$1" "$ECO"
else
    echo "Usage: ws-clone.sh <component> | --all | --url <git-url> [--name <name>] [--add-to-ecosystem]" >&2
    exit 1
fi
