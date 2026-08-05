#!/usr/bin/env bash
# Shared literal .env loading and provider-token variable policy.

_ws_env_parse_value() {
    local raw_value="$1" env_file="$2" line_number="$3"
    local value quote tail trimmed_tail char prev
    local i j closing=-1 backslashes=0 had_leading_whitespace=0

    [[ "$raw_value" == [[:space:]]* ]] && had_leading_whitespace=1
    while [[ "$raw_value" == [[:space:]]* ]]; do raw_value="${raw_value#?}"; done

    if [[ "$raw_value" == \"* || "$raw_value" == \'* ]]; then
        quote="${raw_value:0:1}"
        for ((i=1; i<${#raw_value}; i++)); do
            char="${raw_value:i:1}"
            [[ "$char" == "$quote" ]] || continue
            backslashes=0
            j=$((i - 1))
            while [[ "$j" -ge 1 && "${raw_value:j:1}" == "\\" ]]; do
                backslashes=$((backslashes + 1))
                j=$((j - 1))
            done
            [[ $((backslashes % 2)) -eq 1 ]] && continue
            closing=$i
            break
        done
        if [[ "$closing" -lt 0 ]]; then
            echo "ERROR: invalid .env line $line_number in $env_file; quoted value is not closed." >&2
            return 1
        fi
        tail="${raw_value:closing+1}"
        trimmed_tail="$tail"
        while [[ "$trimmed_tail" == [[:space:]]* ]]; do trimmed_tail="${trimmed_tail#?}"; done
        if [[ -n "$trimmed_tail" && ! ( "$tail" == [[:space:]]* && "$trimmed_tail" == \#* ) ]]; then
            echo "ERROR: invalid .env line $line_number in $env_file; quoted value has trailing content." >&2
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
    local __WS_ENV_FILE="$1"
    [[ -f "$__WS_ENV_FILE" ]] || return 0

    local __WS_ENV_LINE __WS_ENV_LINE_NUMBER=0 __WS_ENV_KEY __WS_ENV_RAW_VALUE __WS_ENV_VALUE
    local __WS_ENV_ASSIGNMENT_RE='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
    while IFS= read -r __WS_ENV_LINE || [[ -n "$__WS_ENV_LINE" ]]; do
        __WS_ENV_LINE_NUMBER=$((__WS_ENV_LINE_NUMBER + 1))
        __WS_ENV_LINE="${__WS_ENV_LINE%$'\r'}"
        [[ "$__WS_ENV_LINE" =~ ^[[:space:]]*$ || "$__WS_ENV_LINE" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$__WS_ENV_LINE" =~ $__WS_ENV_ASSIGNMENT_RE ]]; then
            echo "ERROR: invalid .env line $__WS_ENV_LINE_NUMBER in $__WS_ENV_FILE; expected KEY=value or export KEY=value." >&2
            return 1
        fi

        __WS_ENV_KEY="${BASH_REMATCH[2]}"
        __WS_ENV_RAW_VALUE="${BASH_REMATCH[3]}"
        case "$__WS_ENV_KEY" in
            __WS_ENV_*)
                echo "ERROR: refusing to set reserved variable '$__WS_ENV_KEY' from .env line $__WS_ENV_LINE_NUMBER in $__WS_ENV_FILE." >&2
                return 1
                ;;
            PATH|LD_PRELOAD|LD_LIBRARY_PATH|LD_AUDIT|DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|BASH_ENV|ENV|IFS|PS4|PROMPT_COMMAND|SHELLOPTS|BASHOPTS|GIT_CONFIG*|GIT_SSH*|GIT_ASKPASS|SSH_ASKPASS|GIT_EXEC_PATH|GIT_EXTERNAL_DIFF|GIT_PROXY_COMMAND|GIT_TEMPLATE_DIR|GIT_COMMON_DIR|GIT_TRACE*|GIT_CURL_VERBOSE|GIT_ALLOW_PROTOCOL|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_NAMESPACE|GIT_EDITOR|GIT_SEQUENCE_EDITOR|GIT_PAGER|PAGER|EDITOR|VISUAL|LESSOPEN|LESSCLOSE|GH_PAGER|GLAB_PAGER|GH_DEBUG|GH_HOST|GH_CONFIG_DIR|GLAB_CONFIG_DIR|XDG_CONFIG_HOME|HOME|CDPATH|SCRIPT_DIR|ROOT_DIR|ECOSYSTEM|ECOSYSTEM_LOCAL|REALMS_DIR|COMPONENTS_DIR|HOARDS_DIR|TEMPLATES_DIR)
                echo "ERROR: refusing to set reserved variable '$__WS_ENV_KEY' from .env line $__WS_ENV_LINE_NUMBER in $__WS_ENV_FILE." >&2
                return 1
                ;;
        esac
        if ! __WS_ENV_VALUE="$(_ws_env_parse_value "$__WS_ENV_RAW_VALUE" "$__WS_ENV_FILE" "$__WS_ENV_LINE_NUMBER")"; then
            return 1
        fi

        printf -v "$__WS_ENV_KEY" '%s' "$__WS_ENV_VALUE"
        export "$__WS_ENV_KEY"
    done < "$__WS_ENV_FILE"
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
