#!/usr/bin/env bash
# providers/gitlab.sh — GitLab provider implementation (glab CLI)
#
# Implements the git-provider contract using the GitLab CLI.
# This file is sourced by git-provider.sh — do not run directly.

# Verify glab CLI is installed and has a valid token.
gp_check_cli() {
    if ! command -v glab &>/dev/null; then
        echo "ERROR: GitLab CLI (glab) is not installed." >&2
        echo "" >&2
        echo "  Install:" >&2
        echo "    macOS:   brew install glab" >&2
        echo "    Windows: winget install GLab.GLab" >&2
        echo "    Linux:   https://gitlab.com/gitlab-org/cli#installation" >&2
        echo "" >&2
        echo "  Then set GITLAB_TOKEN in .env (see docs/git-provider-setup.md)." >&2
        return 1
    fi

    if ! glab auth status &>/dev/null; then
        echo "ERROR: glab CLI is not authenticated." >&2
        echo "  Set GITLAB_TOKEN in .env or run 'glab auth login'." >&2
        echo "  See docs/git-provider-setup.md for details." >&2
        return 1
    fi
}

# Extract group/repo slug from a remote URL.
# Handles both HTTPS and SSH formats for any domain, including subgroups.
# Usage: gp_extract_slug URL
gp_extract_slug() {
    local url="$1"
    # Handle SSH (ssh://git@host:port/group/repo), HTTPS (https://host/group/repo), and git@ (git@host:group/repo)
    echo "$url" | sed 's|^ssh://[^/]*/||; s|^https\?://[^/]*/||; s|^git@[^:]*:||; s|\.git$||'
}

# Query the default branch of a GitLab repo.
# Usage: gp_default_branch SLUG
gp_default_branch() {
    local slug="$1"
    glab api "projects/$(echo "$slug" | sed 's|/|%2F|g')" 2>/dev/null | jq -r '.default_branch' 2>/dev/null || echo "main"
}

# Create a merge request.
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

    if [[ -z "$repo" || -z "$base" || -z "$head" || -z "$title" || -z "$body_file" ]]; then
        echo "ERROR: gp_create_pr: missing required argument(s)" >&2
        echo "  Required: --repo, --base, --head, --title, --body-file" >&2
        return 1
    fi

    # glab mr create uses --source-branch and --target-branch
    # For cross-project MRs from a fork, glab uses --repo for the target
    # and --source-project for the source (fork) project
    local cmd=(glab mr create
        --repo "$repo"
        --target-branch "$base"
        --source-branch "$head"
        --title "$title"
        --description "$(cat "$body_file")"
    )

    if [[ -n "$fork_slug" ]]; then
        cmd+=(--source-project "$fork_slug")
    fi

    "${cmd[@]}"
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

    glab issue create \
        --repo "$repo" \
        --title "$title" \
        --label "$label" \
        --description "$(cat "$body_file")"
}

# --- Review functions ---

# Helper: URL-encode a slug for GitLab API paths.
_gl_encode() { printf '%s' "${1//\//%2F}"; }

# Print MR summary.
# Usage: gp_review_summary SLUG MR_NUM
gp_review_summary() {
    local slug="$1" mr_num="$2"
    local encoded; encoded=$(_gl_encode "$slug")
    glab api "projects/$encoded/merge_requests/$mr_num" 2>/dev/null | jq -r '
        "Title: \(.title)\nState: \(.state)\nAuthor: \(.author.username)\nBranch: \(.source_branch) → \(.target_branch)\nURL: \(.web_url)"
    ' 2>/dev/null
}

