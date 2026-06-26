#!/usr/bin/env bash
# ws-k8s-guard.sh — shared k8s practice guard (sourced by ws-k8s.sh and the
# permission hook). Single source of truth for the allow/block verdict.

_k8s_is_read_verb() {
    case "$1" in
        get|describe|logs|top|explain|events|api-resources|api-versions|version|diff|wait|auth|config) return 0 ;;
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

    local verb="" ctx_arg="" ns_arg="" all_ns=0 a
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
            -*) : ;;
            *) [[ -z "$verb" ]] && verb="$a" ;;
        esac
        i=$((i+1))
    done

    if [[ -n "$ctx_arg" && "$ctx_arg" != "$scope_ctx" ]]; then
        printf 'BLOCK:explicit --context %s != practice context %s' "$ctx_arg" "$scope_ctx"; return 0
    fi
    if _k8s_is_read_verb "$verb"; then printf 'READ_IN_SCOPE'; return 0; fi
    if [[ $all_ns -eq 1 ]]; then printf 'BLOCK:--all-namespaces write is not scope-bounded'; return 0; fi
    local target_ns="$ns_arg"
    if [[ -z "$target_ns" ]]; then
        target_ns="$("${KUBECTL:-kubectl}" config view --minify --context "$scope_ctx" -o 'jsonpath={..namespace}' 2>/dev/null)"
        [[ -z "$target_ns" ]] && target_ns="default"
    fi
    local ns
    IFS=',' read -ra _scope_ns <<< "$scope_ns_csv"
    for ns in "${_scope_ns[@]}"; do
        [[ "$ns" == "$target_ns" ]] && { printf 'WRITE_IN_SCOPE'; return 0; }
    done
    printf 'BLOCK:write target namespace %s is outside practice scope (%s)' "$target_ns" "$scope_ns_csv"
}
