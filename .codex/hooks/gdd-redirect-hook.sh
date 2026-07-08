#!/usr/bin/env bash
# Focused Codex PreToolUse bridge for GDD workflow redirects.
# Denies configured raw commands with ws guidance and defers everything else.
set -euo pipefail

input="$(cat)"
JQ="${JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0
"$JQ" -e . >/dev/null 2>&1 <<< "$input" || exit 0

event="$("$JQ" -r '.hook_event_name // "PreToolUse"' <<< "$input")"
tool_name="$("$JQ" -r '.tool_name // ""' <<< "$input")"
cmd="$("$JQ" -r '.tool_input.command // ""' <<< "$input")"
[[ "$event" == "PreToolUse" && "$tool_name" == "Bash" && -n "$cmd" ]] || exit 0
[[ "${WS_HOOK_DISABLE:-0}" == "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GDD_PROJECT_ROOT:="$(cd "$SCRIPT_DIR/../.." && pwd)"}"
rules_file="${GDD_REDIRECT_RULES_FILE:-$GDD_PROJECT_ROOT/.claude/hooks/hook-rules}"
audit_log="$HOME/.codex/hook-audit.log"

audit_safe() {
    local value="$1"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '%s' "$value"
}

audit() {
    mkdir -p "$(dirname "$audit_log")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$audit_log"
}

deny() {
    local slug="$1" reason="$2"
    audit "DENY-REDIRECT [$slug] [PreToolUse]: $(audit_safe "$cmd")"
    "$JQ" -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}

normalize_for_match() {
    local value="$1"
    case "$value" in
        "bash ./scripts/"*) printf '%s' "${value#bash ./scripts/}" ;;
        "bash scripts/"*) printf '%s' "${value#bash scripts/}" ;;
        "./scripts/"*) printf '%s' "${value#./scripts/}" ;;
        "scripts/"*) printf '%s' "${value#scripts/}" ;;
        *) printf '%s' "$value" ;;
    esac
}

redirect_commands=()

parse_redirect_rules() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local section="" line slug pattern suggestion rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        case "$line" in
            "["*"]") section="${line#\[}"; section="${section%\]}"; continue ;;
        esac
        [[ "$section" == "redirect-commands" ]] || continue
        if [[ "$line" != *" | "* ]]; then
            audit "WARNING (hook-rules: malformed [redirect-commands] entry, missing separator): $file"
            continue
        fi
        slug="${line%% | *}"
        rest="${line#* | }"
        if [[ "$rest" != *" | "* ]]; then
            audit "WARNING (hook-rules: malformed [redirect-commands] entry, only two columns): $file"
            continue
        fi
        pattern="${rest%% | *}"
        suggestion="${rest#* | }"
        slug="${slug%"${slug##*[![:space:]]}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        if [[ ! "$slug" =~ ^[a-z][a-z0-9-]*$ || -z "$pattern" || -z "$suggestion" ]]; then
            audit "WARNING (hook-rules: malformed [redirect-commands] entry, invalid fields): $file"
            continue
        fi
        redirect_commands+=("$slug|$pattern|$suggestion")
    done < "$file"
}

if [[ ! -f "$rules_file" ]]; then
    audit "PASSTHROUGH [PreToolUse] (redirect rules unavailable): $(audit_safe "$cmd")"
    exit 0
fi
parse_redirect_rules "$rules_file"
parse_redirect_rules "${GDD_REDIRECT_RULES_LOCAL_FILE:-$GDD_PROJECT_ROOT/.claude/hooks/hook-rules.local}"

session_id="$("$JQ" -r '.session_id // ""' <<< "$input")"

marker_field() {
    local file="$1" key="$2" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            "$key="*) printf '%s' "${line#"$key="}"; return 0 ;;
            "$key:"*)
                line="${line#"$key:"}"
                line="${line#"${line%%[![:space:]]*}"}"
                printf '%s' "$line"
                return 0
                ;;
        esac
    done < "$file"
    return 0
}

match_cmd="$(normalize_for_match "$cmd")"
for entry in ${redirect_commands[@]+"${redirect_commands[@]}"}; do
    slug="${entry%%|*}"
    rest="${entry#*|}"
    pattern="${rest%%|*}"
    suggestion="${rest#*|}"
    match_pattern="$(normalize_for_match "$pattern")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $match_pattern ]]; then
        marker="$GDD_PROJECT_ROOT/.tmp/hook-bypass/$slug.bypass"
        if [[ -n "$session_id" && -f "$marker" ]]; then
            marker_session_id="$(marker_field "$marker" session_id)"
            marker_reason="$(marker_field "$marker" reason)"
            if [[ "$marker_session_id" == "$session_id" ]]; then
                audit "BYPASS-REDIRECT [$slug] reason=\"$(audit_safe "$marker_reason")\" [PreToolUse]: $(audit_safe "$cmd")"
                exit 0
            fi
        fi
        deny "$slug" "$suggestion"
    fi
done

exit 0