# Print formatted reviews/approvals.
# GitLab doesn't have separate "reviews" — approvals are the closest equivalent.
# Usage: gp_review_list_reviews SLUG MR_NUM [JQ_FILTER]
gp_review_list_reviews() {
    local slug="$1" mr_num="$2" filter="${3:-.}"
    local encoded; encoded=$(_gl_encode "$slug")
    # Show approvals
    local approvals
    approvals=$(glab api "projects/$encoded/merge_requests/$mr_num/approvals" 2>/dev/null | jq -r "
        .approved_by[]? | {user: {login: .user.username, username: .user.username}, author: {username: .user.username}, submitted_at: .approved_at, created_at: .approved_at} | $filter | \"[\(.user.username)] APPROVED\n\"
    " 2>/dev/null)
    if [[ -n "$approvals" ]]; then
        echo "$approvals"
    fi
}

# Print formatted inline comments (discussion notes on diff).
# Usage: gp_review_list_comments SLUG MR_NUM [JQ_FILTER]
gp_review_list_comments() {
    local slug="$1" mr_num="$2" filter="${3:-.}"
    local encoded; encoded=$(_gl_encode "$slug")
    glab api "projects/$encoded/merge_requests/$mr_num/discussions" 2>/dev/null | jq -r '
        .[]
        | select(.notes[0].type == "DiffNote")
        | . as $disc
        | .notes[]
        | '"$filter"'
        | "---\n[\(.author.username)] \(.position.new_path // .position.old_path // $disc.notes[0].position.new_path // $disc.notes[0].position.old_path // "?"):\(.position.new_line // .position.old_line // $disc.notes[0].position.new_line // $disc.notes[0].position.old_line // "?")\n\(.body[0:500])\n"
    ' 2>/dev/null
}

# Get MR source branch name (for --since).
# Usage: gp_review_head_branch SLUG MR_NUM
gp_review_head_branch() {
    local slug="$1" mr_num="$2"
    local encoded; encoded=$(_gl_encode "$slug")
    glab api "projects/$encoded/merge_requests/$mr_num" 2>/dev/null | jq -r '.source_branch' 2>/dev/null
}

# Get push event timestamp for a branch.
# GitLab events API differs — use MR updated_at as approximation.
# Usage: gp_review_push_timestamp SLUG BRANCH INDEX
gp_review_push_timestamp() {
    echo "" # Not directly supported — return empty to trigger fallback
}

# List unresolved discussion threads.
# Usage: gp_review_threads_list SLUG MR_NUM
gp_review_threads_list() {
    local slug="$1" mr_num="$2"
    local encoded; encoded=$(_gl_encode "$slug")

    local discussions
    discussions=$(glab api "projects/$encoded/merge_requests/$mr_num/discussions" 2>/dev/null) || return 1

    echo "$discussions" | jq -r '
        .[]
        | select(.notes | length > 0)
        | select(.notes[0].resolvable == true)
        | select(.notes[0].resolved == false)
        | "---\n[\(.notes[0].author.username)] \(.notes[0].position.new_path // .notes[0].position.old_path // "(general)"):\(.notes[0].position.new_line // .notes[0].position.old_line // "?") (\(.id))\n\(.notes[0].body)\n"
    '
}

# Print thread status counts.
# Usage: gp_review_threads_status SLUG MR_NUM
gp_review_threads_status() {
    local slug="$1" mr_num="$2"
    local encoded; encoded=$(_gl_encode "$slug")

    local discussions
    discussions=$(glab api "projects/$encoded/merge_requests/$mr_num/discussions" 2>/dev/null) || return 1

    echo "$discussions" | jq -r --arg mr "$mr_num" --arg slug "$slug" '
        [.[] | select(.notes[0].resolvable == true)]
        | {
            resolved: [.[] | select(.notes[0].resolved == true)] | length,
            unresolved: [.[] | select(.notes[0].resolved == false)] | length,
            total: length
          }
        | "MR #\($mr) (\($slug)): \(.unresolved) unresolved, \(.resolved) resolved (\(.total) total)"
    '
}

# Resolve a single discussion thread.
# Usage: gp_review_thread_resolve SLUG MR_NUM DISCUSSION_ID
gp_review_thread_resolve() {
    local slug="$1" mr_num="$2" discussion_id="$3"
    local encoded; encoded=$(_gl_encode "$slug")
    glab api --method PUT "projects/$encoded/merge_requests/$mr_num/discussions/$discussion_id" \
        -f resolved=true >/dev/null 2>&1
}

# Resolve all unresolved threads. Prints progress.
# Usage: gp_review_threads_resolve_all SLUG MR_NUM
gp_review_threads_resolve_all() {
    local slug="$1" mr_num="$2"
    local encoded; encoded=$(_gl_encode "$slug")

    local discussions
    discussions=$(glab api "projects/$encoded/merge_requests/$mr_num/discussions" 2>/dev/null) || return 1

    local ids
    ids=$(echo "$discussions" | jq -r '
        .[]
        | select(.notes[0].resolvable == true)
        | select(.notes[0].resolved == false)
        | .id
    ')

    if [[ -z "$ids" ]]; then
        echo "No unresolved threads on MR #$mr_num ($slug)."
        return 0
    fi

    local total=0 resolved=0 failed=0
    while IFS= read -r disc_id; do
        total=$((total + 1))
        if gp_review_thread_resolve "$slug" "$mr_num" "$disc_id"; then
            resolved=$((resolved + 1))
        else
            failed=$((failed + 1))
            echo "WARNING: Failed to resolve discussion $disc_id" >&2
        fi
    done <<< "$ids"

    if [[ "$failed" -eq 0 ]]; then
        echo "Resolved $resolved threads on MR #$mr_num ($slug)."
    else
        echo "Resolved $resolved of $total threads on MR #$mr_num ($slug). $failed failed." >&2
        return 1
    fi
}
