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

# Extract group/repo slug from a GitLab remote URL.
# Handles both HTTPS and SSH formats, including subgroups.
# Usage: gp_extract_slug URL
gp_extract_slug() {
    local url="$1"
    # Remove protocol + domain prefix and trailing .git
    echo "$url" | sed 's|.*gitlab\.com[:/]||; s|.*://[^/]*/||; s|\.git$||'
}

# Query the default branch of a GitLab repo.
# Usage: gp_default_branch SLUG
gp_default_branch() {
    local slug="$1"
    glab api "projects/$(echo "$slug" | sed 's|/|%2F|g')" 2>/dev/null | jq -r '.default_branch' 2>/dev/null || echo "main"
}

# Create a merge request.
# Usage: gp_create_pr --repo SLUG --base BRANCH --head REF --title TEXT --body-file PATH [--fork-org ORG]
gp_create_pr() {
    local repo="" base="" head="" title="" body_file="" fork_org=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      repo="$2"; shift 2 ;;
            --base)      base="$2"; shift 2 ;;
            --head)      head="$2"; shift 2 ;;
            --title)     title="$2"; shift 2 ;;
            --body-file) body_file="$2"; shift 2 ;;
            --fork-org)  fork_org="$2"; shift 2 ;;
            *) echo "ERROR: gp_create_pr: unknown arg '$1'" >&2; return 1 ;;
        esac
    done

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

    if [[ -n "$fork_org" ]]; then
        cmd+=(--source-project "${fork_org}/${repo##*/}")
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
