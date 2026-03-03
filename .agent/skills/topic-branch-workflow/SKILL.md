---
name: topic-branch-workflow
description: Use when about to commit and push code changes, or when deciding whether to push directly to main or use a topic branch
---

# Topic Branch Workflow

## Default Rule

Always use a topic branch unless the user explicitly says "push to main" or "commit directly to main". Main is protected — direct pushes are rejected by default.

## Branch Naming

```
<type>/<short-description>
```

Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`

Examples: `feat/gh-issue-helper`, `fix/nordri-velero-assert`, `docs/kuttl-gotchas`

## Utility Scripts

All scripts live in `yggdrasil/scripts/` and auto-source `.env`. Run them from any workspace repo directory.

| Script | Purpose |
|--------|---------|
| `git-push.sh [branch]` | Push current (or named) branch to siliconsaga |
| `git-pr.sh TITLE BODYFILE` | Open PR from current branch to main |
| `gh-issue.sh REPO TITLE LABEL BODYFILE` | File a GitHub issue |

PR body drafts follow the same pattern as issue drafts:
- Template: `yggdrasil/.agent/pr-template.md`
- Clearinghouse: `<repo-root>/.prs/<descriptive-name>.md` (gitignored, auto-created)

## Full Workflow

```bash
# 1. Start from an up-to-date main
git checkout main
git pull siliconsaga main

# 2. Create topic branch
git checkout -b <type>/<description>

# 3. Do the work — commit as normal
git add <files>
git commit -m "type: description

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

# 4. Push (from a sibling repo; use ./scripts/git-push.sh if already in yggdrasil)
../yggdrasil/scripts/git-push.sh

# 5. Draft PR body
cp ../yggdrasil/.agent/pr-template.md .prs/<description>.md
# ... fill in Summary, Test plan, Related ...

# 6. Open PR
../yggdrasil/scripts/git-pr.sh "type: description" .prs/<description>.md
```

## After the PR is Merged

```bash
git checkout main
git pull siliconsaga main
git branch -d <type>/<description>
```

## Key Notes

- Always use `git-push.sh` rather than plain `git push` — GitKraken installs a global
  `url.insteadOf` rule that rewrites `https://github.com/` to `git@github.com:` (SSH),
  which fails in agent scripts without GitKraken's ssh-agent. The script bypasses this
  by pushing to an explicit `https://x-access-token:$GH_TOKEN@...` URL. GitKraken
  continues to push via SSH unaffected.
- `GH_TOKEN` must be set (via `.env` or environment) for both push and PR scripts.
- PR title follows the same `type:` convention as commit messages and issue titles.
- **Always `cp` the template file — never write PR bodies from memory.** The template
  evolves; using a remembered or hardcoded heredoc will produce a stale body. The `cp`
  step is not optional even when batching multiple PRs.

## When Direct Push to Main Is Acceptable

Only when the user explicitly requests it, AND branch protection has not yet been configured on the repo. Once protection is active, all pushes to main require a PR regardless.
