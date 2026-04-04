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
# Provider detection order:
#   1. Per-component gitProvider in ecosystem config (caller passes it)
#   2. defaults.gitProviders.<domain> mapping in ecosystem config
#   3. Auto-detect from remote URL domain (github.com, gitlab.com)
#   4. defaults.gitProvider workspace-wide default in ecosystem config
#   5. Fail with error

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
    if [[ "$url" =~ ^https?://([^/]+)/ ]]; then
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
