---
name: gdd-branch-workflow
description: Use when about to commit and push code changes, or when deciding whether to push directly to main or use a topic branch
---

# GDD Branch Workflow

## Default Rule

Always use a topic branch unless the user explicitly says "push to main" or "commit directly to main". Main is protected — direct pushes are rejected by default.

## Branch Naming

```
<type>/<short-description>
```

Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`

Examples: `feat/gh-issue-helper`, `fix/nordri-velero-assert`, `docs/kuttl-gotchas`

## Workspace CLI Commands

Always use `ws` commands instead of raw git operations — they handle staging,
attribution trailers, auth, and remote selection automatically.

| Command | Purpose |
|---------|---------|
| `ws push <comp> [branch]` | Push current (or named) branch |
| `ws cr <comp> [--upstream] <title> <bodyfile>` | Open CR from current branch |
| `ws issue <comp> <title> <label> <bodyfile>` | File an issue |
| `ws commit <comp> <bodyfile>` | Commit with Co-Authored-By trailer (bodyfile-driven; see `templates/commit.md`) |
| `ws diagnose <comp>` | Show remotes, provider, and token coverage — run before first push to a component |

CR body drafts follow the same pattern as issue drafts:
- Template: `yggdrasil/templates/change.md`
- Clearinghouse: `<repo-root>/.crs/<descriptive-name>.md` (gitignored, auto-created)

## Choose the Push Topology First

Use a direct-source flow only when the selected identity is intentionally authorized to push the source project. A valid token in `ws diagnose` proves authentication, not that authorization.

For upstream contributions, use a fork topology:

1. Run `ws clone-fork <component>` to create or repair the fork remote and source remote.
2. Run `ws diagnose <component>` and confirm the remote marked `push/cr remote (identity.forkRemote)` is the fork namespace.
3. Push the topic branch with `ws push <component>`.
4. Open the cross-fork review with `ws cr <component> --upstream <title> <bodyfile>`.

`--upstream` consumes an existing fork/source topology; it does not reinterpret a sibling team repository as a fork. If the configured fork remote is absent, repair the checkout with `ws clone-fork` before pushing.

On GitLab, a fork-group access-token bot generally cannot be invited directly to an unrelated private source project. Share the fork-home group into the source project or group as Reporter instead; the bot then inherits source read access through its owning group while retaining repository write access only in the fork namespace.

## Full Workflow

### Fork flow for upstream contributions

```bash
# 1. Create or repair the fork/source remotes and synchronize main
ws clone-fork <component>

# 2. Create topic branch
ws exec <component> git switch -c <type>/<description>

# 3. Commit (use ws commit — handles staging and attribution)
ws commit <component> .commits/my-change.md

# 4. Verify the fork marker and token authentication
ws diagnose <component>

# 5. Push to identity.forkRemote
ws push <component>

# 6. Draft the CR body from the current template
cp templates/change.md .crs/<description>.md

# 7. Open the cross-fork CR against the source project
ws cr <component> --upstream "type: description" .crs/<description>.md
```

`ws diagnose` confirms remote selection, token routing, and provider authentication. The push and CR operations establish whether that identity has the required repository authorization.

### Direct-source flow

Use this only when direct source-project write access is intentional:

```bash
ws pull <component>
ws exec <component> git switch -c <type>/<description>
ws commit <component> .commits/my-change.md
ws diagnose <component>
ws push <component> --remote <source-remote> <type>/<description>
cp templates/change.md .crs/<description>.md
ws cr <component> --remote <source-remote> "type: description" .crs/<description>.md
```

## Rebasing onto Updated Main

When main moves ahead during code review (e.g., another CR merges), rebase
to keep a clean linear history before merging.

### Pre-rebase checklist

1. **Announce intent** — tell the human before switching branches or rebasing
2. **Check for uncommitted work** — `git status` must be clean
3. **Create a backup branch** — `git branch <name>-backup` before rebasing.
   Cost is zero (just a pointer), safety is real. Reflog also works but a
   named branch is simpler to find.

### Rebase procedure

```bash
# 1. Fetch latest main
git fetch siliconsaga main

# 2. Survey the conflict surface before starting
git diff --name-only HEAD...siliconsaga/main   # files they changed
git diff --name-only siliconsaga/main...HEAD    # files we changed
# Files in both lists are potential conflicts

# 3. Rebase
git rebase siliconsaga/main
# Resolve conflicts as they appear, then:
#   git add <resolved-files>
#   git rebase --continue

# 4. Verify — no conflict markers left
grep -rn "^<<<<<<<" <files-that-conflicted>

