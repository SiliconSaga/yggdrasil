#!/usr/bin/env bash
# Focused Codex PreToolUse bridge for the GDD Kubernetes scope guard.
# Denies unsafe or misrouted Kubernetes calls and defers everything else to
# Codex's normal sandbox and approval flow.
set -euo pipefail

input="$(cat)"
JQ="${JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0
"$JQ" -e . >/dev/null 2>&1 <<< "$input" || exit 0

event="$("$JQ" -r '.hook_event_name // "PreToolUse"' <<< "$input")"
tool_name="$("$JQ" -r '.tool_name // ""' <<< "$input")"
cmd="$("$JQ" -r '.tool_input.command // ""' <<< "$input")"
cwd="$("$JQ" -r '.cwd // empty' <<< "$input")"
session_id="$("$JQ" -r '.session_id // ""' <<< "$input")"

[[ "$event" == "PreToolUse" && "$tool_name" == "Bash" && -n "$cmd" ]] || exit 0
[[ "${WS_HOOK_DISABLE:-0}" == "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GDD_PROJECT_ROOT:="$(cd "$SCRIPT_DIR/../.." && pwd)"}"
[[ -n "$cwd" ]] || cwd="$GDD_PROJECT_ROOT"

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
    local reason="$1"
    audit "DENY [PreToolUse] ($(audit_safe "$reason")): $(audit_safe "$cmd")"
    "$JQ" -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}

session_helper="$GDD_PROJECT_ROOT/scripts/ws-session.sh"
guard_helper="$GDD_PROJECT_ROOT/scripts/ws-k8s-guard.sh"
if [[ ! -f "$session_helper" || ! -f "$guard_helper" ]]; then
    audit "PASSTHROUGH [PreToolUse] (shared Kubernetes guard unavailable): $(audit_safe "$cmd")"
    exit 0
fi

ROOT_DIR="$GDD_PROJECT_ROOT"
# shellcheck source=../../scripts/ws-session.sh
source "$session_helper"
# shellcheck source=../../scripts/ws-k8s-guard.sh
source "$guard_helper"

[[ -n "$session_id" ]] || exit 0
session_path="$(ws_session_identity_path_for "$session_id")"
ctx="$(ws_session_get GDD_K8S_CONTEXT "$session_path")"
namespaces="$(ws_session_get GDD_K8S_NAMESPACES "$session_path")"
[[ -n "$ctx" ]] || exit 0

marker="$GDD_PROJECT_ROOT/.tmp/hook-bypass/k8s.bypass"
if [[ -f "$marker" ]]; then
    marker_session_id="$(sed -n 's/^session_id: *//p' "$marker" | head -n 1)"
    if [[ "$marker_session_id" == "$session_id" ]]; then
        audit "BYPASS-SCOPE [k8s] [PreToolUse]: $(audit_safe "$cmd")"
        exit 0
    fi
fi

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

match_cmd="$(normalize_for_match "$cmd")"

case "$match_cmd" in
    ws\ k8s\ scope|ws\ k8s\ scope\ *|k8s\ scope|k8s\ scope\ *) exit 0 ;;
esac

evaluate_command() {
    local command="$1"
    local -a args
    read -r -a args <<< "$command"
    k8s_guard_evaluate "$ctx" "$namespaces" "${args[@]}"
}

if [[ "$match_cmd" == ws\ k8s\ * || "$match_cmd" == k8s\ * ]]; then
    verdict="$(evaluate_command "$match_cmd" 2>/dev/null || true)"
    case "$verdict" in
        BLOCK:*) deny "$(k8s_render_block "$verdict" "$ctx" k8s)" ;;
        READ_IN_SCOPE|WRITE_IN_SCOPE|NO_SCOPE|NOT_K8S) exit 0 ;;
        *) deny "Kubernetes guard evaluation failed; the guarded command was not run." ;;
    esac
fi

if [[ "$match_cmd" == kubectl || "$match_cmd" == kubectl\ * ]]; then
    verdict="$(evaluate_command "$match_cmd" 2>/dev/null || true)"
    case "$verdict" in
        READ_IN_SCOPE|NO_SCOPE) exit 0 ;;
        WRITE_IN_SCOPE)
            deny "Use 'ws k8s <args>' so the armed context '$ctx' is injected before this Kubernetes write." ;;
        BLOCK:*) deny "$(k8s_render_block "$verdict" "$ctx" k8s)" ;;
        *) deny "Kubernetes guard evaluation failed; the raw kubectl command was not run." ;;
    esac
fi

case "$match_cmd" in
    bash\ *|sh\ *|source\ *|./*)
        script_path="${match_cmd#* }"
        script_path="${script_path%% *}"
        if [[ "$script_path" != /* ]]; then
            script_path="$cwd/$script_path"
        fi
        if [[ -f "$script_path" ]] && grep -Eq '(^|[^[:alnum:]_])kubectl([^[:alnum:]_]|$)' "$script_path" 2>/dev/null; then
            deny "Script $script_path calls raw kubectl within a guarded scope — run each Kubernetes step via 'ws k8s', or use 'ws hook-bypass k8s'."
        fi
        ;;
esac

exit 0
