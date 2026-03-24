#!/usr/bin/env bash
# ws-review.sh — PR review comments and thread management
#
# Usage:
#   ws-review.sh <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]
#   ws-review.sh <comp> <pr#> [--reviewer <name>] [--since <time>]
#
# Requires GH_TOKEN in .env. Component name is always required.
#
# GraphQL expansion note: if this script accumulates 4-5+ queries,
# consider extracting them to scripts/graphql/*.graphql loaded at runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Function definitions (must precede routing block at bottom) ---

review_help() {
    echo "Usage: ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]"
    echo "       ws review <comp> <pr#> [--reviewer <name>] [--since <time>]"
    echo ""
    echo "PR review comments and thread management."
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
            # Use GitHub Events API for accurate push timestamp
            # Always get branch from the PR — local checkout may differ
            local branch
            branch=$(gh api "repos/$REPO_SLUG/pulls/$pr_num" --jq '.head.ref' 2>/dev/null)
            if [[ -z "$branch" || "$branch" == "null" ]]; then
                echo "ERROR: Cannot determine PR head branch for #$pr_num in $REPO_SLUG." >&2
                exit 1
            fi
            local push_index=0
            [[ "$since" == "prev-push" ]] && push_index=1
            since_ts=$(gh api "repos/$REPO_SLUG/events" \
                --jq "[.[] | select(.type == \"PushEvent\") | select(.payload.ref == \"refs/heads/$branch\")] | .[$push_index].created_at" 2>/dev/null)
            if [[ -z "$since_ts" || "$since_ts" == "null" ]]; then
                echo "ERROR: Cannot determine push time for '$branch'." >&2
                echo "  Has this branch been pushed? Use an explicit timestamp instead." >&2
                exit 1
            fi
            echo "(showing comments since $since: $since_ts)"
        elif [[ "$since" =~ ^[0-9]+[hm]$ ]]; then
            # Relative time: 1h, 30m
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
            # Validate ISO 8601 format to prevent jq filter injection
            if [[ ! "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$ ]]; then
                echo "ERROR: Invalid --since value '$since'." >&2
                echo "  Expected: last-push, prev-push, Nh, Nm, or ISO 8601 (e.g. 2026-03-13T15:00:00Z)" >&2
                exit 1
            fi
            since_ts="$since"
        fi
    fi

    # Build jq filters (reviews use submitted_at, comments use created_at)
    local reviewer_filter="."
    if [[ -n "$reviewer" ]]; then
        reviewer_filter="select(.user.login | test(\"$reviewer\"; \"i\"))"
    fi
    local comment_filter="$reviewer_filter"
    local review_filter="$reviewer_filter"
    if [[ -n "$since_ts" ]]; then
        comment_filter="$comment_filter | select(.created_at > \"$since_ts\")"
        review_filter="$review_filter | select(.submitted_at > \"$since_ts\")"
    fi

    # Fetch PR summary
    echo "=== PR #$pr_num ($REPO_SLUG) ==="
    gh api "repos/$REPO_SLUG/pulls/$pr_num" \
        --jq '"Title: \(.title)\nState: \(.state)\nAuthor: \(.user.login)\nBranch: \(.head.ref) → \(.base.ref)\nURL: \(.html_url)"' 2>/dev/null || {
        echo "ERROR: Could not fetch PR #$pr_num from $REPO_SLUG." >&2
        echo "  Check the PR number and repo name." >&2
        exit 1
    }
    echo ""

    # Fetch top-level reviews
    echo "=== Reviews ==="
    local reviews
    reviews=$(gh api "repos/$REPO_SLUG/pulls/$pr_num/reviews" \
        --jq ".[] | $review_filter | \"[\(.user.login)] \(.state)\(.body | if . != \"\" then \": \" + (.[0:200]) else \"\" end)\"" 2>/dev/null)
    if [[ -n "$reviews" ]]; then
        echo "$reviews"
    else
        echo "(no reviews${reviewer:+ from $reviewer})"
    fi
    echo ""

    # Fetch inline comments
    echo "=== Inline Comments ==="
    local comments
    comments=$(gh api "repos/$REPO_SLUG/pulls/$pr_num/comments" \
        --jq ".[] | $comment_filter | \"---\n[\(.user.login)] \(.path):\(.line // .original_line)\n\(.body[0:500])\n\"" 2>/dev/null)
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

    # Validate PR number
    if [[ ! "$pr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: PR number must be numeric, got '$pr_num'" >&2
        exit 1
    fi

    # Parse flags
    local mode="list"  # list, status, resolve, resolve-all
    local resolve_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                mode="status"; shift ;;
            --resolve-all)
                mode="resolve-all"; shift ;;
            --resolve)
                [[ $# -ge 2 ]] || { echo "ERROR: --resolve requires a thread ID" >&2; exit 1; }
                mode="resolve"
                resolve_id="$2"
                # Validate thread ID format (base64-encoded GitHub node IDs)
                if [[ ! "$resolve_id" =~ ^[A-Za-z0-9_=/-]+$ ]]; then
                    echo "ERROR: Invalid thread ID '$resolve_id'." >&2
                    exit 1
                fi
                shift 2 ;;
            *)
                echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    case "$mode" in
        list)        threads_list "$pr_num" ;;
        status)      threads_status "$pr_num" ;;
        resolve)     threads_resolve_one "$pr_num" "$resolve_id" ;;
        resolve-all) threads_resolve_all "$pr_num" ;;
    esac
}

