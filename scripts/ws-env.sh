#!/usr/bin/env bash
# Shared literal .env loading and provider-token variable policy.

ws_load_env() {
    local env_file="$1"
    [[ -f "$env_file" ]] || return 0

    local line line_number=0 key raw_value value quote
    local assignment_re='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ $assignment_re ]]; then
            echo "ERROR: invalid .env line $line_number in $env_file; expected KEY=value or export KEY=value." >&2
            return 1
        fi

        key="${BASH_REMATCH[2]}"
        raw_value="${BASH_REMATCH[3]}"
        case "$key" in
            PATH|LD_PRELOAD|LD_LIBRARY_PATH|DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|BASH_ENV|ENV|IFS|PS4|PROMPT_COMMAND|SHELLOPTS|BASHOPTS)
                echo "ERROR: refusing to set reserved variable '$key' from .env line $line_number in $env_file." >&2
                return 1
                ;;
        esac
        while [[ "$raw_value" == [[:space:]]* ]]; do raw_value="${raw_value#?}"; done
        while [[ "$raw_value" == *[[:space:]] ]]; do raw_value="${raw_value%?}"; done

        value="$raw_value"
        if [[ "$raw_value" == \"* || "$raw_value" == \'* ]]; then
            quote="${raw_value:0:1}"
            if [[ ${#raw_value} -lt 2 || "${raw_value: -1}" != "$quote" ]]; then
                echo "ERROR: invalid .env line $line_number in $env_file; quoted value is not closed." >&2
                return 1
            fi
            value="${raw_value:1:${#raw_value}-2}"
        fi

        printf -v "$key" '%s' "$value"
        export "$key"
    done < "$env_file"
}

# Provider-token names are prefix-allowlisted so a gitTokens mapping can only
# ever name a variable that exists to hold a git-provider token — it must not
# be able to route an arbitrary secret (AWS_SECRET_ACCESS_KEY, ...) into git
# auth. GITHUB_*/GH_* get the same namespaced freedom as GITLAB_*, which
# multi-org GitHub setups need (e.g. an org bot token plus a personal PAT
# mapped to different namespaces).
ws_is_provider_token_var() {
    local name="$1"
    [[ "$name" =~ ^(GITLAB|GITHUB|GH)_[A-Z0-9_]+$ ]]
}

ws_require_provider_token_var() {
    local name="$1"
    if ! ws_is_provider_token_var "$name"; then
        echo "ERROR: '$name' is not an allowed provider-token variable." >&2
        echo "  gitTokens values must use GITLAB_*, GITHUB_*, or GH_* names." >&2
        return 1
    fi
}