# 5. Force push (rebase rewrites history)
bash scripts/ws push <component> --force
```

### Force-push discipline

**Only use `--force` immediately after a rebase.** Subsequent pushes to
the same branch are fast-forwards — a normal `ws push` is sufficient.
Casually force-pushing is dangerous: it rewrites remote history when
unnecessary, obscures the commit timeline for reviewers, and can lose
work if anyone else has pulled the branch.

If a normal push is rejected with "non-fast-forward" and you didn't just
rebase, investigate why before adding `--force` — someone else may have
pushed, or you may have stale local state.

### Conflict resolution principles

- **Read both sides** before resolving — understand what each change intended
- **Take both changes** when they modify adjacent but independent content
  (e.g., different rows in a table, different functions in a file)
- **Favor the newer main** for shared infrastructure (formatting, imports)
  and **favor our branch** for feature-specific changes
- **Never silently drop changes** — if unsure, ask the human
- If a rebase goes badly: `git rebase --abort` returns to the pre-rebase
  state. Or restore from backup: `git reset --hard <name>-backup`

### When to rebase

- **Before merge** — when main has moved ahead and the CR has conflicts
- **After code review fixes** — to pick up main changes before final push
- **Not during active review** — avoid force-pushing while reviewers are
  mid-review (they lose their place). Coordinate with the human.

### During review-fix cycles

Once you've fetched and addressed review comments in a session, check
for new findings before each subsequent push:

```bash
bash scripts/ws review <comp> <cr#> --since prev-push
```

Reviewers (especially automated ones like CodeRabbit) may post new
comments between your pushes. Addressing them before pushing avoids
a leapfrog cycle where each push triggers new review that you only
see after the next push.

This does not apply to pre-CR pushes — there's no CR to check against.

## After the CR is Merged

```bash
git checkout main
git pull siliconsaga main
git branch -d <type>/<description>
```

## Multi-phase work — tracker issues

When a feature spans multiple phases (a design pass plus 3–6 implementation passes), don't try to thread the work through a single CR. Use a **tracker issue** as the canonical "what's left" view, with a phase issue per implementation pass:

- **One tracker issue per multi-phase design.** Label: `tracker`. Body is a markdown task-list with one checkbox per phase. Add a `#N` reference on a checkbox only once that phase's implementation issue exists — so the presence of `#N` doubles as "this phase is ready to claim."
- **One implementation issue per phase.** Label: `phase`. Linked from the tracker checkbox. GitHub auto-checks the box when the linked issue closes.
- **The design PR itself** can carry the `rfc` label and link to the tracker in its body so reviewers see the shape of what comes next.

Avoids silent drift between design and implementation, ambiguous "designed but not planned" states, and quiet abandonment of later phases. Live example: `SiliconSaga/knarr#6` (tracker) + `#5` (Phase 1 impl).

## Plan and design docs deserve CR review

Even "docs-only" PRs benefit from full CR (CodeRabbit, Copilot, or the equivalent) when the doc surface is substantial — design docs, implementation plans, or any markdown carrying copy-pastable code blocks. Plan-doc code samples drift from reality during authoring and are easy to introduce real correctness bugs into; reviewers catch them. For a meaty plan, budget 3–4 review rounds, not 1, and use the round-by-round fix-bodyfile commit pattern so each rebuttal is auditable.

## Key Notes

- Always use `ws push` rather than plain `git push` — it handles remote selection, auth, and GitKraken `url.insteadOf` workarounds automatically.
- Provider tokens flow through the workspace's token-injection mechanism ([`docs/git-provider-setup.md`](../../docs/git-provider-setup.md)): stored in the gitignored `.env`, sourced by the `ws` dispatcher, injected per-process. Never commit or print token values, in commands or CR bodies.
- CR title follows the same `type:` convention as commit messages and issue titles.
- **Always `cp` the template file — never write CR bodies from memory.** The template evolves; a remembered or hardcoded heredoc will produce a stale body. Not optional even when batching multiple CRs.
- **Avoid "fixes #N" / "closes #N" / "resolves #N" in CR bodies unless the CR fully resolves the issue.** GitHub auto-closes the referenced issue on merge when it sees any of those keywords — even with qualifiers like "partially fixes" (the keyword still wins). For partial fixes or related work, use `relates to #N` or `see #N`, which don't trigger auto-close.

## When Direct Push to Main Is Acceptable

Only when the user explicitly requests it AND branch protection has not yet been configured on the repo — once active, all pushes to main require a CR regardless of user request.
