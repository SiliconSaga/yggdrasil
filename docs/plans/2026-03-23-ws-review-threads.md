# `ws review` Extraction & Threads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `ws review` into a standalone script and add a `threads` subcommand for listing and resolving PR review threads via GitHub GraphQL API.

**Architecture:** Move the inline `ws_review()` function from `scripts/ws` into `scripts/ws-review.sh`. Normalize the interface to component-first positional args. Add `threads` subcommand handling GraphQL queries for thread listing, status, and resolution. The `ws` dispatcher becomes a one-line delegate.

**Tech Stack:** Bash, GitHub GraphQL API via `gh api graphql`, jq for response parsing.

**Spec:** `docs/plans/2026-03-23-ws-review-threads-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/ws-review.sh` | Create | All review logic: comments + threads, shared setup, GraphQL queries |
| `scripts/ws` | Modify (lines 1-25, 196-367, 603-604) | Remove `ws_review()`, update help text, delegate to `ws-review.sh` |
| `.claude/settings.json` | Modify (lines 13-41) | Replace wildcard review patterns with explicit named patterns |
| `AGENTS.md` | Modify (line 105) | Update `ws review` command table row |
| `docs/dev-setup.md` | Modify (line 48) | Update review command in table |
| `docs/ws-cli-guide.md` | Modify (lines 77, 81) | Update tier table |

---

## Task 1: Create `ws-review.sh` scaffold with shared setup

**Files:**
- Create: `scripts/ws-review.sh`

- [ ] **Step 1: Create the script with shared setup and argument routing**

```bash
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
# Note: review_threads, review_comments, and review_help are defined above
# this routing block. In the actual file, all function definitions come first,
# then this routing block is the last executable code.

if [[ "${1:-}" == "threads" ]]; then
    shift
    review_threads "$@"
else
    review_comments "$@"
fi
```

Note: The routing block (from `# Handle --help` through the `if/else` at
the end) must be the **last executable code** in the file. All function
definitions (`review_help`, `review_comments`, `review_threads`, etc.)
go above it. Bash requires functions to be defined before they are called.

- [ ] **Step 2: Make the script executable**

Run: `chmod +x scripts/ws-review.sh`

- [ ] **Step 3: Commit scaffold**

```bash
git add scripts/ws-review.sh
git commit -m "$(cat <<'EOF'
feat(ws): scaffold ws-review.sh with shared setup and routing

Part of #11. Creates the standalone script that will hold all review
logic (comments + threads). Shared setup handles GH_TOKEN, component
validation, and repo slug resolution.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Move comment listing from `ws` to `ws-review.sh`

**Files:**
- Modify: `scripts/ws-review.sh` (add `review_help` and `review_comments` functions)
- Modify: `scripts/ws` (lines 1-25: update help text, lines 196-367: remove `ws_review()`, lines 603-604: change to delegate)

- [ ] **Step 1: Add `review_help` function to `ws-review.sh`**

Add before the routing block at the bottom of the file:

```bash
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
```

- [ ] **Step 2: Move `review_comments` function to `ws-review.sh`**

Copy the body of `ws_review()` from `scripts/ws` (lines 196-367) into a
`review_comments()` function in `ws-review.sh`. Adapt it:

- Remove the argument parsing for `--comp` (component is now `$COMP` from shared setup)
- Remove GH_TOKEN sourcing (handled in shared setup)
- Remove component name validation (handled in shared setup)
- The function receives: `<pr#> [--reviewer <name>] [--since <time>]`
- Use `$REPO_SLUG` (set in shared setup) instead of the local `repo_slug` variable
- Keep all `--reviewer`, `--since` logic (including `last-push`/`prev-push`) intact

- [ ] **Step 3: Update `scripts/ws` — replace inline function with delegate**

In `scripts/ws`:

a) Update the help text (line 19) from:
```
#   review <pr#> [options]  Fetch PR review comments (see ws review --help)
```
to:
```
#   review <comp> <pr#|threads> [options]  PR review comments and threads (see ws review --help)
```

