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

# Extract org/repo slug from a GitHub remote URL.
# Handles both HTTPS and SSH formats.
# Usage: gp_extract_slug URL
gp_extract_slug() {
    local url="$1"
    echo "$url" | sed 's|.*github.com[:/]||; s|\.git$||'
}

# Query the default branch of a GitHub repo.
# Usage: gp_default_branch SLUG
gp_default_branch() {
    local slug="$1"
    gh api "repos/$slug" --jq '.default_branch' 2>/dev/null || echo "main"
}

# Create a pull request.
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

    # GitHub cross-fork PRs use "Org:branch" as head ref
    local head_ref="$head"
    if [[ -n "$fork_org" ]]; then
        head_ref="${fork_org}:${head}"
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
