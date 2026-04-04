#!/usr/bin/env bash
# ws-review.sh — PR/MR review comments and thread management
#
# Usage:
#   ws-review.sh <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]
#   ws-review.sh <comp> <pr#> [--reviewer <name>] [--since <time>]
#
# Supports GitHub (gh) and GitLab (glab). Component name is always required.
# Provider is auto-detected from the component's remote URL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Function definitions (must precede routing block at bottom) ---

review_help() {
    echo "Usage: ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]"
    echo "       ws review <comp> <pr#> [--reviewer <name>] [--since <time>]"
    echo ""
    echo "PR/MR review comments and thread management."
    echo ""
    echo "Subcommands:"
    echo "  threads <pr#>              List unresolved review threads"
    echo "    --status                 Show resolved/unresolved counts"
    echo "    --resolve <thread-id>    Resolve a single thread"
    echo "    --resolve-all            Resolve all unresolved threads"
    echo ""
    echo "  <pr#>                      List review comments (default)"
    echo "    --reviewer <name>        Filter by reviewer login"
    echo "    --since <time>           Filter by time (last-push, prev-push, Nh, Nm, ISO 8601)"
    echo "                             (--since push events: GitHub only)"
    echo ""
    echo "Examples:"
    echo "  ws review yggdrasil threads 8              # List unresolved threads"
    echo "  ws review yggdrasil threads 8 --status     # Thread counts"
    echo "  ws review yggdrasil threads 8 --resolve-all"
    echo "  ws review yggdrasil 8                      # All review comments"
    echo "  ws review ymir 5 --reviewer coderabbitai"
    echo "  ws review yggdrasil 8 --since last-push"
    exit 0
}

review_comments() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> <pr#> [--reviewer <name>] [--since <time>]" >&2
        exit 1
    fi

    # Parse arguments
    local pr_num="$1"
    shift
    local reviewer=""
    local since=""
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

    # Validate PR number is numeric
    if [[ ! "$pr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: PR number must be numeric, got '$pr_num'" >&2
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

    # Fetch PR/MR summary
    echo "=== PR #$pr_num ($REPO_SLUG) ==="
    gp_review_summary "$REPO_SLUG" "$pr_num" || {
        echo "ERROR: Could not fetch PR #$pr_num from $REPO_SLUG." >&2
        echo "  Check the PR number and repo name." >&2
        exit 1
    }
    echo ""

    # Fetch reviews (|| true prevents set -e abort on API failure)
    echo "=== Reviews ==="
    local reviews
    reviews=$(gp_review_list_reviews "$REPO_SLUG" "$pr_num" "$review_filter" || true)
    if [[ -n "$reviews" ]]; then
        echo "$reviews"
    else
        echo "(no reviews${reviewer:+ from $reviewer})"
    fi
    echo ""

    # Fetch inline comments (|| true prevents set -e abort on API failure)
    echo "=== Inline Comments ==="
    local comments
    comments=$(gp_review_list_comments "$REPO_SLUG" "$pr_num" "$comment_filter" || true)
    if [[ -n "$comments" ]]; then
        echo "$comments"
    else
        echo "(no inline comments${reviewer:+ from $reviewer})"
    fi
}

review_threads() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]" >&2
        exit 1
    fi

    local pr_num="$1"
    shift

    if [[ ! "$pr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: PR number must be numeric, got '$pr_num'" >&2
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
                echo "ERROR: Could not fetch threads for PR #$pr_num from $REPO_SLUG." >&2
                exit 1
            }
            if [[ -z "$threads" ]]; then
                echo "No unresolved threads on PR #$pr_num ($REPO_SLUG)."
            else
                echo "=== Unresolved threads: PR #$pr_num ($REPO_SLUG) ==="
                printf '%s\n' "$threads"
            fi
            ;;
        status)
            gp_review_threads_status "$REPO_SLUG" "$pr_num" || {
                echo "ERROR: Could not fetch threads for PR #$pr_num from $REPO_SLUG." >&2
                exit 1
            }
            ;;
        resolve)
            gp_review_thread_resolve "$REPO_SLUG" "$pr_num" "$resolve_id" || {
                echo "ERROR: Failed to resolve thread $resolve_id on PR #$pr_num." >&2
                exit 1
            }
            echo "Resolved thread $resolve_id on PR #$pr_num."
            ;;
        resolve-all)
            gp_review_threads_resolve_all "$REPO_SLUG" "$pr_num"
            ;;
    esac
}

# --- Shared setup ---

# Handle --help before requiring auth — help should always work
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    review_help
fi

