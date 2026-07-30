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

## Full Workflow

```bash
# 1. Start from an up-to-date main
git checkout main && git pull siliconsaga main

# 2. Create topic branch
git checkout -b <type>/<description>

# 3. Commit (use ws commit — handles staging and attribution)
bash scripts/ws commit <component> .commits/my-change.md

# 3b. First push to this component? Verify token coverage first.
#     (Skip if you've pushed this component before in a working session.)
bash scripts/ws diagnose <component>
#     Look for "✓ <TOKEN_VAR> is set" on the push/cr remote row.
#     If it shows "NOT SET", add the token to .env and re-source it,
#     then re-run: bash scripts/ws gitlab-auth

# 4. Push
bash scripts/ws push <component>

# 5. Draft CR body
cp templates/change.md .crs/<description>.md
# ... fill in Summary, Test plan, Related ...

# 6. Open CR
bash scripts/ws cr <component> "type: description" .crs/<description>.md
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
- A provider token must be set in `.env` for push and CR scripts.
- CR title follows the same `type:` convention as commit messages and issue titles.
- **Always `cp` the template file — never write CR bodies from memory.** The template evolves; a remembered or hardcoded heredoc will produce a stale body. Not optional even when batching multiple CRs.
- **Avoid "fixes #N" / "closes #N" / "resolves #N" in CR bodies unless the CR fully resolves the issue.** GitHub auto-closes the referenced issue on merge when it sees any of those keywords — even with qualifiers like "partially fixes" (the keyword still wins). For partial fixes or related work, use `relates to #N` or `see #N`, which don't trigger auto-close.

## When Direct Push to Main Is Acceptable

Only when the user explicitly requests it AND branch protection has not yet been configured on the repo — once active, all pushes to main require a CR regardless of user request.
