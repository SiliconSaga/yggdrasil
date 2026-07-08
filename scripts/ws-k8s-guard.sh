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

# Normalize common transparent command wrappers before hook matching. This is
# deliberately a small shell-token subset, not a general shell parser: GDD is
# catching common mistakes, while complex composition belongs in reviewed
# scripts. Values containing shell-significant whitespace remain outside this
# helper's guarantee.
k8s_guard_normalize_command() {
    local command="$1" token base
    local -a words=()
    read -r -a words <<< "$command"
    [[ ${#words[@]} -gt 0 ]] || return 0

    local i=0
    while [[ $i -lt ${#words[@]} ]]; do
        token="${words[$i]}"
        case "$token" in
            [A-Za-z_][A-Za-z0-9_]*=*) i=$((i + 1)) ;;
            env|*/env)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[$i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -u|--unset) i=$((i + 2)) ;;
                        --unset=*|-i|--ignore-environment|-[^-]*) i=$((i + 1)) ;;
                        [A-Za-z_][A-Za-z0-9_]*=*) i=$((i + 1)) ;;
                        *) break ;;
                    esac
                done ;;
            command|*/command)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    case "${words[i]}" in --|-p) i=$((i + 1)) ;; *) break ;; esac
                done ;;
            *) break ;;
        esac
    done
    [[ $i -lt ${#words[@]} ]] || return 0

    base="${words[i]##*/}"
    [[ "$base" == "kubectl" ]] && words[i]="kubectl"
    printf '%s' "${words[*]:$i}"
}

# Resolve the script executed by a common shell-launch form. The returned path
# is absolute and anchored to the tool payload cwd, not the hook process cwd.
# Inline `bash -c`/`sh -c` commands are intentionally handled separately.
k8s_guard_script_path() {
    local cwd="$1" command="$2" normalized runner token path=""
    normalized="$(k8s_guard_normalize_command "$command")"
    local -a words=()
    read -r -a words <<< "$normalized"
    [[ ${#words[@]} -gt 0 ]] || return 1

    runner="${words[0]##*/}"
    local i=1
    case "$runner" in
        bash|sh)
            while [[ $i -lt ${#words[@]} ]]; do
                token="${words[$i]}"
                if [[ "$token" == "-c" || ( "$token" == -[^-]* && "$token" == *c* ) ]]; then
                    return 1
                fi
                case "$token" in
                    --) i=$((i + 1)); [[ $i -lt ${#words[@]} ]] && path="${words[$i]}"; break ;;
                    -o|--rcfile|--init-file) i=$((i + 2)) ;;
                    -*) i=$((i + 1)) ;;
                    *) path="$token"; break ;;
                esac
            done ;;
        source|.)
            [[ ${#words[@]} -gt 1 ]] && path="${words[1]}" ;;
        *)
            case "${words[0]}" in */*) path="${words[0]}" ;; esac ;;
    esac
    [[ -n "$path" ]] || return 1
    [[ "$path" == /* ]] || path="$cwd/$path"
    [[ -f "$path" ]] || return 1
    printf '%s' "$path"
}

# True when a shell's inline-command option carries a literal kubectl call.
k8s_guard_inline_shell_contains_kubectl() {
    local command="$1" normalized runner token
    normalized="$(k8s_guard_normalize_command "$command")"
    local -a words=()
    read -r -a words <<< "$normalized"
    [[ ${#words[@]} -gt 1 ]] || return 1
    runner="${words[0]##*/}"
    [[ "$runner" == "bash" || "$runner" == "sh" ]] || return 1
    local i
    for ((i = 1; i < ${#words[@]}; i++)); do
        token="${words[$i]}"
        if [[ "$token" == "-c" || ( "$token" == -[^-]* && "$token" == *c* ) ]]; then
            grep -Eq '(^|[^[:alnum:]_])kubectl([^[:alnum:]_]|$)' <<< "$normalized"
            return $?
        fi
    done
    return 1
}

# Plain read verbs. `auth` and `config` are deliberately NOT here: they are
# mixed read/write families (`config use-context`, `auth reconcile`, … mutate
# state) and are classified by sub-command in k8s_guard_evaluate, fail-closed.
_k8s_is_read_verb() {
    case "$1" in
        get|describe|logs|top|explain|events|api-resources|api-versions|version|diff|wait|kustomize) return 0 ;;
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

# True for the namespace resource type (full/plural/short-alias). Used to let an
# in-scope namespace's own create/delete through (see k8s_guard_evaluate) even
# though _k8s_is_cluster_scoped also matches it for the general blanket block.
_k8s_is_namespace_type() {
    case "${1,,}" in namespace|namespaces|ns) return 0 ;; *) return 1 ;; esac
}

# Membership test: is $1 one of the comma-separated namespaces in $2?
# A `*` element is the context-only (all-namespaces) sentinel: it matches ANY
# namespace, so a context-only scope treats every namespace as in scope for
# writes. See _k8s_scope, `ws k8s scope set` with no --namespace.
_k8s_ns_in_csv() {
    local nm="$1" one; local -a arr; IFS=',' read -ra arr <<< "$2"
    for one in "${arr[@]}"; do
        [[ "$one" == "*" ]] && return 0
        [[ "$one" == "$nm" ]] && return 0
    done
    return 1
}

# Validate the rendered objects behind a manifest or Kustomize input. The
# caller supplies either a file path as $5 or a YAML stream on stdin. On
# failure, print the complete BLOCK verdict and return non-zero; success is
# silent so both -f and -k paths share exactly the same scope checks.
_k8s_validate_rendered_docs() {
    local flag="$1" label="$2" ns_arg="$3" scope_ns_csv="$4" input_path="${5:-}"
    local parsed="" doc_kind doc_ns docs_seen=0 action empty_reason
    case "$flag" in
        -f) action="contains"; empty_reason="parsed no documents (yq failed or empty)" ;;
        -k) action="renders"; empty_reason="rendered no documents" ;;
        *) printf 'BLOCK:precondition:%s %s uses an unsupported validation source' "$flag" "$label"; return 1 ;;
    esac
    if [[ -n "$input_path" ]]; then
        parsed="$(yq -r '( (select(.kind == "List") | .items[]) , (select(.kind != "List")) ) | (.kind // "") + "\t" + (.metadata.namespace // "")' "$input_path" 2>/dev/null || true)"
    else
        parsed="$(yq -r '( (select(.kind == "List") | .items[]) , (select(.kind != "List")) ) | (.kind // "") + "\t" + (.metadata.namespace // "")' 2>/dev/null || true)"
    fi
    [[ -n "$parsed" ]] || { printf 'BLOCK:precondition:%s %s %s' "$flag" "$label" "$empty_reason"; return 1; }
    while IFS=$'\t' read -r doc_kind doc_ns; do
        docs_seen=$((docs_seen + 1))
        if [[ -n "$doc_kind" ]] && _k8s_is_cluster_scoped "$doc_kind"; then
            printf 'BLOCK:unbounded:%s %s %s a cluster-scoped %s, which is not namespace-scope-bounded' "$flag" "$label" "$action" "$doc_kind"; return 1
        fi
        [[ -z "$doc_ns" || "$doc_ns" == "null" ]] && doc_ns="$ns_arg"
        if [[ -z "$doc_ns" ]]; then
            if [[ "$flag" == "-f" ]]; then
                printf 'BLOCK:precondition:-f %s has a doc with no namespace and no -n (cannot bound to the guard scope)' "$label"
            else
                printf 'BLOCK:precondition:-k %s renders a doc with no namespace and no -n (cannot bound to the guard scope)' "$label"
            fi
            return 1
        fi
        _k8s_ns_in_csv "$doc_ns" "$scope_ns_csv" || {
            printf 'BLOCK:scope:%s %s targets namespace %s outside the guard scope (%s)' "$flag" "$label" "$doc_ns" "$scope_ns_csv"; return 1;
        }
    done <<< "$parsed"
    [[ $docs_seen -gt 0 ]] || { printf 'BLOCK:precondition:%s %s %s' "$flag" "$label" "$empty_reason"; return 1; }
}

# Print one verdict: NOT_K8S | READ_NO_SCOPE | WRITE_NO_SCOPE |
# READ_IN_SCOPE | WRITE_IN_SCOPE | BLOCK:<reason>
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
    local verb="" verb2="" ctx_arg="" ns_arg="" all_ns=0 a
    local ffiles=()
    local kdirs=()
    local rest_pos=()   # positional resource names after verb + resource-type
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
            -k|--kustomize) kdirs+=("${args[$((i+1))]:-}"); i=$((i+2)); continue ;;
            -k=*|--kustomize=*) kdirs+=("${a#*=}");;
            -k?*) kdirs+=("${a#-k}");;       # attached short form: -k<dir>
            # Known value-taking flags: consume the FOLLOWING token as the flag's
            # value so it isn't mistaken for a positional (e.g. a namespace name
            # in a create/delete lifecycle op — `delete namespace foo --timeout 5s`
            # must not read `5s` as a second namespace). Attached (`-oyaml`) and
            # equals (`--timeout=5s`) forms are single tokens and fall to `-*)`.
            -o|--output|--timeout|--grace-period|-l|--selector|--field-selector) i=$((i+2)); continue ;;
            -*) : ;;
            *) if [[ -z "$verb" ]]; then verb="$a"; elif [[ -z "$verb2" ]]; then verb2="$a"; else rest_pos+=("$a"); fi ;;
        esac
        i=$((i+1))
    done

    # `scope` is a wrapper-management verb (show/set/clear); it is not a
    # kubectl command. Return NOT_K8S so the hook passes it to the normal
    # permission flow instead of blocking it as an unrecognized write verb.
    if [[ "$verb" == "scope" ]]; then printf 'NOT_K8S'; return 0; fi

    if [[ -n "$scope_ctx" && -n "$ctx_arg" && "$ctx_arg" != "$scope_ctx" ]]; then
        printf 'BLOCK:context:explicit --context %s != the guard-scope context %s' "$ctx_arg" "$scope_ctx"; return 0
    fi
    local read_verdict="READ_IN_SCOPE"
    [[ -z "$scope_ctx" ]] && read_verdict="READ_NO_SCOPE"
    # auth / config are mixed read+write families: only an explicit read-only
    # sub-command is auto-allowed; everything else fails closed to a BLOCK so a
    # mutating call (auth reconcile, config use-context/delete-context, …) can
    # never be classified READ_IN_SCOPE or routed through namespace-write logic.
    case "$verb" in
        auth)
            case "$verb2" in
                can-i|whoami) printf '%s' "$read_verdict"; return 0 ;;
                *) [[ -z "$scope_ctx" ]] && { printf 'WRITE_NO_SCOPE'; return 0; }
                   printf 'BLOCK:unbounded:kubectl auth %s is not a scoped read (only `auth can-i` / `auth whoami` are auto-allowed)' "${verb2:-(none)}"; return 0 ;;
            esac ;;
        config)
            case "$verb2" in
                view|get-contexts|current-context|get-clusters|get-users) printf '%s' "$read_verdict"; return 0 ;;
                *) [[ -z "$scope_ctx" ]] && { printf 'WRITE_NO_SCOPE'; return 0; }
                   printf 'BLOCK:unbounded:kubectl config %s mutates kubeconfig and is not namespace-scope-bounded' "${verb2:-(none)}"; return 0 ;;
            esac ;;
    esac
    if _k8s_is_read_verb "$verb"; then printf '%s' "$read_verdict"; return 0; fi
    [[ -z "$scope_ctx" ]] && { printf 'WRITE_NO_SCOPE'; return 0; }
    if [[ $all_ns -eq 1 ]]; then printf 'BLOCK:unbounded:--all-namespaces write is not scope-bounded'; return 0; fi

    # Cluster-scoped writes can't be bounded to the namespace scope: a node-level
    # verb (cordon/drain/…) names a node directly, and a cluster-scoped resource
    # type ignores -n entirely (e.g. `delete namespace prod -n alice-sandbox`
    # deletes prod regardless). Fail closed before any namespace logic.
    case "$verb" in
        cordon|uncordon|drain) printf 'BLOCK:unbounded:kubectl %s operates on a node (cluster-scoped); not namespace-scope-bounded' "$verb"; return 0 ;;
    esac
    # In-scope namespace lifecycle: create/delete of a namespace whose NAME is
    # itself within the guard scope is allowed — it lets a practitioner create
    # (or delete and recreate) their own scoped namespace(s). The namespace name
    # is the scope-check target here, not -n. Requires at least one name and
    # EVERY named namespace in scope; a nameless form (label selector / --all)
    # has no name to bound and falls through to the cluster-scoped block below.
    # (-f Namespace manifests stay conservative — handled in the -f block.)
    # Extract the namespace type and an optional inline name, so the slash form
    # `delete ns/alice-sandbox` is treated like `delete ns alice-sandbox`.
    local _ns_type="$verb2" _ns_inline=""
    if [[ "$verb2" == */* ]]; then _ns_type="${verb2%%/*}"; _ns_inline="${verb2#*/}"; fi
    if [[ ${#ffiles[@]} -eq 0 ]] && _k8s_is_namespace_type "$_ns_type" \
        && { [[ "$verb" == "create" || "$verb" == "delete" ]]; }; then
        local -a _targets=()
        [[ -n "$_ns_inline" ]] && _targets+=("$_ns_inline")
        [[ ${#rest_pos[@]} -gt 0 ]] && _targets+=("${rest_pos[@]}")
        if [[ ${#_targets[@]} -gt 0 ]]; then
            local _nm _bad=""
            for _nm in "${_targets[@]}"; do
                _k8s_ns_in_csv "$_nm" "$scope_ns_csv" || { _bad="$_nm"; break; }
            done
            [[ -z "$_bad" ]] && { printf 'WRITE_IN_SCOPE'; return 0; }
            printf 'BLOCK:scope:%s namespace %s is outside the guard scope (%s)' "$verb" "$_bad" "$scope_ns_csv"; return 0
        fi
        # No name (label selector / --all) → fall through to the cluster-scoped block.
    fi
    if [[ ${#ffiles[@]} -eq 0 && -n "$verb2" ]] && _k8s_is_cluster_scoped "$verb2"; then
        printf 'BLOCK:unbounded:%s is a cluster-scoped resource; writes to it are not namespace-scope-bounded' "${verb2%%/*}"; return 0
    fi

    # -f manifest resolution (writes only). Any unresolved input is a BLOCK.
    if [[ ${#ffiles[@]} -gt 0 ]]; then
        local f f_path validation
        for f in "${ffiles[@]}"; do
            case "$f" in
                -|http://*|https://*) printf 'BLOCK:precondition:-f %s cannot be parsed for namespace (stdin/remote source)' "$f"; return 0 ;;
            esac
            # Resolve the on-disk path, tolerating a native Windows path form.
            f_path="$f"
            [[ -f "$f_path" ]] || f_path="$(_k8s_normalize_path "$f")"
            [[ -f "$f_path" ]] || { printf 'BLOCK:precondition:-f %s not found on disk' "$f"; return 0; }
            validation="$(_k8s_validate_rendered_docs -f "$f" "$ns_arg" "$scope_ns_csv" "$f_path")" || { printf '%s' "$validation"; return 0; }
        done
        printf 'WRITE_IN_SCOPE'; return 0
    fi

    # Kustomize inputs need the same per-resource inspection as -f manifests.
    # Render only an existing local directory; remote inputs and render failures
    # fail closed rather than turning a namespace guess into approval.
    if [[ ${#kdirs[@]} -gt 0 ]]; then
        local k k_path rendered validation
        for k in "${kdirs[@]}"; do
            k_path="$k"
            [[ -d "$k_path" ]] || k_path="$(_k8s_normalize_path "$k")"
            [[ -d "$k_path" ]] || { printf 'BLOCK:precondition:-k %s is not a readable local directory' "$k"; return 0; }
            rendered="$("${KUBECTL:-kubectl}" kustomize "$k_path" 2>/dev/null)" || {
                printf 'BLOCK:precondition:-k %s could not be rendered safely' "$k"; return 0;
            }
            validation="$(_k8s_validate_rendered_docs -k "$k" "$ns_arg" "$scope_ns_csv" <<< "$rendered")" || { printf '%s' "$validation"; return 0; }
        done
        printf 'WRITE_IN_SCOPE'; return 0
    fi

    local target_ns="$ns_arg"
    if [[ -z "$target_ns" ]]; then
        target_ns="$("${KUBECTL:-kubectl}" config view --minify --context "$scope_ctx" -o 'jsonpath={..namespace}' 2>/dev/null)"
        [[ -z "$target_ns" ]] && target_ns="default"
    fi
    # Membership via _k8s_ns_in_csv so a context-only `*` scope accepts any
    # target namespace (all namespaces in scope for writes).
    _k8s_ns_in_csv "$target_ns" "$scope_ns_csv" && { printf 'WRITE_IN_SCOPE'; return 0; }
    printf 'BLOCK:scope:write target namespace %s is outside the guard scope (%s)' "$target_ns" "$scope_ns_csv"
}

# Render a BLOCK verdict into a human-facing message with class-appropriate
# remediation. Single source of truth shared by the wrapper (ws-k8s.sh) and the
# permission hook so their wording can't drift. The verdict's class tells the
# user the RIGHT next step — widening the scope only helps a namespace-scope
# rejection; it can't unblock a cluster-scoped write or a malformed manifest.
#
# Usage: k8s_render_block <verdict> <context> [bypass-slug]
#   <verdict>  full "BLOCK:<class>:<reason>" string from k8s_guard_evaluate
#   <context>  the guard-scope context (for the scope-set hint); may be empty
#   [slug]     accepted for call-site compatibility; not used in the message
k8s_render_block() {
    local verdict="$1" ctx="${2:-}"
    local hint_ctx="${ctx:-<ctx>}"   # placeholder so the scope-set hint never renders a blank --context
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
            # The target namespace is the thing out of scope — adding it (whether
            # for a pod write or a create/delete of that namespace) authorizes the
            # op for just that namespace. Avoid the vague "widen the scope".
            printf ' Reads are free cluster-wide. Add that namespace to the scope to authorize this for just that namespace (`ws k8s scope set --context %s --namespace <ns,...>`), or run plain `kubectl` outside the guard.' "$hint_ctx" ;;
        unbounded)
            # Genuinely not namespace-bounded (the reason already says so — do not
            # repeat it). Widening cannot help; the honest escapes are running
            # outside the guard or dropping it. No hook-bypass: it does not lift
            # the `ws k8s` wrapper guard, so suggesting it here would mislead.
            printf ' Widening the scope cannot authorize this. Run it with plain `kubectl` outside the guard, or drop the guard with `ws k8s scope clear` (re-arm it afterward if you want).' ;;
        precondition)
            printf ' The guard could not evaluate the input, so it failed closed — an input problem, not a scope rejection. Fix the path or manifest and retry.' ;;
        context)
            printf ' Re-arm the scope on that context (`ws k8s scope set --context <ctx> --namespace <ns,...>`) or run plain `kubectl` outside the guard.' ;;
    esac
}
