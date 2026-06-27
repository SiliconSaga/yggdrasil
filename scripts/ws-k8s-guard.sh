#!/usr/bin/env bash
# ws-k8s-guard.sh — shared k8s practice guard (sourced by ws-k8s.sh and the
# permission hook). Single source of truth for the allow/block verdict.

# Normalize a filesystem path for the -f on-disk check. Claude Code passes
# native Windows paths (C:\Users\…\m.yaml) on Windows; Git Bash's `[[ -f ]]`
# and yq choke on the backslash/drive form, so the guard would fail closed with
# a misleading "not found" on a file that exists. Folding backslashes to forward
# slashes yields C:/Users/…/m.yaml, which both resolve. On POSIX paths (no
# backslashes) this is a no-op.
_k8s_normalize_path() {
    printf '%s' "${1//\\//}"
}

# Plain read verbs. `auth` and `config` are deliberately NOT here: they are
# mixed read/write families (`config use-context`, `auth reconcile`, … mutate
# state) and are classified by sub-command in k8s_guard_evaluate, fail-closed.
_k8s_is_read_verb() {
    case "$1" in
        get|describe|logs|top|explain|events|api-resources|api-versions|version|diff|wait) return 0 ;;
        *) return 1 ;;
    esac
}

# True when a kubectl resource type or manifest Kind is cluster-scoped (has no
# namespace). A write to one of these can never be bounded to the guard's
# namespace scope, so the guard fails closed on it regardless of -n. Best-effort
# accident-prevention list of the common/dangerous types (this is not a security
# boundary); accepts singular/plural/short-alias and PascalCase Kind forms.
_k8s_is_cluster_scoped() {
    local t="${1,,}"   # lowercase (folds PascalCase Kinds onto the same entries)
    t="${t%%/*}"       # strip a /name suffix (ns/prod → ns)
    t="${t%%.*}"       # strip an api-group suffix (clusterroles.rbac.authorization.k8s.io → clusterroles)
    case "$t" in
        namespace|namespaces|ns|node|nodes|no|persistentvolume|persistentvolumes|pv|\
        clusterrole|clusterroles|clusterrolebinding|clusterrolebindings|\
        customresourcedefinition|customresourcedefinitions|crd|crds|\
        storageclass|storageclasses|sc|priorityclass|priorityclasses|\
        mutatingwebhookconfiguration|mutatingwebhookconfigurations|\
        validatingwebhookconfiguration|validatingwebhookconfigurations|\
        apiservice|apiservices|certificatesigningrequest|certificatesigningrequests|csr|\
        podsecuritypolicy|podsecuritypolicies|psp|volumeattachment|volumeattachments|\
        ingressclass|ingressclasses|runtimeclass|runtimeclasses|\
        csidriver|csidrivers|csinode|csinodes|componentstatus|componentstatuses|\
        flowschema|flowschemas|prioritylevelconfiguration|prioritylevelconfigurations) return 0 ;;
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
            -n?*) ns_arg="${a#-n}";;        # attached short form: -n<ns>
            -A|--all-namespaces) all_ns=1 ;;
            -f|--filename) ffiles+=("${args[$((i+1))]:-}"); i=$((i+2)); continue ;;
            -f=*|--filename=*) ffiles+=("${a#*=}");;
            -f?*) ffiles+=("${a#-f}");;      # attached short form: -f<file>
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
        printf 'BLOCK:context:explicit --context %s != the guard-scope context %s' "$ctx_arg" "$scope_ctx"; return 0
    fi
    # auth / config are mixed read+write families: only an explicit read-only
    # sub-command is auto-allowed; everything else fails closed to a BLOCK so a
    # mutating call (auth reconcile, config use-context/delete-context, …) can
    # never be classified READ_IN_SCOPE or routed through namespace-write logic.
    case "$verb" in
        auth)
            case "$verb2" in
                can-i|whoami) printf 'READ_IN_SCOPE'; return 0 ;;
                *) printf 'BLOCK:unbounded:kubectl auth %s is not a scoped read (only `auth can-i` / `auth whoami` are auto-allowed)' "${verb2:-(none)}"; return 0 ;;
            esac ;;
        config)
            case "$verb2" in
                view|get-contexts|current-context|get-clusters|get-users) printf 'READ_IN_SCOPE'; return 0 ;;
                *) printf 'BLOCK:unbounded:kubectl config %s mutates kubeconfig and is not namespace-scope-bounded' "${verb2:-(none)}"; return 0 ;;
            esac ;;
    esac
    if _k8s_is_read_verb "$verb"; then printf 'READ_IN_SCOPE'; return 0; fi
    if [[ $all_ns -eq 1 ]]; then printf 'BLOCK:unbounded:--all-namespaces write is not scope-bounded'; return 0; fi

    # Cluster-scoped writes can't be bounded to the namespace scope: a node-level
    # verb (cordon/drain/…) names a node directly, and a cluster-scoped resource
    # type ignores -n entirely (e.g. `delete namespace prod -n alice-sandbox`
    # deletes prod regardless). Fail closed before any namespace logic.
    case "$verb" in
        cordon|uncordon|drain) printf 'BLOCK:unbounded:kubectl %s operates on a node (cluster-scoped); not namespace-scope-bounded' "$verb"; return 0 ;;
    esac
    if [[ ${#ffiles[@]} -eq 0 && -n "$verb2" ]] && _k8s_is_cluster_scoped "$verb2"; then
        printf 'BLOCK:unbounded:%s is a cluster-scoped resource; writes to it are not namespace-scope-bounded' "${verb2%%/*}"; return 0
    fi

    # -f manifest resolution (writes only). Any unresolved input is a BLOCK.
    if [[ ${#ffiles[@]} -gt 0 ]]; then
        local f f_path doc_kind doc_ns
        for f in "${ffiles[@]}"; do
            case "$f" in
                -|http://*|https://*) printf 'BLOCK:precondition:-f %s cannot be parsed for namespace (stdin/remote source)' "$f"; return 0 ;;
            esac
            # Resolve the on-disk path, tolerating a native Windows path form.
            f_path="$f"
            [[ -f "$f_path" ]] || f_path="$(_k8s_normalize_path "$f")"
            [[ -f "$f_path" ]] || { printf 'BLOCK:precondition:-f %s not found on disk' "$f"; return 0; }
            local docs_seen=0
            while IFS=$'\t' read -r doc_kind doc_ns; do
                docs_seen=$((docs_seen + 1))
                # A cluster-scoped Kind ignores -n; it can't be bound to the scope.
                if [[ -n "$doc_kind" ]] && _k8s_is_cluster_scoped "$doc_kind"; then
                    printf 'BLOCK:unbounded:-f %s contains a cluster-scoped %s, which is not namespace-scope-bounded' "$f" "$doc_kind"; return 0
                fi
                [[ -z "$doc_ns" || "$doc_ns" == "null" ]] && doc_ns="$ns_arg"
                # A doc with no metadata.namespace and no -n cannot be bound to the
                # guard scope (it may be cluster-scoped, or just unqualified) — fail closed.
                [[ -z "$doc_ns" ]] && { printf 'BLOCK:precondition:-f %s has a doc with no namespace and no -n (cannot bound to the guard scope)' "$f"; return 0; }
                local ok=0 n
                local -a _sns  # Fix B: declare local to avoid caller-scope leak
                IFS=',' read -ra _sns <<< "$scope_ns_csv"
                for n in "${_sns[@]}"; do [[ "$n" == "$doc_ns" ]] && ok=1; done
                [[ $ok -eq 1 ]] || { printf 'BLOCK:scope:-f %s targets namespace %s outside the guard scope (%s)' "$f" "$doc_ns" "$scope_ns_csv"; return 0; }
            # Expand a `kind: List` wrapper into its items so each embedded
            # resource gets its own kind/namespace scope check (a List can carry
            # items in several namespaces); non-List docs pass through unchanged.
            done < <(yq -r '( (select(.kind == "List") | .items[]) , (select(.kind != "List")) ) | (.kind // "") + "\t" + (.metadata.namespace // "")' "$f_path" 2>/dev/null)
            [[ $docs_seen -eq 0 ]] && { printf 'BLOCK:precondition:-f %s parsed no documents (yq failed or empty)' "$f"; return 0; }
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
    printf 'BLOCK:scope:write target namespace %s is outside the guard scope (%s)' "$target_ns" "$scope_ns_csv"
}

# Render a BLOCK verdict into a human-facing message with class-appropriate
# remediation. Single source of truth shared by the wrapper (ws-k8s.sh) and the
# permission hook so their wording can't drift. The verdict's class tells the
# user the RIGHT next step — widening the scope only helps a namespace-scope
# rejection; it can't unblock a cluster-scoped write or a malformed manifest.
#
# Usage: k8s_render_block <verdict> <context> <bypass-slug>
#   <verdict>  full "BLOCK:<class>:<reason>" string from k8s_guard_evaluate
#   <context>  the guard-scope context (for the widen hint); may be empty
#   <slug>     hook-bypass slug (defaults to k8s)
k8s_render_block() {
    local verdict="$1" ctx="${2:-}" slug="${3:-k8s}"
    local body="${verdict#BLOCK:}" class reason
    class="${body%%:*}"
    reason="${body#*:}"
    # Back-compat: a classless "BLOCK:<reason>" (no recognized class prefix)
    # keeps the whole remainder as the reason and uses the scope remediation.
    case "$class" in
        scope|unbounded|precondition|context) ;;
        *) reason="$body"; class="scope" ;;
    esac
    printf 'REJECTED by the k8s scope guard: %s.' "$reason"
    case "$class" in
        scope)
            printf ' Reads are free cluster-wide; to write here, widen the scope (`ws k8s scope set --context %s --namespace <ns>`) or lift the guard for this session (`ws hook-bypass %s`).' "$ctx" "$slug" ;;
        unbounded)
            printf ' This is not namespace-scope-bounded, so widening the scope cannot allow it — lift the guard for this session (`ws hook-bypass %s`) and use raw kubectl, or run it from a terminal outside the guard.' "$slug" ;;
        precondition)
            printf ' The guard could not evaluate the input, so it failed closed — this is an input problem, not a scope rejection. Fix the path or manifest and retry.' ;;
        context)
            printf ' Re-arm the scope on that context (`ws k8s scope set --context <ctx> --namespace <ns>`) or drop the explicit --context; or lift the guard for this session (`ws hook-bypass %s`).' "$slug" ;;
    esac
}
