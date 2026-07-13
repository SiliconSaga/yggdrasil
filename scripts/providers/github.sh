#!/usr/bin/env bash
# providers/github.sh — GitHub provider implementation (gh CLI)
#
# Implements the git-provider contract using the GitHub CLI.
# This file is sourced by git-provider.sh — do not run directly.

# Verify gh CLI is installed and has a valid token.
gp_check_cli() {
    if ! command -v gh &>/dev/null; then
        echo "ERROR: GitHub CLI (gh) is not installed." >&2
        echo "" >&2
        echo "  Install:" >&2
        echo "    macOS:   brew install gh" >&2
        echo "    Windows: winget install GitHub.cli" >&2
        echo "    Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md" >&2
        echo "" >&2
        echo "  Then set GH_TOKEN in .env (see docs/git-provider-setup.md)." >&2
        return 1
    fi

    if ! gh auth status &>/dev/null; then
        echo "ERROR: gh CLI is not authenticated." >&2
        echo "  Set GH_TOKEN in .env or run 'gh auth login'." >&2
        echo "  See docs/git-provider-setup.md for details." >&2
        return 1
    fi
}

# Extract org/repo slug from a remote URL.
# Handles both HTTPS and SSH formats for any domain.
# Usage: gp_extract_slug URL
gp_extract_slug() {
    local url="$1"
    # Handle SSH (ssh://git@host:port/org/repo), HTTPS (https://host/org/repo), and git@ (git@host:org/repo)
    echo "$url" | sed 's|^ssh://[^/]*/||; s|^https://[^/]*/||; s|^http://[^/]*/||; s|^git@[^:]*:||; s|\.git$||'
}

# Query the default branch of a GitHub repo.
# Usage: gp_default_branch SLUG
gp_default_branch() {
    local slug="$1"
    gh api "repos/$slug" --jq '.default_branch' 2>/dev/null || echo "main"
}

# Create a pull request.
# Usage: gp_create_pr --repo SLUG --base BRANCH --head REF --title TEXT --body-file PATH [--fork-slug SLUG]
gp_create_pr() {
    local repo="" base="" head="" title="" body_file="" fork_slug=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      repo="$2"; shift 2 ;;
            --base)      base="$2"; shift 2 ;;
            --head)      head="$2"; shift 2 ;;
            --title)     title="$2"; shift 2 ;;
            --body-file) body_file="$2"; shift 2 ;;
            --fork-slug) fork_slug="$2"; shift 2 ;;
            *) echo "ERROR: gp_create_pr: unknown arg '$1'" >&2; return 1 ;;
        esac
    done

    # GitHub cross-fork PRs use "Org:branch" as head ref
    local head_ref="$head"
    if [[ -n "$fork_slug" ]]; then
        local fork_owner="${fork_slug%%/*}"
        head_ref="${fork_owner}:${head}"
    fi

    gh pr create \
        --repo "$repo" \
        --base "$base" \
        --head "$head_ref" \
        --title "$title" \
        --body-file "$body_file"
}

# Create an issue.
# Usage: gp_create_issue --repo SLUG --title TEXT --label LABEL --body-file PATH
gp_create_issue() {
    local repo="" title="" label="" body_file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      repo="$2"; shift 2 ;;
            --title)     title="$2"; shift 2 ;;
            --label)     label="$2"; shift 2 ;;
            --body-file) body_file="$2"; shift 2 ;;
            *) echo "ERROR: gp_create_issue: unknown arg '$1'" >&2; return 1 ;;
        esac
    done

    gh issue create \
        --repo "$repo" \
        --title "$title" \
        --label "$label" \
        --body-file "$body_file"
}

# --- Review functions ---

# Print PR summary.
# Usage: gp_review_summary SLUG PR_NUM
gp_review_summary() {
    local slug="$1" pr_num="$2"
    gh api "repos/$slug/pulls/$pr_num" \
        --jq '"Title: \(.title)\nState: \(.state)\nAuthor: \(.user.login)\nBranch: \(.head.ref) → \(.base.ref)\nURL: \(.html_url)"'
}

