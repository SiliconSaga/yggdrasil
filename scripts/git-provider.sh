#!/usr/bin/env bash
# git-provider.sh — Git provider detection and dispatch
#
# Source this file from scripts that need provider-specific operations.
# Provides:
#   gp_detect URL           — detect provider from a remote URL (prints: github, gitlab, ...)
#   gp_load PROVIDER        — load a provider implementation
#   gp_check_cli            — verify CLI tool is installed (delegates to loaded provider)
#   gp_extract_slug URL     — extract org/repo slug from URL (delegates to loaded provider)
#   gp_create_pr ARGS       — create PR/MR (delegates to loaded provider)
#   gp_create_issue ARGS    — file an issue (delegates to loaded provider)
#   gp_default_branch SLUG  — query default branch (delegates to loaded provider)
#
# Provider detection order (gp_detect):
#   1. defaults.gitProviders.<domain> mapping in ecosystem config
#   2. Auto-detect from remote URL domain (github.com, gitlab.com)
#   3. defaults.gitProvider workspace-wide default in ecosystem config
#   4. Fail with error
#
# Per-component gitProvider overrides are handled by callers before
# invoking gp_detect (see design spec for the full 5-step order).

_GP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GP_LOADED_PROVIDER=""

# Detect provider from a remote URL.
# Usage: gp_detect URL [ECOSYSTEM_FILE]
#   URL             — git remote URL (https or ssh)
#   ECOSYSTEM_FILE  — optional path to merged ecosystem config (for config-based detection)
# Prints the provider name to stdout (e.g., "github", "gitlab").
gp_detect() {
    local url="$1"
    local eco="${2:-}"

    # Extract domain from URL
    local domain=""
    if [[ "$url" =~ ^ssh://[^@]*@([^:/]+) ]]; then
        domain="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^https?://([^/:]+) ]]; then
        domain="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^git@([^:]+): ]]; then
        domain="${BASH_REMATCH[1]}"
    fi

    # Step 2: Check defaults.gitProviders.<domain> mapping
    if [[ -n "$eco" && -n "$domain" ]]; then
        local mapped
        mapped=$(DOMAIN="$domain" yq '.defaults.gitProviders[strenv(DOMAIN)] // ""' "$eco" 2>/dev/null)
        if [[ -n "$mapped" && "$mapped" != "null" ]]; then
            echo "$mapped"
            return
        fi
    fi

    # Step 3: Auto-detect from well-known domains
    case "$domain" in
        github.com)  echo "github"; return ;;
        gitlab.com)  echo "gitlab"; return ;;
    esac

    # Step 4: Workspace-wide default
    if [[ -n "$eco" ]]; then
        local default_provider
        default_provider=$(yq '.defaults.gitProvider // ""' "$eco" 2>/dev/null)
        if [[ -n "$default_provider" && "$default_provider" != "null" ]]; then
            echo "$default_provider"
            return
        fi
    fi

    # Step 5: Fail
    echo "ERROR: Cannot detect git provider for URL: $url" >&2
    echo "  Domain: ${domain:-(unknown)}" >&2
    echo "  Set defaults.gitProvider or defaults.gitProviders.$domain in ecosystem config." >&2
    return 1
}

# Load a provider implementation by name.
# Usage: gp_load PROVIDER
gp_load() {
    local provider="$1"
    if [[ "$_GP_LOADED_PROVIDER" == "$provider" ]]; then
        return 0
    fi

    local provider_file="$_GP_SCRIPT_DIR/providers/${provider}.sh"
    if [[ ! -f "$provider_file" ]]; then
        echo "ERROR: No provider implementation for '$provider'." >&2
        echo "  Expected: $provider_file" >&2
        local _providers=""
        for _f in "$_GP_SCRIPT_DIR/providers/"*.sh; do
            [[ -f "$_f" ]] && _providers+="$(basename "$_f" .sh) "
        done
        echo "  Available providers: ${_providers:-none}" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$provider_file"
    _GP_LOADED_PROVIDER="$provider"
}

# Convenience: detect + load in one call.
# Usage: gp_detect_and_load URL [ECOSYSTEM_FILE]
gp_detect_and_load() {
    local provider
    provider=$(gp_detect "$@") || return 1
    gp_load "$provider"
}

# Select and export the appropriate authentication token for a URL.
# Reads defaults.gitTokens from ecosystem config using longest-prefix match.
# For GitLab: exports GITLAB_TOKEN. No-op for GitHub (uses GH_TOKEN directly).
# Usage: gp_set_token_for_url URL [ECO]
gp_set_token_for_url() {
    local url="$1"
    local eco="${2:-}"

    [[ -z "$eco" ]] && return 0

    local map_count
    map_count=$(yq '.defaults.gitTokens | length' "$eco" 2>/dev/null || echo 0)
    [[ "$map_count" -eq 0 ]] && return 0

    # Normalize URL: strip protocol, embedded credentials, .git suffix
    # Use explicit http/https patterns — \? is GNU sed only, not macOS BSD sed
    # ssh://user@host:port/path → host/path  (BRE: capture host, discard port)
    # git@host:path            → host/path
    # https://host/path        → host/path
    local normalized
    normalized=$(echo "$url" \
        | sed 's|^ssh://[^@]*@\([^:/]*\)[^/]*/|\1/|; s|^https://[^@]*@||; s|^http://[^@]*@||; s|^https://||; s|^http://||; s|^git@\([^:]*\):|/\1/|; s|^/||; s|\.git$||; s|/$||')

    # Find the longest matching key (most-specific group path wins)
    local best_var="" best_len=0
    while IFS= read -r key; do
        [[ -z "$key" || "$key" == "null" ]] && continue
        local key_len=${#key}
        if [[ ( "$normalized" == "${key}/"* || "$normalized" == "$key" ) && $key_len -gt $best_len ]]; then
            best_len=$key_len
            best_var=$(KEY="$key" yq '.defaults.gitTokens[strenv(KEY)] // ""' "$eco" 2>/dev/null)
        fi
    done < <(yq '.defaults.gitTokens | keys | .[]' "$eco" 2>/dev/null)

    if [[ -n "$best_var" && "$best_var" != "null" ]]; then
        local token_value="${!best_var:-}"
        if [[ -n "$token_value" ]]; then
            export GITLAB_TOKEN="$token_value"
        else
            echo "WARNING: gitTokens maps '$normalized' to env var '$best_var', but it is not set." >&2
            echo "  Add it to .env (see docs/git-provider-setup.md)." >&2
        fi
    fi
}
