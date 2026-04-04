# Git Provider Abstraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Abstract GitHub-specific CLI calls behind a provider layer so the workspace scripts work with both GitHub and GitLab.

**Architecture:** A thin dispatcher (`scripts/git-provider.sh`) detects the git provider from remote URLs or ecosystem config, then lazy-loads provider-specific implementations from `scripts/providers/<name>.sh`. Each provider exports a fixed contract of functions (`gp_check_cli`, `gp_extract_slug`, `gp_create_pr`, `gp_create_issue`, `gp_default_branch`). Existing scripts source the dispatcher and call these functions instead of `gh` directly.

**Tech Stack:** Bash, `gh` CLI (GitHub), `glab` CLI (GitLab), `yq` for config parsing.

**Spec:** `docs/plans/2026-04-02-git-provider-abstraction-design.md`

---

## Task 1: Create the provider dispatcher (`git-provider.sh`)

**Files:**
- Create: `scripts/git-provider.sh`

This is the core library. All other scripts source it. It handles provider detection
and delegates calls to the loaded provider file.

- [ ] **Step 1: Create `scripts/git-provider.sh`**

```bash
#!/usr/bin/env bash
# git-provider.sh — Git provider detection and dispatch
#
# Source this file from scripts that need provider-specific operations.
# Provides:
#   gp_detect URL           — detect provider from a remote URL (prints: github, gitlab, ...)
#   gp_load PROVIDER        — load a provider implementation
#   gp_check_cli            — verify CLI tool is installed (delegates to loaded provider)
#   gp_extract_slug URL     — extract org/repo slug from URL (delegates to loaded provider)
#   gp_create_pr ARGS       — create PR/MR (delegates to loaded provider)
#   gp_create_issue ARGS    — file an issue (delegates to loaded provider)
#   gp_default_branch SLUG  — query default branch (delegates to loaded provider)
#
# Provider detection order:
#   1. Per-component gitProvider in ecosystem config (caller passes it)
#   2. defaults.gitProviders.<domain> mapping in ecosystem config
#   3. Auto-detect from remote URL domain (github.com, gitlab.com)
#   4. defaults.gitProvider workspace-wide default in ecosystem config
#   5. Fail with error

_GP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GP_LOADED_PROVIDER=""

# Detect provider from a remote URL.
# Usage: gp_detect URL [ECOSYSTEM_FILE]
#   URL             — git remote URL (https or ssh)
#   ECOSYSTEM_FILE  — optional path to merged ecosystem config (for config-based detection)
# Prints the provider name to stdout (e.g., "github", "gitlab").
gp_detect() {
    local url="$1"
    local eco="${2:-}"

    # Extract domain from URL
    local domain=""
    if [[ "$url" =~ ^https?://([^/]+)/ ]]; then
        domain="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^git@([^:]+): ]]; then
        domain="${BASH_REMATCH[1]}"
    fi

    # Step 2: Check defaults.gitProviders.<domain> mapping
    if [[ -n "$eco" && -n "$domain" ]]; then
        local mapped
        mapped=$(DOMAIN="$domain" yq '.defaults.gitProviders[strenv(DOMAIN)] // ""' "$eco" 2>/dev/null)
        if [[ -n "$mapped" && "$mapped" != "null" ]]; then
            echo "$mapped"
            return
        fi
    fi

    # Step 3: Auto-detect from well-known domains
    case "$domain" in
        github.com)  echo "github"; return ;;
        gitlab.com)  echo "gitlab"; return ;;
    esac

    # Step 4: Workspace-wide default
    if [[ -n "$eco" ]]; then
        local default_provider
        default_provider=$(yq '.defaults.gitProvider // ""' "$eco" 2>/dev/null)
        if [[ -n "$default_provider" && "$default_provider" != "null" ]]; then
            echo "$default_provider"
            return
        fi
    fi

    # Step 5: Fail
    echo "ERROR: Cannot detect git provider for URL: $url" >&2
    echo "  Domain: ${domain:-(unknown)}" >&2
    echo "  Set defaults.gitProvider or defaults.gitProviders.$domain in ecosystem config." >&2
    return 1
}

# Load a provider implementation by name.
# Usage: gp_load PROVIDER
gp_load() {
    local provider="$1"
    if [[ "$_GP_LOADED_PROVIDER" == "$provider" ]]; then
        return 0
    fi

    local provider_file="$_GP_SCRIPT_DIR/providers/${provider}.sh"
    if [[ ! -f "$provider_file" ]]; then
        echo "ERROR: No provider implementation for '$provider'." >&2
        echo "  Expected: $provider_file" >&2
        echo "  Available providers: $(ls "$_GP_SCRIPT_DIR/providers/"*.sh 2>/dev/null | xargs -I{} basename {} .sh | tr '\n' ' ')" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$provider_file"
    _GP_LOADED_PROVIDER="$provider"
}

# Convenience: detect + load in one call.
# Usage: gp_detect_and_load URL [ECOSYSTEM_FILE]
gp_detect_and_load() {
    local provider
    provider=$(gp_detect "$@") || return 1
    gp_load "$provider"
}
```