b) Remove the entire `ws_review()` function (lines 196-367).

c) Change the case entry (line 603-604) from:
```bash
    review)
        ws_review "$@"
        ;;
```
to:
```bash
    review)
        bash "$SCRIPT_DIR/ws-review.sh" "$@"
        ;;
```

- [ ] **Step 4: Verify comment listing still works**

Run: `bash scripts/ws review --help`
Expected: Shows the new help text from `ws-review.sh`

Run: `bash scripts/ws review yggdrasil 15`
Expected: Shows PR #15 comments (same output format as before, with the new
component-first interface)

- [ ] **Step 5: Commit migration**

```bash
git add scripts/ws scripts/ws-review.sh
git commit -m "$(cat <<'EOF'
refactor(ws): extract review to ws-review.sh, normalize to component-first

Moves ws_review() from inline in ws dispatcher to standalone
scripts/ws-review.sh.

BREAKING: Interface changes from `ws review <pr#> [--comp X]`
to `ws review <comp> <pr#>`, consistent with all other ws commands.
The --comp flag is removed; component is now a required first positional arg.

Part of #11.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Implement thread listing (`ws review <comp> threads <pr#>`)

**Files:**
- Modify: `scripts/ws-review.sh` (add `review_threads` function with listing logic)

- [ ] **Step 1: Add `review_threads` function with argument parsing**

Add to `ws-review.sh` before the routing block:

```bash
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
                # Validate thread ID format
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
        list)    threads_list "$pr_num" ;;
        status)  threads_status "$pr_num" ;;
        resolve) threads_resolve_one "$pr_num" "$resolve_id" ;;
        resolve-all) threads_resolve_all "$pr_num" ;;
    esac
}
```

- [ ] **Step 2: Add `threads_list` — fetch and display unresolved threads**

```bash
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
```

- [ ] **Step 3: Verify thread listing works**

Run: `bash scripts/ws review yggdrasil threads 15`
Expected: Lists unresolved threads (or "No unresolved threads" message) for PR #15.

- [ ] **Step 4: Commit thread listing**

```bash
git add scripts/ws-review.sh
git commit -m "$(cat <<'EOF'
feat(ws): add thread listing via GraphQL

ws review <comp> threads <pr#> lists unresolved review threads in
compact format: [author] path:line (thread-id) with truncated snippet.

Part of #11.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Implement thread status (`--status`)

**Files:**
- Modify: `scripts/ws-review.sh` (add `threads_status` function)

- [ ] **Step 1: Add `threads_status` function**

```bash
threads_status() {
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
                  isResolved
                }
              }
            }
          }
        }' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" 2>/dev/null) || {
        echo "ERROR: Could not fetch threads for PR #$pr_num from $REPO_SLUG." >&2
        exit 1
    }

    local counts
    counts=$(echo "$response" | jq -r --arg pr "$pr_num" --arg slug "$REPO_SLUG" '
        .data.repository.pullRequest.reviewThreads.nodes
        | {
            resolved: [.[] | select(.isResolved == true)] | length,
            unresolved: [.[] | select(.isResolved == false)] | length,
            total: length
          }
        | "PR #\($pr) (\($slug)): \(.unresolved) unresolved, \(.resolved) resolved (\(.total) total)"
    ')

    echo "$counts"
}
```

- [ ] **Step 2: Verify status works**

Run: `bash scripts/ws review yggdrasil threads 15 --status`
Expected: Output like `PR #15 (SiliconSaga/yggdrasil): 0 unresolved, 5 resolved (5 total)`

- [ ] **Step 3: Commit status**

