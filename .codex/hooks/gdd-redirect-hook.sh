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

[[ -f "$rules_file" ]] || exit 0
redirect_commands=()
section=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
        "["*"]") section="${line#\[}"; section="${section%\]}"; continue ;;
    esac
    [[ "$section" == "redirect-commands" ]] || continue
    [[ "$line" == *" | "* ]] || continue
    slug="${line%% | *}"
    rest="${line#* | }"
    [[ "$rest" == *" | "* ]] || continue
    pattern="${rest%% | *}"
    suggestion="${rest#* | }"
    slug="${slug%"${slug##*[![:space:]]}"}"
    pattern="${pattern%"${pattern##*[![:space:]]}"}"
    [[ "$slug" =~ ^[a-z][a-z0-9-]*$ && -n "$pattern" && -n "$suggestion" ]] || continue
    redirect_commands+=("$slug|$pattern|$suggestion")
done < "$rules_file"

match_cmd="$(normalize_for_match "$cmd")"
for entry in ${redirect_commands[@]+"${redirect_commands[@]}"}; do
    slug="${entry%%|*}"
    rest="${entry#*|}"
    pattern="${rest%%|*}"
    suggestion="${rest#*|}"
    match_pattern="$(normalize_for_match "$pattern")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $match_pattern ]]; then
        deny "$slug" "$suggestion"
    fi
done

exit 0
