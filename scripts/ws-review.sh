#!/usr/bin/env bash
# ws-review.sh — CR review comments and thread management
# ws:use-when triaging review comments + resolving threads on an open CR
#
# Usage:
#   ws-review.sh <comp> threads <cr#> [--status | --resolve <id> | --resolve-all]
#   ws-review.sh <comp> reply <cr#> <thread-id> <message> [--resolve]
#   ws-review.sh <comp> <cr#> [--reviewer <name>] [--since <time>]
#
# Supports GitHub (gh) and GitLab (glab). Component name is always required.
# Provider is auto-detected from the component's remote URL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Function definitions (must precede routing block at bottom) ---

review_help() {
    echo "Usage: ws review <comp> <cr#> [--remote <name>] [--reviewer <name>] [--since <time>] [--compact] [--limit N] [--output <phrase>]"
    echo "       ws review <comp> threads <cr#> [--remote <name>] [--status | --resolve <id> | --resolve-all]"
    echo "       ws review <comp> notes <cr#> [--remote <name>] [--reviewer <name>] [--since <time>]"
    echo "       ws review <comp> reply <cr#> <thread-id> <message> [--remote <name>] [--resolve]"
    echo ""
    echo "CR review comments and thread management."
    echo ""
    echo "Subcommands:"
    echo "  <cr#>                      Full review: inline comments + top-level notes"
    echo "                             (use this first; gets everything in one call)"
    echo "    --reviewer <name>        Filter by reviewer login"
    echo "    --since <time>           Filter by time (last-push, prev-push, Nh, Nm, ISO 8601)"
    echo "                             (--since push events: GitHub only)"
    echo "    --compact                Headline-only view: each comment shrinks to its"
    echo "                             [reviewer] file:line + first body line. Useful when"
    echo "                             a busy PR's full output runs into thousands of lines"
    echo "                             and you just want to triage at a glance."
    echo "    --limit N | --limit=N    Show only the first N inline comments (and the"
    echo "                             first N notes). Both spaced and equals forms"
    echo "                             work. Pairs naturally with --compact. Replaces a"
    echo "                             '| head -N' pipe — native flag stays inside"
    echo "                             auto-approved permissions."
    echo "    --output <phrase>        Save the rendered review to .outputs/<ts>-<phrase>.txt"
    echo "                             (timestamp prefix: YYYYMMDD-HHMMSS, sorts cleanly)."
    echo "                             Phrase carries intent (e.g. 'before-fix'); script"
    echo "                             appends timestamp so re-runs don't collide. Prints"
    echo "                             the path on stdout for downstream commands like grep."
    echo "                             Replaces a '> file' redirect — native flag keeps the"
    echo "                             write confined to .outputs/ (covered by ws clean)."
    echo "    --remote <name>          Select a specific git remote when a CR number exists"
    echo "                             on multiple remotes for the same component."
    echo ""
    echo "  threads <cr#>              Unresolved diff threads (targeted follow-up)"
    echo "    --status                 Show resolved/unresolved counts"
    echo "    --resolve <thread-id>    Resolve a single thread"
    echo "    --resolve-all            Resolve all unresolved threads"
    echo ""
    echo "  notes <cr#>                Top-level MR/PR notes only (bot summaries, etc.)"
    echo "    --reviewer <name>        Filter by reviewer login"
    echo "    --since <time>           Filter by time"
    echo ""
    echo "  reply <cr#> <thread-id> <message> [--resolve]"
    echo "                             Reply to a review thread"
    echo "    --resolve                Also resolve the thread after replying"
    echo ""
    echo "Examples:"
    echo "  ws review yggdrasil 8                      # All review output (start here)"
    echo "  ws review yggdrasil 8 --compact             # Headline-only triage view"
    echo "  ws review yggdrasil 8 --compact --limit 5   # First 5 comments, headline-only"
    echo "  ws review yggdrasil 8 --output before-fix    # Save snapshot for grep follow-up"
    echo "  ws review silence 1 --remote rpraestholm-fork-group"
    echo "  ws review mimir 5 --reviewer coderabbitai"
    echo "  ws review yggdrasil 8 --since last-push"
    echo "  ws review yggdrasil notes 8                # Top-level notes only"
    echo "  ws review yggdrasil threads 8              # Unresolved diff threads only"
    echo "  ws review yggdrasil threads 8 --status     # Thread counts"
    echo "  ws review yggdrasil threads 8 --resolve-all"
    echo "  ws review yggdrasil reply 8 THREAD_ID 'Addressed in abc123'"
    echo "  ws review yggdrasil reply 8 THREAD_ID 'Fixed' --resolve"
    exit 0
}

review_probe_not_found() {
    local rc="$1" msg="$2"
    [[ "$(gp_api_error_classify "$rc" "$msg")" == "not_found" ]]
}

review_probe_one_line() {
    gp_api_error_one_line "$1"
}

review_jq_string_literal() {
    jq -Rn -r --arg v "$1" '$v | @json'
}

review_reviewer_filter() {
    local reviewer="$1"
    if [[ -z "$reviewer" ]]; then
        printf '.'
        return
    fi

    local reviewer_literal
    reviewer_literal="$(review_jq_string_literal "$reviewer")"
    printf 'select(((.user.login // .author.username // "") | ascii_downcase) == (%s | ascii_downcase))' "$reviewer_literal"
}

