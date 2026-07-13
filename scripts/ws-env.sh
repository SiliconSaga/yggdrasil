#!/usr/bin/env bash
# Shared literal .env loading and provider-token variable policy.

_ws_env_parse_value() {
    local raw_value="$1" env_file="$2" line_number="$3"
    local value quote tail trimmed_tail char prev
    local i closing=-1 saw_quote=0 had_leading_whitespace=0

    [[ "$raw_value" == [[:space:]]* ]] && had_leading_whitespace=1
    while [[ "$raw_value" == [[:space:]]* ]]; do raw_value="${raw_value#?}"; done

    if [[ "$raw_value" == \"* || "$raw_value" == \'* ]]; then
        quote="${raw_value:0:1}"
        for ((i=${#raw_value}-1; i>=1; i--)); do
            char="${raw_value:i:1}"
            [[ "$char" == "$quote" ]] || continue
            saw_quote=1
            tail="${raw_value:i+1}"
            trimmed_tail="$tail"
            while [[ "$trimmed_tail" == [[:space:]]* ]]; do trimmed_tail="${trimmed_tail#?}"; done
            if [[ -z "$trimmed_tail" || ( "$tail" == [[:space:]]* && "$trimmed_tail" == \#* ) ]]; then
                closing=$i
                break
            fi
        done
        if [[ "$closing" -lt 0 ]]; then
            if [[ "$saw_quote" -eq 0 ]]; then
                echo "ERROR: invalid .env line $line_number in $env_file; quoted value is not closed." >&2
            else
                echo "ERROR: invalid .env line $line_number in $env_file; quoted value has trailing content." >&2
            fi
            return 1
        fi
        value="${raw_value:1:closing-1}"
    else
        value="$raw_value"
        if [[ "$had_leading_whitespace" -eq 1 && "$value" == \#* ]]; then
            value=""
        else
            for ((i=1; i<${#value}; i++)); do
                char="${value:i:1}"
                [[ "$char" == "#" ]] || continue
                prev="${value:i-1:1}"
                if [[ "$prev" == [[:space:]] ]]; then
                    value="${value:0:i}"
                    break
                fi
            done
        fi
        while [[ "$value" == *[[:space:]] ]]; do value="${value%?}"; done
    fi

    printf '%s' "$value"
}

ws_load_env() {
    local env_file="$1"
    [[ -f "$env_file" ]] || return 0

    local line line_number=0 key raw_value value
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
            PATH|LD_PRELOAD|LD_LIBRARY_PATH|DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|BASH_ENV|ENV|IFS|PS4|PROMPT_COMMAND|SHELLOPTS|BASHOPTS|GIT_CONFIG*|GIT_SSH*|GIT_ASKPASS|SSH_ASKPASS|GIT_EXEC_PATH|GIT_EXTERNAL_DIFF|GIT_PROXY_COMMAND|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_NAMESPACE|GIT_EDITOR|GIT_SEQUENCE_EDITOR|GIT_PAGER|HOME|CDPATH|SCRIPT_DIR|ROOT_DIR|ECOSYSTEM|ECOSYSTEM_LOCAL|REALMS_DIR|COMPONENTS_DIR)
                echo "ERROR: refusing to set reserved variable '$key' from .env line $line_number in $env_file." >&2
                return 1
                ;;
        esac
        if ! value="$(_ws_env_parse_value "$raw_value" "$env_file" "$line_number")"; then
            return 1
        fi

        printf -v "$key" '%s' "$value"
        export "$key"
    done < "$env_file"
}

# Provider-token names are prefix-allowlisted: a gitTokens mapping may only
# name a variable inside the provider namespaces (GITLAB_*/GITHUB_*/GH_*), so
# it cannot route an arbitrary out-of-namespace secret (AWS_SECRET_ACCESS_KEY,
# ...) into git auth. The guarantee is namespace-scoped, not token-only — a
# mapping could still name a non-token var like GH_HOST, which then simply
# fails as an unset/wrong credential rather than leaking anything foreign.
# GITHUB_*/GH_* get the same namespaced freedom as GITLAB_*, which multi-org
# GitHub setups need (e.g. an org bot token plus a personal PAT mapped to
# different namespaces).
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
