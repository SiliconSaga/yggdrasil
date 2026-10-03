#!/usr/bin/env bash
# ws-k8s-guard.sh — shared k8s practice guard (sourced by ws-k8s.sh and the
# permission hook). Single source of truth for the allow/block verdict.

# Complex shell forms cannot be tokenized safely by the small normalizer below.
# Every consumer recognizes this fixed sentinel and handles Kubernetes-looking
# payloads as a fail-closed decision rather than inspecting only the first line.
K8S_GUARD_UNSAFE_COMMAND_SENTINEL="__GDD_K8S_UNSAFE_COMMAND__"
K8S_GUARD_NO_XARGS_SENTINEL="__GDD_K8S_NO_XARGS__"

# The cluster tools whose literal mention in a script or inline shell makes it
# a Kubernetes candidate. helm writes namespaces, CRDs and ClusterRoles as
# readily as kubectl, so a script that runs it gets the same scan.
K8S_GUARD_TOOL_RE='(^|[^[:alnum:]_])(kubectl|helm)([^[:alnum:]_]|$)'

# Appended to every composition denial of a Kubernetes command, in both hooks.
# The generic text names ws exec and ws commit, which are the wrong way out
# here; the right one is a single ws k8s call with kubectl's own shaping.
K8S_GUARD_COMPOSITION_HINT="For Kubernetes, issue one \`ws k8s <args>\` per call (it injects the armed --context). In place of a pipe or filter use kubectl's own output shaping — \`-o custom-columns=NAME:.metadata.name,...\`, \`-o jsonpath='{range .items[*]}...{end}'\`, \`-l\` / \`--field-selector\` — and \`kubectl wait --for=...\` in place of a poll loop. A loop inside \`exec -- sh -c\` counts too: run each sample as its own \`ws k8s exec <pod> -- <cmd>\` call."

# Normalize a filesystem path for the -f on-disk check. Claude Code passes
# native Windows paths (C:\Users\…\m.yaml) on Windows; Git Bash's `[[ -f ]]`
# and yq choke on the backslash/drive form, so the guard would fail closed with
# a misleading "not found" on a file that exists. Folding backslashes to forward
# slashes yields C:/Users/…/m.yaml, which both resolve. On POSIX paths (no
# backslashes) this is a no-op.
_k8s_normalize_path() {
    printf '%s' "${1//\\//}"
}

# True when shell evaluation can change the argv that the guard classifies.
# Single-quoted and backslash-escaped dollars/backticks are literal data;
# unquoted or double-quoted forms are live expansions and must fail closed.
k8s_guard_has_live_shell_expansion() {
    local input="$1" char state="plain"
    local i=0 length=${#1}
    while [[ $i -lt $length ]]; do
        char="${input:i:1}"
        case "$state:$char" in
            plain:"\\") i=$((i + 2)); continue ;;
            plain:"'") state="single" ;;
            plain:'"') state="double" ;;
            plain:'$'|plain:'`') return 0 ;;
            single:"'") state="plain" ;;
            double:"\\") i=$((i + 2)); continue ;;
            double:'"') state="plain" ;;
            double:'$'|double:'`') return 0 ;;
        esac
        i=$((i + 1))
    done
    return 1
}

