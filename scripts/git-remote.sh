#!/usr/bin/env bash
# Shared validation for values passed to git clone / remote URL sinks.

[[ -n "${_GIT_REMOTE_SH_LOADED:-}" ]] && return 0
_GIT_REMOTE_SH_LOADED=1

git_remote_host() {
    local value="${1:-}" authority="" host=""
    case "$value" in
        https://*)
            authority="${value#https://}"
            authority="${authority%%/*}"
            authority="${authority##*@}"
            if [[ "$authority" == \[*\]* ]]; then
                host="${authority#\[}"
                host="${host%%\]*}"
            else
                host="${authority%%:*}"
            fi
            ;;
        ssh://*)
            authority="${value#ssh://}"
            authority="${authority%%/*}"
            authority="${authority##*@}"
            if [[ "$authority" == \[*\]* ]]; then
                host="${authority#\[}"
                host="${host%%\]*}"
            else
                host="${authority%%:*}"
            fi
            ;;
        *)
            if [[ "$value" =~ ^([^@/:]+@)?([^@/:]+):(.+)$ ]]; then
                host="${BASH_REMATCH[2]}"
            else
                return 1
            fi
            ;;
    esac
    [[ -n "$host" ]] || return 1
    printf '%s' "$host" | tr '[:upper:]' '[:lower:]'
}

git_remote_display_value() {
    local value="${1:-}" prefix rest authority
    if [[ "$value" == *://* ]]; then
        prefix="${value%%://*}://"
        rest="${value#*://}"
        authority="${rest%%/*}"
        if [[ "$authority" == *@* ]]; then
            printf '%s[redacted]@%s' "$prefix" "${rest##*@}"
            return
        fi
    elif [[ "$value" =~ ^[^@/:]+@[^:]+:.+$ ]]; then
        printf '[redacted]@%s' "${value##*@}"
        return
    fi
    printf '%s' "$value"
}

git_remote_validate() {
    local value="${1:-}" mode="${2:-remote}" expected="${3:-}"
    local display_value
    display_value="$(git_remote_display_value "$value")"
    if [[ -z "$value" ]]; then
        echo "ERROR: Git remote value is empty." >&2
        return 1
    fi
    if [[ "$value" == -* ]]; then
        echo "ERROR: refusing option-like Git remote value '$display_value'." >&2
        return 1
    fi
    if [[ "$value" =~ [[:cntrl:]] ]]; then
        echo "ERROR: refusing Git remote value containing a control character." >&2
        return 1
    fi
    if [[ "$value" =~ ^[A-Za-z][A-Za-z0-9+.-]*:: ]]; then
        echo "ERROR: refusing executable Git remote helper syntax in '$display_value'." >&2
        return 1
    fi

    local host=""
    case "$value" in
        https://*|ssh://*)
            host="$(git_remote_host "$value")" || {
                echo "ERROR: malformed Git remote '$display_value'; use HTTPS or SSH." >&2
                return 1
            }
            case "$value" in
                https://*/*|ssh://*/*) : ;;
                *)
                    echo "ERROR: malformed Git remote '$display_value'; repository path is missing." >&2
                    return 1
                    ;;
            esac
            ;;
        file://*)
            if [[ "$mode" != "local" || "$value" != file:///* ]]; then
                echo "ERROR: Git remotes must use HTTPS or SSH; file URLs require an explicit local clone flow." >&2
                return 1
            fi
            ;;
        *://*)
            echo "ERROR: Git remotes must use HTTPS or SSH; unsupported URL scheme in '$display_value'." >&2
            return 1
            ;;
        *)
            if [[ "$value" =~ ^([^@/:]+@)?([^@/:]+):(.+)$ ]]; then
                host="$(git_remote_host "$value")" || return 1
            elif [[ "$mode" == "local" && ( "$value" == /* || "$value" == ./* || "$value" == ../* ) ]]; then
                :
            else
                echo "ERROR: Git remotes must use HTTPS or SSH; filesystem paths require an explicit local clone flow." >&2
                return 1
            fi
            ;;
    esac

    if [[ -n "$expected" ]]; then
        local expected_lower
        expected_lower="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$host" || "$host" != "$expected_lower" ]]; then
            echo "ERROR: Git remote host '${host:-(none)}' does not match expected host '$expected_lower'." >&2
            return 1
        fi
    fi
}
