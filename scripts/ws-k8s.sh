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
            if [[ -n "$c" ]]; then
                echo "context: $c"
                if [[ "$n" == "*" ]]; then echo "namespaces: (all — context-only)"; else echo "namespaces: $n"; fi
            else echo "scope: none"; fi ;;
        clear)
            ws_session_set GDD_K8S_CONTEXT ""; ws_session_set GDD_K8S_NAMESPACES ""; echo "guard scope cleared" ;;
        set)
            local ctx="" ns="" ns_given=0
            while [[ $# -gt 0 ]]; do case "$1" in
                --context)
                    [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --context requires a value" >&2; return 1; }
                    ctx="$2"; shift 2 ;;
                --namespace)
                    [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --namespace requires a value" >&2; return 1; }
                    ns="$2"; ns_given=1; shift 2 ;;
                *) echo "ERROR: unknown arg '$1'" >&2; return 1 ;;
            esac; done
            [[ -n "$ctx" ]] || { echo "Usage: ws k8s scope set --context <c> [--namespace <n[,n]>]  (omit --namespace, or include '*', for a context-only scope)" >&2; return 1; }
            # Context-only scope: no --namespace given, or a namespace CSV with
            # a '*' element. Pins the context but leaves ALL namespaces in scope for
            # writes — for a throwaway cluster doing deep infra testing across a
            # dozen dynamically-created namespaces, where per-namespace scoping is
            # constant friction and pinning the context is the safety that matters.
            # Stored as the sentinel '*' in GDD_K8S_NAMESPACES; the guard's
            # _k8s_ns_in_csv treats '*' as matching any namespace.
            if [[ $ns_given -eq 0 ]] || _k8s_ns_in_csv "*" "$ns"; then ns="*"; fi
            "$KUBECTL" config get-contexts "$ctx" >/dev/null 2>&1 || { echo "ERROR: context '$ctx' not found." >&2; return 1; }
            # The context must exist (you can't create a kube context through the
            # guard). A namespace, though, may legitimately not exist yet: arming
            # a scope on namespaces you intend to create (across one or more
            # environments) is a supported workflow — in-scope 'ws k8s create
            # namespace <ns>' can then create them. So a missing namespace WARNS
            # (surfacing a likely typo) but does not block the arm. Context-only
            # (ns='*') has no per-namespace list to check, so this is skipped.
            if [[ "$ns" != "*" ]]; then
                local one; local -a _ns; IFS=',' read -ra _ns <<< "$ns"
                local _missing=()
                for one in "${_ns[@]}"; do
                    "$KUBECTL" --context "$ctx" get namespace "$one" >/dev/null 2>&1 || _missing+=("$one")
                done
                if [[ ${#_missing[@]} -gt 0 ]]; then
                    echo "NOTE: namespace(s) not found on context '$ctx' — arming anyway: ${_missing[*]}" >&2
                    echo "  In-scope 'ws k8s create namespace <ns>' can create them. If one is a typo, re-run scope set with the correct name." >&2
                fi
            fi
            ws_session_set GDD_K8S_CONTEXT "$ctx"
            ws_session_set GDD_K8S_NAMESPACES "$ns"
            if [[ "$ns" == "*" ]]; then
                echo "guard scope armed: context=$ctx namespaces=(all — context-only)"
            else
                echo "guard scope armed: context=$ctx namespaces=$ns"
            fi ;;
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

_k8s_help() {
    cat <<'HELP'
Usage: ws k8s scope set|show|clear        # manage the practice guard scope
       ws k8s <kubectl args...>           # guarded kubectl passthrough

A safety scope that bounds accidental kubectl WRITES to an armed context +
namespace(s) — training wheels while learning, a guardrail near production.
Reads are free cluster-wide; out-of-scope or cluster-scoped writes are blocked
before kubectl runs. Accident-prevention, not a security boundary — see the
gdd-k8s skill.
Agent hooks also classify writes before a scope is armed: Claude force-prompts,
while Codex denies until a scope or explicitly confirmed session bypass exists.

Scope management:
  ws k8s scope set --context <ctx> --namespace <ns[,ns]>   arm the guard
  ws k8s scope set --context <ctx>                         context-only scope
  ws k8s scope show                                        print the armed scope
  ws k8s scope clear                                       disarm

Context-only scope (no --namespace, or a namespace list containing '*'): pins the context
but leaves ALL namespaces in scope for writes — no per-namespace rejection.
Handy for a throwaway cluster doing infra testing across many dynamic
namespaces. Context-pin protections still apply (a different --context and
context-mutating/cluster-scoped/--all-namespaces writes are still blocked).

Guarded passthrough (any other args go to kubectl, with --context injected):
  ws k8s get pods                  in-scope read  → runs
  ws k8s get pods -n kube-system   any-namespace read → runs (reads are free)
  ws k8s run probe --image=pause -n <ns>   in-scope write → runs
  ws k8s delete pod x -n other     out-of-scope write → REJECTED

Choose the boundary deliberately:
  - Keep the scope for namespace-scoped or production-adjacent work.
  - With explicit confirmation, clear it for sustained cluster-wide interactive
    work on a disposable cluster. The unscoped write safety floor remains.
  - With explicit confirmation, use 'ws hook-bypass k8s' for unattended raw-
    kubectl automation or deliberately unscoped Codex writes. An armed wrapper
    scope still applies. The bypass lasts for the session, not one command.

A kubectl subcommand's own help still passes through, e.g. 'ws k8s get --help'.

On Windows, QUOTE a native -f path or use forward slashes — an unquoted
backslash path (ws k8s apply -f C:\dir\m.yaml) is mangled by the shell before
ws sees it. Use 'ws k8s apply -f "C:\dir\m.yaml"' or '.../C:/dir/m.yaml'.
HELP
}

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
        _k8s_help; return 0
    fi
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
        BLOCK:*) k8s_render_block "$verdict" "$ctx" "k8s" >&2; printf '\n' >&2; return 1 ;;
        READ_NO_SCOPE|WRITE_NO_SCOPE|NOT_K8S) exec "$KUBECTL" "$@" ;;
        READ_IN_SCOPE|WRITE_IN_SCOPE) exec "$KUBECTL" --context "$ctx" "$@" ;;
        *) echo "ws k8s: unrecognized guard verdict '$verdict'" >&2; return 1 ;;
    esac
}
main "$@"