# Slash-qualified wrapper names are trusted only when they identify the same
# executable the ambient PATH would select. Otherwise an arbitrary local file
# could borrow a transparent wrapper's parsing rules and evade classification.
k8s_guard_executable_path_is_trusted() {
    local candidate="$1" executable="$2" expected
    [[ "$candidate" == */* ]] || return 0
    expected="$(type -P "$executable" 2>/dev/null)" || return 1
    [[ -n "$expected" && -e "$candidate" && "$candidate" -ef "$expected" ]]
}

# Normalize common transparent command wrappers before hook matching. This is
# deliberately a small shell-token subset, not a general shell parser: GDD is
# catching common mistakes, while complex composition belongs in reviewed
# scripts. Values containing shell-significant whitespace remain outside this
# helper's guarantee.
k8s_guard_normalize_command() {
    local command="$1" mode="${2:-classify}" token base saw_xargs=0
    if k8s_guard_has_live_shell_expansion "$command"; then
        printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
        return 0
    fi
    case "$command" in
        *$'\n'*|*$'\r'*|*"&&"*|*"||"*|*";"*|*"|"*|*"&"*|*">"*|*"<"* )
            printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
            return 0
            ;;
    esac
    # Subshell parens are compound forms too, but only OUTSIDE quotes — a
    # label selector like -l 'env in (prod)' is a single command. Check the
    # inert-quote-masked form: quoted parens vanish, live ones classify
    # unsafe (and a malformed-quote input returns unmasked, failing closed).
    case "$(k8s_guard_mask_inert_quotes "$command")" in
        *"("*|*")"*)
            printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
            return 0
            ;;
    esac
    local -a words=()
    read -r -a words <<< "$command"
    [[ ${#words[@]} -gt 0 ]] || return 0

    # `read -a` deliberately avoids shell evaluation, but it also retains
    # harmless whole-word quoting. Normalize only balanced, whitespace-free
    # word quotes so wrapper and interpreter names share one representation;
    # quoted multi-word data stays untouched and cannot be retokenized.
    local word_index word
    for ((word_index = 0; word_index < ${#words[@]}; word_index++)); do
        word="${words[word_index]}"
        case "$word" in
            \"*\") [[ ${#word} -ge 2 ]] && words[word_index]="${word:1:${#word}-2}" ;;
            \'*\') [[ ${#word} -ge 2 ]] && words[word_index]="${word:1:${#word}-2}" ;;
        esac
    done

    local i=0
    while [[ $i -lt ${#words[@]} ]]; do
        token="${words[$i]}"
        base="${token##*/}"
        case "$base" in
            env|command|nohup|setsid|time|timeout|gtimeout|nice|ionice|stdbuf|xargs)
                if ! k8s_guard_executable_path_is_trusted "$token" "$base"; then
                    printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                    return 0
                fi
                ;;
        esac
        case "$token" in
            [A-Za-z_][A-Za-z0-9_]*=*) i=$((i + 1)) ;;
            env|*/env)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[$i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -u|--unset|-C|--chdir|-a|--argv0|-P)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        -u?*|-C?*|-a?*|-P?*|--unset=*|--chdir=*|--argv0=*) i=$((i + 1)) ;;
                        -S|--split-string|-S?*|--split-string=*)
                            printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                            return 0
                            ;;
                        -i|--ignore-environment) i=$((i + 1)) ;;
                        --help|--version) printf '%s' "$command"; return 0 ;;
                        -*)
                            printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                            return 0
                            ;;
                        [A-Za-z_][A-Za-z0-9_]*=*) i=$((i + 1)) ;;
                        *) break ;;
                    esac
                done ;;
            command|*/command)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    case "${words[i]}" in --|-p) i=$((i + 1)) ;; *) break ;; esac
                done ;;
            nohup|*/nohup)
                i=$((i + 1))
                if [[ $i -lt ${#words[@]} ]]; then
                    case "${words[i]}" in
                        --) i=$((i + 1)) ;;
                        --help|--version) printf '%s' "$command"; return 0 ;;
                        -*) printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"; return 0 ;;
                    esac
                fi
                ;;
            setsid|*/setsid)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -c|-f|-w|--ctty|--fork|--wait) i=$((i + 1)) ;;
                        -h|--help|-V|--version) printf '%s' "$command"; return 0 ;;
                        -*)
                            if [[ "$token" =~ ^-[cfw]+$ ]]; then
                                i=$((i + 1))
                            else
                                printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                                return 0
                            fi
                            ;;
                        *) break ;;
                    esac
                done
                ;;
            time|*/time)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -a|-p|-q|-v|--append|--portability|--quiet|--verbose) i=$((i + 1)) ;;
                        -o|-f|--output|--format)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$command"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        -o?*|-f?*|--output=*|--format=*) i=$((i + 1)) ;;
                        -h|--help|-V|--version) printf '%s' "$command"; return 0 ;;
                        -*)
                            if [[ "$token" =~ ^-[apqv]+$ ]]; then
                                i=$((i + 1))
                            else
                                printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                                return 0
                            fi
                            ;;
                        *) break ;;
                    esac
                done
                ;;
            timeout|*/timeout|gtimeout|*/gtimeout)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        --foreground|--preserve-status|--verbose) i=$((i + 1)) ;;
                        -k|-s|--kill-after|--signal)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$command"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        -k?*|-s?*|--kill-after=*|--signal=*) i=$((i + 1)) ;;
                        --help|--version) printf '%s' "$command"; return 0 ;;
                        -*) printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"; return 0 ;;
                        *) break ;;
                    esac
                done
                # timeout consumes one duration before the child command.
                if [[ $i -lt ${#words[@]} ]]; then
                    i=$((i + 1))
                fi
                ;;
            nice|*/nice)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -n|--adjustment)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$command"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        --adjustment=*) i=$((i + 1)) ;;
                        --help|--version) printf '%s' "$command"; return 0 ;;
                        -*)
                            if [[ "$token" =~ ^-[0-9]+$ ]]; then
                                i=$((i + 1))
                            else
                                printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                                return 0
                            fi
                            ;;
                        *) break ;;
                    esac
                done
                ;;
            ionice|*/ionice)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -p|-P|-u|-p?*|-P?*|-u?*|--pid|--pgid|--uid|--pid=*|--pgid=*|--uid=*) printf '%s' "$command"; return 0 ;;
                        -c|-n|--class|--classdata)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$command"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        -c?*|-n?*|--class=*|--classdata=*|-t|--ignore) i=$((i + 1)) ;;
                        -h|--help|-V|--version) printf '%s' "$command"; return 0 ;;
                        -*) printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"; return 0 ;;
                        *) break ;;
                    esac
                done
                ;;
            stdbuf|*/stdbuf)
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -i|-o|-e|--input|--output|--error)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$command"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        -i?*|-o?*|-e?*|--input=*|--output=*|--error=*) i=$((i + 1)) ;;
                        --help|--version) printf '%s' "$command"; return 0 ;;
                        -*) printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"; return 0 ;;
                        *) break ;;
                    esac
                done
                ;;
            xargs|*/xargs)
                if [[ "$mode" != "xargs-child" ]]; then
                    printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                    return 0
                fi
                saw_xargs=1
                i=$((i + 1))
                while [[ $i -lt ${#words[@]} ]]; do
                    token="${words[i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -0|-o|-p|-r|-t|-x|--null|--open-tty|--interactive|--no-run-if-empty|--verbose|--exit|--show-limits)
                            i=$((i + 1)) ;;
                        -a|-d|-E|-I|-J|-L|-n|-P|-R|-S|-s|--arg-file|--delimiter|--eof|--replace|--max-lines|--max-args|--max-procs|--max-replacements|--replsize|--max-chars|--process-slot-var)
                            if [[ $((i + 1)) -ge ${#words[@]} ]]; then
                                printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                                return 0
                            fi
                            i=$((i + 2))
                            ;;
                        -a?*|-d?*|-E?*|-I?*|-J?*|-L?*|-n?*|-P?*|-R?*|-S?*|-s?*|--arg-file=*|--delimiter=*|--eof=*|--replace=*|--max-lines=*|--max-args=*|--max-procs=*|--max-replacements=*|--replsize=*|--max-chars=*|--process-slot-var=*)
                            i=$((i + 1)) ;;
                        -e|-i|-l|-e?*|-i?*|-l?*) i=$((i + 1)) ;;
                        --help|--version)
                            printf '%s' "$K8S_GUARD_NO_XARGS_SENTINEL"
                            return 0
                            ;;
                        -*)
                            printf '%s' "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"
                            return 0
                            ;;
                        *) break ;;
                    esac
                done
                break
                ;;
            *) break ;;
        esac
    done
    if [[ "$mode" == "xargs-child" && "$saw_xargs" != "1" ]]; then
        printf '%s' "$K8S_GUARD_NO_XARGS_SENTINEL"
        return 0
    fi
    [[ $i -lt ${#words[@]} ]] || return 0

    token="${words[i]}"
    base="${token##*/}"
    # Native Windows spellings (`helm.exe`, `C:/tools/kubectl.exe`) are the
    # same tools and must reach the same checks.
    base="${base%.exe}"; base="${base%.EXE}"
    [[ "$base" == "kubectl" || "$base" == "helm" ]] && words[i]="$base"
    printf '%s' "${words[*]:$i}"
}

# Inspect only the executable selected by an effective xargs wrapper. The
# ordinary normalizer deliberately rejects xargs because it constructs argv;
# this narrower pass exists solely to distinguish a quoted command word from
# the same quoted text passed as inert data to a different xargs child.
k8s_guard_xargs_child_contains_kubectl() {
    local command="$1" child normalized word base
    child="$(k8s_guard_normalize_command "$command" xargs-child)"
    case "$child" in
        ""|"$K8S_GUARD_UNSAFE_COMMAND_SENTINEL"|"$K8S_GUARD_NO_XARGS_SENTINEL") return 1 ;;
    esac

    local -a words=()
    read -r -a words <<< "$child"
    [[ ${#words[@]} -gt 0 ]] || return 1
    local i
    for ((i = 0; i < ${#words[@]}; i++)); do
        word="${words[i]}"
        case "$word" in
            \"*\"|\'*\') words[i]="${word:1:${#word}-2}" ;;
        esac
    done

    normalized="$(k8s_guard_normalize_command "${words[*]}")"
    [[ "$normalized" != "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL" ]] || return 1
    read -r -a words <<< "$normalized"
    [[ ${#words[@]} -gt 0 ]] || return 1
    base="${words[0]##*/}"
    [[ "$base" == "kubectl" ]]
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
            local noexec=0
            while [[ $i -lt ${#words[@]} ]]; do
                token="${words[$i]}"
                if [[ "$token" == "-c" || ( "$token" == -[^-]* && "$token" == *c* ) ]]; then
                    return 1
                fi
                # -n (noexec) makes the shell parse the file without
                # executing anything — but a later +n on the same invocation
                # turns execution back on, so track the toggle across the
                # whole option list instead of trusting first sight.
                if [[ "$token" == -[^-]* && "$token" == *n* ]]; then
                    noexec=1
                elif [[ "$token" == +[^+]* && "$token" == *n* ]]; then
                    noexec=0
                fi
                case "$token" in
                    --) i=$((i + 1)); [[ $i -lt ${#words[@]} ]] && path="${words[$i]}"; break ;;
                    -o|+o|--rcfile|--init-file) i=$((i + 2)) ;;
                    -*|+*) i=$((i + 1)) ;;
                    *) path="$token"; break ;;
                esac
            done
            if [[ "$noexec" -eq 1 ]]; then
                return 1
            fi
            ;;
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

# True only for the two reviewed workspace entrypoints whose source text
# legitimately mentions kubectl while dispatching or auditing other commands.
# Exact inode comparison tolerates alternate path spellings; rejecting symlinks
# prevents an exempt name from becoming an alias to different content.
k8s_guard_script_content_exempt() {
    local root="$1" path="$2" candidate
    [[ -n "$root" && -n "$path" && ! -L "$path" ]] || return 1
    for candidate in \
        "$root/scripts/ws" \
        "$root/scripts/ws-audit-permissions.sh"; do
        if [[ -f "$candidate" && "$path" -ef "$candidate" ]]; then
            return 0
        fi
    done
    return 1
}

# Does an executed FILE's own text invoke kubectl? The content-inspection half
# of the guard, shared by both hooks so they cannot drift apart.
#
#   0  yes — deny (or ask, unscoped)
#   1  no
#   2  COULD NOT INSPECT — callers must fail closed, never treat as "no"
#
# WHY NOT `grep -I`
#
# The obvious fix for "a Go binary linking client-go carries `kubectl` in its
# rodata, so `kustomize build` gets denied" is `grep -I`, which skips anything
# grep considers binary. That is wrong, and measurably so: grep's binary
# heuristic keys off NUL bytes, and a perfectly ordinary shell script with one
# NUL in a comment is therefore "binary" to grep while still executing normally
# under bash. `grep -IEq kubectl` on such a file exits 1 — no match — and the
# guard waves through a script whose next line is `kubectl delete namespace`.
# Trading a false-positive class for an evasion vector is not a fix.
#
# So the binary question is answered by FILE FORMAT, not by byte statistics.
# Only recognised executable images are skipped — ELF, PE/COFF (Windows .exe),
# Mach-O — because those are the things whose embedded strings were never a
# control the guard could enforce anyway. The guard's reach has always stopped
# at literal invocations in readable text; the skill says so, and RBAC is the
# boundary beyond it.
#
# EVERYTHING ELSE IS SCANNED, with NULs stripped first so their presence cannot
# hide the text around them. Unknown format therefore means inspected, which is
# the fail-closed direction.
k8s_guard_script_mentions_kubectl() {
    local path="$1" magic text
    [[ -n "$path" ]] || return 1
    [[ -f "$path" ]] || return 1
    # Unreadable is not "no kubectl", it is "no answer". Callers treat 2 as a
    # reason to stop rather than a clean bill of health.
    [[ -r "$path" ]] || return 2

    magic="$(head -c 4 "$path" 2>/dev/null | od -An -tx1 -v 2>/dev/null | tr -d ' \n')" || return 2
    case "$magic" in
        7f454c46*) return 1 ;;                          # ELF
        4d5a*) return 1 ;;                              # PE/COFF — .exe, .dll
        feedface*|feedfacf*|cefaedfe*|cffaedfe*) return 1 ;;  # Mach-O, both endians
    esac

    text="$(tr -d '\000' < "$path" 2>/dev/null)" || return 2
    grep -Eq "$K8S_GUARD_TOOL_RE" <<< "$text"
}

# Mask inert single- and double-quoted spans before deciding whether an unsafe
# compound command is Kubernetes-related. Shell operators and words inside a
# quoted search pattern are data, not executable syntax. Double-quoted spans
# containing expansion syntax and malformed quoting retain the original input
# so callers continue to fail closed.
k8s_guard_mask_inert_quotes() {
    local input="$1" output="" char quote segment word=""
    local i=0 start length=${#1} closed live at_command_start=1 wrapper_operand=0
    local wrapper_kind="" handled=0
    while [[ $i -lt $length ]]; do
        char="${input:i:1}"
        if [[ "$char" != "'" && "$char" != '"' ]]; then
            output+="$char"
            case "$char" in
                $'\n'|$'\r'|';'|'|'|'&'|'('|')')
                    word=""
                    at_command_start=1
                    ;;
                ' '|$'\t')
                    if [[ -n "$word" ]]; then
                        if [[ "$at_command_start" == "1" ]]; then
                            if [[ "$wrapper_operand" == "1" ]]; then
                                wrapper_operand=0
                            else
                                handled=0
                                case "$wrapper_kind" in
                                    env)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -u|--unset|-C|--chdir|-a|--argv0|-P) wrapper_operand=1 ;;
                                            -u?*|-C?*|-a?*|-P?*|--unset=*|--chdir=*|--argv0=*|-i|--ignore-environment|[A-Za-z_][A-Za-z0-9_]*=*) ;;
                                            -S|--split-string|-S?*|--split-string=*) wrapper_kind="" ;;
                                            --help|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                    xargs)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -0|-o|-p|-r|-t|-x|--null|--open-tty|--interactive|--no-run-if-empty|--verbose|--exit|--show-limits) ;;
                                            -a|-d|-E|-I|-J|-L|-n|-P|-R|-S|-s|--arg-file|--delimiter|--eof|--replace|--max-lines|--max-args|--max-procs|--max-replacements|--replsize|--max-chars|--process-slot-var) wrapper_operand=1 ;;
                                            -a?*|-d?*|-E?*|-I?*|-J?*|-L?*|-n?*|-P?*|-R?*|-S?*|-s?*|--arg-file=*|--delimiter=*|--eof=*|--replace=*|--max-lines=*|--max-args=*|--max-procs=*|--max-replacements=*|--replsize=*|--max-chars=*|--process-slot-var=*|-e|-i|-l|-e?*|-i?*|-l?*) ;;
                                            --help|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                    setsid)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -c|-f|-w|--ctty|--fork|--wait|-[cfw]*) ;;
                                            -h|--help|-V|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                    time)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -a|-p|-q|-v|--append|--portability|--quiet|--verbose|-[apqv]*) ;;
                                            -o|-f|--output|--format) wrapper_operand=1 ;;
                                            -o?*|-f?*|--output=*|--format=*) ;;
                                            -h|--help|-V|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                    timeout)
                                        handled=1
                                        case "$word" in
                                            --|--foreground|--preserve-status|--verbose) ;;
                                            -k|-s|--kill-after|--signal) wrapper_operand=1 ;;
                                            -k?*|-s?*|--kill-after=*|--signal=*) ;;
                                            --help|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind="" ;;
                                        esac
                                        ;;
                                    nice)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -n|--adjustment) wrapper_operand=1 ;;
                                            --adjustment=*|-[0-9]*) ;;
                                            --help|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                    ionice)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -p|-P|-u|-p?*|-P?*|-u?*|--pid|--pgid|--uid|--pid=*|--pgid=*|--uid=*) wrapper_kind=""; at_command_start=0 ;;
                                            -c|-n|--class|--classdata) wrapper_operand=1 ;;
                                            -c?*|-n?*|--class=*|--classdata=*|-t|--ignore) ;;
                                            -h|--help|-V|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                    stdbuf)
                                        handled=1
                                        case "$word" in
                                            --) wrapper_kind="" ;;
                                            -i|-o|-e|--input|--output|--error) wrapper_operand=1 ;;
                                            -i?*|-o?*|-e?*|--input=*|--output=*|--error=*) ;;
                                            --help|--version) wrapper_kind=""; at_command_start=0 ;;
                                            -*) ;;
                                            *) wrapper_kind=""; handled=0 ;;
                                        esac
                                        ;;
                                esac
                                if [[ "$handled" != "1" ]]; then
                                    case "$word" in
                                        [A-Za-z_][A-Za-z0-9_]*=*|command|*/command|nohup|*/nohup|--|-p)
                                            ;;
                                        env|*/env) wrapper_kind="env" ;;
                                        xargs|*/xargs) wrapper_kind="xargs" ;;
                                        setsid|*/setsid) wrapper_kind="setsid" ;;
                                        time|*/time) wrapper_kind="time" ;;
                                        timeout|*/timeout|gtimeout|*/gtimeout) wrapper_kind="timeout" ;;
                                        nice|*/nice) wrapper_kind="nice" ;;
                                        ionice|*/ionice) wrapper_kind="ionice" ;;
                                        stdbuf|*/stdbuf) wrapper_kind="stdbuf" ;;
                                        # Control-flow words keep the NEXT word in
                                        # command position — `if true; then "kubectl"
                                        # …` must not mask the quoted command word.
                                        if|then|else|elif|fi|while|until|do|done|'case'|'esac'|'!'|'{'|'}')
                                            ;;
                                        *)
                                            at_command_start=0
                                            ;;
                                    esac
                                fi
                            fi
                        fi
                        word=""
                    fi
                    ;;
                *) word+="$char" ;;
            esac
            i=$((i + 1))
            continue
        fi

        quote="$char"
        start=$i
        i=$((i + 1))
        closed=0
        live=0
        while [[ $i -lt $length ]]; do
            char="${input:i:1}"
            if [[ "$quote" == '"' && "$char" == '\' ]]; then
                i=$((i + 2))
                continue
            fi
            if [[ "$char" == "$quote" ]]; then
                i=$((i + 1))
                closed=1
                break
            fi
            if [[ "$quote" == '"' && ( "$char" == '$' || "$char" == '`' ) ]]; then
                live=1
            fi
            i=$((i + 1))
        done
        if [[ "$closed" != "1" || "$live" == "1" ]]; then
            printf '%s' "$input"
            return 0
        fi

        segment="${input:start:i-start}"
        local quote_is_operand=0 quote_placeholder="q"
        if [[ "$at_command_start" == "1" ]]; then
            if [[ "$wrapper_operand" == "1" ]]; then
                quote_is_operand=1
            elif [[ "$wrapper_kind" == "env" && -z "$word" ]]; then
                case "${segment:1:${#segment}-2}" in
                    [A-Za-z_][A-Za-z0-9_]*=*)
                        quote_is_operand=1
                        # Preserve assignment grammar for the state machine:
                        # a generic placeholder would look like env's child
                        # command and hide the executable that follows it.
                        quote_placeholder="A="
                        ;;
                esac
            else
                case "$wrapper_kind:$word" in
                    env:[A-Za-z_][A-Za-z0-9_]*=|env:-u|env:-C|env:-a|env:-P|env:--unset=|env:--chdir=|env:--argv0=)
                        quote_is_operand=1
                        ;;
                    xargs:-a|xargs:-d|xargs:-E|xargs:-I|xargs:-J|xargs:-L|xargs:-n|xargs:-P|xargs:-R|xargs:-S|xargs:-s|xargs:--arg-file=|xargs:--delimiter=|xargs:--eof=|xargs:--replace=|xargs:--max-lines=|xargs:--max-args=|xargs:--max-procs=|xargs:--max-replacements=|xargs:--replsize=|xargs:--max-chars=|xargs:--process-slot-var=)
                        quote_is_operand=1
                        ;;
                    timeout:|time:-o|time:-f|time:--output=|time:--format=|timeout:-k|timeout:-s|timeout:--kill-after=|timeout:--signal=|nice:-n|nice:--adjustment=|ionice:-c|ionice:-n|ionice:--class=|ionice:--classdata=|stdbuf:-i|stdbuf:-o|stdbuf:-e|stdbuf:--input=|stdbuf:--output=|stdbuf:--error=)
                        quote_is_operand=1
                        ;;
                    :[A-Za-z_][A-Za-z0-9_]*=)
                        quote_is_operand=1
                        ;;
                esac
            fi
        fi
        if [[ "$at_command_start" == "1" && "$quote_is_operand" != "1" ]]; then
            output+="$segment"
            # Track the span's INNER text as word content: a quoted wrapper
            # word ("env", "command") must still match the wrapper case when
            # the word completes. A placeholder here flipped command position
            # off and let the NEXT quoted command word be blanked — a
            # compound `then "env" "kubectl" …` slipped the deny floor.
            word+="${segment:1:${#segment}-2}"
        else
            output+="${segment//?/ }"
            word+="$quote_placeholder"
        fi
    done
    printf '%s' "$output"
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
            grep -Eq "$K8S_GUARD_TOOL_RE" <<< "$normalized"
            return $?
        fi
    done
    return 1
}