```bash
git add scripts/ws-review.sh
git commit -m "$(cat <<'EOF'
feat(ws): add thread status counts

ws review <comp> threads <pr#> --status shows resolved/unresolved
counts for quick PR triage polling.

Part of #11.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Implement thread resolution (`--resolve`, `--resolve-all`)

**Files:**
- Modify: `scripts/ws-review.sh` (add `threads_resolve_one` and `threads_resolve_all` functions)

- [ ] **Step 1: Add `threads_resolve_one` function**

```bash
threads_resolve_one() {
    local pr_num="$1"
    local thread_id="$2"

    gh api graphql -f query='
        mutation($id: ID!) {
          resolveReviewThread(input: {threadId: $id}) {
            thread { isResolved }
          }
        }' -f id="$thread_id" >/dev/null 2>&1 || {
        echo "ERROR: Failed to resolve thread $thread_id on PR #$pr_num." >&2
        exit 1
    }

    echo "Resolved thread $thread_id on PR #$pr_num."
}
```

- [ ] **Step 2: Add `threads_resolve_all` function**

```bash
threads_resolve_all() {
    local pr_num="$1"
    local owner="${REPO_SLUG%%/*}"
    local repo="${REPO_SLUG##*/}"

    # Fetch unresolved thread IDs
    local response
    response=$(gh api graphql -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                nodes {
                  id
                  isResolved
                }
              }
            }
          }
        }' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" 2>/dev/null) || {
        echo "ERROR: Could not fetch threads for PR #$pr_num from $REPO_SLUG." >&2
        exit 1
    }

    local ids
    ids=$(echo "$response" | jq -r '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | .id
    ')

    if [[ -z "$ids" ]]; then
        echo "No unresolved threads on PR #$pr_num ($REPO_SLUG)."
        return
    fi

    local total=0
    local resolved=0
    local failed=0
    while IFS= read -r thread_id; do
        total=$((total + 1))
        if gh api graphql -f query='
            mutation($id: ID!) {
              resolveReviewThread(input: {threadId: $id}) {
                thread { isResolved }
              }
            }' -f id="$thread_id" >/dev/null 2>&1; then
            resolved=$((resolved + 1))
        else
            failed=$((failed + 1))
            echo "WARNING: Failed to resolve thread $thread_id" >&2
        fi
    done <<< "$ids"

    if [[ "$failed" -eq 0 ]]; then
        echo "Resolved $resolved threads on PR #$pr_num ($REPO_SLUG)."
    else
        echo "Resolved $resolved of $total threads on PR #$pr_num ($REPO_SLUG). $failed failed." >&2
    fi
}
```

- [ ] **Step 3: Verify resolve works**

Run on a PR with unresolved threads (or verify the error path):
`bash scripts/ws review yggdrasil threads <pr#> --resolve-all`
Expected: Reports count of resolved threads, or "No unresolved threads" if none.

- [ ] **Step 4: Commit resolution**

```bash
git add scripts/ws-review.sh
git commit -m "$(cat <<'EOF'
feat(ws): add thread resolution (--resolve, --resolve-all)

Single and bulk thread resolution via GraphQL mutation. --resolve-all
continues on individual failures and reports summary.

Part of #11.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Update permissions in `.claude/settings.json`

**Files:**
- Modify: `.claude/settings.json` (lines 30-36)

- [ ] **Step 1: Replace old review allow patterns with explicit named patterns**

In `.claude/settings.json`, replace lines 30-36 (the wildcard review patterns):

```json
      "Bash(bash scripts/ws review *)",
      "Bash(bash scripts/ws review * *)",
      "Bash(bash scripts/ws review * * *)",
      "Bash(bash scripts/ws review * * * *)",
      "Bash(bash scripts/ws review * * * * *)",
      "Bash(bash scripts/ws review * * * * * *)",
      "Bash(bash scripts/ws review * * * * * * *)",
```

with:

```json
      "Bash(bash scripts/ws review --help)",
      "Bash(bash scripts/ws review * --help)",
      "Bash(bash scripts/ws review * threads *)",
      "Bash(bash scripts/ws review * threads * --status)",
      "Bash(bash scripts/ws review * *)",
      "Bash(bash scripts/ws review * * --reviewer *)",
      "Bash(bash scripts/ws review * * --since *)",
      "Bash(bash scripts/ws review * * --reviewer * --since *)",
      "Bash(bash scripts/ws review * * --since * --reviewer *)",
