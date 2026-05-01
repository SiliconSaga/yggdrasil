#!/usr/bin/env bash
# ws-review.sh — CR review comments and thread management
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
    echo "Usage: ws review <comp> <cr#> [--reviewer <name>] [--since <time>] [--compact]"
    echo "       ws review <comp> threads <cr#> [--status | --resolve <id> | --resolve-all]"
    echo "       ws review <comp> notes <cr#> [--reviewer <name>] [--since <time>]"
    echo "       ws review <comp> reply <cr#> <thread-id> <message> [--resolve]"
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

review_comments() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> <cr#> [--reviewer <name>] [--since <time>] [--compact]" >&2
        exit 1
    fi

    # Parse arguments
    local pr_num="$1"
    shift
    local reviewer=""
    local since=""
    local compact=false
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
            *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
    done

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
                echo "  Push event lookup may not be supported for this provider." >&2
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
            $0 ~ hdr "[^[:space:]]+:[0-9]+" || $0 ~ hdr "\\(note\\)" {
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
                # sequence starting with \xF0\x9F. Match each exact
                # byte sequence — narrower than [\x80-\xff], which
                # would also drop legitimate non-English review content
                # (CJK, accented Latin, etc.). LC_ALL=C above makes awk
                # operate in byte mode so these sequences match
                # reliably regardless of system locale.
                if (/^\xF0\x9F\x8F\x81/) next  # chequered flag
                if (/^\xF0\x9F\x93\x9D/) next  # memo
                if (/^\xF0\x9F\x8C\x90/) next  # globe with meridians
                if (/^\xF0\x9F\x92\xA1/) next  # light bulb
                line = $0
                sub(/^\*\*/, "", line)
                sub(/\*\*\.?$/, "", line)
                print "    " line
                emitted_body=1
            }
        '
    }

    # Build jq filters
    local reviewer_filter="."
    if [[ -n "$reviewer" ]]; then
        reviewer_filter="select(.user.login // .author.username | test(\"$reviewer\"; \"i\"))"
    fi
    local comment_filter="$reviewer_filter"
    local review_filter="$reviewer_filter"
    if [[ -n "$since_ts" ]]; then
        comment_filter="$comment_filter | select((.created_at // .updated_at) > \"$since_ts\")"
        review_filter="$review_filter | select((.submitted_at // .created_at) > \"$since_ts\")"
    fi

    # Fetch CR summary
    echo "=== CR #$pr_num ($REPO_SLUG) ==="
    gp_review_summary "$REPO_SLUG" "$pr_num" || {
        echo "ERROR: Could not fetch CR #$pr_num from $REPO_SLUG." >&2
        echo "  Check the CR number and repo name." >&2
        exit 1
    }
    echo ""

    # Fetch reviews — warn on failure instead of aborting mid-report
    echo "=== Reviews ==="
    local reviews="" _rc=0
    reviews=$(gp_review_list_reviews "$REPO_SLUG" "$pr_num" "$review_filter") || _rc=$?
    if [[ $_rc -ne 0 ]]; then
        echo "(failed to fetch reviews — check auth and connectivity)" >&2
    elif [[ -n "$reviews" ]]; then
        echo "$reviews"
    else
        echo "(no reviews${reviewer:+ from $reviewer})"
    fi
    echo ""

    # Fetch inline comments — warn on failure instead of aborting mid-report
    echo "=== Inline Comments ==="
    local comments="" _rc=0
    comments=$(gp_review_list_comments "$REPO_SLUG" "$pr_num" "$comment_filter") || _rc=$?
    if [[ $_rc -ne 0 ]]; then
        echo "(failed to fetch inline comments — check auth and connectivity)" >&2
    elif [[ -n "$comments" ]]; then
        if [[ "$compact" == true ]]; then
            printf '%s\n' "$comments" | _render_compact
        else
            echo "$comments"
        fi
    else
        echo "(no inline comments${reviewer:+ from $reviewer})"
    fi
    echo ""

    # Fetch top-level notes (bot summaries, general comments) — warn on failure
    echo "=== Notes ==="
    local notes="" _rc=0
    notes=$(gp_review_list_notes "$REPO_SLUG" "$pr_num" "$comment_filter") || _rc=$?
    if [[ $_rc -ne 0 ]]; then
        echo "(failed to fetch notes — check auth and connectivity)" >&2
    elif [[ -n "$notes" ]]; then
        if [[ "$compact" == true ]]; then
            printf '%s\n' "$notes" | _render_compact
        else
            echo "$notes"
        fi
    else
        echo "(no notes${reviewer:+ from $reviewer})"
    fi
}

review_notes() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> notes <cr#> [--reviewer <name>] [--since <time>]" >&2
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

    local comment_filter="."
    if [[ -n "$reviewer" ]]; then
        comment_filter="select(.user.login // .author.username | test(\"$reviewer\"; \"i\"))"
    fi
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
        comment_filter="$comment_filter | select((.created_at // .updated_at) > \"$since_ts\")"
    fi

    echo "=== Notes: CR #$pr_num ($REPO_SLUG) ==="
    local notes="" _rc=0
    notes=$(gp_review_list_notes "$REPO_SLUG" "$pr_num" "$comment_filter") || _rc=$?
    if [[ $_rc -ne 0 ]]; then
        echo "(failed to fetch notes — check auth and connectivity)" >&2
    elif [[ -n "$notes" ]]; then
        echo "$notes"
    else
        echo "(no notes${reviewer:+ from $reviewer})"
    fi
}

