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

## Full Workflow

```bash
# 1. Start from an up-to-date main
source /Users/cervator/dev/git_ws/yggdrasil/.env
git checkout main
git pull siliconsaga main

# 2. Create topic branch
git checkout -b <type>/<description>

# 3. Do the work — commit as normal
git add <files>
git commit -m "type: description

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

# 4. Push topic branch
git push siliconsaga <type>/<description>

# 5. Open PR
gh pr create \
  --repo SiliconSaga/REPO \
  --base main \
  --head <type>/<description> \
  --title "type: concise description" \
  --body "$(cat <<'EOF'
## Summary
- What this does and why

## Related
- Closes #N (if applicable)

🤖 Assisted by Claude Code
EOF
)"
```

## After the PR is Merged

```bash
git checkout main
git pull siliconsaga main
git branch -d <type>/<description>
```

## Key Notes

- `source .env` is required before `git push` — the credential helper reads `GH_TOKEN` from the environment
- PR title follows the same `type:` convention as commit messages and issue titles
- If the PR resolves a GitHub issue, add `Closes #N` to the PR body — GitHub will close the issue on merge
- For multi-commit PRs, squash on merge keeps main history clean; leave this to the human reviewer

## When Direct Push to Main Is Acceptable

Only when the user explicitly requests it, AND branch protection has not yet been configured on the repo. Once protection is active, all pushes to main require a PR regardless.
