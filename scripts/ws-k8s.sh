#!/usr/bin/env bash
# ws-k8s.sh — guarded kubectl wrapper. Prevalidates the kube context and
# namespace against the active guard scope. See
# docs/plans/2026-06-25-mentoring-k8s-training-wheels-design.md.
# ws:use-when running kubectl while a k8s guard scope is set
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
source "$SCRIPT_DIR/ws-session.sh"
source "$SCRIPT_DIR/ws-k8s-guard.sh"
KUBECTL="${KUBECTL:-kubectl}"

_k8s_scope() {
    local sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
    case "$sub" in
        show)
            local c n; c="$(ws_session_get GDD_K8S_CONTEXT)"; n="$(ws_session_get GDD_K8S_NAMESPACES)"
            if [[ -n "$c" ]]; then echo "context: $c"; echo "namespaces: $n"; else echo "scope: none"; fi ;;
        clear)
            ws_session_set GDD_K8S_CONTEXT ""; ws_session_set GDD_K8S_NAMESPACES ""; echo "guard scope cleared" ;;
        set)
            local ctx="" ns=""
            while [[ $# -gt 0 ]]; do case "$1" in
                --context)
                    [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --context requires a value" >&2; return 1; }
                    ctx="$2"; shift 2 ;;
                --namespace)
                    [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --namespace requires a value" >&2; return 1; }
                    ns="$2"; shift 2 ;;
                *) echo "ERROR: unknown arg '$1'" >&2; return 1 ;;
            esac; done
            [[ -n "$ctx" && -n "$ns" ]] || { echo "Usage: ws k8s scope set --context <c> --namespace <n[,n]>" >&2; return 1; }
            "$KUBECTL" config get-contexts "$ctx" >/dev/null 2>&1 || { echo "ERROR: context '$ctx' not found." >&2; return 1; }
            local one; IFS=',' read -ra _ns <<< "$ns"
            for one in "${_ns[@]}"; do
                "$KUBECTL" --context "$ctx" get namespace "$one" >/dev/null 2>&1 || { echo "ERROR: namespace '$one' not found on context '$ctx'." >&2; return 1; }
            done
            ws_session_set GDD_K8S_CONTEXT "$ctx"
            ws_session_set GDD_K8S_NAMESPACES "$ns"
            echo "guard scope armed: context=$ctx namespaces=$ns" ;;
        *) echo "Usage: ws k8s scope set|show|clear" >&2; return 1 ;;
    esac
}

# When no session id resolves (e.g. a human's own terminal, which has no
# CLAUDE_CODE_SESSION_ID), gather the guard scope from ALL local session files
# so `ws k8s` still guards. Unions namespaces when every scope shares a context;
# refuses (exit 2) when scopes target different contexts. Prints
# "context|namespaces" on success, nothing when no scope is active.
#
# Deliberately reads every session file without filtering by age: this model has
# no liveness marker, and gating on age would be basing an action on staleness,
# which is a soft-nudge signal only — never a gate (see the session-liveness-
# marker arc). An ended session's lingering scope only ever over-restricts
# (fail-safe) or makes the ambient path decline to guard, in which case a human
# falls back to raw kubectl. Remedy for stale scopes: `ws clean --sessions-all`.
_k8s_ambient_scope() {
    local dir="$ROOT_DIR/.tmp/gdd-agent-sessions"
    [[ -d "$dir" ]] || return 0
    local f ctx ns found_ctx="" all_ns="" n=0
    for f in "$dir"/*.env; do
        [[ -f "$f" ]] || continue
        ctx="$(ws_session_get GDD_K8S_CONTEXT "$f")"
        [[ -n "$ctx" ]] || continue
        ns="$(ws_session_get GDD_K8S_NAMESPACES "$f")"
        if [[ -z "$found_ctx" ]]; then
            found_ctx="$ctx"; all_ns="$ns"
        elif [[ "$ctx" == "$found_ctx" ]]; then
            all_ns="${all_ns:+$all_ns,}$ns"
        else
            echo "ws k8s: active guard scopes target different contexts ('$found_ctx' and '$ctx') — refusing to guard ambiguously. Run within a single session, or clear the extra scope." >&2
            return 2
        fi
        n=$((n+1))
    done
    [[ $n -eq 0 ]] && return 0
    # Dedup the unioned namespace list (preserve first-seen order, drop empties).
    all_ns="$(printf '%s' "$all_ns" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd, -)"
    [[ $n -gt 1 ]] && echo "ws k8s: aggregated $n active guard scopes for context '$found_ctx' → namespaces: $all_ns" >&2
    printf '%s|%s' "$found_ctx" "$all_ns"
}

main() {
    if [[ "${1:-}" == "scope" ]]; then shift; _k8s_scope "$@"; return; fi
    local ctx ns
    if [[ -n "$(ws_resolve_session_id)" ]]; then
        ctx="$(ws_session_get GDD_K8S_CONTEXT)"; ns="$(ws_session_get GDD_K8S_NAMESPACES)"
    else
        # No session id (e.g. a human's own terminal) — fall back to the ambient
        # guard scope aggregated across all active local sessions.
        # Preserve the ambient exit code: 2 specifically signals an ambiguous
        # multi-context refusal, which callers/tests distinguish from a generic
        # failure (1).
        local ambient
        ambient="$(_k8s_ambient_scope)" || return $?
        ctx="${ambient%%|*}"; ns="${ambient#*|}"
    fi
    local verdict; verdict="$(k8s_guard_evaluate "$ctx" "$ns" kubectl "$@")"
    case "$verdict" in
        BLOCK:*) echo "ws k8s: REJECTED by the guard — ${verdict#BLOCK:}." >&2
                 echo "  Widen with 'ws k8s scope set --context $ctx --namespace <ns>', or lift with 'ws hook-bypass k8s'." >&2; return 1 ;;
        NO_SCOPE|NOT_K8S) exec "$KUBECTL" "$@" ;;
        READ_IN_SCOPE|WRITE_IN_SCOPE) exec "$KUBECTL" --context "$ctx" "$@" ;;
        *) echo "ws k8s: unrecognized guard verdict '$verdict'" >&2; return 1 ;;
    esac
}
main "$@"