# True for the first half of a value the shell would have kept whole: a word
# that ends inside an open quote, or with an unescaped backslash (an escaped
# space). Scanned with shell quoting rules, so an apostrophe inside double
# quotes ("/work/O'Neil") is data, not an open quote. Only meaningful on the
# hooks' whitespace-split view of shell text; real argv never splits.
_k8s_is_split_fragment() {
    local word="$1" char state="plain" i=0 length=${#1}
    while [[ $i -lt $length ]]; do
        char="${word:i:1}"
        case "$state:$char" in
            plain:"\\")
                [[ $((i + 1)) -lt $length ]] || return 0
                i=$((i + 2)); continue ;;
            plain:"'") state="single" ;;
            plain:'"') state="double" ;;
            single:"'") state="plain" ;;
            double:"\\") i=$((i + 2)); continue ;;
            double:'"') state="plain" ;;
        esac
        i=$((i + 1))
    done
    [[ "$state" != "plain" ]]
}

# Print the kubectl verb of an argv, past global options. Only meaningful
# after k8s_guard_evaluate accepted the same argv: anything it lets through
# before the verb is one of the value options named here or valueless.
k8s_guard_verb() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --) shift; break ;;
            --context|-n|--namespace|-f|--filename|-k|--kustomize|-o|--output|--timeout|--grace-period|-l|--selector|--field-selector|--cache-dir|--type|--request-timeout|-c|--container|--field-manager|--raw)
                shift 2 || return 0 ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    [[ $# -gt 0 ]] && printf '%s' "$1"
}

# Classify an inline shell (`bash -c <payload>`) by its payload, the way the
# payload would be classified if run directly. Status:
#   0  the payload invokes kubectl, literally or through a script it runs
#   1  not an inline shell, or a simple payload with no kubectl in reach
#   2  the payload runs a script that could not be read
#   3  UNINSPECTABLE — compound, expanding or nested; callers deny under scope
# Inspecting only the command line used to wave `bash -c ./deploy.sh` through
# unscanned while the same `./deploy.sh` run directly was content-checked.
k8s_guard_inline_shell_status() {
    local cwd="$1" command="$2" masked normalized payload=""
    # The payload's own quoting would trip the compound-form sentinel, so
    # decide "is this an inline shell" from the quote-masked command.
    masked="$(k8s_guard_mask_inert_quotes "$command")"
    normalized="$(k8s_guard_normalize_command "$masked")"
    if [[ "$normalized" == "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL" ]]; then
        # A compound or expanding command that still launches an inline
        # shell somewhere cannot be followed into its payload. Quotes are
        # dropped first so a quoted `"-c"` still reads as the option.
        local inline_re='(^|[[:space:];&|(])([^[:space:]]*/)?(bash|sh)[[:space:]]([^[:space:]]+[[:space:]])*-[A-Za-z]*c([[:space:]]|$)'
        local unquoted="${command//[\"\']/}"
        [[ "$unquoted" =~ $inline_re ]] && return 3
        return 1
    fi
    # Masking blanks quoted operands, a quoted `"-c"` included, so it only
    # names the runner; the -c question goes to the quote-aware word split.
    case "${normalized%% *}" in bash|*/bash|sh|*/sh) ;; *) return 1 ;; esac
    local rc=0
    payload="$(_k8s_inline_payload "$command")" || rc=$?
    case "$rc" in
        0) ;;
        1) return 1 ;;   # no -c before the script operand: a script run
        *) return 3 ;;
    esac
    grep -Eq "$K8S_GUARD_TOOL_RE" <<< "$command" && return 0
    [[ -n "$payload" ]] || return 1
    k8s_guard_has_live_shell_expansion "$payload" && return 3
    normalized="$(k8s_guard_normalize_command "$payload")"
    [[ "$normalized" != "$K8S_GUARD_UNSAFE_COMMAND_SENTINEL" ]] || return 3
    [[ -n "$normalized" ]] || return 1
    # `exec <cmd>` runs <cmd>; judge that. An option to exec (-a, -c, -l)
    # is a shape not worth following.
    if [[ "$normalized" == exec || "$normalized" == "exec "* ]]; then
        payload="${normalized#exec}"; payload="${payload# }"
        [[ -n "$payload" && "$payload" != -* ]] || return 3
        normalized="$payload"
    fi
    _k8s_is_inline_shell "$normalized" && return 3
    [[ "${normalized%% *}" == "eval" ]] && return 3
    local script
    script="$(k8s_guard_script_path "$cwd" "$payload" 2>/dev/null)" || return 1
    k8s_guard_script_mentions_kubectl "$script"
}

# True when a normalized command is `bash`/`sh` with a -c option among its
# own options — those before the script operand. A `-c` after the operand is
# the script's argument (`bash ./run.sh -c config.yaml`).
_k8s_is_inline_shell() {
    local -a words=()
    read -r -a words <<< "$1"
    [[ ${#words[@]} -gt 1 ]] || return 1
    case "${words[0]##*/}" in bash|sh) ;; *) return 1 ;; esac
    local i
    for ((i = 1; i < ${#words[@]}; i++)); do
        case "${words[i]}" in
            -c|-[!-]*c*) return 0 ;;
            -o|+o|--rcfile|--init-file) i=$((i + 1)) ;;
            --) return 1 ;;
            -*|+*) ;;
            *) return 1 ;;
        esac
    done
    return 1
}

# The command string an inline shell will run: the first non-option word
# after the shell, unquoted. Returns 1 when the shell has no -c before its
# first operand (a script run, not an inline shell) and 2 on quoting it
# cannot follow, which the caller treats as uninspectable.
_k8s_inline_payload() {
    local input="$1" char quote="" word="" in_word=0 past_shell=0 saw_c=0
    local i=0 length=${#1}
    local -a out=()
    while [[ $i -le $length ]]; do
        char="${input:i:1}"
        if [[ -n "$quote" ]]; then
            if [[ "$char" == "$quote" ]]; then quote=""
            elif [[ -z "$char" ]]; then return 2
            elif [[ "$quote" == '"' && "$char" == '\' ]]; then i=$((i + 1)); word+="${input:i:1}"
            else word+="$char"; fi
        else
            case "$char" in
                "'"|'"') quote="$char"; in_word=1 ;;
                '\') i=$((i + 1)); word+="${input:i:1}"; in_word=1 ;;
                ' '|$'\t'|'')
                    if [[ $in_word -eq 1 ]]; then out+=("$word"); word=""; in_word=0; fi ;;
                *) word+="$char"; in_word=1 ;;
            esac
        fi
        i=$((i + 1))
    done
    for ((i = 0; i < ${#out[@]}; i++)); do
        word="${out[i]}"
        if [[ $past_shell -eq 0 ]]; then
            case "${word##*/}" in bash|sh) past_shell=1 ;; esac
            continue
        fi
        case "$word" in
            -o|+o|--rcfile|--init-file) i=$((i + 1)); continue ;;
            -c|-[!-]*c*) saw_c=1; continue ;;
            -*|+*) continue ;;
        esac
        [[ $saw_c -eq 1 ]] && { printf '%s' "$word"; return 0; }
        return 1
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

# True for built-in kubectl mutation families whose standard --dry-run flag is
# enforced by kubectl/Kubernetes. Keep unknown verbs and plugins on the normal
# write path: an arbitrary plugin may accept the same spelling without honoring
# Kubernetes dry-run semantics.
_k8s_supports_dry_run() {
    case "$1" in
        annotate|apply|autoscale|create|delete|expose|label|patch|replace|run|scale|set|taint) return 0 ;;
        rollout) [[ "${2:-}" == "undo" ]] ;;
        *) return 1 ;;
    esac
}