# Source .env for provider tokens (GH_TOKEN, GITLAB_TOKEN, etc.)
env_file="$ROOT_DIR/.env"
if [[ -f "$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_file"
fi

# Source provider dispatcher for slug extraction
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Load merged ecosystem config for provider detection (self-hosted mappings)
_ECO=""
if [[ -f "$SCRIPT_DIR/ws-overlay.sh" ]]; then
    source "$SCRIPT_DIR/ws-overlay.sh"
    _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
fi

# Parse component (first positional arg, always required)
if [[ $# -lt 1 ]]; then
    echo "Usage: ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]" >&2
    echo "       ws review <comp> <pr#> [--reviewer <name>] [--since <time>]" >&2
    echo "" >&2
    echo "Run 'ws review --help' for details." >&2
    exit 1
fi

COMP="$1"
shift

# Validate component name (same regex as ws_validate_component)
if [[ ! "$COMP" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
    echo "ERROR: Invalid component name '$COMP'. Must be lowercase alphanumeric with hyphens/dots." >&2
    exit 1
fi

# Resolve repo slug from component's remotes.
# Unlike push/issue (which target YOUR fork), review reads PRs that may live
# on any remote (typically upstream). Strategy: extract the PR number from args,
# try each remote's slug until the PR is found.
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
for _r in $(cd "$COMP_DIR" && git remote); do
    _url=$(cd "$COMP_DIR" && git remote get-url "$_r" 2>/dev/null) || continue
    _prov=$(gp_detect "$_url" "$_ECO" 2>/dev/null) || continue
    gp_load "$_prov" 2>/dev/null || continue
    _slug=$(gp_extract_slug "$_url")
    if [[ -n "$_slug" && "$_slug" == */* ]]; then
        _CANDIDATE_SLUGS+=("$_slug")
        _CANDIDATE_PROVIDERS+=("$_prov")
    fi
done

if [[ ${#_CANDIDATE_SLUGS[@]} -eq 0 ]]; then
    echo "ERROR: No supported remotes found for '$COMP'." >&2
    exit 1
fi

# Peek at the PR number from remaining args to probe which slug has it
_PEEK_PR=""
if [[ "${1:-}" == "threads" && "${2:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_PR="$2"
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_PR="$1"
fi

REPO_SLUG=""
_SELECTED_PROVIDER=""
if [[ ${#_CANDIDATE_SLUGS[@]} -eq 1 ]]; then
    REPO_SLUG="${_CANDIDATE_SLUGS[0]}"
    _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[0]}"
elif [[ -n "$_PEEK_PR" ]]; then
    # Try each slug — collect all matches (PR numbers aren't unique across repos)
    _MATCH_SLUGS=()
    _MATCH_PROVIDERS=()
    for i in "${!_CANDIDATE_SLUGS[@]}"; do
        _slug="${_CANDIDATE_SLUGS[$i]}"
        _prov="${_CANDIDATE_PROVIDERS[$i]}"
        gp_load "$_prov" 2>/dev/null || continue
        if gp_review_summary "$_slug" "$_PEEK_PR" &>/dev/null; then
            _MATCH_SLUGS+=("$_slug")
            _MATCH_PROVIDERS+=("$_prov")
        fi
    done
    if [[ ${#_MATCH_SLUGS[@]} -eq 0 ]]; then
        echo "ERROR: PR/MR #$_PEEK_PR not found on any remote for '$COMP'." >&2
        echo "  Tried: ${_CANDIDATE_SLUGS[*]}" >&2
        exit 1
    elif [[ ${#_MATCH_SLUGS[@]} -gt 1 ]]; then
        echo "ERROR: PR/MR #$_PEEK_PR found on multiple remotes for '$COMP'." >&2
        echo "  Matches: ${_MATCH_SLUGS[*]}" >&2
        echo "  Remove extra remotes or specify which repo to review." >&2
        exit 1
    fi
    REPO_SLUG="${_MATCH_SLUGS[0]}"
    _SELECTED_PROVIDER="${_MATCH_PROVIDERS[0]}"
else
    # Can't probe without a PR number — use first slug
    REPO_SLUG="${_CANDIDATE_SLUGS[0]}"
    _SELECTED_PROVIDER="${_CANDIDATE_PROVIDERS[0]}"
fi

# Ensure the selected provider is loaded
gp_load "$_SELECTED_PROVIDER"

# Provider-specific auth check
gp_check_cli || exit 1

# --- Route to subcommand ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    review_help
elif [[ "${1:-}" == "threads" ]]; then
    shift
    review_threads "$@"
else
    review_comments "$@"
fi