# Print formatted reviews.
# Usage: gp_review_list_reviews SLUG PR_NUM [JQ_FILTER]
gp_review_list_reviews() {
    local slug="$1" pr_num="$2" filter="${3:-.}"
    gh api "repos/$slug/pulls/$pr_num/reviews" \
        --jq ".[] | $filter | \"[\(.user.login)] \(.state)\(.body | if . != \"\" then \":\n\" + . else \"\" end)\n\"" 2>/dev/null
}

# Print formatted inline comments.
# Usage: gp_review_list_comments SLUG PR_NUM [JQ_FILTER]
gp_review_list_comments() {
    local slug="$1" pr_num="$2" filter="${3:-.}"
    gh api "repos/$slug/pulls/$pr_num/comments" \
        --jq ".[] | $filter | \"---\n[\(.user.login)] \(.path):\(.line // .original_line)\n\(.body)\n\"" 2>/dev/null
}

# Print formatted top-level PR notes (issue comments — not inline review comments).
# GitHub treats PRs as issues; top-level comments live on the issues endpoint.
# Usage: gp_review_list_notes SLUG PR_NUM [JQ_FILTER]
gp_review_list_notes() {
    local slug="$1" pr_num="$2" filter="${3:-.}"
    gh api "repos/$slug/issues/$pr_num/comments" \
        --jq ".[] | $filter | \"---\n[\(.user.login)] (note)\n\(.body)\n\"" 2>/dev/null
}

# Get PR head branch name (for --since push event lookup).
# Usage: gp_review_head_branch SLUG PR_NUM
gp_review_head_branch() {
    local slug="$1" pr_num="$2"
    gh api "repos/$slug/pulls/$pr_num" --jq '.head.ref' 2>/dev/null
}

# Get push event timestamp for a branch.
# Usage: gp_review_push_timestamp SLUG BRANCH INDEX
gp_review_push_timestamp() {
    local slug="$1" branch="$2" index="${3:-0}"
    local ref_json
    ref_json=$(jq -Rn --arg ref "refs/heads/$branch" '$ref')
    # Paginate the (best-effort, ~300-event / 90-day) events feed at 100/page so
    # the branch's Nth PushEvent isn't crowded out of the default first 30 by
    # unrelated repo activity. Keep each event's prior branch head so prev-push
    # can recover conservatively when GitHub's lossy event feed omits that event.
    local events timestamp
    events=$(gh api --paginate "repos/$slug/events?per_page=100" \
        --jq ".[] | select(.type == \"PushEvent\") | select(.payload.ref == $ref_json) | [.created_at, .payload.before] | @tsv" \
        2>/dev/null) || return 1

    timestamp=$(awk -F $'\t' -v row="$((index + 1))" 'NR == row { print $1; exit }' <<< "$events")
    if [[ -n "$timestamp" ]]; then
        echo "$timestamp"
        return 0
    fi

    # If GitHub's lossy event feed omitted the preceding push, do not substitute
    # the previous head's committer date: a PR author controls that timestamp and
    # can forge it forward to suppress review comments. Fall back to all history;
    # this is noisier but cannot hide feedback.
    if [[ "$index" -eq 1 ]]; then
        echo "NOTE: GitHub omitted the previous push event; ignoring untrusted commit timestamps and showing all review history." >&2
        echo "1970-01-01T00:00:00Z"
    fi
}

# List unresolved review threads.
# Usage: gp_review_threads_list SLUG PR_NUM
# Output: one block per thread: ---\n[author] path:line (id)\nbody\n
gp_review_threads_list() {
    local slug="$1" pr_num="$2"
    local owner="${slug%%/*}" repo="${slug##*/}"

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
        }' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" 2>/dev/null) || return 1

    local thread_count
    thread_count=$(echo "$response" | jq '.data.repository.pullRequest.reviewThreads.nodes | length')
    if [[ "$thread_count" -ge 100 ]]; then
        echo "WARNING: PR #$pr_num has $thread_count+ threads (max 100 per page). Results may be incomplete." >&2
    fi

    echo "$response" | jq -r '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | "---\n[\(.comments.nodes[0].author.login // "unknown")] \(.comments.nodes[0].path // "?"):\(.comments.nodes[0].line // "?") (\(.id))\n\(.comments.nodes[0].body // "")\n"
    '
}