# True when a kubectl resource type or manifest Kind is cluster-scoped (has no
# namespace). A write to one of these can never be bounded to the guard's
# namespace scope, so the guard fails closed on it regardless of -n. Best-effort
# accident-prevention list of the common/dangerous types (this is not a security
# boundary); accepts singular/plural/short-alias and PascalCase Kind forms.
# ASCII lowercase fold. `${var,,}` would be shorter but is bash 4.0+, and this
# file is sourced by .claude/hooks/gdd-permission-hook.sh — which runs under
# whatever `bash` PATH resolves to, i.e. 3.2.57 on a stock Mac (Apple froze
# there in 2007 over the GPLv3 relicense). A `bad substitution` here does not
# fail loudly; it makes k8s_guard_evaluate return nothing, which the hook then
# treats as "guard evaluation failed" and downgrades to an ask. Safe, but the
# guard would be silently inert on every Mac. LC_ALL=C keeps the fold
# locale-independent; kubectl resource types and Kinds are ASCII.
_k8s_lc() { LC_ALL=C printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

_k8s_is_cluster_scoped() {
    local t; t="$(_k8s_lc "$1")"   # folds PascalCase Kinds onto the same entries
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

# Positive built-in scope knowledge; an unfamiliar kind is never namespaced by
# default. Group matching prevents a CRD borrowing a built-in kind's scope.
_k8s_builtin_namespaced() {
    local t group="${2-*}" builtin_group
    t="$(_k8s_lc "${1%%/*}")"
    if [[ "$t" == *.* ]]; then group="${t#*.}"; t="${t%%.*}"; fi
    case "$t" in
        pod|pods|po|service|services|svc|configmap|configmaps|cm|secret|secrets|\
        persistentvolumeclaim|persistentvolumeclaims|pvc|replicationcontroller|replicationcontrollers|rc|\
        serviceaccount|serviceaccounts|sa|endpoints|ep|limitrange|limitranges|limits|\
        resourcequota|resourcequotas|quota) builtin_group="" ;;
        deployment|deployments|deploy|replicaset|replicasets|rs|daemonset|daemonsets|ds|\
        statefulset|statefulsets|sts|controllerrevision|controllerrevisions) builtin_group=apps ;;
        job|jobs|cronjob|cronjobs|cj) builtin_group=batch ;;
        role|roles|rolebinding|rolebindings) builtin_group=rbac.authorization.k8s.io ;;
        ingress|ingresses|ing|networkpolicy|networkpolicies|netpol) builtin_group=networking.k8s.io ;;
        horizontalpodautoscaler|horizontalpodautoscalers|hpa) builtin_group=autoscaling ;;
        poddisruptionbudget|poddisruptionbudgets|pdb) builtin_group=policy ;;
        endpointslice|endpointslices) builtin_group=discovery.k8s.io ;;
        lease|leases) builtin_group=coordination.k8s.io ;;
        event|events|ev) [[ "$group" == events.k8s.io ]] && return 0; builtin_group="" ;;
        *) return 1 ;;
    esac
    [[ "$group" == '*' || "$group" == "$builtin_group" ]]
}

_k8s_verified_namespaced_type() {
    local t="${1%%/*}" context="$2" discovered name
    _k8s_builtin_namespaced "$t" && return 0
    # Require the canonical group-qualified name for custom positional types.
    # Unqualified names and aliases can resolve to a different API group.
    [[ "$t" == *.* && "$t" =~ ^[a-z0-9.-]+$ ]] || return 1
    discovered="$("${KUBECTL:-kubectl}" --context "$context" --request-timeout=5s api-resources --cached=false --namespaced=true -o name 2>/dev/null)" || return 1
    while IFS= read -r name; do [[ "$name" == "$t" ]] && return 0; done <<< "$discovered"
    return 1
}

_k8s_manifest_scope() {
    local kind="$1" version="$2" context="$3" group="" endpoint discovery scope
    [[ "$version" =~ ^[a-z0-9][a-z0-9.-]*(/[a-z0-9][a-z0-9]*)?$ && "$kind" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || return 1
    [[ "$version" != */* ]] || group="${version%/*}"
    if _k8s_builtin_namespaced "$kind" "$group"; then printf namespaced; return 0; fi
    endpoint="/api/$version"
    [[ -z "$group" ]] || endpoint="/apis/$version"
    discovery="$("${KUBECTL:-kubectl}" --context "$context" --request-timeout=5s get --raw "$endpoint" 2>/dev/null)" || return 1
    # Subresources do not establish the scope of the parent resource. Demand
    # exactly one Boolean scope result; malformed or ambiguous discovery closes.
    scope="$(KIND="$kind" yq -r '[.resources[] | select(.kind == strenv(KIND) and (.name | contains("/") | not)) | select(.namespaced | tag == "!!bool") | .namespaced] | unique | .[]' <<< "$discovery" 2>/dev/null)" || return 1
    case "$scope" in true) printf namespaced ;; false) printf cluster ;; *) return 1 ;; esac
}

# True for the namespace resource type (full/plural/short-alias). Used to let an
# in-scope namespace's own create/delete through (see k8s_guard_evaluate) even
# though _k8s_is_cluster_scoped also matches it for the general blanket block.
_k8s_is_namespace_type() {
    case "$(_k8s_lc "$1")" in namespace|namespaces|ns) return 0 ;; *) return 1 ;; esac
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
    local flag="$1" label="$2" ns_arg="$3" scope_ns_csv="$4" input_path="${5:-}" context="$6"
    local parsed="" doc_kind doc_version doc_ns doc_name doc_scope docs_seen=0 action empty_reason
    case "$flag" in
        -f) action="contains"; empty_reason="parsed no documents (yq failed or empty)" ;;
        -k|helm) action="renders"; empty_reason="rendered no documents" ;;
        *) printf 'BLOCK:precondition:%s %s uses an unsupported validation source' "$flag" "$label"; return 1 ;;
    esac
    # `select(. != null)` drops empty documents — a leading `---` or a
    # comment-only tail — which kubectl skips too; counting them demanded a
    # namespace for a document that does not exist.
    # `|` separates the fields because tab is whitespace to `read`: an empty
    # namespace column collapsed and the name slid into its place. No Kind,
    # namespace or object name can contain `|`.
    local query='select(. != null) | ( (select(.kind == "List") | .items[]) , (select(.kind != "List")) ) | (.kind // "") + "|" + (.apiVersion // "") + "|" + (.metadata.namespace // "") + "|" + (.metadata.name // "")'
    if [[ -n "$input_path" ]]; then
        parsed="$(yq -r "$query" "$input_path" 2>/dev/null || true)"
    else
        parsed="$(yq -r "$query" 2>/dev/null || true)"
    fi
    [[ -n "$parsed" ]] || { printf 'BLOCK:precondition:%s %s %s' "$flag" "$label" "$empty_reason"; return 1; }
    while IFS='|' read -r doc_kind doc_version doc_ns doc_name; do
        doc_name="${doc_name%$'\r'}"
        # yq prints `---` between the rows of a multi-document file. Read as a
        # row it was a document with no namespace — or, once scope discovery
        # arrived, one whose scope "cannot be verified" — so every
        # multi-document manifest failed whatever its documents said.
        [[ "${doc_kind%$'\r'}" == "---" && -z "$doc_version" ]] && continue
        docs_seen=$((docs_seen + 1))
        # A Namespace manifest naming an in-scope namespace is the same act
        # as `create namespace <in-scope>`, which the CLI path already allows.
        # Core v1 only: a custom resource named Namespace in another API
        # group gets no exemption from the cluster-scope checks below.
        if [[ -n "$doc_kind" && "${doc_version%$'\r'}" == "v1" ]] && _k8s_is_namespace_type "$doc_kind"; then
            if [[ -z "$doc_name" || "$doc_name" == "null" ]]; then
                printf 'BLOCK:precondition:%s %s %s a Namespace with no name' "$flag" "$label" "$action"; return 1
            fi
            _k8s_ns_in_csv "$doc_name" "$scope_ns_csv" || {
                printf 'BLOCK:scope:%s %s %s namespace %s, outside the guard scope (%s)' "$flag" "$label" "$action" "$doc_name" "$scope_ns_csv"; return 1;
            }
            continue
        fi
        if [[ -n "$doc_kind" ]] && _k8s_is_cluster_scoped "$doc_kind"; then
            printf 'BLOCK:unbounded:%s %s %s a cluster-scoped %s, which is not namespace-scope-bounded' "$flag" "$label" "$action" "$doc_kind"; return 1
        fi
        doc_scope="$(_k8s_manifest_scope "$doc_kind" "$doc_version" "$context")" || {
            printf 'BLOCK:precondition:%s %s cannot verify namespace scope for %s (%s)' "$flag" "$label" "$doc_kind" "$doc_version"; return 1;
        }
        if [[ "$doc_scope" == cluster ]]; then
            printf 'BLOCK:unbounded:%s %s %s a cluster-scoped %s, which is not namespace-scope-bounded' "$flag" "$label" "$action" "$doc_kind"; return 1
        fi
        [[ -z "$doc_ns" || "$doc_ns" == "null" ]] && doc_ns="$ns_arg"
        if [[ -z "$doc_ns" ]]; then
            if [[ "$flag" == "-f" ]]; then
                printf 'BLOCK:precondition:-f %s has a doc with no namespace and no -n (cannot bound to the guard scope)' "$label"
            else
                printf 'BLOCK:precondition:%s %s renders a doc with no namespace and no -n (cannot bound to the guard scope)' "$flag" "$label"
            fi
            return 1
        fi
        _k8s_ns_in_csv "$doc_ns" "$scope_ns_csv" || {
            printf 'BLOCK:scope:%s %s targets namespace %s outside the guard scope (%s)' "$flag" "$label" "$doc_ns" "$scope_ns_csv"; return 1;
        }
    done <<< "$parsed"
    [[ $docs_seen -gt 0 ]] || { printf 'BLOCK:precondition:%s %s %s' "$flag" "$label" "$empty_reason"; return 1; }
}

_k8s_kustomization_file() {
    local dir="$1" name
    for name in kustomization.yaml kustomization.yml Kustomization; do
        [[ -f "$dir/$name" ]] && { printf '%s' "$dir/$name"; return 0; }
    done
    return 1
}

