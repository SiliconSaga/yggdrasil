#!/usr/bin/env bash
# ws-budget.sh — advisory word budget for change notes. Sourced by ws-commit.sh,
# git-cr.sh and git-issue.sh.
#
# Words, not lines: prose here is never hard-wrapped, so a line is a paragraph
# of any length and a line count measures nothing.

# ws_budget_limit <kind> <style> → word limit on stdout; empty means unlimited.
ws_budget_limit() {
    case "$2:$1" in
        detailed:*)   ;;
        terse:commit) echo 50 ;;
        terse:cr)     echo 120 ;;
        terse:issue)  echo 150 ;;
        *:commit)     echo 120 ;;
        *:cr)         echo 250 ;;
        *:issue)      echo 300 ;;
    esac
}

# Prose words only. Fences are evidence, blockquotes carry the attribution
# banner, headings are structure.
ws_budget_count_words() {
    printf '%s\n' "$1" | awk '
        match($0, /^[[:space:]]*(```|~~~)/) { c = substr($0, RLENGTH, 1); if (!fence) { fence = c } else if (fence == c) { fence = "" } next }
        fence || /^[[:space:]]*>/ || /^#/ { next }
        { n += NF }
        END { print n + 0 }'
}

# ws_budget_note <kind: commit|cr|issue> <text> <style>. Never blocks: a wrapper
# that refused a long body would be worked around rather than obeyed.
ws_budget_note() {
    local kind="$1" text="$2" style="${3:-}" limit count
    [[ -n "$text" ]] || return 0
    case "$style" in terse|standard|detailed) ;; *) style="standard" ;; esac

    limit="$(ws_budget_limit "$kind" "$style")"
    [[ -n "$limit" ]] || return 0
    count="$(ws_budget_count_words "$text")"
    [[ "$count" -gt "$limit" ]] || return 0

    echo "NOTE: $kind body is $count words against a budget of $limit (style.changeNotes: $style)." >&2
    echo "  Keep evidence, traps, and why it matters; cut what restates the diff." >&2
    return 0
}
