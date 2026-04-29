#!/usr/bin/env bash
# ws-clone.sh — Clone ecosystem components or arbitrary repos into components/
#
# Usage:
#   ws-clone.sh <component>                          Clone a declared component
#   ws-clone.sh --all                                Clone all non-disabled components
#   ws-clone.sh --url <git-url> [--name <name>] [--add-eco]
#                                                    Clone an arbitrary repo
#     --name    Override the component directory name (default: derived from URL)
#     --add-eco Add the component to ecosystem.local.yaml as trusted
#
# Components are cloned into components/<component-name>/ as independent
# Git repos. If the directory already exists, it is skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source shared realm/merge functions
# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"


if ! command -v yq &>/dev/null; then
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

clone_component() {
    local name="$1"
    local eco="$2"

    # Validate component name (same pattern as ws_validate_component)
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
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

    echo "CLONE: $name -> $target (remote: $remote)"
    git clone --origin "$remote" "$repo_url" "$target"
}

clone_url() {
    local url="$1"
    local name="$2"
    local add_eco="$3"

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
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Derived name '$name' is not a valid component name." >&2
        echo "  Use --name <name> to specify a valid one (lowercase, alphanumeric, hyphens, dots)." >&2
        exit 1
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
        git clone --origin "$remote" "$url" "$target"
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
        echo "  Use 'ws clone --url <url> --add-eco' to add it, or add manually."
        echo "  Without ecosystem config, ws commands won't recognize this component."
    fi
}

# Parse arguments
URL=""
NAME=""
ADD_ECO="false"

# Help mode — print usage and exit before any arg validation.
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage:
  ws clone <component>                          Clone a declared ecosystem component
  ws clone --all                                Clone all non-disabled components
  ws clone --url <git-url> [--name <name>] [--add-eco]
                                                Clone an arbitrary repo
    --name     Override the component directory name (default: derived from URL)
    --add-eco  Add the component to ecosystem.local.yaml as trusted

Components are cloned into components/<component-name>/ as independent
Git repos. If the directory already exists, it is skipped.
HELP
    exit 0
fi

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
            --add-eco) ADD_ECO="true" ;;
            *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$URL" ]]; then
        echo "Usage: ws-clone.sh --url <git-url> [--name <name>] [--add-eco]" >&2
        exit 1
    fi

    clone_url "$URL" "$NAME" "$ADD_ECO"
elif [[ "${1:-}" == "--all" ]]; then
    ECO="$(ws_resolve_ecosystem)"
    comp_count=$(yq '.components | length' "$ECO" 2>/dev/null || echo 0)
    if [[ "$comp_count" -eq 0 ]]; then
        echo "No components declared." >&2
        echo "  Run 'ws realm init' to get started, or 'ws realm <url>' for your community." >&2
        exit 1
    fi
    for name in $(yq '.components | keys | .[]' "$ECO"); do
        clone_component "$name" "$ECO"
    done
elif [[ -n "${1:-}" ]]; then
    ECO="$(ws_resolve_ecosystem)"
    if [[ "$(yq ".components[\"${1}\"] // \"missing\"" "$ECO")" == "missing" ]]; then
        echo "ERROR: '$1' is not declared in ecosystem config." >&2
        echo "  Use 'ws clone --url <git-url>' for repos not in the ecosystem." >&2
        exit 1
    fi
    clone_component "$1" "$ECO"
else
    echo "Usage: ws-clone.sh <component> | --all | --url <git-url> [--name <name>] [--add-eco]" >&2
    exit 1
fi