review_comments() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> <cr#> [--remote <name>] [--reviewer <name>] [--since <time>] [--compact] [--limit N] [--output <phrase>]" >&2
        exit 1
    fi

    # Parse arguments
    local pr_num="$1"
    shift
    local reviewer=""
    local since=""
    local compact=false
    local limit=""
    local output_phrase=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reviewer)
                [[ $# -ge 2 ]] || { echo "ERROR: --reviewer requires a value" >&2; exit 1; }
                reviewer="$2"; shift 2 ;;
            --since)
                [[ $# -ge 2 ]] || { echo "ERROR: --since requires a value" >&2; exit 1; }
                since="$2"; shift 2 ;;
            --compact)
                compact=true; shift ;;
            --limit)
                [[ $# -ge 2 ]] || { echo "ERROR: --limit requires a value" >&2; exit 1; }
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "ERROR: --limit value '$2' must be a non-negative integer" >&2
                    exit 1
                fi
                limit="$2"; shift 2 ;;
            --limit=*)
                limit="${1#--limit=}"
                if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
                    echo "ERROR: --limit value '$limit' must be a non-negative integer" >&2
                    exit 1
                fi
                shift ;;
            --output)
                [[ $# -ge 2 ]] || { echo "ERROR: --output requires a phrase" >&2; exit 1; }
                [[ -n "$2" ]] || { echo "ERROR: --output phrase cannot be empty" >&2; exit 1; }
                output_phrase="$2"; shift 2 ;;
            --output=*)
                output_phrase="${1#--output=}"
                [[ -n "$output_phrase" ]] || { echo "ERROR: --output= phrase cannot be empty" >&2; exit 1; }
                shift ;;
            *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    # Validate --output phrase: alphanumeric + dot/dash/underscore only.
    # Rejects slashes (the only real path-traversal vector) — destination
    # is always confined to <workspace>/.outputs/ since the resulting
    # name has no path component. Phrases like `..foo` or `..` are
    # technically allowed because they're interpreted as literal
    # filenames inside .outputs/, not directory traversals; harmless
    # weird names if they slip through.
    # The phrase carries intent (e.g. `before-fix`); the script
    # PREFIXES a YYYYMMDD-HHMMSS timestamp for collision-free re-runs
    # and clean `ls`-by-time sorting.
    local output_path=""
    local output_tmp=""
    if [[ -n "$output_phrase" ]]; then
        if [[ ! "$output_phrase" =~ ^[A-Za-z0-9._-]+$ ]]; then
            echo "ERROR: --output phrase '$output_phrase' must contain only alphanumeric, dot, dash, or underscore characters." >&2
            echo "  No slashes — destination is always under <workspace>/.outputs/." >&2
            exit 1
        fi
        local outputs_dir="$ROOT_DIR/.outputs"
        mkdir -p "$outputs_dir"
        # Timestamp-first so `ls .outputs/` sorts cleanly by time —
        # latest snapshot at the bottom, easy to spot. Re-review
        # iterations on the same PR also stay adjacent because they
        # share the date prefix.
        output_path="$outputs_dir/$(date +%Y%m%d-%H%M%S)-${output_phrase}.txt"
        # Write to a sibling temp file and rename on success. Avoids
        # leaving stale partial snapshots if a fetch (or anything
        # else) fails mid-render. Trap on EXIT removes the tmp if
        # we don't reach the explicit `mv` below.
        output_tmp="$(mktemp "${output_path}.tmp.XXXXXX")"
        # shellcheck disable=SC2064  # intentional immediate expansion
        trap "rm -f '$output_tmp'" EXIT
    fi

    # Validate CR number is numeric
    if [[ ! "$pr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: CR number must be numeric, got '$pr_num'" >&2
        exit 1
    fi

    # Validate reviewer name (prevent jq filter injection)
    if [[ -n "$reviewer" ]] && [[ ! "$reviewer" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "ERROR: Invalid reviewer name '$reviewer'. Use alphanumeric, dot, dash, underscore." >&2
        exit 1
    fi

    # Resolve --since to ISO 8601 timestamp
    local since_ts=""
    if [[ -n "$since" ]]; then
        if [[ "$since" == "last-push" || "$since" == "prev-push" ]]; then
            local branch
            branch=$(gp_review_head_branch "$REPO_SLUG" "$pr_num")
            if [[ -z "$branch" || "$branch" == "null" ]]; then
                echo "ERROR: Cannot determine PR head branch for #$pr_num in $REPO_SLUG." >&2
                exit 1
            fi
            local push_index=0
            [[ "$since" == "prev-push" ]] && push_index=1
            since_ts=$(gp_review_push_timestamp "$REPO_SLUG" "$branch" "$push_index")
            if [[ -z "$since_ts" || "$since_ts" == "null" ]]; then
                echo "ERROR: Cannot determine push time for '$branch'." >&2
                echo "  The provider did not return enough push history for '$since'." >&2
                echo "  Use an explicit timestamp instead." >&2
                exit 1
            fi
            echo "(showing comments since $since: $since_ts)"
        elif [[ "$since" =~ ^[0-9]+[hm]$ ]]; then
            local unit="${since: -1}"
            local amount="${since%?}"
            local seconds=0
            if [[ "$unit" == "h" ]]; then
                seconds=$((amount * 3600))
            else
                seconds=$((amount * 60))
            fi
            since_ts=$(date -u -d "$seconds seconds ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || date -u -v-"${seconds}S" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || { echo "ERROR: Cannot compute relative time. Use ISO 8601 format." >&2; exit 1; })
        else
            if [[ ! "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$ ]]; then
                echo "ERROR: Invalid --since value '$since'." >&2
                echo "  Expected: last-push, prev-push, Nh, Nm, or ISO 8601 (e.g. 2026-03-13T15:00:00Z)" >&2
                exit 1
            fi
            since_ts="$since"
        fi
    fi

    # Limit to first N entries (where each entry is delimited by a `---`
    # line, matching the format gp_review_list_comments / list_notes
    # produce). Reads stdin, prints stdout. Used for triage on busy PRs
    # where even compact output is dozens of lines — pairs naturally
    # with --compact but works on the full output too. Replaces what
    # would otherwise be a `| head -N` pipe (which can trigger
    # permission prompts as a compound shell). Native flag is the
    # better path.
    _apply_limit() {
        local n="$1"
        [[ -z "$n" ]] && { cat; return; }
        # Only count `---` lines that begin a real entry — i.e. that
        # are immediately followed by `[reviewer-pattern]`. CR bodies
        # contain markdown horizontal rules and `<details>` separators
        # that also render as `---`; those would otherwise miscount.
        # Peek next line via getline.
        # LC_ALL=C makes the `[A-Za-z0-9._-]` ranges in the header
        # regex lexicographic instead of locale-collated, so behavior
        # is identical regardless of the user's locale (mirrors what
        # _render_compact does for the same reason).
        LC_ALL=C awk -v lim="$n" '
            BEGIN { hdr = "^\\[[A-Za-z0-9._-]+(\\[bot\\])?\\] " }
            /^---$/ {
                separator = $0
                if ((getline next_line) > 0) {
                    if (next_line ~ hdr) {
                        count++
                        if (count > lim) exit
                    }
                    print separator
                    print next_line
                } else {
                    print separator
                }
                next
            }
            { print }
        '
    }

    # Count `entry headers` on stdin. The three section formats all
    # share the leading `[<reviewer>(\[bot\])?] ` shape (reviews end in
    # `STATE:`, inline comments end in `path:LINE`, notes end in
    # `(note)`), so a single header regex counts entries across any of
    # the three streams. Used by the Index section to surface
    # `N reviews / N inline / N notes` at the top so a busy PR's full
    # rendered output doesn't bury the high-level shape.
    _count_entries() {
        LC_ALL=C awk '
            BEGIN { hdr = "^\\[[A-Za-z0-9._-]+(\\[bot\\])?\\] " }
            $0 ~ hdr { count++ }
            END { print count+0 }
        '
    }

    # Extract `[reviewer] STATE` headers from the reviews stream so the
    # Index can show who said what at a glance (e.g. `coderabbitai[bot]:
    # CHANGES_REQUESTED`, `copilot-pull-request-reviewer[bot]:
    # COMMENTED`). The strict state allowlist guards against matching
    # comment / note headers if a future provider's output format drifts
    # — only review headers carry these terminal states. Drops the
    # trailing `:` for clean indentation under the Index.
    _list_review_states() {
        LC_ALL=C awk '
            /^\[[A-Za-z0-9._-]+(\[bot\])?\] (APPROVED|CHANGES_REQUESTED|COMMENTED|DISMISSED|PENDING):?$/ {
                line = $0
                sub(/:$/, "", line)
                print line
            }
        '
    }

    # CodeRabbit (and occasionally other bots) sometimes embed findings
    # *inside* the main review body rather than as inline threads — the
    # two patterns to watch are `Outside diff range comments (N)` and
    # `Nitpick comments (N)` collapsibles. These never appear in the
    # inline-comments fetch and are easy to miss when scrolling through
    # the rendered review text. Surface their counts in the Index so
    # they don't silently disappear under a long review body.
    #
    # The N inside the parens is the finding count for that block —
    # sum across all such blocks in the stream so the Index reports
    # the total number of findings, not just the number of blocks.
    _count_embedded_findings() {
        local pattern="$1"
        # Pipeline keeps the extraction portable across awk variants
        # (gawk's `match($0, re, arr)` array-capture form isn't
        # available in mawk / BSD awk). grep -o emits each match on its
        # own line, sed peels out the integer, awk sums.
        #
        # The `|| true` guard on grep is load-bearing under `set -o
        # pipefail` (enabled at the top of this script): grep returns
        # exit 1 when nothing matches, which the absence of these
        # findings on most PRs would otherwise translate to "abort the
        # script." Here, no-matches should report `0`, not fail.
        { LC_ALL=C grep -oE "${pattern} \\([0-9]+\\)" || true; } \
            | LC_ALL=C sed -E 's/.*\(([0-9]+)\).*/\1/' \
            | awk '{ sum += $1 } END { print sum+0 }'
    }

    # Compact rendering: extract `[reviewer] file:line` headers + the
    # first meaningful body line per comment block, drop the rest.
    # Skip severity markers (start with `_`), HTML <details> wrappers,
    # blockquoted prefixes (`>`), code fences, and the `---` separator.
    # Strip leading/trailing markdown bold from titles. Output stays
    # readable as a flat list — fits comfortably in agent context for
    # PRs with dozens of comments where the full output runs 1000+
    # lines.
    _render_compact() {
        # Tight header regex: must look like `[<login>[bot]] <path>:<N>`
        # or `[<login>[bot]] (note)`. Distinguishes real reviewer headers
        # from CR analysis-chain `[warning]` / `[grammar]` lint lines and
        # from bash conditionals like `[[ "${1:-}" == ... ]]` that start
        # with a `[`.
        #
        # Track depth into `<details>` blocks (CR's analysis chain wraps
        # everything in nested details — script blobs, web queries, etc.)
        # and skip the entire block. Without this, `#!/bin/bash` inside
        # a shell code-fence inside an analysis-chain details would slip
        # through as the "first body line."
        LC_ALL=C awk '
            BEGIN { hdr = "^\\[[A-Za-z0-9._-]+(\\[bot\\])?\\] "; details_depth=0 }
            /^---$/ { in_block=0; emitted_body=0; details_depth=0; next }
            # Match either path:LINE (numeric) or path:? (GitLab fallback
            # when no line number is available — see providers/gitlab.sh
            # gp_review_list_comments where missing line positions render
            # as ":?"). Without the "?" alternative, GitLab review
            # comments without line numbers were parsed as body text and
            # their headlines were merged into the previous block.
            $0 ~ hdr "[^[:space:]]+:(\\?|[0-9]+)" || $0 ~ hdr "\\(note\\)" {
                if (in_block && !emitted_body) print ""
                print
                in_block=1; emitted_body=0; details_depth=0
                next
            }
            /<details>/ { details_depth++; next }
            /<\/details>/ { if (details_depth > 0) details_depth--; next }
            details_depth > 0 { next }
            in_block && !emitted_body && NF > 0 {
                if (/^_/ || /^</ || /^>/ || /^```/) next
                # Skip CR analysis-chain marker lines. The four known
                # marker emoji all live in the Symbols & Pictographs
                # supplementary block, so each is a 4-byte UTF-8
                # sequence starting with 0xF0 0x9F. Match each exact
                # byte sequence using POSIX-portable octal escapes
                # (\NNN) — narrower than [\x80-\xff], which would also
                # drop legitimate non-English review content (CJK,
                # accented Latin, etc.). Octal rather than \xHH because
                # \xHH is GNU-specific; \NNN is portable across mawk,
                # nawk, and traditional awk. LC_ALL=C above makes awk
                # operate in byte mode so these sequences match
                # reliably regardless of system locale.
                if (/^\360\237\217\201/) next  # 0xF0 9F 8F 81 — chequered flag
                if (/^\360\237\223\235/) next  # 0xF0 9F 93 9D — memo
                if (/^\360\237\214\220/) next  # 0xF0 9F 8C 90 — globe with meridians
                if (/^\360\237\222\241/) next  # 0xF0 9F 92 A1 — light bulb
                line = $0
                sub(/^\*\*/, "", line)
                sub(/\*\*\.?$/, "", line)
                print "    " line
                emitted_body=1
            }
        '
    }

    # Build jq filters
    local reviewer_filter
    reviewer_filter="$(review_reviewer_filter "$reviewer")"
    local comment_filter="$reviewer_filter"
    local review_filter="$reviewer_filter"
    if [[ -n "$since_ts" ]]; then
        local since_literal
        since_literal="$(review_jq_string_literal "$since_ts")"
        comment_filter="$comment_filter | select((.created_at // .updated_at) > $since_literal)"
        review_filter="$review_filter | select((.submitted_at // .created_at) > $since_literal)"
    fi

    # If --output set, redirect stdout to a sibling temp file. We
    # rename the temp to the final $output_path only after every
    # fetch + render succeeds, so failed runs don't leave stale
    # partial snapshots. Save original stdout to fd 3 for the final
    # "Saved:" announce. Stderr is unaffected — errors still surface
    # to the terminal even when output is being captured.
    if [[ -n "$output_path" ]]; then
        exec 3>&1 1>"$output_tmp"
    fi

    # Fetch CR summary
    echo "=== CR #$pr_num ($REPO_SLUG) ==="
    gp_review_summary "$REPO_SLUG" "$pr_num" || {
        echo "ERROR: Could not fetch CR #$pr_num from $REPO_SLUG." >&2
        echo "  Check the CR number and repo name." >&2
        exit 1
    }
    echo ""

    # === Phase 1: Fetch all three sections ===
    #
    # The fetches used to happen interleaved with prints. We now buffer
    # them so an Index block can lead the output — a busy PR's full
    # rendered review can be thousands of lines, and the high-level
    # shape ("3 reviews, 5 inline, 1 note, 1 outside-diff-range find
    # hiding in a CR body") would otherwise be invisible from the top.
    # Failure markers still go to stdout, not stderr, so they remain
    # in `--output` snapshots; rc tracking moves the warn-vs-content
    # decision to the print phase.
    local reviews="" reviews_rc=0
    reviews=$(gp_review_list_reviews "$REPO_SLUG" "$pr_num" "$review_filter") || reviews_rc=$?

    local comments="" comments_rc=0
    comments=$(gp_review_list_comments "$REPO_SLUG" "$pr_num" "$comment_filter") || comments_rc=$?

    local notes="" notes_rc=0
    notes=$(gp_review_list_notes "$REPO_SLUG" "$pr_num" "$comment_filter") || notes_rc=$?

    # === Phase 2: Lead with an Index ===
    #
    # Counts derive from the same `[<reviewer>] ...` header regex used
    # everywhere else in this file (kept in `_count_entries`), so a
    # format drift in any provider's emit changes one regex, not three.
    # Embedded-finding counts surface the two CodeRabbit patterns
    # (`Outside diff range comments` and `Nitpick comments`) that hide
    # *inside* the main review body rather than appearing as inline
    # threads — easy to skim past without this nudge.
    local n_reviews n_comments n_notes
    n_reviews=$(printf '%s\n' "$reviews" | _count_entries)
    n_comments=$(printf '%s\n' "$comments" | _count_entries)
    n_notes=$(printf '%s\n' "$notes" | _count_entries)

    local review_states=""
    review_states=$(printf '%s\n' "$reviews" | _list_review_states)

    local n_outside n_embedded_nits n_low_conf
    n_outside=$(printf '%s\n' "$reviews" | _count_embedded_findings 'Outside diff range comments')
    n_embedded_nits=$(printf '%s\n' "$reviews" | _count_embedded_findings 'Nitpick comments')
    # Copilot's reviewer bot wraps "low confidence" findings inside the
    # leading review body as a collapsed <details> block — they never
    # land as inline threads and they don't show up in any auth'd
    # comments fetch. They're real, often actionable findings, so
    # promote the count to the Index alongside the CodeRabbit patterns.
    n_low_conf=$(printf '%s\n' "$reviews" | _count_embedded_findings 'Comments suppressed due to low confidence')

    echo "=== Index ==="
    echo "  Reviews:         $n_reviews"
    if [[ -n "$review_states" ]]; then
        # Indent each header line under the count so it visually attaches.
        printf '%s\n' "$review_states" | sed 's/^/    /'
    fi
    echo "  Inline comments: $n_comments"
    echo "  Notes:           $n_notes"
    # `(( … ))` returns exit 1 when the arithmetic test is false, which
    # under `set -e` plays badly with `&&` short-circuit lines (the
    # bash-manual carve-out for `&&` lists is narrow and easy to
    # misjudge). Pure `if` statements keep the control flow
    # unambiguous — no compound that might trip `errexit` if the count
    # happens to be 0.
    if (( n_outside > 0 )) || (( n_embedded_nits > 0 )) || (( n_low_conf > 0 )); then
        echo ""
        echo "  ! Special finds inside review bodies (NOT as separate threads):"
        if (( n_outside > 0 )); then
            echo "      Outside diff range comments:        $n_outside"
        fi
        if (( n_embedded_nits > 0 )); then
            echo "      Embedded nitpick comments:          $n_embedded_nits"
        fi
        if (( n_low_conf > 0 )); then
            echo "      Suppressed (low confidence) finds:  $n_low_conf"
        fi
    fi
    echo ""

    # === Phase 3: Print all sections ===
    echo "=== Reviews ==="
    if [[ $reviews_rc -ne 0 ]]; then
        echo "(failed to fetch reviews — check auth and connectivity)"
    elif [[ -n "$reviews" ]]; then
        echo "$reviews"
    else
        echo "(no reviews${reviewer:+ from $reviewer})"
    fi
    echo ""

    echo "=== Inline Comments ==="
    if [[ $comments_rc -ne 0 ]]; then
        echo "(failed to fetch inline comments — check auth and connectivity)"
    elif [[ -n "$comments" ]]; then
        if [[ "$compact" == true ]]; then
            printf '%s\n' "$comments" | _apply_limit "$limit" | _render_compact
        else
            printf '%s\n' "$comments" | _apply_limit "$limit"
        fi
    else
        echo "(no inline comments${reviewer:+ from $reviewer})"
    fi
    echo ""

    echo "=== Notes ==="
    if [[ $notes_rc -ne 0 ]]; then
        echo "(failed to fetch notes — check auth and connectivity)"
    elif [[ -n "$notes" ]]; then
        if [[ "$compact" == true ]]; then
            printf '%s\n' "$notes" | _apply_limit "$limit" | _render_compact
        else
            printf '%s\n' "$notes" | _apply_limit "$limit"
        fi
    else
        echo "(no notes${reviewer:+ from $reviewer})"
    fi

    # Restore stdout (if redirected), promote temp to final, and
    # announce. Disarm the cleanup trap once the rename succeeds so
    # the file persists past function exit.
    if [[ -n "$output_path" ]]; then
        exec 1>&3 3>&-
        mv "$output_tmp" "$output_path"
        trap - EXIT
        echo "Saved: $output_path"
    fi

    # Reply nudge — to stderr so it never lands in --output snapshots or
    # downstream greps of stdout. Replies are the exception, not the rule:
    # addressing a finding normally lets CodeRabbit self-resolve, so only reach
    # for `reply` when rejecting a comment or explaining a non-obvious fix.
    if (( n_comments > 0 )); then
        echo "" >&2
        echo "↪ Reply to a thread: ws review <comp> reply <cr#> <thread-id> <msg> [--resolve] — only when rejecting a comment or explaining an unexpected fix; just addressing it usually lets the bot self-resolve." >&2
    fi
}

review_notes() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> notes <cr#> [--remote <name>] [--reviewer <name>] [--since <time>]" >&2
        exit 1
    fi

    local pr_num="$1"
    shift
    local reviewer="" since=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reviewer)
                [[ $# -ge 2 ]] || { echo "ERROR: --reviewer requires a value" >&2; exit 1; }
                reviewer="$2"; shift 2 ;;
            --since)
                [[ $# -ge 2 ]] || { echo "ERROR: --since requires a value" >&2; exit 1; }
                since="$2"; shift 2 ;;
            *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    if [[ ! "$pr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: CR number must be numeric, got '$pr_num'" >&2
        exit 1
    fi

    if [[ -n "$reviewer" ]] && [[ ! "$reviewer" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "ERROR: Invalid reviewer name '$reviewer'." >&2
        exit 1
    fi

    local comment_filter
    comment_filter="$(review_reviewer_filter "$reviewer")"
    if [[ -n "$since" ]]; then
        # Reuse simple relative-time parsing; skip push-event lookup (notes only)
        local since_ts=""
        if [[ "$since" =~ ^[0-9]+[hm]$ ]]; then
            local unit="${since: -1}" amount="${since%?}" seconds=0
            [[ "$unit" == "h" ]] && seconds=$((amount * 3600)) || seconds=$((amount * 60))
            since_ts=$(date -u -d "$seconds seconds ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || date -u -v-"${seconds}S" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || { echo "ERROR: Cannot compute relative time." >&2; exit 1; })
        else
            if [[ ! "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$ ]]; then
                echo "ERROR: Invalid --since value '$since'." >&2
                echo "  Expected: Nh, Nm, or ISO 8601 (e.g. 2026-03-13T15:00:00Z)" >&2
                exit 1
            fi
            since_ts="$since"
        fi
        local since_literal
        since_literal="$(review_jq_string_literal "$since_ts")"
        comment_filter="$comment_filter | select((.created_at // .updated_at) > $since_literal)"
    fi

    echo "=== Notes: CR #$pr_num ($REPO_SLUG) ==="
    local notes="" _rc=0
    notes=$(gp_review_list_notes "$REPO_SLUG" "$pr_num" "$comment_filter") || _rc=$?
    # Failure marker on stdout (not stderr) — section status, not
    # script error. Consistent with review_comments. If --output
    # ever extends to this subcommand, the marker will land in
    # the captured file rather than getting lost on stderr.
    if [[ $_rc -ne 0 ]]; then
        echo "(failed to fetch notes — check auth and connectivity)"
    elif [[ -n "$notes" ]]; then
        echo "$notes"
    else
        echo "(no notes${reviewer:+ from $reviewer})"
    fi
}

review_threads() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> threads <cr#> [--remote <name>] [--status | --resolve <id> | --resolve-all]" >&2
        exit 1
    fi

    local pr_num="$1"
    shift

    if [[ ! "$pr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: CR number must be numeric, got '$pr_num'" >&2
        exit 1
    fi

    local mode="list"
    local resolve_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                [[ "$mode" == "list" ]] || { echo "ERROR: --status, --resolve, and --resolve-all are mutually exclusive" >&2; exit 1; }
                mode="status"; shift ;;
            --resolve-all)
                [[ "$mode" == "list" ]] || { echo "ERROR: --status, --resolve, and --resolve-all are mutually exclusive" >&2; exit 1; }
                mode="resolve-all"; shift ;;
            --resolve)
                [[ $# -ge 2 ]] || { echo "ERROR: --resolve requires a thread ID" >&2; exit 1; }
                [[ "$mode" == "list" ]] || { echo "ERROR: --status, --resolve, and --resolve-all are mutually exclusive" >&2; exit 1; }
                mode="resolve"
                resolve_id="$2"
                if [[ ! "$resolve_id" =~ ^[A-Za-z0-9_=+/.:-]+$ ]]; then
                    echo "ERROR: Invalid thread ID '$resolve_id'." >&2
                    exit 1
                fi
                shift 2 ;;
            *)
                echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    case "$mode" in
        list)
            local threads
            threads=$(gp_review_threads_list "$REPO_SLUG" "$pr_num") || {
                echo "ERROR: Could not fetch threads for CR #$pr_num from $REPO_SLUG." >&2
                exit 1
            }
            if [[ -z "$threads" ]]; then
                echo "No unresolved threads on CR #$pr_num ($REPO_SLUG)."
            else
                echo "=== Unresolved threads: CR #$pr_num ($REPO_SLUG) ==="
                printf '%s\n' "$threads"
            fi
            ;;
        status)
            gp_review_threads_status "$REPO_SLUG" "$pr_num" || {
                echo "ERROR: Could not fetch threads for CR #$pr_num from $REPO_SLUG." >&2
                exit 1
            }
            ;;
        resolve)
            gp_review_thread_resolve "$REPO_SLUG" "$pr_num" "$resolve_id" || {
                echo "ERROR: Failed to resolve thread $resolve_id on CR #$pr_num." >&2
                exit 1
            }
            echo "Resolved thread $resolve_id on CR #$pr_num."
            ;;
        resolve-all)
            gp_review_threads_resolve_all "$REPO_SLUG" "$pr_num"
            ;;
    esac
}

review_reply() {
    if [[ $# -lt 3 || $# -gt 4 ]]; then
        echo "Usage: ws review <comp> reply <cr#> <thread-id> <message> [--remote <name>] [--resolve]" >&2
        exit 1
    fi

    local cr_num="$1" thread_id="$2" message="$3"
    local resolve=false
    if [[ $# -eq 4 ]]; then
        [[ "$4" == "--resolve" ]] || { echo "ERROR: Unknown option '$4'" >&2; exit 1; }
        resolve=true
    fi

    if [[ ! "$cr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: CR number must be numeric, got '$cr_num'" >&2
        exit 1
    fi

    if [[ -z "$thread_id" ]]; then
        echo "ERROR: Thread ID is required." >&2
        exit 1
    fi

    gp_review_thread_reply "$REPO_SLUG" "$cr_num" "$thread_id" "$message" || {
        echo "ERROR: Failed to reply to thread $thread_id on CR #$cr_num." >&2
        exit 1
    }
    echo "Replied to thread on CR #$cr_num ($REPO_SLUG)."

    if [[ "$resolve" == true ]]; then
        gp_review_thread_resolve "$REPO_SLUG" "$cr_num" "$thread_id" || {
            echo "WARNING: Reply posted but failed to resolve thread $thread_id." >&2
            exit 1
        }
        echo "Thread resolved."
    fi
}

# --- Shared setup ---

# Handle --help before requiring auth — help should always work
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    review_help
fi


# Source provider dispatcher for slug extraction
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Load merged ecosystem config for provider detection (self-hosted mappings)
_ECO=""
_AUTH_ECO=""
# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"
_ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
_AUTH_ECO=$(ws_resolve_local_ecosystem 2>/dev/null) || _AUTH_ECO=""

# Parse component (first positional arg, always required)
if [[ $# -lt 1 ]]; then
    echo "Usage: ws review <comp> threads <cr#> [--remote <name>] [--status | --resolve <id> | --resolve-all]" >&2
    echo "       ws review <comp> reply <cr#> <thread-id> <message> [--remote <name>] [--resolve]" >&2
    echo "       ws review <comp> <cr#> [--remote <name>] [--reviewer <name>] [--since <time>] [--compact]" >&2
    echo "" >&2
    echo "Run 'ws review --help' for details." >&2
    exit 1
fi

COMP="$1"
shift

# Reserve 'help' before component validation so 'ws review help' works
if [[ "$COMP" == "help" ]]; then
    review_help
    exit 0
fi

REVIEW_REMOTE=""
_FILTERED_ARGS=()
# `--remote` is extracted here, ahead of subcommand dispatch, because it drives
# the remote/slug resolution below. The wrinkle is `reply <cr#> <thread-id>
# <message>`: its <message> is free-form and may legitimately begin with
# `--remote`, so that positional must pass through verbatim rather than be
# consumed as the flag. Locate the subcommand keyword first (looking past any
# leading `--remote` flag), then shield the reply message positional.
_subcmd=""
_peek_args=("$@")
_pi=0
while [[ $_pi -lt ${#_peek_args[@]} ]]; do
    case "${_peek_args[$_pi]}" in
        --remote) _pi=$((_pi + 2)) ;;
        --remote=*) _pi=$((_pi + 1)) ;;
        *) _subcmd="${_peek_args[$_pi]}"; break ;;
    esac
done
# For `reply`, the <message> is the 4th positional: reply, cr#, thread-id, message.
_positional=0
while [[ $# -gt 0 ]]; do
    if [[ "$_subcmd" == "reply" && $_positional -eq 3 ]]; then
        _FILTERED_ARGS+=("$1")
        _positional=$((_positional + 1))
        shift
        continue
    fi
    case "$1" in
        --remote)
            [[ $# -ge 2 ]] || { echo "ERROR: --remote requires a value" >&2; exit 1; }
            REVIEW_REMOTE="$2"
            shift 2
            ;;
        --remote=*)
            REVIEW_REMOTE="${1#--remote=}"
            [[ -n "$REVIEW_REMOTE" ]] || { echo "ERROR: --remote value cannot be empty" >&2; exit 1; }
            shift
            ;;
        *)
            _FILTERED_ARGS+=("$1")
            _positional=$((_positional + 1))
            shift
            ;;
    esac
done
set -- "${_FILTERED_ARGS[@]}"

if [[ -n "$REVIEW_REMOTE" && ! "$REVIEW_REMOTE" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "ERROR: Invalid remote name '$REVIEW_REMOTE'. Use alphanumeric, dot, dash, underscore, or slash." >&2
    exit 1
fi

# Resolve the target directory via the shared helper — accepts components,
# realms, hoards, and 'yggdrasil' (workspace root), matching ws commit/push.
# (Previously hardcoded components/<name>, which broke realm/hoard CR review —
# the ws_resolve_target gap hit on realm-siliconsaga #9.)
# Unlike push/issue (which target YOUR fork), review reads CRs that may live
# on any remote (typically upstream). Strategy: extract the CR number from args,
# try each remote's slug until the CR is found.
ws_resolve_target "$COMP"
COMP_DIR="$COMPONENT_DIR"

# ws_resolve_target guarantees the directory exists, not that it's a git
# repo. Guard before the git-remote probing below so a bare folder fails with
# a friendly message instead of a raw git fatal under set -e. rev-parse is
# worktree-safe where a plain `-d .git` check is not.
if ! git -C "$COMP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: '$COMP' at $COMP_DIR is not a git repository." >&2
    exit 1
fi

# Build list of candidate slugs from all remotes, grouped by provider
_CANDIDATE_SLUGS=()
_CANDIDATE_PROVIDERS=()
_CANDIDATE_URLS=()
_CANDIDATE_REMOTES=()
for _r in $(cd "$COMP_DIR" && git remote); do
    _url=$(cd "$COMP_DIR" && git remote get-url "$_r" 2>/dev/null) || continue
    _prov=$(gp_detect "$_url" "$_ECO" 2>/dev/null) || continue
    gp_load "$_prov" 2>/dev/null || continue
    _slug=$(gp_extract_slug "$_url")
    if [[ -n "$_slug" && "$_slug" == */* ]]; then
        _CANDIDATE_SLUGS+=("$_slug")
        _CANDIDATE_PROVIDERS+=("$_prov")
        _CANDIDATE_URLS+=("$_url")
        _CANDIDATE_REMOTES+=("$_r")
    fi
done

if [[ ${#_CANDIDATE_SLUGS[@]} -eq 0 ]]; then
    echo "ERROR: No supported remotes found for '$COMP'." >&2
    exit 1
fi

# Peek at the CR number from remaining args to probe which slug has it
_PEEK_CR=""
if [[ "${1:-}" == "threads" && "${2:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_CR="$2"
elif [[ "${1:-}" == "notes" && "${2:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_CR="$2"
elif [[ "${1:-}" == "reply" && "${2:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_CR="$2"
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_CR="$1"
fi

REPO_SLUG=""
_SELECTED_PROVIDER=""
# Track the exact selected remote's URL alongside its slug. Matching by slug
# alone is ambiguous when two remotes share owner/repo across hosts or provider
# mappings — token setup below needs the precise URL, not "first slug match".
_SELECTED_URL=""
if [[ -n "$REVIEW_REMOTE" ]]; then
    for i in "${!_CANDIDATE_REMOTES[@]}"; do
        if [[ "${_CANDIDATE_REMOTES[$i]}" == "$REVIEW_REMOTE" ]]; then
            REPO_SLUG="${_CANDIDATE_SLUGS[$i]}"
            _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[$i]}"
            _SELECTED_URL="${_CANDIDATE_URLS[$i]}"
            break
        fi
    done
    if [[ -z "$REPO_SLUG" ]]; then
        _available=()
        for i in "${!_CANDIDATE_REMOTES[@]}"; do
            _available+=("${_CANDIDATE_REMOTES[$i]}=${_CANDIDATE_SLUGS[$i]}")
        done
        echo "ERROR: Remote '$REVIEW_REMOTE' is not a supported review remote for '$COMP'." >&2
        echo "  Available remotes: ${_available[*]:-(none)}" >&2
        exit 1
    fi
elif [[ ${#_CANDIDATE_SLUGS[@]} -eq 1 ]]; then
    REPO_SLUG="${_CANDIDATE_SLUGS[0]}"
    _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[0]}"
    _SELECTED_URL="${_CANDIDATE_URLS[0]}"
elif [[ -n "$_PEEK_CR" ]]; then
    # Try each slug — collect all matches (CR numbers aren't unique across repos)
    # Deduplicate: skip slug/provider pairs we've already probed. Carry the
    # remote name and URL through the probe so the error/selection paths use the
    # matched remote identity directly instead of reconstructing it by slug.
    _MATCH_SLUGS=()
    _MATCH_PROVIDERS=()
    _MATCH_REMOTES=()
    _MATCH_URLS=()
    _PROBE_FAILURES=()
    _seen=""
    for i in "${!_CANDIDATE_SLUGS[@]}"; do
        _slug="${_CANDIDATE_SLUGS[$i]}"
        _prov="${_CANDIDATE_PROVIDERS[$i]}"
        _key="${_prov}:${_slug}"
        [[ "$_seen" == *"|${_key}|"* ]] && continue
        _seen+="|${_key}|"
        gp_load "$_prov" 2>/dev/null || continue
        _probe_output=""
        if _probe_output="$(gp_review_summary "$_slug" "$_PEEK_CR" 2>&1)"; then
            _MATCH_SLUGS+=("$_slug")
            _MATCH_PROVIDERS+=("$_prov")
            _MATCH_REMOTES+=("${_CANDIDATE_REMOTES[$i]}")
            _MATCH_URLS+=("${_CANDIDATE_URLS[$i]}")
        else
            _probe_rc=$?
            _probe_msg="$(review_probe_one_line "$_probe_output")"
            [[ -n "$_probe_msg" ]] || _probe_msg="provider exited $_probe_rc without details"
            if ! review_probe_not_found "$_probe_rc" "$_probe_msg"; then
                _PROBE_FAILURES+=("${_prov}:${_slug}: $_probe_msg")
            fi
        fi
    done
    if [[ ${#_MATCH_SLUGS[@]} -eq 0 ]]; then
        if [[ ${#_PROBE_FAILURES[@]} -gt 0 ]]; then
            echo "ERROR: Could not verify CR #$_PEEK_CR on any remote for '$COMP'." >&2
            echo "  Provider lookup failed before a not-found result could be trusted:" >&2
            for _failure in "${_PROBE_FAILURES[@]}"; do
                echo "    - $_failure" >&2
            done
            echo "  Check network/auth, then retry." >&2
            echo "  Tried: ${_CANDIDATE_SLUGS[*]}" >&2
            exit 1
        fi
        echo "ERROR: CR #$_PEEK_CR not found on any remote for '$COMP'." >&2
        echo "  Tried: ${_CANDIDATE_SLUGS[*]}" >&2
        exit 1
    elif [[ ${#_MATCH_SLUGS[@]} -gt 1 ]]; then
        _matches=()
        for i in "${!_MATCH_SLUGS[@]}"; do
            _matches+=("${_MATCH_REMOTES[$i]}=${_MATCH_SLUGS[$i]}")
        done
        echo "ERROR: CR #$_PEEK_CR found on multiple remotes for '$COMP'." >&2
        echo "  Matches: ${_matches[*]}" >&2
        echo "  Use --remote <name> to select one." >&2
        exit 1
    fi
    REPO_SLUG="${_MATCH_SLUGS[0]}"
    _SELECTED_PROVIDER="${_MATCH_PROVIDERS[0]}"
    _SELECTED_URL="${_MATCH_URLS[0]}"
else
    # Can't probe without a CR number — use first slug
    REPO_SLUG="${_CANDIDATE_SLUGS[0]}"
    _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[0]}"
    _SELECTED_URL="${_CANDIDATE_URLS[0]}"
fi

# Ensure the selected provider is loaded
gp_load "$_SELECTED_PROVIDER"

# Pre-populate the provider token from ecosystem config so gp_check_cli
# doesn't fall through to glab auth status when only split tokens are set.
# Use the exact selected remote URL captured above — not a re-match by slug.
if [[ -n "$_SELECTED_URL" ]]; then
    gp_set_token_for_url "$_SELECTED_URL" "$_AUTH_ECO"
fi

# Provider-specific auth check
gp_check_cli || exit 1

# --- Route to subcommand ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    review_help
elif [[ "${1:-}" == "threads" ]]; then
    shift
    review_threads "$@"
elif [[ "${1:-}" == "notes" ]]; then
    shift
    review_notes "$@"
elif [[ "${1:-}" == "reply" ]]; then
    shift
    review_reply "$@"
else
    review_comments "$@"
fi