# Print thread status counts.
# Usage: gp_review_threads_status SLUG PR_NUM
gp_review_threads_status() {
    local slug="$1" pr_num="$2"
    local owner="${slug%%/*}" repo="${slug##*/}"

    local response
    response=$(gh api graphql -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                nodes { isResolved }
              }
            }
          }
        }' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" 2>/dev/null) || return 1

    local thread_count
    thread_count=$(echo "$response" | jq '.data.repository.pullRequest.reviewThreads.nodes | length')
    if [[ "$thread_count" -ge 100 ]]; then
        echo "WARNING: PR #$pr_num has $thread_count+ threads (max 100 per page). Results may be incomplete." >&2
    fi

    echo "$response" | jq -r --arg pr "$pr_num" --arg slug "$slug" '
        .data.repository.pullRequest.reviewThreads.nodes
        | {
            resolved: [.[] | select(.isResolved == true)] | length,
            unresolved: [.[] | select(.isResolved == false)] | length,
            total: length
          }
        | "PR #\($pr) (\($slug)): \(.unresolved) unresolved, \(.resolved) resolved (\(.total) total)"
    '
}

# Reply to a review thread.
# Usage: gp_review_thread_reply SLUG PR_NUM THREAD_ID MESSAGE
gp_review_thread_reply() {
    local slug="$1" pr_num="$2" thread_id="$3" message="$4"
    gh api graphql -f query='
        mutation($threadId: ID!, $body: String!) {
          addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
            comment { id }
          }
        }' -f threadId="$thread_id" -f body="$message" >/dev/null 2>&1
}

# Resolve a single thread.
# Usage: gp_review_thread_resolve SLUG PR_NUM THREAD_ID
gp_review_thread_resolve() {
    local slug="$1" pr_num="$2" thread_id="$3"
    gh api graphql -f query='
        mutation($id: ID!) {
          resolveReviewThread(input: {threadId: $id}) {
            thread { isResolved }
          }
        }' -f id="$thread_id" >/dev/null 2>&1
}

# Resolve all unresolved threads. Prints progress.
# Usage: gp_review_threads_resolve_all SLUG PR_NUM
gp_review_threads_resolve_all() {
    local slug="$1" pr_num="$2"
    local owner="${slug%%/*}" repo="${slug##*/}"

    local response
    response=$(gh api graphql -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                nodes { id isResolved }
              }
            }
          }
        }' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" 2>/dev/null) || return 1

    local thread_count
    thread_count=$(echo "$response" | jq '.data.repository.pullRequest.reviewThreads.nodes | length')
    if [[ "$thread_count" -ge 100 ]]; then
        echo "WARNING: PR #$pr_num has $thread_count+ threads (max 100 per page). Resolution may be incomplete." >&2
    fi

    local ids
    ids=$(echo "$response" | jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .id')

    if [[ -z "$ids" ]]; then
        echo "No unresolved threads on PR #$pr_num ($slug)."
        return 0
    fi

    local total=0 resolved=0 failed=0
    while IFS= read -r thread_id; do
        total=$((total + 1))
        if gp_review_thread_resolve "$slug" "$pr_num" "$thread_id"; then
            resolved=$((resolved + 1))
        else
            failed=$((failed + 1))
            echo "WARNING: Failed to resolve thread $thread_id" >&2
        fi
    done <<< "$ids"

    if [[ "$failed" -eq 0 ]]; then
        echo "Resolved $resolved threads on PR #$pr_num ($slug)."
    else
        echo "Resolved $resolved of $total threads on PR #$pr_num ($slug). $failed failed." >&2
        return 1
    fi
}
