#!/usr/bin/env bash
# ws-k8s.sh — guarded kubectl wrapper (training wheels). See
# docs/plans/2026-06-25-mentoring-k8s-training-wheels-design.md.
# ws:use-when running kubectl during a guarded practice session
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
            ws_session_set GDD_K8S_CONTEXT ""; ws_session_set GDD_K8S_NAMESPACES ""; echo "scope cleared" ;;
        set)
            local ctx="" ns=""
            while [[ $# -gt 0 ]]; do case "$1" in
                --context) ctx="$2"; shift 2 ;;
                --namespace) ns="$2"; shift 2 ;;
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
            echo "practice scope armed: context=$ctx namespaces=$ns" ;;
        *) echo "Usage: ws k8s scope set|show|clear" >&2; return 1 ;;
    esac
}

main() {
    if [[ "${1:-}" == "scope" ]]; then shift; _k8s_scope "$@"; return; fi
    local ctx ns; ctx="$(ws_session_get GDD_K8S_CONTEXT)"; ns="$(ws_session_get GDD_K8S_NAMESPACES)"
    local verdict; verdict="$(k8s_guard_evaluate "$ctx" "$ns" kubectl "$@")"
    case "$verdict" in
        BLOCK:*) echo "ws k8s: blocked — ${verdict#BLOCK:}" >&2
                 echo "  widen with: ws k8s scope set --context $ctx --namespace <ns>" >&2; return 1 ;;
        NO_SCOPE|NOT_K8S) exec "$KUBECTL" "$@" ;;
        *) exec "$KUBECTL" --context "$ctx" "$@" ;;
    esac
}
main "$@"