```

Note: `--resolve` and `--resolve-all` are intentionally NOT in the allow list.
They are Side-effect tier (user gets prompted).

- [ ] **Step 2: Verify settings are valid JSON**

Run: `python -c "import json; json.load(open('.claude/settings.json'))"`
Expected: No output (valid JSON)

- [ ] **Step 3: Commit permissions**

```bash
git add .claude/settings.json
git commit -m "$(cat <<'EOF'
fix(permissions): replace wildcard review patterns with explicit named patterns

Old wildcard patterns (ws review * * * ...) would inadvertently
auto-approve --resolve and --resolve-all, which are Side-effect tier.
New patterns explicitly name Safe operations only.

Part of #11.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update documentation

**Files:**
- Modify: `AGENTS.md` (line 105)
- Modify: `docs/dev-setup.md` (line 48)
- Modify: `docs/ws-cli-guide.md` (line 77)

- [ ] **Step 1: Update AGENTS.md command table**

Change line 105 from:
```
| `ws review <pr#> [--reviewer <name>]` | Fetch PR review comments from GitHub |
```
to:
```
| `ws review <comp> <pr#\|threads> [options]` | PR review comments and thread management (see `ws review --help`) |
```

- [ ] **Step 2: Update docs/dev-setup.md command table**

Change line 48 from:
```
| `ws review <pr#> [--reviewer <name>]` | Fetch PR review comments from GitHub |
```
to:
```
| `ws review <comp> <pr#\|threads> [options]` | PR review comments and thread management |
```

- [ ] **Step 3: Update docs/ws-cli-guide.md tier table**

In the tier table (line 77), `review` is listed as Safe. Update to note that
`review` listing/status are Safe but `--resolve*` are Side-effect:

Change:
```
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode`, `test`, `review`, `log`, `clean` |
| **Side-effect** | User's choice (ask) | No | `push`, `pr`, `issue`, `commit` |
```
to:
```
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode`, `test`, `review` (listing/status), `log`, `clean` |
| **Side-effect** | User's choice (ask) | No | `push`, `pr`, `issue`, `commit`, `review --resolve*` |
```

- [ ] **Step 4: Commit documentation**

```bash
git add AGENTS.md docs/dev-setup.md docs/ws-cli-guide.md
git commit -m "$(cat <<'EOF'
docs: update ws review command references for threads subcommand

Updates AGENTS.md, dev-setup.md, and ws-cli-guide.md to reflect the
new component-first interface and threads subcommand.

Part of #11.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: End-to-end verification

- [ ] **Step 1: Verify help output**

Run: `bash scripts/ws review --help`
Expected: Full help text showing both threads and comments subcommands.

- [ ] **Step 2: Verify comment listing (migrated behavior)**

Run: `bash scripts/ws review yggdrasil 15`
Expected: PR summary, reviews, inline comments — same format as before.

- [ ] **Step 3: Verify thread listing**

Run: `bash scripts/ws review yggdrasil threads 15`
Expected: Unresolved threads or "No unresolved threads" message.

- [ ] **Step 4: Verify thread status**

Run: `bash scripts/ws review yggdrasil threads 15 --status`
Expected: Count line like `PR #15 (SiliconSaga/yggdrasil): N unresolved, M resolved (T total)`

- [ ] **Step 5: Verify error handling**

Run: `bash scripts/ws review badname!! threads 1`
Expected: `ERROR: Invalid component name`

Run: `bash scripts/ws review yggdrasil threads abc`
Expected: `ERROR: PR number must be numeric`

Run: `bash scripts/ws review yggdrasil threads 99999`
Expected: Error fetching (PR doesn't exist)

- [ ] **Step 6: Verify settings.json patterns allow safe operations**

Confirm that `bash scripts/ws review yggdrasil threads 15` and
`bash scripts/ws review yggdrasil threads 15 --status` are auto-approved,
while `bash scripts/ws review yggdrasil threads 15 --resolve-all` prompts.