review_threads() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> threads <cr#> [--status | --resolve <id> | --resolve-all]" >&2
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
        echo "Usage: ws review <comp> reply <cr#> <thread-id> <message> [--resolve]" >&2
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
# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"
_ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""

# Parse component (first positional arg, always required)
if [[ $# -lt 1 ]]; then
    echo "Usage: ws review <comp> threads <cr#> [--status | --resolve <id> | --resolve-all]" >&2
    echo "       ws review <comp> reply <cr#> <thread-id> <message> [--resolve]" >&2
    echo "       ws review <comp> <cr#> [--reviewer <name>] [--since <time>]" >&2
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

# Validate component name (same regex as ws_validate_component)
if [[ ! "$COMP" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
    echo "ERROR: Invalid component name '$COMP'. Must be lowercase alphanumeric with hyphens/dots." >&2
    exit 1
fi

# Resolve repo slug from component's remotes.
# Unlike push/issue (which target YOUR fork), review reads CRs that may live
# on any remote (typically upstream). Strategy: extract the CR number from args,
# try each remote's slug until the CR is found.
COMP_DIR="$ROOT_DIR/components/$COMP"
[[ "$COMP" == "yggdrasil" ]] && COMP_DIR="$ROOT_DIR"

if [[ ! -d "$COMP_DIR" ]] || [[ ! -d "$COMP_DIR/.git" ]]; then
    echo "ERROR: Component '$COMP' is not cloned locally." >&2
    echo "  Run 'ws clone $COMP' first." >&2
    exit 1
fi

# Build list of candidate slugs from all remotes, grouped by provider
_CANDIDATE_SLUGS=()
_CANDIDATE_PROVIDERS=()
_CANDIDATE_URLS=()
for _r in $(cd "$COMP_DIR" && git remote); do
    _url=$(cd "$COMP_DIR" && git remote get-url "$_r" 2>/dev/null) || continue
    _prov=$(gp_detect "$_url" "$_ECO" 2>/dev/null) || continue
    gp_load "$_prov" 2>/dev/null || continue
    _slug=$(gp_extract_slug "$_url")
    if [[ -n "$_slug" && "$_slug" == */* ]]; then
        _CANDIDATE_SLUGS+=("$_slug")
        _CANDIDATE_PROVIDERS+=("$_prov")
        _CANDIDATE_URLS+=("$_url")
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
if [[ ${#_CANDIDATE_SLUGS[@]} -eq 1 ]]; then
    REPO_SLUG="${_CANDIDATE_SLUGS[0]}"
    _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[0]}"
elif [[ -n "$_PEEK_CR" ]]; then
    # Try each slug — collect all matches (CR numbers aren't unique across repos)
    # Deduplicate: skip slug/provider pairs we've already probed
    _MATCH_SLUGS=()
    _MATCH_PROVIDERS=()
    _seen=""
    for i in "${!_CANDIDATE_SLUGS[@]}"; do
        _slug="${_CANDIDATE_SLUGS[$i]}"
        _prov="${_CANDIDATE_PROVIDERS[$i]}"
        _key="${_prov}:${_slug}"
        [[ "$_seen" == *"|${_key}|"* ]] && continue
        _seen+="|${_key}|"
        gp_load "$_prov" 2>/dev/null || continue
        if gp_review_summary "$_slug" "$_PEEK_CR" &>/dev/null; then
            _MATCH_SLUGS+=("$_slug")
            _MATCH_PROVIDERS+=("$_prov")
        fi
    done
    if [[ ${#_MATCH_SLUGS[@]} -eq 0 ]]; then
        echo "ERROR: CR #$_PEEK_CR not found on any remote for '$COMP'." >&2
        echo "  Tried: ${_CANDIDATE_SLUGS[*]}" >&2
        exit 1
    elif [[ ${#_MATCH_SLUGS[@]} -gt 1 ]]; then
        echo "ERROR: CR #$_PEEK_CR found on multiple remotes for '$COMP'." >&2
        echo "  Matches: ${_MATCH_SLUGS[*]}" >&2
        echo "  Remove extra remotes or specify which repo to review." >&2
        exit 1
    fi
    REPO_SLUG="${_MATCH_SLUGS[0]}"
    _SELECTED_PROVIDER="${_MATCH_PROVIDERS[0]}"
else
    # Can't probe without a CR number — use first slug
    REPO_SLUG="${_CANDIDATE_SLUGS[0]}"
    _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[0]}"
fi

# Ensure the selected provider is loaded
gp_load "$_SELECTED_PROVIDER"

# Pre-populate the provider token from ecosystem config so gp_check_cli
# doesn't fall through to glab auth status when only split tokens are set.
for _i in "${!_CANDIDATE_SLUGS[@]}"; do
    if [[ "${_CANDIDATE_SLUGS[$_i]}" == "$REPO_SLUG" ]]; then
        gp_set_token_for_url "${_CANDIDATE_URLS[$_i]}" "$_ECO"
        break
    fi
done

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
