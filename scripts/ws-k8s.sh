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
            # namespace <ns>' can then create them. So a successful empty lookup
            # WARNS (surfacing a likely typo) but does not block the arm. A failed
            # lookup is reported separately rather than misclassifying DNS, auth,
            # or RBAC errors as absence. Context-only (ns='*') has no per-namespace
            # list to check, so this is skipped.
            if [[ "$ns" != "*" ]]; then
                local one; local -a _ns; IFS=',' read -ra _ns <<< "$ns"
                local _probe_output _probe_stderr _probe_stderr_file _detail
                local -a _missing=() _unverified=() _diagnostics=()
                if _probe_stderr_file="$(mktemp "${TMPDIR:-/tmp}/ws-k8s-scope-stderr.XXXXXX" 2>/dev/null)"; then
                    for one in "${_ns[@]}"; do
                        if _probe_output="$("$KUBECTL" --context "$ctx" get namespace "$one" --ignore-not-found -o name 2>"$_probe_stderr_file")"; then
                            [[ -n "$_probe_output" ]] || _missing+=("$one")
                        else
                            _probe_stderr="$(<"$_probe_stderr_file")"
                            _unverified+=("$one")
                            _diagnostics+=("$_probe_stderr")
                        fi
                    done
                    rm -f "$_probe_stderr_file"
                else
                    for one in "${_ns[@]}"; do
                        _unverified+=("$one")
                        _diagnostics+=("could not create a temporary file for the kubectl diagnostic")
                    done
                fi
                if [[ ${#_missing[@]} -gt 0 ]]; then
                    echo "NOTE: namespace(s) not found on context '$ctx' — arming anyway: ${_missing[*]}" >&2
                    echo "  In-scope 'ws k8s create namespace <ns>' can create them. If one is a typo, re-run scope set with the correct name." >&2
                fi
                if [[ ${#_unverified[@]} -gt 0 ]]; then
                    echo "NOTE: namespace verification failed on context '$ctx' — arming anyway: ${_unverified[*]}" >&2
                    local i
                    for ((i=0; i<${#_unverified[@]}; i++)); do
                        _detail="${_diagnostics[$i]%%$'\n'*}"
                        _detail="${_detail%$'\r'}"
                        _detail="$(printf '%s' "$_detail" | tr -d '\000-\010\013-\037\177')"
                        [[ -n "$_detail" ]] || _detail="kubectl exited without a diagnostic"
                        printf '  %s: %s\n' "${_unverified[$i]}" "${_detail:0:500}" >&2
                    done
                    echo "  Namespace verification requires live cluster access. If networking is restricted, re-run this command outside the sandbox." >&2
                fi
            fi
            ws_session_set GDD_K8S_CONTEXT "$ctx"
            ws_session_set GDD_K8S_NAMESPACES "$ns"
            if [[ "$ns" == "*" ]]; then
                echo "guard scope armed: context=$ctx namespaces=(all — context-only)"
            else
                echo "guard scope armed: context=$ctx namespaces=$ns"
            fi
            # Arming does not switch kubeconfig. Say so when they differ:
            # plain kubectl keeps going to the old context, and nothing else
            # makes that visible until the answers stop making sense.
            local current
            current="$("$KUBECTL" config current-context 2>/dev/null || true)"
            current="${current%$'\r'}"
            if [[ -n "$current" && "$current" != "$ctx" ]]; then
                echo "NOTE: kubectl's current context is $current, not $ctx. Use 'ws k8s <args>' (it injects --context); the guard refuses plain kubectl without --context until they match." >&2
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

# `ws k8s sample <pod> [exec options] [--every s] [--count n] -- <cmd…>`:
# run one read-only command in a pod repeatedly, from here. It replaces the
# `exec -- sh -c 'for …; sleep 1; done'` loop, which the hooks cannot inspect.
# The guard has already vetted the command against its read-only list.
_k8s_sample() {
    local ctx="$1"; shift
    shift   # the `sample` verb itself
    local every=1 count=5 pod="" k rc=0
    local -a opts=() cmd=() ctx_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --) shift; cmd=("$@"); break ;;
            --every) every="${2:-}"; shift 2 || shift ;;
            --every=*) every="${1#*=}"; shift ;;
            --count) count="${2:-}"; shift 2 || shift ;;
            --count=*) count="${1#*=}"; shift ;;
            -n|--namespace|-c|--container|--context|--request-timeout) opts+=("$1" "${2:-}"); shift 2 || shift ;;
            -*) opts+=("$1"); shift ;;
            *)
                [[ -z "$pod" ]] || { echo "ERROR: sample takes one pod; got '$pod' and '$1'" >&2; return 1; }
                pod="$1"; shift ;;
        esac
    done
    every="${every%s}"
    [[ "$every" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --every wants seconds (e.g. 2 or 0.5), not '$every'" >&2; return 1; }
    [[ "$count" =~ ^[0-9]+$ && "$count" -ge 1 && "$count" -le 1000 ]] || { echo "ERROR: --count wants 1-1000, not '$count'" >&2; return 1; }
    [[ -n "$pod" && ${#cmd[@]} -gt 0 ]] || { echo "Usage: ws k8s sample <pod> [-n ns] [-c container] [--every s] [--count n] -- <cmd>" >&2; return 1; }
    [[ -n "$ctx" ]] && ctx_args=(--context "$ctx")
    for ((k = 1; k <= count; k++)); do
        printf -- '--- sample %d/%d %s\n' "$k" "$count" "$(date '+%H:%M:%S')"
        "$KUBECTL" ${ctx_args[@]+"${ctx_args[@]}"} exec ${opts[@]+"${opts[@]}"} "$pod" -- "${cmd[@]}" || rc=$?
        [[ $k -lt $count ]] && sleep "$every"
    done
    return "$rc"
}

_k8s_help() {
    cat <<'HELP'
Usage: ws k8s scope set|show|clear        # manage the practice guard scope
       ws k8s <kubectl args...>           # guarded kubectl passthrough

A safety scope that bounds accidental kubectl WRITES to an armed context +
namespace(s) — a guardrail, whether you are learning a cluster or working near production.
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

Sampling (a read, so no prompt) in place of an in-pod `sh -c 'for …'` loop:
  ws k8s sample <pod> [-n ns] [-c container] [--every 1] [--count 5] -- <cmd>
  <cmd> is one of: cat head tail ls ps df du free uptime date wc nproc stat id hostname

A kubectl subcommand's own help still passes through, e.g. 'ws k8s get --help'.

On Windows, QUOTE a native -f path or use forward slashes — an unquoted
backslash path (ws k8s apply -f C:\dir\m.yaml) is mangled by the shell before
ws sees it. Use 'ws k8s apply -f "C:\dir\m.yaml"' or '.../C:/dir/m.yaml'.
exec, cp, debug, attach and run turn off Git Bash path conversion, so in-pod
paths arrive intact; give cp's local side as a relative path.
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
    # The `ws k8s` form tells the guard --context is injected below, so
    # kubectl's own current context is not the one that matters.
    local verdict; verdict="$(k8s_guard_evaluate "$ctx" "$ns" ws k8s "$@")"
    case "$verdict" in
        BLOCK:*) k8s_render_block "$verdict" "$ctx" "k8s" >&2; printf '\n' >&2; return 1 ;;
    esac
    # Git Bash rewrites absolute-looking arguments for native kubectl.exe:
    # `exec … -- cat /sys/fs/cgroup/cpu.stat` reached the pod as
    # `C:/Program Files/Git/sys/…`, and `ns/pod:/tmp/x` became a Windows
    # path list. These verbs carry in-pod paths, so conversion only does harm;
    # verbs that read local files (-f, -k) keep it.
    local verb; verb="$(k8s_guard_verb "$@")"
    case "$verb" in
        exec|cp|debug|attach|run|sample)
            case "$(uname -s 2>/dev/null || echo unknown)" in
                MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 ;;
            esac
            ;;
    esac
    if [[ "$verb" == "sample" ]]; then
        case "$verdict" in
            READ_IN_SCOPE) _k8s_sample "$ctx" "$@"; return ;;
            READ_NO_SCOPE) _k8s_sample "" "$@"; return ;;
            *) echo "ws k8s: unexpected guard verdict '$verdict' for sample" >&2; return 1 ;;
        esac
    fi
    case "$verdict" in
        READ_NO_SCOPE|WRITE_NO_SCOPE|NOT_K8S) exec "$KUBECTL" "$@" ;;
        READ_IN_SCOPE|DRY_RUN_IN_SCOPE|WRITE_IN_SCOPE) exec "$KUBECTL" --context "$ctx" "$@" ;;
        *) echo "ws k8s: unrecognized guard verdict '$verdict'" >&2; return 1 ;;
    esac
}
main "$@"
