#!/usr/bin/env bash
# ws-k8s-guard.sh — shared k8s practice guard (sourced by ws-k8s.sh and the
# permission hook). Single source of truth for the allow/block verdict.

# Plain read verbs. `auth` and `config` are deliberately NOT here: they are
# mixed read/write families (`config use-context`, `auth reconcile`, … mutate
# state) and are classified by sub-command in k8s_guard_evaluate, fail-closed.
_k8s_is_read_verb() {
    case "$1" in
        get|describe|logs|top|explain|events|api-resources|api-versions|version|diff|wait) return 0 ;;
        *) return 1 ;;
    esac
}

# Print one verdict: NOT_K8S | NO_SCOPE | READ_IN_SCOPE | WRITE_IN_SCOPE | BLOCK:<reason>
# Usage: k8s_guard_evaluate <context> <namespaces-csv> <argv...>
k8s_guard_evaluate() {
    local scope_ctx="$1" scope_ns_csv="$2"; shift 2
    # Recognize both `kubectl ...` and `ws k8s ...` forms.
    if [[ "$1" == "kubectl" ]]; then shift
    elif [[ "$1" == *"/ws" || "$1" == "ws" || "$1" == "bash" ]]; then
        while [[ $# -gt 0 && "$1" != "k8s" ]]; do shift; done
        [[ "$1" == "k8s" ]] && shift || { printf 'NOT_K8S'; return 0; }
    else
        printf 'NOT_K8S'; return 0
    fi
    [[ -z "$scope_ctx" ]] && { printf 'NO_SCOPE'; return 0; }

    local verb="" verb2="" ctx_arg="" ns_arg="" all_ns=0 a
    local ffiles=()
    local args=("$@")
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        a="${args[$i]}"
        case "$a" in
            --context) ctx_arg="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
            --context=*) ctx_arg="${a#--context=}";;
            -n|--namespace) ns_arg="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
            -n=*|--namespace=*) ns_arg="${a#*=}";;
            -A|--all-namespaces) all_ns=1 ;;
            -f|--filename) ffiles+=("${args[$((i+1))]:-}"); i=$((i+2)); continue ;;
            -f=*|--filename=*) ffiles+=("${a#*=}");;
            -*) : ;;
            *) if [[ -z "$verb" ]]; then verb="$a"; else [[ -z "$verb2" ]] && verb2="$a"; fi ;;
        esac
        i=$((i+1))
    done

    # `scope` is a wrapper-management verb (show/set/clear); it is not a
    # kubectl command. Return NOT_K8S so the hook passes it to the normal
    # permission flow instead of blocking it as an unrecognized write verb.
    if [[ "$verb" == "scope" ]]; then printf 'NOT_K8S'; return 0; fi

    if [[ -n "$ctx_arg" && "$ctx_arg" != "$scope_ctx" ]]; then
        printf 'BLOCK:explicit --context %s != the guard-scope context %s' "$ctx_arg" "$scope_ctx"; return 0
    fi
    # auth / config are mixed read+write families: only an explicit read-only
    # sub-command is auto-allowed; everything else fails closed to a BLOCK so a
    # mutating call (auth reconcile, config use-context/delete-context, …) can
    # never be classified READ_IN_SCOPE or routed through namespace-write logic.
    case "$verb" in
        auth)
            case "$verb2" in
                can-i|whoami) printf 'READ_IN_SCOPE'; return 0 ;;
                *) printf 'BLOCK:kubectl auth %s is not a scoped read (only `auth can-i` / `auth whoami` are auto-allowed)' "${verb2:-(none)}"; return 0 ;;
            esac ;;
        config)
            case "$verb2" in
                view|get-contexts|current-context|get-clusters|get-users) printf 'READ_IN_SCOPE'; return 0 ;;
                *) printf 'BLOCK:kubectl config %s mutates kubeconfig and is not namespace-scope-bounded' "${verb2:-(none)}"; return 0 ;;
            esac ;;
    esac
    if _k8s_is_read_verb "$verb"; then printf 'READ_IN_SCOPE'; return 0; fi
    if [[ $all_ns -eq 1 ]]; then printf 'BLOCK:--all-namespaces write is not scope-bounded'; return 0; fi

    # -f manifest resolution (writes only). Any unresolved input is a BLOCK.
    if [[ ${#ffiles[@]} -gt 0 ]]; then
        local f doc_ns
        for f in "${ffiles[@]}"; do
            case "$f" in
                -|http://*|https://*) printf 'BLOCK:-f %s cannot be parsed for namespace (stdin/remote)' "$f"; return 0 ;;
            esac
            [[ -f "$f" ]] || { printf 'BLOCK:-f %s not found on disk' "$f"; return 0; }
            local docs_seen=0
            while IFS= read -r doc_ns; do
                docs_seen=$((docs_seen + 1))
                [[ -z "$doc_ns" || "$doc_ns" == "null" ]] && doc_ns="$ns_arg"
                # Cluster-scoped resources have no metadata.namespace; they BLOCK here when no -n is given — documented limitation.
                [[ -z "$doc_ns" ]] && { printf 'BLOCK:-f %s has a namespaced doc with no namespace and no -n' "$f"; return 0; }
                local ok=0 n
                local -a _sns  # Fix B: declare local to avoid caller-scope leak
                IFS=',' read -ra _sns <<< "$scope_ns_csv"
                for n in "${_sns[@]}"; do [[ "$n" == "$doc_ns" ]] && ok=1; done
                [[ $ok -eq 1 ]] || { printf 'BLOCK:-f %s targets namespace %s outside the guard scope (%s)' "$f" "$doc_ns" "$scope_ns_csv"; return 0; }
            done < <(yq -r '.metadata.namespace // ""' "$f" 2>/dev/null)
            [[ $docs_seen -eq 0 ]] && { printf 'BLOCK:-f %s parsed no documents (yq failed or empty)' "$f"; return 0; }
        done
        printf 'WRITE_IN_SCOPE'; return 0
    fi

    local target_ns="$ns_arg"
    if [[ -z "$target_ns" ]]; then
        target_ns="$("${KUBECTL:-kubectl}" config view --minify --context "$scope_ctx" -o 'jsonpath={..namespace}' 2>/dev/null)"
        [[ -z "$target_ns" ]] && target_ns="default"
    fi
    local ns
    local -a _scope_ns  # Fix B: declare local to avoid caller-scope leak
    IFS=',' read -ra _scope_ns <<< "$scope_ns_csv"
    for ns in "${_scope_ns[@]}"; do
        [[ "$ns" == "$target_ns" ]] && { printf 'WRITE_IN_SCOPE'; return 0; }
    done
    printf 'BLOCK:write target namespace %s is outside the guard scope (%s)' "$target_ns" "$scope_ns_csv"
}
