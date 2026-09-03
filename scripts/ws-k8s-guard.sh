#!/usr/bin/env bash
# ws-k8s-guard.sh — shared k8s practice guard (sourced by ws-k8s.sh and the
# permission hook). Single source of truth for the allow/block verdict.

# Complex shell forms cannot be tokenized safely by the small normalizer below.
# Every consumer recognizes this fixed sentinel and handles Kubernetes-looking
# payloads as a fail-closed decision rather than inspecting only the first line.
K8S_GUARD_UNSAFE_COMMAND_SENTINEL="__GDD_K8S_UNSAFE_COMMAND__"
K8S_GUARD_NO_XARGS_SENTINEL="__GDD_K8S_NO_XARGS__"

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
    [[ "$base" == "kubectl" ]] && words[i]="kubectl"
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
        case "$ref" in
            ..|../*|*/..|*/../*)
                echo "parent traversal in kustomization reference is not allowed: $ref"
                return 1
                ;;
        esac

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
            *) echo "kustomization reference escapes the selected local root: $ref"; return 1 ;;
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
    _k8s_validate_kustomize_dir "$root_real" "$root_real"
}

# Print one verdict: NOT_K8S | READ_NO_SCOPE | WRITE_NO_SCOPE |
# READ_IN_SCOPE | DRY_RUN_IN_SCOPE | WRITE_IN_SCOPE | BLOCK:<reason>
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
    local verb="" verb2="" ctx_arg="" ctx_arg_present=0 ns_arg="" all_ns=0 raw_api=0 a all_ns_value namespaced_value
    local dry_run_mode="" dry_run_seen=0 options_done=0
    local ffiles=()
    local kdirs=()
    local rest_pos=()   # positional resource names after verb + resource-type
    local args=("$@")
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        a="${args[$i]}"
        if [[ $options_done -eq 1 ]]; then
            if [[ -z "$verb" ]]; then verb="$a"; elif [[ -z "$verb2" ]]; then verb2="$a"; else rest_pos+=("$a"); fi
            i=$((i+1))
            continue
        fi
        case "$a" in
            --) options_done=1 ;;
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
            --kubeconfig|--server|--token|--as|--as-group|--as-uid|--as-user-extra|--user|--cluster|--client-certificate|--client-key|--certificate-authority|--tls-server-name|--insecure-skip-tls-verify)
                printf 'BLOCK:context:%s cannot override the guarded Kubernetes connection or credentials' "$a"
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
            -o|--output|--timeout|--grace-period|-l|--selector|--field-selector|--cache-dir|--type|--request-timeout) i=$((i+2)); continue ;;
            --request-timeout=*) ;;
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
                if [[ -z "$verb" || -z "$verb2" ]]; then
                    printf 'BLOCK:precondition:unrecognized option before kubectl resource: %s' "$a"
                    return 0
                fi
                ;;
            *) if [[ -z "$verb" ]]; then verb="$a"; elif [[ -z "$verb2" ]]; then verb2="$a"; else rest_pos+=("$a"); fi ;;
        esac
        i=$((i+1))
    done

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
    # (-f Namespace manifests stay conservative — handled in the -f block.)
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
            validation="$(_k8s_validate_rendered_docs -f "$f" "$ns_arg" "$scope_ns_csv" "$f_path")" || { printf '%s' "$validation"; return 0; }
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
            validation="$(_k8s_validate_rendered_docs -k "$k" "$ns_arg" "$scope_ns_csv" <<< "$rendered")" || { printf '%s' "$validation"; return 0; }
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
