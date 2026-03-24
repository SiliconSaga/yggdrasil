# Design: `ws review` extraction and threads subcommand

**Issue:** [#11 — feat(ws): add threads subcommand for PR review thread management](https://github.com/SiliconSaga/yggdrasil/issues/11)
**Date:** 2026-03-23
**Status:** Approved

## Summary

Extract `ws review` from the `ws` dispatcher into a standalone `scripts/ws-review.sh`,
normalize its interface to component-first positional args (matching all other `ws`
commands), and add a `threads` subcommand for listing, inspecting, and resolving
PR review threads via the GitHub GraphQL API.

## Motivation

PR review cycles involve repetitive GraphQL operations to list, count, and resolve
review threads. During PR #8, 19+ individual `resolveReviewThread` mutations were
run manually. The workflow auditor flagged this pattern.

Additionally, the `ws` dispatcher has grown to 622 lines with several large inline
functions. Extracting `ws review` into its own script addresses this bloat while
co-locating the closely related threads functionality.

These commands are primarily agent-facing — humans use the GitHub GUI for review
workflows. Design decisions optimize for agent ergonomics: non-interactive, compact
output, composable flags.

## Command Surface

Component is always required as the first positional argument.

```bash
# Thread operations (checked first during argument parsing)
ws review <comp> threads <pr#>                    # list unresolved threads (compact)
ws review <comp> threads <pr#> --status           # resolved/unresolved counts
ws review <comp> threads <pr#> --resolve <id>     # resolve a single thread
ws review <comp> threads <pr#> --resolve-all      # resolve all unresolved threads

# Comment listing (current ws review behavior, normalized interface)
ws review <comp> <pr#> [--reviewer <name>] [--since <time>]
```

### Interface change from current behavior

Current: `ws review <pr#> [--comp <component>]` (component as optional flag,
defaults to yggdrasil).

New: `ws review <comp> <pr#>` (component as required first positional).

This aligns with every other `ws` command (`ws push <comp>`, `ws test <comp>`,
`ws commit <comp>`, etc.). No backward compatibility concern — still prototyping.

### Argument parsing logic

After parsing `<comp>`, check if the next argument is `threads`. If so, route to
thread handling. Otherwise, treat it as `<pr#>` and route to comment handling.

## File Structure

### New file: `scripts/ws-review.sh`

Contains all review logic — comments and threads. Internal structure:

```
#!/usr/bin/env bash
set -euo pipefail

# Shared setup: ROOT_DIR, .env sourcing, GH_TOKEN check
# Argument parsing: detect "threads" subcommand vs direct comments
# Shared helpers: repo slug resolution, PR number validation, component name validation

review_threads()     # listing, --status, --resolve, --resolve-all
review_comments()    # current ws review behavior (moved from ws)

# Route to the appropriate function
```

Estimated size: ~300-350 lines.

Note: `ws_validate_component` is defined in `scripts/ws` (the dispatcher). Standalone
scripts like `ws-clone.sh` duplicate their own validation inline rather than sourcing
the dispatcher. `ws-review.sh` follows the same pattern — it performs its own component
name validation (regex check + repo slug construction) without depending on the
dispatcher function. This is consistent and avoids circular sourcing.

### Changes to `scripts/ws`

Remove the entire `ws_review()` function (~170 lines). Replace with a thin delegate:

```bash
    review)
        bash "$SCRIPT_DIR/ws-review.sh" "$@"
        ;;
```

The help text for `review` in the header comment updates to reflect subcommands.

## GraphQL Queries

### Thread listing query

```graphql
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
}
```

- **`first: 100` on threads** — GitHub caps at 100 per page. No pagination for v1.
  If a PR has 100+ threads, something else is wrong. Cursor-based pagination can
  be added later.
- **`comments(first: 1)`** — only the first comment (the review finding) is needed
  for compact listing. Full conversation is available via `ws review <comp> <pr#>`.
- **Invoked via `gh api graphql`** — no extra dependencies. Query as heredoc,
  variables passed with `-f` flags.

### Resolve mutation

```graphql
mutation($id: ID!) {
  resolveReviewThread(input: {threadId: $id}) {
    thread { isResolved }
  }
}
```

No batch mutation exists in GitHub's API. `--resolve-all` collects unresolved
thread IDs from the listing query, then loops individual mutations.

### GraphQL expansion path

This is the first GraphQL consumer in the workspace. If the workspace accumulates
4-5+ GraphQL queries in the future (e.g., PR checks/status rollups, label mutations,
batch queries), consider migrating to queries stored in `scripts/graphql/*.graphql`
and loaded at runtime. This keeps query logic separate from shell logic and avoids
heredoc escaping. For now, inline heredocs are appropriate for 2 queries.

## Data Flow

| Subcommand | Query | Post-processing |
|------------|-------|-----------------|
| `threads <pr#>` | Listing query, filter `isResolved: false` | jq: compact format per thread |
| `threads <pr#> --status` | Listing query, no filter | jq: count resolved vs unresolved |
| `threads <pr#> --resolve <id>` | Resolve mutation | Report success/failure |
| `threads <pr#> --resolve-all` | Listing query (unresolved IDs) then resolve loop | Continue on individual failures, report summary (N resolved, M failed) |

## Output Format

### Thread listing (compact, one line + truncated snippet per thread)

```
=== Unresolved threads: PR #8 (SiliconSaga/yggdrasil) ===
[coderabbitai] scripts/ws:142 (PRRT_kwDO...abc)
  "Consider validating the input before..."
[copilot] docs/dev-setup.md:38 (PRRT_kwDO...def)
  "This section references an outdated..."
```

### Status (counts only)

```
PR #8 (SiliconSaga/yggdrasil): 2 unresolved, 17 resolved (19 total)
```

### Resolve-all

```
Resolved 2 threads on PR #8 (SiliconSaga/yggdrasil).
```

### Resolve single

```
Resolved thread PRRT_kwDO...abc on PR #8.
```

## Permission Tiers

| Operation | Tier | Rationale |
|-----------|------|-----------|
| `ws review <comp> <pr#>` | Safe | Read-only, unchanged |
| `ws review <comp> threads <pr#>` | Safe | Read-only listing |
| `ws review <comp> threads <pr#> --status` | Safe | Read-only counts |
| `ws review <comp> threads <pr#> --resolve <id>` | Side-effect | Mutates PR state on GitHub |
| `ws review <comp> threads <pr#> --resolve-all` | Side-effect | Mutates PR state on GitHub |

### `.claude/settings.json` updates

Safe tier (auto-approve):
```json
"Bash(bash scripts/ws review * threads *)",
"Bash(bash scripts/ws review * threads * --status)",
"Bash(bash scripts/ws review * *)",
"Bash(bash scripts/ws review * * --reviewer *)",
"Bash(bash scripts/ws review * * --since *)",
"Bash(bash scripts/ws review * * --reviewer * --since *)"
```

Side-effect tier (user prompted, opt-in via `settings.local.json`):
```json
"Bash(bash scripts/ws review * threads * --resolve *)",
"Bash(bash scripts/ws review * threads * --resolve-all)"
```

Remove old patterns that matched the previous `ws review <pr#> [--comp ...]`
argument order.

## Documentation Updates

- `scripts/ws` — update `review` help text line
- `AGENTS.md` — update `ws review` row in the command table
- `docs/ws-cli-guide.md` — update tier table, add threads to examples
- `docs/dev-setup.md` — add threads to command reference

## Security Considerations

- Component name validation: same regex (`^[a-z][a-z0-9-]*$`) as all other commands
- Thread ID validation: opaque GitHub node IDs — validate format (`^[A-Za-z0-9_=/-]+$`)
  before passing to GraphQL mutation to prevent query injection
- GH_TOKEN: sourced from `.env`, same pattern as existing review code
- No `eval`, all variables quoted, Bash 3.2 compatible

## Related Issues

- [#11](https://github.com/SiliconSaga/yggdrasil/issues/11) — this feature
- Future: rename `ws resolve` (ArgoCD) to avoid confusion with `--resolve` (threads)
- Future: formalize inline-vs-standalone script criteria in `docs/ws-cli-guide.md`