- [ ] **Step 2: Verify the file is syntactically valid**

Run: `bash -n scripts/git-provider.sh`
Expected: no output (clean parse)

- [ ] **Step 3: Commit**

Create `.commits/git-provider-dispatcher.md`:
```markdown
---
add:
  - scripts/git-provider.sh
---

feat: add git provider dispatcher for multi-forge support

Introduces git-provider.sh, the core dispatch library for abstracting
GitHub vs GitLab CLI operations. Detects provider from remote URLs
and ecosystem config, lazy-loads provider implementations.
```

Run: `bash scripts/ws commit yggdrasil .commits/git-provider-dispatcher.md`

---

## Task 2: Create the GitHub provider (`providers/github.sh`)

**Files:**
- Create: `scripts/providers/github.sh`

Implements the provider contract using the `gh` CLI. This extracts the
existing `gh` calls from `git-pr.sh` and `gh-issue.sh` into the contract functions.

- [ ] **Step 1: Create `scripts/providers/github.sh`**

```bash
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
# Handles SSH (ssh://), HTTPS, and git@ formats for any domain.
# Usage: gp_extract_slug URL
gp_extract_slug() {
    local url="$1"
    echo "$url" | sed 's|^ssh://[^/]*/||; s|^https\?://[^/]*/||; s|^git@[^:]*:||; s|\.git$||'
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
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/providers/github.sh`
Expected: no output (clean parse)

- [ ] **Step 3: Commit**

Create `.commits/github-provider.md`:
```markdown
---
add:
  - scripts/providers/github.sh
---

feat: add GitHub provider implementation

Implements the git-provider contract using the gh CLI.
Extracts PR creation, issue filing, slug parsing, and
default branch detection from the existing scripts.
```

Run: `bash scripts/ws commit yggdrasil .commits/github-provider.md`

---

## Task 3: Create the GitLab provider (`providers/gitlab.sh`)

**Files:**
- Create: `scripts/providers/gitlab.sh`

Implements the same contract using the `glab` CLI. Key differences:
PRs are "merge requests", cross-fork uses source project, slug may include subgroups.

- [ ] **Step 1: Create `scripts/providers/gitlab.sh`**

```bash
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
# Handles SSH (ssh://), HTTPS, and git@ formats for any domain, including subgroups.
# Usage: gp_extract_slug URL
gp_extract_slug() {
    local url="$1"
    echo "$url" | sed 's|^ssh://[^/]*/||; s|^https\?://[^/]*/||; s|^git@[^:]*:||; s|\.git$||'
}

# Query the default branch of a GitLab repo.
# Usage: gp_default_branch SLUG
gp_default_branch() {
    local slug="$1"
    glab api "projects/$(echo "$slug" | sed 's|/|%2F|g')" --jq '.default_branch' 2>/dev/null || echo "main"
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
```

Note: `glab issue create` uses `--description` (not `--body-file`), and
`glab mr create` uses `--description` + `--source-branch`/`--target-branch`
instead of `--head`/`--base`. These differences are absorbed here.

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/providers/gitlab.sh`
Expected: no output (clean parse)

- [ ] **Step 3: Commit**

Create `.commits/gitlab-provider.md`:
```markdown
---
add:
  - scripts/providers/gitlab.sh
---

feat: add GitLab provider implementation