_k8s_kustomize_refs() {
    local file="$1"
    yq -r '[
      (.resources // [])[],
      (.bases // [])[],
      (.components // [])[],
      (.patchesStrategicMerge // [])[],
      ((.patchesJson6902 // [])[] | (.path // "")),
      ((.patches // [])[] | select(tag == "!!str")),
      ((.patches // [])[] | select(tag == "!!map") | (.path // "")),
      (.generators // [])[],
      (.transformers // [])[],
      (.configurations // [])[],
      (.crds // [])[],
      ((.configMapGenerator // [])[] | (.files // [])[]),
      ((.configMapGenerator // [])[] | (.envs // [])[]),
      ((.secretGenerator // [])[] | (.files // [])[]),
      ((.secretGenerator // [])[] | (.envs // [])[]),
      (.openapi.path // "")
    ] | .[] | select(. != "" and . != null)' "$file" 2>/dev/null
}

_k8s_validate_kustomize_dir() {
    local root_real="$1" dir="$2"
    local dir_real file refs ref path candidate probe probe_real
    [[ -L "$dir" ]] && { echo "symlinked kustomization directory is not allowed: $dir"; return 1; }
    dir_real="$(cd "$dir" 2>/dev/null && pwd -P)" || { echo "cannot resolve local kustomization directory: $dir"; return 1; }
    case "$dir_real/" in
        "$root_real/"*) : ;;
        *) echo "kustomization directory escapes the selected local root: $dir"; return 1 ;;
    esac

    case "${_K8S_KUSTOMIZE_VISITED:-}" in
        *$'\n'"$dir_real"$'\n'*) return 0 ;;
    esac
    _K8S_KUSTOMIZE_VISITED="${_K8S_KUSTOMIZE_VISITED:-}"$'\n'"$dir_real"$'\n'

    file="$(_k8s_kustomization_file "$dir_real")" || {
        echo "local kustomization directory has no kustomization file: $dir"
        return 1
    }
    [[ -L "$file" ]] && { echo "symlinked kustomization file is not allowed: $file"; return 1; }
    if ! refs="$(_k8s_kustomize_refs "$file")"; then
        echo "could not parse local kustomization file: $file"
        return 1
    fi

    while IFS= read -r ref || [[ -n "$ref" ]]; do
        [[ -n "$ref" ]] || continue
        if [[ "$ref" =~ [[:cntrl:]] ]]; then
            echo "kustomization reference contains a control character"
            return 1
        fi
        case "$ref" in
            *://*|*::*|*'?'*|*'#'*|*//*|git@*:*|/*|\\*|[A-Za-z]:[/\\]*)
                echo "remote or absolute kustomization reference is not allowed: $ref"
                return 1
                ;;
        esac
        # Parent traversal is how every real overlay reaches its base
        # (`../../base`), so it is allowed; the resolved-path check below
        # keeps it inside the bound.

        # Generator files may use key=path syntax. Validate the path side;
        # remote/query forms were already rejected above before stripping.
        path="$ref"
        case "$path" in *=*) path="${path#*=}" ;; esac
        [[ -n "$path" ]] || { echo "empty kustomization file reference"; return 1; }
        candidate="$dir_real/$path"
        [[ -e "$candidate" || -L "$candidate" ]] || {
            echo "local kustomization reference does not exist: $ref"
            return 1
        }
        [[ -L "$candidate" ]] && {
            echo "symlinked kustomization reference is not allowed: $ref"
            return 1
        }
        if [[ -d "$candidate" ]]; then probe="$candidate"; else probe="${candidate%/*}"; fi
        probe_real="$(cd "$probe" 2>/dev/null && pwd -P)" || {
            echo "cannot resolve local kustomization reference: $ref"
            return 1
        }
        case "$probe_real/" in
            "$root_real/"*) : ;;
            *) echo "kustomization reference escapes the repository holding the overlay ($root_real): $ref"; return 1 ;;
        esac
        if [[ -d "$candidate" ]]; then
            _k8s_validate_kustomize_dir "$root_real" "$candidate" || return 1
        fi
    done <<< "$refs"
}

k8s_guard_validate_kustomize_tree() {
    local root="$1" root_real
    [[ -d "$root" && ! -L "$root" ]] || {
        echo "kustomization target is not a non-symlink local directory: $root"
        return 1
    }
    root_real="$(cd "$root" 2>/dev/null && pwd -P)" || return 1
    _K8S_KUSTOMIZE_VISITED=""
    _k8s_validate_kustomize_dir "$(_k8s_kustomize_bound "$root_real")" "$root_real"
}

# The directory every kustomize reference must resolve inside: the nearest
# enclosing Git repository (a `.git` directory or worktree file), else the
# overlay itself. A repository is the unit someone reviewed; a reference that
# leaves it could pull a stray file — a secretGenerator reading ~/.ssh — into
# a Secret applied to the cluster.
_k8s_kustomize_bound() {
    local dir="$1"
    while [[ -n "$dir" ]]; do
        [[ -e "$dir/.git" ]] && { printf '%s' "$dir"; return 0; }
        [[ "$dir" == "/" || "$dir" != */* ]] && break
        dir="${dir%/*}"
        [[ -n "$dir" ]] || dir="/"
    done
    printf '%s' "$1"
}

# True when raw shell text, split on whitespace as the hooks see it, holds a
# word that is half of a quoted or escaped value. Checked on the text before
# normalization, which strips balanced outer quotes and would make the
# apostrophe in "/work/O'Neil" look like an open quote.
k8s_guard_has_split_value() {
    local -a words=()
    read -r -a words <<< "$1"
    local word
    for word in ${words[@]+"${words[@]}"}; do
        _k8s_is_split_fragment "$word" && return 0
    done
    return 1
}

# Print the name of a command-local assignment that redirects kubectl or helm
# to other credentials or another cluster (`KUBECONFIG=other.yaml kubectl …`),
# else nothing. Normalization drops such assignments, and the guard's own
# current-context probe reads the hook's environment, not the command's, so
# under a scope these are refused outright rather than half-checked.
k8s_guard_env_override() {
    local -a words=()
    read -r -a words <<< "$1"
    local word
    # Only the prefix before the command word: leading assignments, and those
    # an `env` (with its options) sets up. Later words are the tool's data.
    local i
    for ((i = 0; i < ${#words[@]}; i++)); do
        word="${words[i]#[\"\']}"
        case "$word" in
            KUBECONFIG=*|HELM_KUBE*=*|HELM_NAMESPACE=*) printf '%s=' "${word%%=*}"; return 0 ;;
            # Clearing the environment, or unsetting KUBECONFIG, changes the
            # kubeconfig the tool reads away from the one the guard checked.
            -i|--ignore-environment|-) printf 'env %s' "$word"; return 0 ;;
            -u|--unset)
                case "${words[i + 1]:-}" in KUBECONFIG|HELM_KUBE*|HELM_NAMESPACE) printf 'env -u %s' "${words[i + 1]}"; return 0 ;; esac
                i=$((i + 1)) ;;
            -uKUBECONFIG|--unset=KUBECONFIG) printf 'env %s' "$word"; return 0 ;;
            # Other operand-taking options: skip the operand, or `env -C dir
            # KUBECONFIG=…` hides the assignment behind it.
            -C|--chdir|-a|--argv0|-P) i=$((i + 1)) ;;
            [A-Za-z_]*=*|env|*/env|-*) ;;
            *) return 1 ;;
        esac
    done
    return 1
}

# Print a BLOCK:context verdict when kubeconfig's current context is not the
# scope's, else nothing. An empty answer means kubectl has no current context
# and the tool will refuse to run, so there is nothing to compare.
_k8s_current_context_mismatch() {
    local scope_ctx="$1" tool="$2" remedy="$3" current
    current="$("${KUBECTL:-kubectl}" config current-context 2>/dev/null || true)"
    current="${current%$'\r'}"
    [[ -n "$current" && "$current" != "$scope_ctx" ]] || return 0
    printf 'BLOCK:context:kubectl'"'"'s current context %s is not the guard-scope context %s, so plain %s would act on %s — %s' "$current" "$scope_ctx" "$tool" "$current" "$remedy"
}

# helm, classified with the same verdicts as kubectl. Under a scope a write is
# previewed by helm itself — install/upgrade with `--dry-run=server -o json`,
# uninstall/rollback/test from the stored manifests and hooks — and every
# resource goes through the -f/-k checks. A remote chart is refused with the
# pull-then-install route, so its crds/ directory can be checked too.
_k8s_guard_evaluate_helm() {
    local scope_ctx="$1" scope_ns_csv="$2"; shift 2
    local -a args=("$@") pos=()
    local i=0 a verb="" kube_ctx="" kube_ctx_present=0 ns_arg="" all_ns=0 dry_run=0 skip_crds=0 post_renderer=0 options_done=0
    local generate_name=0
    # Same split-value refusal as kubectl's, on any helm command: a value
    # flag that consumes half of `'a list'` leaves `list` in the verb slot.
    if [[ "${K8S_GUARD_NO_SPLIT_CHECK:-0}" != "1" ]]; then
        for ((i = 0; i < ${#args[@]}; i++)); do
            [[ "${args[i]}" == "--" ]] && break
            if _k8s_is_split_fragment "${args[i]}"; then
                printf 'BLOCK:precondition:a quoted or escaped value with whitespace (%s) cannot be tokenized safely in a helm command; pass it without spaces or from a values file' "${args[i]}"
                return 0
            fi
        done
        i=0
    fi
    while [[ $i -lt ${#args[@]} ]]; do
        a="${args[$i]}"
        if [[ $options_done -eq 1 ]]; then
            if [[ -z "$verb" ]]; then verb="$a"; else pos+=("$a"); fi
            i=$((i + 1)); continue
        fi
        case "$a" in
            --) options_done=1 ;;
            --kube-context) kube_ctx_present=1; kube_ctx="${args[$((i + 1))]:-}"; i=$((i + 2)); continue ;;
            --kube-context=*) kube_ctx_present=1; kube_ctx="${a#*=}" ;;
            -n|--namespace) ns_arg="${args[$((i + 1))]:-}"; i=$((i + 2)); continue ;;
            -n=*|--namespace=*) ns_arg="${a#*=}" ;;
            -n?*) ns_arg="${a#-n}" ;;
            -A|--all-namespaces) all_ns=1 ;;
            --kubeconfig|--kubeconfig=*|--kube-apiserver|--kube-apiserver=*|--kube-token|--kube-token=*|--kube-as-user|--kube-as-user=*|--kube-as-group|--kube-as-group=*|--kube-ca-file|--kube-ca-file=*|--kube-tls-server-name|--kube-tls-server-name=*|--kube-insecure-skip-tls-verify|--kube-insecure-skip-tls-verify=*)
                printf 'BLOCK:context:%s cannot override the guarded Kubernetes connection or credentials' "${a%%=*}"
                return 0
                ;;
            --post-renderer|--post-renderer-args) post_renderer=1; i=$((i + 2)); continue ;;
            --post-renderer=*|--post-renderer-args=*) post_renderer=1 ;;
            -f|--values|--set|--set-string|--set-file|--set-json|--set-literal|--version|--repo|--timeout|--description|--username|--password|--ca-file|--cert-file|--key-file|--keyring|--name-template|-l|--labels|-o|--output|--history-max|--max|--offset|--filter|--revision|--burst-limit|--qps|--registry-config|--repository-cache|--repository-config|--time-format)
                i=$((i + 2)); continue ;;
            -f?*) ;;
            --dry-run) dry_run=1 ;;
            --dry-run=*) [[ "${a#*=}" == "none" ]] || dry_run=1 ;;
            --skip-crds) skip_crds=1 ;;
            -g|--generate-name) generate_name=1 ;;
            --reuse-values|--reset-then-reuse-values|--reset-values|--atomic|--wait|--wait-for-jobs|--create-namespace|--force|--devel|--dependency-update|--disable-openapi-validation|-i|--install|--cleanup-on-fail|--no-hooks|--render-subchart-notes|--skip-schema-validation|--take-ownership|--enable-dns|--insecure-skip-tls-verify|--pass-credentials|--plain-http|--verify|--debug|--keep-history|--hide-notes|--include-crds|-a|--all|--deployed|--failed|--pending|--superseded|--uninstalled|--uninstalling|--short|-q|--date|-r|--reverse|--no-headers|--hide-secret|--rollback-on-failure|--force-replace|--force-conflicts|--server-side|--recreate-pods|--cascade|--cascade=*) ;;
            --*=*) ;;   # a self-contained equals form cannot shift a positional
            -*)
                # After a read or a local verb an option cannot make the
                # command a cluster write; elsewhere it may shift a positional.
                if [[ -z "$verb" ]] || { ! _k8s_helm_is_read_verb "$verb" && ! _k8s_helm_is_local_verb "$verb"; }; then
                    printf 'BLOCK:precondition:unrecognized helm option before the chart: %s' "$a"
                    return 0
                fi
                ;;
            *) if [[ -z "$verb" ]]; then verb="$a"; else pos+=("$a"); fi ;;
        esac
        i=$((i + 1))
    done

    local read_verdict="READ_IN_SCOPE"
    [[ -z "$scope_ctx" ]] && read_verdict="READ_NO_SCOPE"
    # Local housekeeping — plugins, registries, repos, chart files — never
    # touches the cluster, but it can run or fetch code, so it is no read for
    # the hooks to auto-approve: NOT_K8S hands it to normal approval. A
    # post-renderer turns template/lint into running a local binary. Neither
    # reaches the cluster, so neither needs the context checks below; nor do
    # the offline reads.
    if _k8s_helm_is_local_verb "$verb"; then printf 'NOT_K8S'; return 0; fi
    if [[ $post_renderer -eq 1 ]] && [[ "$verb" == template || "$verb" == lint ]]; then printf 'NOT_K8S'; return 0; fi
    case "$verb" in
        ""|template|lint|show|inspect|search|version|env|help|completion|verify) printf '%s' "$read_verdict"; return 0 ;;
    esac

    if [[ -n "$scope_ctx" ]]; then
        # Exported HELM_KUBE* settings move helm off the kubeconfig the
        # context checks read, and a command-line prefix is not where they
        # live, so check the environment helm will inherit.
        local env_name
        for env_name in HELM_KUBEAPISERVER HELM_KUBETOKEN HELM_KUBEASUSER HELM_KUBEASGROUPS HELM_KUBECAFILE HELM_KUBEINSECURE_SKIP_TLS_VERIFY HELM_KUBETLS_SERVER_NAME; do
            if [[ -n "${!env_name:-}" ]]; then
                printf 'BLOCK:context:%s is set in the environment, which points helm at a connection the guard does not check' "$env_name"; return 0
            fi
        done
        if [[ $kube_ctx_present -eq 1 ]]; then
            [[ "$kube_ctx" == "$scope_ctx" ]] || {
                printf 'BLOCK:context:explicit --kube-context %s != the guard-scope context %s' "${kube_ctx:-(empty)}" "$scope_ctx"; return 0;
            }
        elif [[ -n "${HELM_KUBECONTEXT:-}" && "$HELM_KUBECONTEXT" != "$scope_ctx" ]]; then
            printf 'BLOCK:context:HELM_KUBECONTEXT %s != the guard-scope context %s' "$HELM_KUBECONTEXT" "$scope_ctx"; return 0
        elif [[ -z "${HELM_KUBECONTEXT:-}" ]]; then
            local mismatch
            mismatch="$(_k8s_current_context_mismatch "$scope_ctx" helm "pass --kube-context $scope_ctx")"
            [[ -z "$mismatch" ]] || { printf '%s' "$mismatch"; return 0; }
        fi
    fi
    if _k8s_helm_is_read_verb "$verb"; then printf '%s' "$read_verdict"; return 0; fi
    case "$verb" in
        install|upgrade|uninstall|delete|del|un|rollback|test) ;;
        *)
            [[ -z "$scope_ctx" ]] && { printf 'WRITE_NO_SCOPE'; return 0; }
            printf 'BLOCK:unbounded:helm %s is not a helm command the guard recognizes, so it cannot be bounded' "$verb"; return 0
            ;;
    esac
    [[ -z "$scope_ctx" ]] && { printf 'WRITE_NO_SCOPE'; return 0; }
    [[ $all_ns -eq 1 ]] && { printf 'BLOCK:unbounded:--all-namespaces write is not scope-bounded'; return 0; }
    if [[ $post_renderer -eq 1 ]]; then
        printf 'BLOCK:unbounded:a helm --post-renderer rewrites the manifests after the guard has checked them'; return 0
    fi

    local target_ns="${ns_arg:-${HELM_NAMESPACE:-}}"
    if [[ -z "$target_ns" ]]; then
        target_ns="$("${KUBECTL:-kubectl}" config view --minify --context "$scope_ctx" -o 'jsonpath={..namespace}' 2>/dev/null)"
        [[ -n "$target_ns" ]] || target_ns="default"
    fi
    _k8s_ns_in_csv "$target_ns" "$scope_ns_csv" || {
        printf 'BLOCK:scope:helm %s targets namespace %s outside the guard scope (%s)' "$verb" "$target_ns" "$scope_ns_csv"; return 0;
    }
    # The user's own dry run writes nothing; no preview needed.
    [[ $dry_run -eq 1 ]] && { printf 'DRY_RUN_IN_SCOPE'; return 0; }

    # What a helm write touches is decided by helm: values merged with the
    # release's, `.Release.IsUpgrade`, stored manifests and hooks. An offline
    # `helm template` gets each of those subtly wrong, so ask helm itself —
    # every call below is a read — and check what it reports.
    local -a conn=(--kube-context "$scope_ctx" --namespace "$target_ns")
    local preview="" label="" release chart chart_path
    case "$verb" in
        install|upgrade)
            if [[ $generate_name -eq 1 ]] || [[ "$verb" == install && ${#pos[@]} -eq 1 ]]; then
                printf 'BLOCK:precondition:helm %s --generate-name picks a name the guard cannot preview with; name the release' "$verb"; return 0
            fi
            [[ ${#pos[@]} -eq 2 ]] || { printf 'BLOCK:precondition:helm %s expects NAME CHART, got %s positional arguments' "$verb" "${#pos[@]}"; return 0; }
            release="${pos[0]}"; chart="${pos[1]}"; label="$chart"
            chart_path="$chart"
            [[ -e "$chart_path" ]] || chart_path="$(_k8s_normalize_path "$chart")"
            case "$chart" in oci://*|http://*|https://*) chart_path="" ;; esac
            if [[ -z "$chart_path" ]] || { [[ ! -d "$chart_path" ]] && [[ ! -f "$chart_path" || "$chart_path" != *.tgz ]]; }; then
                printf 'BLOCK:precondition:helm %s of %s cannot be inspected without fetching it — run `helm pull %s --untar --untardir <dir>` first, then install from that directory' "$verb" "$chart" "$chart"
                return 0
            fi
            # CRDs under crds/ are installed outside the release manifest,
            # and every CRD is cluster-scoped.
            if [[ $skip_crds -eq 0 ]] && _k8s_helm_chart_has_crds "$chart_path"; then
                printf 'BLOCK:unbounded:chart %s installs CRDs from its crds/ directory, which are cluster-scoped (--skip-crds if they are already installed)' "$chart"; return 0
            fi
            preview="$(_k8s_helm_preview_json "${HELM:-helm}" "${args[@]}" "${conn[@]}" --dry-run=server -o json)" || {
                printf 'BLOCK:precondition:helm %s %s could not be previewed with --dry-run=server (missing dependencies, or the cluster is unreachable)' "$verb" "$chart"; return 0;
            }
            ;;
        uninstall|delete|del|un|test)
            [[ ${#pos[@]} -ge 1 ]] || { printf 'BLOCK:precondition:helm %s needs a release name' "$verb"; return 0; }
            local rel; label="release ${pos[*]}"
            for rel in "${pos[@]}"; do
                local part=""
                if [[ "$verb" != test ]]; then
                    part="$("${HELM:-helm}" get manifest "$rel" "${conn[@]}" 2>/dev/null)" || {
                        printf 'BLOCK:precondition:could not read the stored manifest of release %s' "$rel"; return 0;
                    }
                fi
                preview+="$part"$'\n---\n'"$("${HELM:-helm}" get hooks "$rel" "${conn[@]}" 2>/dev/null || true)"$'\n---\n'
            done
            ;;
        rollback)
            [[ ${#pos[@]} -eq 2 ]] || { printf 'BLOCK:precondition:helm rollback under a scope needs the revision named (helm rollback <release> <revision>), so the guard can read what it restores'; return 0; }
            label="release ${pos[0]} revision ${pos[1]}"
            preview="$("${HELM:-helm}" get manifest "${pos[0]}" --revision "${pos[1]}" "${conn[@]}" 2>/dev/null)" || {
                printf 'BLOCK:precondition:could not read revision %s of release %s' "${pos[1]}" "${pos[0]}"; return 0;
            }
            preview+=$'\n---\n'"$("${HELM:-helm}" get hooks "${pos[0]}" --revision "${pos[1]}" "${conn[@]}" 2>/dev/null || true)"
            ;;
    esac
    # A release with no resources (or no hooks for `test`) touches nothing.
    if [[ -z "$(tr -d '[:space:]-' <<< "$preview")" ]]; then printf 'WRITE_IN_SCOPE'; return 0; fi
    local validation
    validation="$(_k8s_validate_rendered_docs helm "$label" "$target_ns" "$scope_ns_csv" "" "$scope_ctx" <<< "$preview")" || { printf '%s' "$validation"; return 0; }
    printf 'WRITE_IN_SCOPE'
}

# Run a helm dry-run that prints a release as JSON and print its manifest
# and hook manifests as one YAML stream.
_k8s_helm_preview_json() {
    local json
    json="$("$@" 2>/dev/null)" || return 1
    yq -p json -r '([.manifest] + [(.hooks // [])[] | .manifest]) | .[] | select(. != null) | . + "\n---"' <<< "$json" 2>/dev/null
}

# True when a local chart (directory or .tgz) carries files under crds/.
_k8s_helm_chart_has_crds() {
    local chart="$1"
    if [[ -d "$chart" ]]; then
        [[ -d "$chart/crds" && -n "$(ls -A "$chart/crds" 2>/dev/null)" ]]
    else
        tar -tzf "$chart" 2>/dev/null | grep -Eq '^[^/]+/crds/.+'
    fi
}

# helm commands that only read: the cluster, a chart, or helm itself.
_k8s_helm_is_read_verb() {
    case "$1" in
        list|ls|status|get|history|hist|show|inspect|search|template|lint|version|env|help|completion|verify) return 0 ;;
        *) return 1 ;;
    esac
}

# helm commands that change local state or a registry, never the cluster.
_k8s_helm_is_local_verb() {
    case "$1" in
        pull|fetch|package|repo|dependency|dep|plugin|registry|create|push) return 0 ;;
        *) return 1 ;;
    esac
}

# Print one verdict: NOT_K8S | READ_NO_SCOPE | WRITE_NO_SCOPE |
# READ_IN_SCOPE | DRY_RUN_IN_SCOPE | WRITE_IN_SCOPE | BLOCK:<reason>
# Usage: k8s_guard_evaluate <context> <namespaces-csv> <argv...>
k8s_guard_evaluate() {
    local scope_ctx="$1" scope_ns_csv="$2"; shift 2
    # Recognize both `kubectl ...` and `ws k8s ...` forms. Only the raw form
    # runs against kubectl's current context; `ws k8s` injects the scope's.
    local raw_form=0
    if [[ "$1" == "helm" ]]; then shift; _k8s_guard_evaluate_helm "$scope_ctx" "$scope_ns_csv" "$@"; return 0
    elif [[ "$1" == "kubectl" ]]; then shift; raw_form=1
    elif [[ "$1" == *"/ws" || "$1" == "ws" || "$1" == "bash" ]]; then
        while [[ $# -gt 0 && "$1" != "k8s" ]]; do shift; done
        [[ "$1" == "k8s" ]] && shift || { printf 'NOT_K8S'; return 0; }
    else
        printf 'NOT_K8S'; return 0
    fi
    local verb="" verb2="" ctx_arg="" ctx_arg_present=0 ns_arg="" all_ns=0 raw_api=0 a all_ns_value namespaced_value
    local dry_run_mode="" dry_run_seen=0 options_done=0
    local ffiles=()
    local kdirs=()
    local rest_pos=()   # positional resource names after verb + resource-type
    local args=("$@")
    local i=0 verb_index=-1 verb2_index=-1 first_fragment=-1 dd_index=-1 rest_first_index=-1
    # Only shell text with its quotes intact can show a split value. The
    # wrapper's real argv never splits, and the hooks' quote-stripped view
    # cannot tell; both set K8S_GUARD_NO_SPLIT_CHECK=1, and the hooks run
    # this check on a separate quote-preserving view instead.
    if [[ "${K8S_GUARD_NO_SPLIT_CHECK:-0}" != "1" ]]; then
        for ((i = 0; i < ${#args[@]}; i++)); do
            [[ "${args[i]}" == "--" ]] && break
            if _k8s_is_split_fragment "${args[i]}"; then first_fragment=$i; break; fi
        done
    fi
    i=0
    while [[ $i -lt ${#args[@]} ]]; do
        a="${args[$i]}"
        if [[ $options_done -eq 1 ]]; then
            if [[ -z "$verb" ]]; then verb="$a"; verb_index=$i
            elif [[ -z "$verb2" ]]; then verb2="$a"; verb2_index=$i
            else [[ $rest_first_index -lt 0 ]] && rest_first_index=$i; rest_pos+=("$a"); fi
            i=$((i+1))
            continue
        fi
        case "$a" in
            --) options_done=1; dd_index=$i ;;
            --context) ctx_arg_present=1; ctx_arg="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
            --context=*) ctx_arg_present=1; ctx_arg="${a#--context=}";;
            -n|--namespace) ns_arg="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
            -n=*|--namespace=*) ns_arg="${a#*=}";;
            -n?*) ns_arg="${a#-n}";;        # attached short form: -n<ns>
            -A|--all-namespaces) all_ns=1 ;;
            --all-namespaces=*)
                all_ns_value="${a#*=}"
                case "$all_ns_value" in
                    true|True|TRUE|1|t|T) all_ns=1 ;;
                    false|False|FALSE|0|f|F) all_ns=0 ;;
                    *)
                        printf 'BLOCK:precondition:invalid --all-namespaces boolean value'
                        return 0
                        ;;
                esac
                ;;
            --kubeconfig|--server|-s|--token|--as|--as-group|--as-uid|--as-user-extra|--user|--cluster|--client-certificate|--client-key|--certificate-authority|--tls-server-name|--insecure-skip-tls-verify)
                printf 'BLOCK:context:%s cannot override the guarded Kubernetes connection or credentials' "$a"
                return 0
                ;;
            -s?*)   # attached short --server
                printf 'BLOCK:context:-s cannot override the guarded Kubernetes connection or credentials'
                return 0
                ;;
            --kubeconfig=*|--server=*|--token=*|--as=*|--as-group=*|--as-uid=*|--as-user-extra=*|--user=*|--cluster=*|--client-certificate=*|--client-key=*|--certificate-authority=*|--tls-server-name=*|--insecure-skip-tls-verify=*)
                printf 'BLOCK:context:%s cannot override the guarded Kubernetes connection or credentials' "${a%%=*}"
                return 0
                ;;
            -f|--filename) ffiles+=("${args[$((i+1))]:-}"); i=$((i+2)); continue ;;
            -f=*|--filename=*) ffiles+=("${a#*=}");;
            -f?*) ffiles+=("${a#-f}");;      # attached short form: -f<file>
            -k|--kustomize) kdirs+=("${args[$((i+1))]:-}"); i=$((i+2)); continue ;;
            -k=*|--kustomize=*) kdirs+=("${a#*=}");;
            -k?*) kdirs+=("${a#-k}");;       # attached short form: -k<dir>
            --dry-run)
                if [[ $dry_run_seen -eq 1 ]]; then
                    printf 'BLOCK:precondition:multiple --dry-run options are ambiguous'
                    return 0
                fi
                dry_run_seen=1
                dry_run_mode="client"
                ;;
            --dry-run=*)
                if [[ $dry_run_seen -eq 1 ]]; then
                    printf 'BLOCK:precondition:multiple --dry-run options are ambiguous'
                    return 0
                fi
                dry_run_seen=1
                dry_run_mode="${a#*=}"
                case "$dry_run_mode" in
                    client|server|none) ;;
                    *)
                        printf 'BLOCK:precondition:invalid --dry-run mode: %s' "$dry_run_mode"
                        return 0
                        ;;
                esac
                ;;
            --raw) raw_api=1; i=$((i+2)); continue ;;
            --raw=*) raw_api=1 ;;
            # Known value-taking flags: consume the FOLLOWING token as the flag's
            # value so it isn't mistaken for a positional (e.g. a namespace name
            # in a create/delete lifecycle op — `delete namespace foo --timeout 5s`
            # must not read `5s` as a second namespace). Attached (`-oyaml`) and
            # equals (`--timeout=5s`) forms are single tokens and fall to `-*)`.
            -o|--output|--timeout|--grace-period|-l|--selector|--field-selector|--cache-dir|--type|--request-timeout|-c|--container|--field-manager|--every|--count) i=$((i+2)); continue ;;
            --request-timeout=*|--container=*|--field-manager=*|-c?*) ;;
            # Valueless write options seen in real sessions (`apply
            # --server-side`, `exec -it`). Their space form never consumes the
            # next token, so the resource slot stays put.
            --server-side|--force-conflicts|--overwrite|--force|--now|--all|--wait|--cascade|--validate|--record|--save-config|-i|--stdin|-t|--tty|-it|-ti|-q|--quiet) ;;
            --server-side=*|--force-conflicts=*|--overwrite=*|--force=*|--now=*|--all=*|--wait=*|--cascade=*|--validate=*|--record=*|--save-config=*|--stdin=*|--tty=*|--quiet=*) ;;
            --namespaced)
                if [[ "$verb" != "api-resources" ]]; then
                    printf 'BLOCK:precondition:unrecognized option before kubectl resource: %s' "$a"
                    return 0
                fi
                namespaced_value="${args[$((i+1))]:-}"
                case "$namespaced_value" in
                    true|True|TRUE|1|t|T|false|False|FALSE|0|f|F)
                        i=$((i+2))
                        ;;
                    *)
                        # A Boolean flag may omit its value. Do not consume an
                        # arbitrary next token, especially a connection flag.
                        i=$((i+1))
                        ;;
                esac
                continue
                ;;
            --namespaced=*)
                if [[ "$verb" != "api-resources" ]]; then
                    printf 'BLOCK:precondition:unrecognized option before kubectl resource: %s' "$a"
                    return 0
                fi
                namespaced_value="${a#*=}"
                case "$namespaced_value" in
                    true|True|TRUE|1|t|T|false|False|FALSE|0|f|F) ;;
                    *)
                        printf 'BLOCK:precondition:invalid --namespaced boolean value'
                        return 0
                        ;;
                esac
                ;;
            -w|--watch|--watch-only|--show-labels|--no-headers|--ignore-not-found|--show-kind|--recursive|-R|--client|--watch=*|--watch-only=*|--show-labels=*|--no-headers=*|--ignore-not-found=*|--show-kind=*|--recursive=*|--client=*) ;;
            -*)
                # Unknown options before the verb or its resource are ambiguous:
                # they may take the next token as a value, shifting the command
                # or resource into a slot with weaker classification. Fail closed
                # and let the hook surface the guard reason to the operator.
                # Once the verb is a plain read, nothing after it can turn the
                # command into a write, so `logs --tail 5 pod` is safe to pass.
                if [[ -z "$verb" ]] || { [[ -z "$verb2" ]] && ! _k8s_is_read_verb "$verb"; }; then
                    printf 'BLOCK:precondition:unrecognized option before kubectl resource: %s' "$a"
                    return 0
                fi
                ;;
            *)
                if [[ -z "$verb" ]]; then verb="$a"; verb_index=$i
                elif [[ -z "$verb2" ]]; then verb2="$a"; verb2_index=$i
                else [[ $rest_first_index -lt 0 ]] && rest_first_index=$i; rest_pos+=("$a"); fi
                ;;
        esac
        i=$((i+1))
    done

    # The hooks hand the guard shell text split on whitespace, so `-l 'a get'`
    # arrives as `-l`, `'a`, `get'` and -l consumes only the first half. A
    # split value sitting before the verb, or before a write's resource, can
    # put the wrong token in that slot — `-l a\ get delete …` read as `get`.
    if [[ $first_fragment -ge 0 ]]; then
        if [[ $verb_index -lt 0 || $first_fragment -le $verb_index ]] \
            || { { [[ $verb2_index -lt 0 || $first_fragment -le $verb2_index ]]; } && ! _k8s_is_read_verb "$verb"; }; then
            printf 'BLOCK:precondition:a quoted or escaped value with whitespace (%s) sits before the kubectl verb or resource and cannot be tokenized safely; move that option after the resource' "${args[first_fragment]}"
            return 0
        fi
    fi

    # `scope` is a wrapper-management verb (show/set/clear); it is not a
    # kubectl command. Return NOT_K8S so the hook passes it to the normal
    # permission flow instead of blocking it as an unrecognized write verb.
    if [[ "$verb" == "scope" ]]; then printf 'NOT_K8S'; return 0; fi

    if [[ -n "$scope_ctx" && "$ctx_arg_present" -eq 1 && -z "$ctx_arg" ]]; then
        printf 'BLOCK:context:explicit --context cannot be empty'; return 0
    fi
    if [[ -n "$scope_ctx" && -n "$ctx_arg" && "$ctx_arg" != "$scope_ctx" ]]; then
        printf 'BLOCK:context:explicit --context %s != the guard-scope context %s' "$ctx_arg" "$scope_ctx"; return 0
    fi
    # Without --context, raw kubectl acts on kubeconfig's current context, and
    # arming a scope does not switch it. Comparing only an explicit flag let a
    # plain `kubectl get` read homelab while the scope said GKE. An empty
    # answer means kubectl has no current context and will refuse to run, so
    # there is nothing to compare. `config` and `kustomize` never reach a
    # cluster.
    if [[ -n "$scope_ctx" && $raw_form -eq 1 && $ctx_arg_present -eq 0 && "$verb" != "config" && "$verb" != "kustomize" ]]; then
        local mismatch
        mismatch="$(_k8s_current_context_mismatch "$scope_ctx" kubectl "use \`ws k8s <args>\`, which injects --context, or pass --context $scope_ctx")"
        [[ -z "$mismatch" ]] || { printf '%s' "$mismatch"; return 0; }
    fi
    # `ws k8s sample` is the wrapper's own verb: repeated exec of one command
    # from a read-only list, so a poll loop needs no `sh -c 'for …'` in the
    # pod. Raw `kubectl sample` would be a plugin and stays on the write path.
    if [[ $raw_form -eq 0 && "$verb" == "sample" ]]; then
        # The pod comes before `--` and nothing else does: a stray word there
        # would be the pod to the wrapper while the guard vetted another.
        if [[ -z "$verb2" || $dd_index -lt 0 || $verb2_index -gt $dd_index || ${#rest_pos[@]} -eq 0 || $rest_first_index -lt $dd_index ]]; then
            printf 'BLOCK:precondition:ws k8s sample needs a pod and a command after --: ws k8s sample <pod> [-n ns] [-c container] [--every s] [--count n] -- <cmd>'
            return 0
        fi
        # Bare names only: `/tmp/x/cat` is whatever binary sits there. date
        # and hostname also have write forms, which are refused.
        local sample_arg
        case "${rest_pos[0]}" in
            cat|head|tail|ls|ps|df|du|free|uptime|date|wc|nproc|stat|id|hostname) ;;
            *)
                printf 'BLOCK:precondition:ws k8s sample runs read-only commands by bare name only (cat head tail ls ps df du free uptime date wc nproc stat id hostname), not %s' "${rest_pos[0]}"
                return 0
                ;;
        esac
        # date and hostname take arguments from an allowlist of read forms:
        # date sets the clock from a bare timestamp or a clustered -s.
        for sample_arg in "${rest_pos[@]:1}"; do
            case "${rest_pos[0]}:$sample_arg" in
                date:-u|date:--utc|date:--universal|date:-R|date:--rfc-email|date:-I|date:-I[a-z]*|date:--iso-8601*|date:--rfc-3339=*|date:+*) ;;
                hostname:-f|hostname:--fqdn|hostname:--long|hostname:-s|hostname:--short|hostname:-d|hostname:--domain|hostname:-i|hostname:--ip-address|hostname:-I|hostname:--all-ip-addresses|hostname:-A|hostname:--all-fqdns) ;;
                date:*|hostname:*)
                    printf 'BLOCK:precondition:ws k8s sample allows only the read forms of %s, not %s' "${rest_pos[0]}" "$sample_arg"
                    return 0
                    ;;
            esac
        done
        [[ -z "$scope_ctx" ]] && { printf 'READ_NO_SCOPE'; return 0; }
        printf 'READ_IN_SCOPE'; return 0
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
        proxy)
            printf 'BLOCK:unbounded:kubectl proxy exposes the full cluster API and is not namespace-scope-bounded'
            return 0
            ;;
        cluster-info)
            if [[ -z "$verb2" ]]; then
                printf '%s' "$read_verdict"
            elif [[ -z "$scope_ctx" ]]; then
                printf 'WRITE_NO_SCOPE'
            else
                printf 'BLOCK:unbounded:kubectl cluster-info %s is not a bounded read' "$verb2"
            fi
            return 0
            ;;
    esac
    if _k8s_is_read_verb "$verb"; then printf '%s' "$read_verdict"; return 0; fi
    if [[ $raw_api -eq 1 ]]; then
        printf 'BLOCK:unbounded:--raw API paths are not namespace-scope-bounded for writes'
        return 0
    fi
    [[ -z "$scope_ctx" ]] && { printf 'WRITE_NO_SCOPE'; return 0; }
    if [[ $all_ns -eq 1 ]]; then printf 'BLOCK:unbounded:--all-namespaces write is not scope-bounded'; return 0; fi
    local write_verdict="WRITE_IN_SCOPE"
    if [[ "$dry_run_mode" == "client" || "$dry_run_mode" == "server" ]] \
        && _k8s_supports_dry_run "$verb" "$verb2"; then
        write_verdict="DRY_RUN_IN_SCOPE"
    fi

    # Cluster-scoped writes can't be bounded to the namespace scope: a node-level
    # verb (cordon/drain/…) names a node directly, and a cluster-scoped resource
    # type ignores -n entirely (e.g. `delete namespace prod -n alice-sandbox`
    # deletes prod regardless). Fail closed before any namespace logic.
    case "$verb" in
        cordon|uncordon|drain) printf 'BLOCK:unbounded:kubectl %s operates on a node (cluster-scoped); not namespace-scope-bounded' "$verb"; return 0 ;;
        certificate)
            case "$verb2" in
                approve|deny)
                    printf 'BLOCK:unbounded:kubectl certificate %s changes a cluster-scoped certificate request' "$verb2"
                    return 0
                    ;;
            esac
            ;;
    esac

    # `kubectl cp` accepts [namespace/]pod:path on either side. An explicit
    # operand namespace overrides the context default, so inspect both operands
    # before falling back to the ordinary -n/default-namespace check.
    if [[ "$verb" == "cp" ]]; then
        local cp_operand cp_remote cp_ns cp_explicit=0
        local -a cp_operands=("$verb2")
        [[ ${#rest_pos[@]} -gt 0 ]] && cp_operands+=("${rest_pos[@]}")
        for cp_operand in "${cp_operands[@]}"; do
            [[ "$cp_operand" == *:* ]] || continue
            cp_remote="${cp_operand%%:*}"
            [[ "$cp_remote" == */* ]] || continue
            cp_ns="${cp_remote%%/*}"
            [[ -n "$cp_ns" ]] || continue
            cp_explicit=1
            if ! _k8s_ns_in_csv "$cp_ns" "$scope_ns_csv"; then
                printf 'BLOCK:scope:kubectl cp operand namespace %s is outside the guard scope (%s)' "$cp_ns" "$scope_ns_csv"
                return 0
            fi
        done
        if [[ "$cp_explicit" == "1" ]]; then
            if [[ -n "$ns_arg" ]] && ! _k8s_ns_in_csv "$ns_arg" "$scope_ns_csv"; then
                printf 'BLOCK:scope:kubectl cp -n namespace %s is outside the guard scope (%s)' "$ns_arg" "$scope_ns_csv"
                return 0
            fi
            printf '%s' "$write_verdict"
            return 0
        fi
    fi

    # In-scope namespace lifecycle: create/delete of a namespace whose NAME is
    # itself within the guard scope is allowed — it lets a practitioner create
    # (or delete and recreate) their own scoped namespace(s). The namespace name
    # is the scope-check target here, not -n. Requires at least one name and
    # EVERY named namespace in scope; a nameless form (label selector / --all)
    # has no name to bound and falls through to the cluster-scoped block below.
    # (-f / -k Namespace manifests get the same by-name check in
    # _k8s_validate_rendered_docs.)
    # Extract the namespace type and an optional inline name, so the slash form
    # `delete ns/alice-sandbox` is treated like `delete ns alice-sandbox`.
    local _ns_type="$verb2" _ns_inline="" _ns_lifecycle_tuples_in_scope=0
    if [[ "$verb2" == */* ]]; then _ns_type="${verb2%%/*}"; _ns_inline="${verb2#*/}"; fi
    if [[ ${#ffiles[@]} -eq 0 ]] && _k8s_is_namespace_type "$_ns_type" \
        && { [[ "$verb" == "create" || "$verb" == "delete" ]]; }; then
        local -a _targets=()
        local _nm _ns_tuple_type _ns_tuple_name _ns_typed_mismatch=0
        [[ -n "$_ns_inline" ]] && _targets+=("$_ns_inline")
        # Bare later operands remain namespace names. A slash-form tuple must
        # itself use a namespace type; otherwise general delete parsing owns it.
        for _nm in ${rest_pos[@]+"${rest_pos[@]}"}; do
            if [[ "$_nm" == */* ]]; then
                _ns_tuple_type="${_nm%%/*}"
                _ns_tuple_name="${_nm#*/}"
                if _k8s_is_namespace_type "$_ns_tuple_type" && [[ -n "$_ns_tuple_name" ]]; then
                    _targets+=("$_ns_tuple_name")
                else
                    _ns_typed_mismatch=1
                fi
            else
                _targets+=("$_nm")
            fi
        done
        if [[ ${#_targets[@]} -gt 0 ]]; then
            local _bad=""
            for _nm in "${_targets[@]}"; do
                _k8s_ns_in_csv "$_nm" "$scope_ns_csv" || { _bad="$_nm"; break; }
            done
            if [[ -z "$_bad" && "$_ns_typed_mismatch" -eq 0 ]]; then
                printf '%s' "$write_verdict"; return 0
            fi
            if [[ -n "$_bad" ]]; then
                printf 'BLOCK:scope:%s namespace %s is outside the guard scope (%s)' "$verb" "$_bad" "$scope_ns_csv"; return 0
            fi
            if [[ "$verb" == "delete" ]]; then _ns_lifecycle_tuples_in_scope=1; fi
        fi
        # No name (label selector / --all) → fall through to the cluster-scoped block.
    fi
    # rollout/set put their resource after a subcommand rather than verb2.
    if [[ ${#ffiles[@]} -eq 0 && ( "$verb" == rollout || "$verb" == set ) ]]; then
        local _nested_target _nested_type _nested_first=1
        for _nested_target in ${rest_pos[@]+"${rest_pos[@]}"}; do
            [[ "$_nested_target" == *=* || "$_nested_target" == *- ]] && break
            if [[ "$_nested_first" -eq 1 || "$_nested_target" == */* ]]; then
                _nested_first=0
                local -a _nested_segments=()
                IFS=',' read -ra _nested_segments <<< "$_nested_target"
                for _nested_type in "${_nested_segments[@]}"; do
                    _nested_type="${_nested_type%%/*}"
                    if _k8s_is_cluster_scoped "$_nested_type"; then
                        printf 'BLOCK:unbounded:%s is a cluster-scoped resource; writes to it are not namespace-scope-bounded' "$_nested_type"; return 0
                    fi
                    _k8s_verified_namespaced_type "$_nested_type" "$scope_ctx" || {
                        printf 'BLOCK:precondition:cannot verify namespace scope for resource type %s; use a group-qualified resource name or a manifest' "$_nested_type"; return 0;
                    }
                done
            fi
        done
    fi
    if [[ ${#ffiles[@]} -eq 0 && -n "$verb2" ]]; then
        local _resource_segment _resource_type _typed_operand
        local -a _resource_segments=()
        IFS=',' read -ra _resource_segments <<< "$verb2"
        for _resource_segment in "${_resource_segments[@]}"; do
            _resource_type="${_resource_segment%%/*}"
            if [[ "$_ns_lifecycle_tuples_in_scope" -eq 1 ]] && _k8s_is_namespace_type "$_resource_type"; then
                continue
            fi
            if _k8s_is_cluster_scoped "$_resource_type"; then
                printf 'BLOCK:unbounded:%s is a cluster-scoped resource; writes to it are not namespace-scope-bounded' "$_resource_type"; return 0
            fi
            case "$verb" in
                delete|patch|edit|replace|scale|autoscale|expose|label|annotate)
                    _k8s_verified_namespaced_type "$_resource_type" "$scope_ctx" || {
                        printf 'BLOCK:precondition:cannot verify namespace scope for resource type %s; use a group-qualified resource name or a manifest' "$_resource_type"; return 0;
                    }
                    ;;
            esac
        done
        # label/annotate accept extra resource tuples before their first key
        # assignment or removal; everything from that data operand onward is inert.
        if [[ "$verb" == "delete" || "$verb" == "label" || "$verb" == "annotate" ]]; then
            for _typed_operand in ${rest_pos[@]+"${rest_pos[@]}"}; do
                if [[ "$verb" == "label" || "$verb" == "annotate" ]]; then
                    [[ "$_typed_operand" == *=* || "$_typed_operand" == *- ]] && break
                fi
                [[ "$_typed_operand" == */* ]] || continue
                _resource_type="${_typed_operand%%/*}"
                if [[ "$_ns_lifecycle_tuples_in_scope" -eq 1 ]] && _k8s_is_namespace_type "$_resource_type"; then
                    continue
                fi
                if _k8s_is_cluster_scoped "$_resource_type"; then
                    printf 'BLOCK:unbounded:%s is a cluster-scoped resource; writes to it are not namespace-scope-bounded' "$_resource_type"; return 0
                fi
                _k8s_verified_namespaced_type "$_resource_type" "$scope_ctx" || {
                    printf 'BLOCK:precondition:cannot verify namespace scope for resource type %s; use a group-qualified resource name or a manifest' "$_resource_type"; return 0;
                }
            done
        fi
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
            validation="$(_k8s_validate_rendered_docs -f "$f" "$ns_arg" "$scope_ns_csv" "$f_path" "$scope_ctx")" || { printf '%s' "$validation"; return 0; }
        done
        printf '%s' "$write_verdict"; return 0
    fi

    # Kustomize inputs need the same per-resource inspection as -f manifests.
    # Render only an existing local directory; remote inputs and render failures
    # fail closed rather than turning a namespace guess into approval.
    if [[ ${#kdirs[@]} -gt 0 ]]; then
        local k k_path rendered validation preflight
        for k in "${kdirs[@]}"; do
            k_path="$k"
            [[ -d "$k_path" ]] || k_path="$(_k8s_normalize_path "$k")"
            [[ -d "$k_path" ]] || { printf 'BLOCK:precondition:-k %s is not a readable local directory' "$k"; return 0; }
            if ! preflight="$(k8s_guard_validate_kustomize_tree "$k_path" 2>&1)"; then
                preflight="${preflight//$'\n'/; }"
                printf 'BLOCK:precondition:-k %s failed local-only reference validation: %s' "$k" "$preflight"
                return 0
            fi
            rendered="$("${KUBECTL:-kubectl}" kustomize "$k_path" 2>/dev/null)" || {
                printf 'BLOCK:precondition:-k %s could not be rendered safely' "$k"; return 0;
            }
            validation="$(_k8s_validate_rendered_docs -k "$k" "$ns_arg" "$scope_ns_csv" "" "$scope_ctx" <<< "$rendered")" || { printf '%s' "$validation"; return 0; }
        done
        printf '%s' "$write_verdict"; return 0
    fi

    local target_ns="$ns_arg"
    if [[ -z "$target_ns" ]]; then
        target_ns="$("${KUBECTL:-kubectl}" config view --minify --context "$scope_ctx" -o 'jsonpath={..namespace}' 2>/dev/null)"
        [[ -z "$target_ns" ]] && target_ns="default"
    fi
    # Membership via _k8s_ns_in_csv so a context-only `*` scope accepts any
    # target namespace (all namespaces in scope for writes).
    _k8s_ns_in_csv "$target_ns" "$scope_ns_csv" && { printf '%s' "$write_verdict"; return 0; }
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
