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

# shellcheck source=ws-env.sh
source "$_GP_SCRIPT_DIR/ws-env.sh"
# shellcheck source=git-remote.sh
source "$_GP_SCRIPT_DIR/git-remote.sh"
# shellcheck source=git-auth.sh
source "$_GP_SCRIPT_DIR/git-auth.sh"

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

# Percent-encode a string for a URL query value: everything outside the RFC
# 3986 unreserved set (A-Z a-z 0-9 - _ . ~) becomes %XX. Keeps deep-link
# descriptions/names safe even with &, ?, #, +, =, %, or spaces in them.
_gp_urlencode() {
    local s="$1" out="" i c
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [A-Za-z0-9._~-]) out+="$c" ;;
            *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

# Build a deep-link URL to create a personal access token with the scopes
# ws push / cr / review need pre-selected, so the user lands on a page with
# the right boxes already checked instead of guessing. The scope + name/
# description query params are honored by github.com and GitHub Enterprise,
# and by gitlab.com and self-hosted GitLab. On an unrecognized provider it
# falls back to the host root so the link still goes somewhere useful.
# Usage: gp_pat_create_url PROVIDER HOST [DESCRIPTION]
gp_pat_create_url() {
    local provider="$1" host="$2" desc="${3:-GDD}"
    local enc
    enc=$(_gp_urlencode "$desc")
    case "$provider" in
        github)
            # Classic PAT. `repo` covers push + PR creation; the read:* scopes are
            # the recommended baseline (docs/git-provider-setup.md) that keep
            # `gh pr edit`-shaped ops from failing with a read:org scope error.
            printf 'https://%s/settings/tokens/new?scopes=repo,read:org,read:discussion,read:project&description=%s' "$host" "$enc"
            ;;
        gitlab)
            # `api` (MR creation) + `write_repository` (git push over HTTPS).
            printf 'https://%s/-/user_settings/personal_access_tokens?name=%s&scopes=api,write_repository' "$host" "$enc"
            ;;
        *)
            printf 'https://%s' "$host"
            ;;
    esac
}

# True (rc 0) if VALUE is one of the literal sample token values shipped in .env.example, so `ws diagnose` can flag "you left the placeholder" instead of reporting it as a real token. Exact match only — no heuristics.
gp_token_is_placeholder() {
    case "$1" in
        ghp_xxxxxxxxxxxx|glpat-xxxxxxxxxxxx) return 0 ;;
        *) return 1 ;;
    esac
}