Implements the git-provider contract using the glab CLI.
Handles GitLab-specific differences: merge requests instead
of pull requests, subgroup slug encoding, --description flag.
```

Run: `bash scripts/ws commit yggdrasil .commits/gitlab-provider.md`

---

## Task 4: Simplify `git-push.sh`

**Files:**
- Modify: `scripts/git-push.sh`

Remove the `GH_TOKEN` sourcing, `.env` loading, and GitHub-specific token URL
construction. Push becomes plain `git push`.

- [ ] **Step 1: Rewrite `git-push.sh`**

Replace the full file with:

```bash
#!/usr/bin/env bash
# git-push.sh — push a branch to a named remote
#
# Usage: git-push.sh [--force] [branch]
#   --force — force push (for rebased branches). Refuses to force-push main/master.
#   branch  — branch to push (default: current branch)
#
# Auth is handled by the system credential helper (credential.helper=manager
# on Windows, osxkeychain on macOS, or gh/glab auth). No token needed here.
#
# The target remote is detected by finding a non-origin remote whose name
# matches the org (case-insensitive). Override by setting GIT_PUSH_REMOTE.

set -euo pipefail

# Parse --force flag
FORCE=""
if [[ "${1:-}" == "--force" ]]; then
  FORCE="--force"
  shift
fi

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

# Find the push remote.
# If GIT_PUSH_REMOTE is set, use that. Otherwise, pick the first remote
# that isn't literally "origin" (our convention: remotes are named after orgs).
if [[ -n "${GIT_PUSH_REMOTE:-}" ]]; then
  REMOTE_NAME="$GIT_PUSH_REMOTE"
else
  REMOTE_NAME=""
  for r in $(git remote); do
    if [[ "$(echo "$r" | tr '[:upper:]' '[:lower:]')" != "origin" ]]; then
      REMOTE_NAME="$r"
      break
    fi
  done
fi

if [[ -z "$REMOTE_NAME" ]]; then
  echo "ERROR: No named remote found (only 'origin' exists)." >&2
  echo "  Name your remote after the org: git remote rename origin <orgname>" >&2
  echo "  Or set GIT_PUSH_REMOTE=<remote-name>." >&2
  echo "  Available remotes: $(git remote | tr '\n' ' ')" >&2
  exit 1
fi

REMOTE_URL=$(git remote get-url "$REMOTE_NAME" 2>/dev/null || echo "")
ORG_REPO=$(echo "$REMOTE_URL" | sed 's|.*[:/]\([^/]*/[^/]*\)$|\1|; s|\.git$||')