threads_list() {
    local pr_num="$1"
    local owner="${REPO_SLUG%%/*}"
    local repo="${REPO_SLUG##*/}"

    local response
    response=$(gh api graphql -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                nodes {
                  id
                  isResolved
                  comments(first: 1) {
                    nodes {
                      author { login }
                      body
                      path
                      line
                    }
                  }
                }
              }
            }
          }
        }' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" 2>/dev/null) || {
        echo "ERROR: Could not fetch threads for PR #$pr_num from $REPO_SLUG." >&2
        exit 1
    }

    local threads
    threads=$(echo "$response" | jq -r '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | {
            id: .id,
            author: (.comments.nodes[0].author.login // "unknown"),
            path: (.comments.nodes[0].path // "?"),
            line: (.comments.nodes[0].line // "?"),
            body: (.comments.nodes[0].body // "" | .[0:80] | gsub("\n"; " "))
          }
        | "[\(.author)] \(.path):\(.line) (\(.id))\n  \"\(.body)...\""
    ')

    if [[ -z "$threads" ]]; then
        echo "No unresolved threads on PR #$pr_num ($REPO_SLUG)."
    else
        echo "=== Unresolved threads: PR #$pr_num ($REPO_SLUG) ==="
        printf '%b\n' "$threads"
    fi
}

threads_status() {
    echo "ERROR: threads_status not yet implemented" >&2
    exit 1
}

threads_resolve_one() {
    echo "ERROR: threads_resolve_one not yet implemented" >&2
    exit 1
}

threads_resolve_all() {
    echo "ERROR: threads_resolve_all not yet implemented" >&2
    exit 1
}

# --- Shared setup ---

# Source .env for GH_TOKEN
env_file="$ROOT_DIR/.env"
if [[ -z "${GH_TOKEN:-}" ]] && [[ -f "$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_file"
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "ERROR: GH_TOKEN not set. Create .env from .env.example." >&2
    exit 1
fi

# Handle --help before component parsing (--help is not a valid component name)
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    review_help
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
if [[ ! "$COMP" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: Invalid component name '$COMP'. Must match [a-z][a-z0-9-]*." >&2
    exit 1
fi

REPO_SLUG="SiliconSaga/$COMP"

# --- Route to subcommand ---
# All function definitions are above this block.

if [[ "${1:-}" == "threads" ]]; then
    shift
    review_threads "$@"
else
    review_comments "$@"
fi