# Render provider diagnostics as a bounded, terminal-safe single line. The optional secret is removed with literal bash substring operations so it is never passed through another process's argv or interpreted as a pattern.
gp_api_error_one_line() {
    local msg="$1" secret="${2:-}" prefix suffix
    msg="${msg//$'\r'/ }"
    msg="${msg//$'\n'/ }"
    msg="${msg//$'\t'/ }"
    msg="$(printf '%s' "$msg" | tr -d '\000-\010\013-\037\177')"
    if [[ -n "$secret" ]]; then
        while [[ "$msg" == *"$secret"* ]]; do
            prefix="${msg%%"$secret"*}"
            suffix="${msg#*"$secret"}"
            msg="${prefix}[redacted]${suffix}"
        done
    fi
    while [[ "$msg" == *"  "* ]]; do msg="${msg//  / }"; done
    msg="${msg#"${msg%%[![:space:]]*}"}"
    msg="${msg%"${msg##*[![:space:]]}"}"
    if [[ ${#msg} -gt 240 ]]; then
        msg="${msg:0:237}..."
    fi
    printf '%s' "$msg"
}

# Classify a provider/API failure without treating a generic non-zero exit as credential rejection. Output is intentionally provider-neutral so diagnose, review, and future callers share the same decision boundary.
gp_api_error_classify() {
    local rc="$1" msg="$2" normalized
    if [[ "$rc" -eq 124 ]]; then
        echo "transport"
        return 0
    fi
    normalized="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
        *"http 401"*|*"http 403"*|*"401 unauthorized"*|*"403 forbidden"*|*"status code 401"*|*"status code 403"*)
            echo "auth"
            ;;
        *"http 404"*|*"404 not found"*|*"status code 404"*)
            echo "not_found"
            ;;
        *"dial tcp"*|*"no such host"*|*"could not resolve host"*|*"temporary failure in name resolution"*|*"network is unreachable"*|*"error connecting"*|*"failed to connect"*|*"connection refused"*|*"connection reset"*|*"tls handshake"*|*"certificate verify failed"*|*"context deadline exceeded"*|*"operation timed out"*|*"i/o timeout"*)
            echo "transport"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Best-effort token validity probe. Echoes the account login on success (rc 0); rc 1 = explicit provider authentication/scope rejection; rc 2 = unsupported or unavailable CLI; rc 3 = transport or otherwise indeterminate failure, with a sanitized diagnostic. Never prints the token itself.
# Usage: gp_token_api_login PROVIDER HOST TOKEN
gp_token_api_login() {
    local provider="$1" host="$2" tok="$3"
    # Portable, optional timeout so a slow or unreachable network can't hang the probe. Absent on stock macOS (no coreutils) — then we run without it.
    local -a to=()
    if command -v timeout >/dev/null 2>&1; then to=(timeout 10)
    elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout 10)
    fi
    local out rc parsed class reason diagnostic stderr_file stderr_out
    case "$provider" in
        github)
            command -v gh >/dev/null 2>&1 || return 2
            if ! stderr_file=$(mktemp "${TMPDIR:-/tmp}/gdd-provider-stderr.XXXXXX"); then
                printf '%s' "could not create temporary provider diagnostic file"
                return 3
            fi
            out=$(env GH_TOKEN="$tok" GH_HOST="$host" GH_NO_UPDATE_NOTIFIER=1 ${to[@]+"${to[@]}"} gh api user --jq .login 2>"$stderr_file")
            rc=$?
            ;;
        gitlab)
            command -v glab >/dev/null 2>&1 || return 2
            command -v jq >/dev/null 2>&1 || return 2
            if ! stderr_file=$(mktemp "${TMPDIR:-/tmp}/gdd-provider-stderr.XXXXXX"); then
                printf '%s' "could not create temporary provider diagnostic file"
                return 3
            fi
            out=$(env GITLAB_TOKEN="$tok" GITLAB_HOST="$host" GLAB_CHECK_UPDATE=false ${to[@]+"${to[@]}"} glab api user 2>"$stderr_file")
            rc=$?
            ;;
        *)
            return 2
            ;;
    esac
    stderr_out="$(<"$stderr_file")"
    rm -f "$stderr_file"
    if [[ $rc -ne 0 ]]; then
        diagnostic="$stderr_out"
        [[ -n "$diagnostic" ]] || diagnostic="$out"
        class="$(gp_api_error_classify "$rc" "$diagnostic")"
        reason="$(gp_api_error_one_line "$diagnostic" "$tok")"
        if [[ "$class" == "auth" ]]; then
            return 1
        fi
        if [[ -z "$reason" ]]; then
            if [[ "$class" == "transport" ]]; then
                reason="provider API probe timed out or could not connect"
            else
                reason="provider CLI exited $rc without details"
            fi
        fi
        printf '%s' "$reason"
        return 3
    fi

    if [[ "$provider" == "gitlab" ]]; then
        if ! parsed=$(printf '%s' "$out" | jq -r '.username // empty' 2>/dev/null); then
            printf '%s' "provider returned an invalid user response"
            return 3
        fi
        out="$parsed"
    fi
    out="$(gp_api_error_one_line "$out")"
    if [[ -z "$out" ]]; then
        printf '%s' "provider returned an empty user response"
        return 3
    fi
    printf '%s' "$out"
}

# Load a provider implementation by name.
# Usage: gp_load PROVIDER
gp_load() {
    local provider="$1"
    if [[ ! "$provider" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: Invalid provider name '$provider'." >&2
        echo "  Provider names must contain only letters, digits, dashes, and underscores." >&2
        return 1
    fi
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
    local provider host
    provider=$(gp_detect "$@") || return 1
    gp_load "$provider" || return 1

    # Provider CLIs accept owner/repo slugs that do not encode the host. Pin their API authority from the already-selected remote so enterprise provider calls cannot silently fall back to a public host.
    host="$(git_remote_host "$1")" || return 1
    case "$provider" in
        github) export GH_HOST="$host" ;;
        gitlab) export GITLAB_HOST="$host" ;;
    esac
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

    local normalized
    normalized="$(git_auth_normalize_url "$url")"

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
        ws_require_provider_token_var "$best_var" || return 1
        local token_value="${!best_var:-}"
        if [[ -n "$token_value" ]]; then
            export GITLAB_TOKEN="$token_value"
        else
            echo "WARNING: gitTokens maps '$normalized' to env var '$best_var', but it is not set." >&2
            echo "  Add it to .env (see docs/git-provider-setup.md)." >&2
        fi
    fi
}