# Safety: refuse to force-push main or master
if [[ -n "$FORCE" ]] && [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Refusing to force-push to $BRANCH. This is almost certainly a mistake." >&2
  exit 1
fi

if [[ -n "$FORCE" ]]; then
  echo "Force pushing $BRANCH → $REMOTE_NAME ($ORG_REPO)"
  git push --force "$REMOTE_NAME" "$BRANCH"
else
  echo "Pushing $BRANCH → $REMOTE_NAME ($ORG_REPO)"
  git push "$REMOTE_NAME" "$BRANCH"
fi
```

Key changes:
- No `.env` sourcing or `GH_TOKEN` dependency
- No `github.com`-specific token URL construction
- Remote detection generalized: picks first non-`origin` remote (not hardcoded `siliconsaga`)
- `GIT_PUSH_REMOTE` env var for explicit override
- Pushes via remote name, not constructed URL — credential helper handles auth

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/git-push.sh`
Expected: no output

- [ ] **Step 3: Test dry-run push**

Run: `git push --dry-run siliconsaga main` (from yggdrasil root)
Expected: `Everything up-to-date` (confirms credential helper works without token URL)

- [ ] **Step 4: Commit**

Create `.commits/simplify-push.md`:
```markdown
---
add:
  - scripts/git-push.sh
---

refactor: simplify git-push to use plain git push

Remove GitHub-specific token URL construction and .env dependency.
Auth is now handled by the system credential helper. Remote detection
is generalized to pick the first non-origin remote instead of
hardcoding siliconsaga.
```

Run: `bash scripts/ws commit yggdrasil .commits/simplify-push.md`

---

## Task 5: Refactor `git-pr.sh` to use provider

**Files:**
- Modify: `scripts/git-pr.sh`

Replace direct `gh` calls with the provider contract functions.

- [ ] **Step 1: Rewrite `git-pr.sh`**

Replace the full file with:

```bash
#!/usr/bin/env bash
# git-pr.sh — open a pull/merge request from the current branch
#
# Usage: git-pr.sh [--upstream] TITLE BODYFILE
#   --upstream — target the upstream (non-fork) remote instead of the fork.
#                Creates a cross-fork PR/MR: fork:branch → upstream:base.
#   TITLE     — PR/MR title
#   BODYFILE  — path to markdown file containing the body
#
# Without --upstream, targets the fork remote with --base main.
# With --upstream, auto-detects the upstream remote and targets its default branch.
#
# Draft files live in .prs/ (gitignored, auto-created).
# Copy .agent/pr-template.md to .prs/<descriptive-name>.md to start a draft.
#
# Uses git-provider.sh for provider-agnostic PR/MR creation.
# Run from the repo the branch belongs to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source provider dispatcher
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Try to load ecosystem config for provider detection (optional — may not exist)
_ECO=""
if [[ -f "$SCRIPT_DIR/ws-overlay.sh" ]]; then
  source "$SCRIPT_DIR/ws-overlay.sh"
  _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
fi

# Parse --upstream flag
UPSTREAM=""
if [[ "${1:-}" == "--upstream" ]]; then
  UPSTREAM="1"
  shift
fi

TITLE="${1:-}"
BODYFILE="${2:-}"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Ensure .prs/ clearinghouse exists
mkdir -p "$REPO_ROOT/.prs"

if [[ -z "$TITLE" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 [--upstream] TITLE BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || "$BRANCH" == "develop" ]]; then
  echo "ERROR: current branch is '$BRANCH' — check out a topic branch first" >&2
  exit 1
fi

# Find the fork remote (first non-origin remote)
FORK_REMOTE=""
for r in $(git remote); do
  if [[ "$(echo "$r" | tr '[:upper:]' '[:lower:]')" != "origin" ]]; then
    FORK_REMOTE="$r"
    break
  fi
done
if [[ -z "$FORK_REMOTE" ]]; then
  echo "ERROR: No named remote found (only 'origin' exists)." >&2
  echo "  Name your remote after the org: git remote rename origin <orgname>" >&2
  exit 1
fi
FORK_URL=$(git remote get-url "$FORK_REMOTE" 2>/dev/null)

# Detect provider and load implementation
gp_detect_and_load "$FORK_URL" "$_ECO"
gp_check_cli

FORK_SLUG=$(gp_extract_slug "$FORK_URL")
FORK_ORG="${FORK_SLUG%%/*}"

if [[ -n "$UPSTREAM" ]]; then
  # Cross-fork PR: find the upstream (non-fork) remote
  UPSTREAM_REMOTE=""
  for remote in $(git remote); do
    if [[ "$remote" != "$FORK_REMOTE" ]]; then
      UPSTREAM_REMOTE="$remote"
      break
    fi
  done
  if [[ -z "$UPSTREAM_REMOTE" ]]; then
    echo "ERROR: No upstream remote found (only '$FORK_REMOTE' exists)." >&2
    exit 1
  fi
  UPSTREAM_URL=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null)
  UPSTREAM_SLUG=$(gp_extract_slug "$UPSTREAM_URL")

  UPSTREAM_DEFAULT=$(gp_default_branch "$UPSTREAM_SLUG")

  echo "Opening cross-fork PR/MR: $FORK_SLUG:$BRANCH → $UPSTREAM_SLUG:$UPSTREAM_DEFAULT"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gp_create_pr \
    --repo "$UPSTREAM_SLUG" \
    --base "$UPSTREAM_DEFAULT" \
    --head "$BRANCH" \
    --fork-org "$FORK_ORG" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
else
  echo "Opening PR/MR for $FORK_SLUG/$BRANCH → main"
  echo "  Title: $TITLE"
  echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
  echo ""

  gp_create_pr \
    --repo "$FORK_SLUG" \
    --base main \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body-file "$BODYFILE"
fi
```

Key changes:
- Sources `git-provider.sh` instead of loading `.env` / `GH_TOKEN`
- Uses `gp_detect_and_load`, `gp_check_cli`, `gp_extract_slug`, `gp_default_branch`, `gp_create_pr`
- Remote detection generalized: first non-origin remote (not hardcoded `siliconsaga`)
- No hardcoded `SiliconSaga:$BRANCH` — `--fork-org` passed to provider

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/git-pr.sh`
Expected: no output

- [ ] **Step 3: Commit**

Create `.commits/refactor-pr.md`:
```markdown
---
add:
  - scripts/git-pr.sh
---

refactor: make git-pr.sh provider-agnostic

Replace direct gh CLI calls with git-provider contract functions.
Remove hardcoded SiliconSaga references and GH_TOKEN dependency.
PR creation now works with any supported git provider.
```

Run: `bash scripts/ws commit yggdrasil .commits/refactor-pr.md`

---

## Task 6: Rename and refactor `gh-issue.sh` → `git-issue.sh`

**Files:**
- Delete: `scripts/gh-issue.sh` (via git mv)
- Create: `scripts/git-issue.sh`
- Modify: `scripts/ws:568`

- [ ] **Step 1: Rename the file**

Run: `git mv scripts/gh-issue.sh scripts/git-issue.sh`

- [ ] **Step 2: Rewrite `scripts/git-issue.sh`**

Replace the full file with:

```bash
#!/usr/bin/env bash
# git-issue.sh — file an issue from a draft file
#
# Usage: ./scripts/git-issue.sh COMPONENT_DIR REMOTE TITLE LABEL BODYFILE
#   COMPONENT_DIR — path to the component git repo
#   REMOTE        — git remote name (e.g. 'SiliconSaga', 'MyGitLabGroup')
#                   The org/repo slug is resolved from the remote URL.
#   TITLE         — issue title
#   LABEL         — single label: bug | enhancement | documentation
#   BODYFILE      — path to the issue body markdown file
#
# The first line of the body file must contain an AI attribution line.
# The script reads identity.human_account from the merged ecosystem config
# and validates that the attribution references it.
#
# Draft files live in .issues/ (gitignored, created on first use).
# Copy .agent/issue-template.md to .issues/<descriptive-name>.md to start a draft.
#
# Uses git-provider.sh for provider-agnostic issue creation.

set -euo pipefail

COMPONENT_DIR="${1:-}"
REMOTE="${2:-}"
TITLE="${3:-}"
LABEL="${4:-}"
BODYFILE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# Ensure clearinghouse directory exists
mkdir -p "$REPO_ROOT/.issues"

# Source provider dispatcher
# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"

# Source shared overlay/merge functions for ecosystem config
source "$SCRIPT_DIR/ws-overlay.sh"

# Validate arguments
if [[ -z "$COMPONENT_DIR" || -z "$REMOTE" || -z "$TITLE" || -z "$LABEL" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 COMPONENT_DIR REMOTE TITLE LABEL BODYFILE" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

# Resolve identity from merged ecosystem config
ECO=$(ws_resolve_ecosystem)
HUMAN_ACCOUNT=$(yq '.identity.human_account // ""' "$ECO" 2>/dev/null)

if [[ -z "$HUMAN_ACCOUNT" ]]; then
  echo "ERROR: identity.human_account not set in ecosystem config." >&2
  echo "  Set it in ecosystem.local.yaml (see ecosystem.local.yaml.example)." >&2
  exit 1
fi

# Enforce AI attribution line referencing the driving human
if ! grep -q 'AI-assisted issue' "$BODYFILE"; then
  echo "ERROR: body file is missing the AI attribution line." >&2
  echo "  First line must contain: > **AI-assisted issue.**" >&2
  exit 1
fi

# Substitute @HUMAN_ACCOUNT placeholder in a temp copy of the body file
RESOLVED_BODY=$(mktemp)
trap 'rm -f "$RESOLVED_BODY" "$_RESOLVED_ECOSYSTEM" 2>/dev/null' EXIT
sed "s/@HUMAN_ACCOUNT/@${HUMAN_ACCOUNT}/g" "$BODYFILE" > "$RESOLVED_BODY"

# Resolve remote URL and detect provider
REMOTE_NAME=$(cd "$COMPONENT_DIR" && git remote | grep -i "^${REMOTE}$" | head -1)
if [[ -z "$REMOTE_NAME" ]]; then
  echo "ERROR: No remote matching '$REMOTE' found in $COMPONENT_DIR." >&2
  echo "  Available remotes: $(cd "$COMPONENT_DIR" && git remote | tr '\n' ' ')" >&2
  exit 1
fi
REMOTE_URL=$(cd "$COMPONENT_DIR" && git remote get-url "$REMOTE_NAME")

# Detect and load provider
gp_detect_and_load "$REMOTE_URL" "$ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$REMOTE_URL")

if [[ -z "$TARGET_SLUG" || "$TARGET_SLUG" != */* ]]; then
  echo "ERROR: Could not resolve org/repo from remote URL: $REMOTE_URL" >&2
  exit 1
fi

# Show a summary before filing
echo "Filing issue to $TARGET_SLUG (via remote '$REMOTE_NAME'):"
echo "  Title : $TITLE"
echo "  Label : $LABEL"
echo "  Author: @$HUMAN_ACCOUNT (via agent)"
echo "  Body  : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

gp_create_issue \
  --repo "$TARGET_SLUG" \
  --title "$TITLE" \
  --label "$LABEL" \
  --body-file "$RESOLVED_BODY"
```

Key changes:
- Sources `git-provider.sh` instead of loading `.env` / `GH_TOKEN`
- Uses `gp_detect_and_load`, `gp_check_cli`, `gp_extract_slug`, `gp_create_issue`
- Removes hardcoded `github.com` URL parsing
- Keeps: AI attribution validation, identity resolution, body file handling

- [ ] **Step 3: Update `ws` to reference `git-issue.sh`**

In `scripts/ws:568`, change:
```bash
    bash "$SCRIPT_DIR/gh-issue.sh" "$COMPONENT_DIR" "$remote" "$@"
```
to:
```bash
    bash "$SCRIPT_DIR/git-issue.sh" "$COMPONENT_DIR" "$remote" "$@"
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n scripts/git-issue.sh && bash -n scripts/ws`
Expected: no output

- [ ] **Step 5: Commit**

Create `.commits/refactor-issue.md`:
```markdown
---
add:
  - scripts/git-issue.sh
  - scripts/ws
---

refactor: rename gh-issue.sh to git-issue.sh, use provider layer

Rename to reflect provider-agnostic behavior. Replace direct gh CLI
calls with git-provider contract functions. Update ws dispatcher to
reference the new filename.
```

Run: `bash scripts/ws commit yggdrasil .commits/refactor-issue.md`

---

## Task 7: Update `.env.example`

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Replace `.env.example` contents**

```bash
# Copy to .env (gitignored) and fill in real values.
# Load with: source .env  (or add to shell profile)
# Only uncomment the sections for providers you use.

# ── GitHub ───────────────────────────────────────────────────
# Create a classic personal access token at:
#   https://github.com/settings/tokens/new
#
# Required scopes:
#   repo           (full repo access — PRs, issues, code, cross-org forks)
#   workflow        (if you need to touch .github/workflows files)
#
# Note: Fine-grained PATs exist but have known limitations with cross-org
# PRs and workflow files. Classic PATs are recommended for GDD workspaces.
#
# The gh CLI reads GH_TOKEN automatically — no 'gh auth login' needed.
export GH_TOKEN=ghp_xxxxxxxxxxxx
export GH_USER=your-github-username

# ── GitLab ───────────────────────────────────────────────────
# Create a personal access token at:
#   https://gitlab.com/-/user_settings/personal_access_tokens
#   (self-hosted: https://<your-host>/-/user_settings/personal_access_tokens)
#
# Required scopes:
#   api            (full API access — MRs, issues, repo reads)
#
# The glab CLI reads GITLAB_TOKEN automatically — no 'glab auth login' needed.
# export GITLAB_TOKEN=glpat-xxxxxxxxxxxx
# export GITLAB_USER=your-gitlab-username
```

- [ ] **Step 2: Commit**

Create `.commits/env-example-gitlab.md`:
```markdown
---
add:
  - .env.example
---

docs: expand .env.example with GitLab token setup

Add commented GitLab section alongside existing GitHub config.
Switch GitHub guidance from fine-grained to classic PATs due to
cross-org limitations.
```

Run: `bash scripts/ws commit yggdrasil .commits/env-example-gitlab.md`

---

## Task 8: Update `ecosystem.local.yaml.example`

**Files:**
- Modify: `ecosystem.local.yaml.example`

- [ ] **Step 1: Add gitProvider examples**

After the existing `identity:` section (line 20), add:

```yaml

# Git provider detection — usually auto-detected from remote URLs.
# Override here for self-hosted instances or mixed-provider workspaces.
# defaults:
#   gitProvider: github            # workspace-wide default
#   gitProviders:                  # domain → provider mapping
#     git.mycompany.com: gitlab
#     gitea.local: gitea

# Per-component provider override:
# components:
#   some-corp-thing:
#     gitProvider: gitlab
```

- [ ] **Step 2: Commit**

Create `.commits/eco-example-provider.md`:
```markdown
---
add:
  - ecosystem.local.yaml.example
---

docs: add gitProvider config examples to ecosystem.local.yaml.example

Show how to set workspace-wide provider defaults, domain mappings
for self-hosted instances, and per-component overrides.
```

Run: `bash scripts/ws commit yggdrasil .commits/eco-example-provider.md`

---

## Task 9: Replace `docs/github-cli-setup.md` with `docs/git-provider-setup.md`

**Files:**
- Delete: `docs/github-cli-setup.md` (via git mv)
- Create: `docs/git-provider-setup.md`

- [ ] **Step 1: Rename the file**

Run: `git mv docs/github-cli-setup.md docs/git-provider-setup.md`

- [ ] **Step 2: Rewrite `docs/git-provider-setup.md`**

```markdown
# Git Provider Setup

One-time setup for using the workspace CLI (`ws`) with GitHub and/or GitLab.
The workspace auto-detects your provider from remote URLs — no config needed
for `github.com` or `gitlab.com`. Self-hosted instances need a config entry
(see Provider Detection below).

## GitHub

### Install the GitHub CLI

**macOS:**
```bash
brew install gh
```

**Windows (Git Bash):**
```bash
winget install GitHub.cli
```
After install, open a fresh Git Bash session so the updated `PATH` is picked up.

**Linux:** See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

### Create a classic Personal Access Token

Go to **GitHub → Settings → Developer settings → Personal access tokens →
Tokens (classic) → Generate new token (classic)**.

Settings:
- **Note**: descriptive name, e.g. `yggdrasil-workspace`
- **Expiration**: set a reasonable expiry (90 days, 1 year)
- **Scopes**:

| Scope | Why |
|-------|-----|
| `repo` | Full repo access — PRs, issues, code, cross-org forks |
| `workflow` | Only if you modify `.github/workflows` files |

> **Why classic and not fine-grained?** Fine-grained PATs have known
> limitations with cross-org pull requests and workflow file access.
> Classic PATs are simpler and more reliable for GDD workspaces that span
> multiple orgs or forks.

### Store the token

Create `.env` in the yggdrasil root (gitignored):

```bash
export GH_TOKEN=ghp_xxxxxxxxxxxx
export GH_USER=your-github-username
```

### Verify

```bash
source .env
gh auth status
gh issue list --repo <your-org>/<your-repo> --limit 5
```

---

## GitLab

### Install the GitLab CLI

**macOS:**
```bash
brew install glab
```

**Windows (Git Bash):**
```bash
winget install GLab.GLab
```
After install, open a fresh Git Bash session.

**Linux:** See https://gitlab.com/gitlab-org/cli#installation

### Create a Personal Access Token

Go to **GitLab → User Settings → Access Tokens** (or for self-hosted:
`https://<your-host>/-/user_settings/personal_access_tokens`).

Settings:
- **Token name**: descriptive, e.g. `yggdrasil-workspace`
- **Expiration**: set a reasonable expiry
- **Scopes**:

| Scope | Why |
|-------|-----|
| `api` | Full API access — MRs, issues, repo reads |

### Store the token

Add to `.env` in the yggdrasil root:

```bash
export GITLAB_TOKEN=glpat-xxxxxxxxxxxx
export GITLAB_USER=your-gitlab-username
```

For self-hosted instances, also set the host:
```bash
export GITLAB_HOST=git.mycompany.com
```

### Verify

```bash
source .env
glab auth status
glab issue list --repo <your-group>/<your-repo>
```

---

## Provider Detection

The workspace auto-detects which provider to use from the remote URL:
- `github.com` → GitHub (`gh` CLI)
- `gitlab.com` → GitLab (`glab` CLI)

For self-hosted instances, add a mapping in `ecosystem.local.yaml`:

```yaml
defaults:
  gitProviders:
    git.mycompany.com: gitlab
```

See `ecosystem.local.yaml.example` for more options.

---

## Shared Prerequisites

### yq (YAML processor)

The workspace scripts require [yq](https://github.com/mikefarah/yq) v4+.

**macOS:**
```bash
brew install yq
```

**Windows:**
```bash
# Option 1: winget
winget install MikeFarah.yq

# Option 2: manual download (no admin needed)
mkdir -p "$HOME/bin"
curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_windows_amd64.exe \
  -o "$HOME/bin/yq.exe"
```

If you use the manual download, add `~/bin` to your PATH in `~/.bashrc`:
```bash
export PATH="$HOME/bin:$PATH"
```

Verify: `yq --version` should report v4.x.

### Running Shell Scripts on Windows

All workspace scripts are Bash scripts. Windows needs Git Bash (installed
with Git for Windows).

| From | How to run |
|------|------------|
| Git Bash | `bash scripts/ws help` |
| cmd / PowerShell | `bash scripts/ws help` (Git Bash must be on PATH) |
| VS Code terminal | Set default shell to Git Bash, or prefix with `bash` |

A `.gitattributes` in the repo root forces LF line endings on `.sh` files,
preventing `\r: command not found` errors.

### Git Remote Naming Convention

Name remotes after the org or service — never use the generic `origin`.

| Remote name | Points to |
|-------------|-----------|
| `siliconsaga` | `github.com/SiliconSaga/*` |
| `mygroup` | `gitlab.com/mygroup/*` |
| `local-gitea` | Homelab Gitea instance |

The rule: the remote name should answer "where does this push go?" without
running `git remote -v`.

---

## Troubleshooting

**`gh`/`glab` not found after install**
Open a fresh terminal session. The installer updates PATH, but existing
sessions don't pick it up.

**"Bad credentials" or 401 errors (GitHub)**
- Token may be expired — check the expiration date at GitHub → Settings →
  Developer settings → Personal access tokens.
- Classic PAT: ensure the `repo` scope is selected.
- Org-scoped fine-grained PAT: the org owner may need to approve it.

**"401 Unauthorized" (GitLab)**
- Token may be expired or revoked.
- Ensure the `api` scope is selected.
- For self-hosted: set `GITLAB_HOST` in `.env`.

**Push fails with "remote: Permission denied"**
- Credential helper may not have your token stored. Run
  `gh auth status` (GitHub) or `glab auth status` (GitLab).
- On Windows, check Windows Credential Manager for stale entries.
- GitKraken users: check `~/.gitconfig` for `url.insteadOf` entries that
  redirect HTTPS to SSH. Remove or scope them if they interfere with CLI auth.

**"Cannot detect git provider for URL"**
- Self-hosted domain not recognized. Add it to `defaults.gitProviders` in
  `ecosystem.local.yaml` (see Provider Detection above).
```

- [ ] **Step 3: Update any references to the old filename**

Search for `github-cli-setup` in the codebase and update. Known reference:

In `docs/github-cli-setup.md` itself (now renamed). Check AGENTS.md and
skills for references.

Run: `grep -r "github-cli-setup"  --include="*.md" --include="*.sh" -l`

Update any files found to reference `git-provider-setup.md` instead.

- [ ] **Step 4: Commit**

Create `.commits/provider-setup-docs.md`:
```markdown
---
add:
  - docs/git-provider-setup.md
---

docs: replace github-cli-setup.md with multi-provider setup guide

Covers GitHub (classic PAT) and GitLab (personal access token) setup,
provider detection, shared prerequisites, and troubleshooting for
common auth issues across providers.
```

Run: `bash scripts/ws commit yggdrasil .commits/provider-setup-docs.md`

---

## Task 10: Integration smoke test

**Files:** None (verification only)

- [ ] **Step 1: Verify all scripts parse cleanly**

Run:
```bash
bash -n scripts/git-provider.sh && \
bash -n scripts/providers/github.sh && \
bash -n scripts/providers/gitlab.sh && \
bash -n scripts/git-push.sh && \
bash -n scripts/git-pr.sh && \
bash -n scripts/git-issue.sh && \
bash -n scripts/ws && \
echo "All scripts parse OK"
```

Expected: `All scripts parse OK`

- [ ] **Step 2: Test provider detection**

Run from yggdrasil root:
```bash
source scripts/git-provider.sh
gp_detect "https://github.com/SiliconSaga/nordri.git"
gp_detect "https://gitlab.com/mygroup/myrepo.git"
gp_detect "git@github.com:SiliconSaga/nordri.git"
```

Expected output:
```
github
gitlab
github
```

- [ ] **Step 3: Test GitHub CLI check**

Run:
```bash
source scripts/git-provider.sh
gp_load github
gp_check_cli && echo "gh CLI OK"
```

Expected: `gh CLI OK` (assuming `gh` is installed and GH_TOKEN is set)

- [ ] **Step 4: Test push dry-run**

Run: `bash scripts/git-push.sh --dry-run main 2>&1 || true`

Note: `--dry-run` is not a flag the script handles — this tests that the
script finds the remote and attempts a push. Use `git push --dry-run siliconsaga main`
directly to verify the credential helper path works.

- [ ] **Step 5: Verify ws dispatch**

Run: `bash scripts/ws help`

Expected: Help text shows, no parse errors. The `issue` command line should
still appear in the help output.
