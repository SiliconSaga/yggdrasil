---
name: creating-github-issues
description: Use when deciding to file a GitHub issue, filing a deferred task, or capturing work that a fresh agent in a new session should be able to complete independently in a single repo
---

# Creating GitHub Issues

## Overview

Pattern for filing well-structured, agent-actionable GitHub issues in the SiliconSaga multi-repo workspace using the `gh` CLI.

## Pre-flight Checks

```bash
# 1. Verify gh is installed
gh --version
# If missing: brew install gh

# 2. Verify GH_TOKEN is set (no browser login needed)
# Load if needed: source /Users/cervator/dev/git_ws/yggdrasil/.env
gh auth status

# 3. Identify the target repo (run in the repo directory)
git remote -v
# Remotes are named after their org/service (e.g. 'siliconsaga', 'local-gitea')
# Extract owner/repo from the github.com URL of the appropriate remote
```

## Should This Be an Issue?

Answer all three. All must be yes to file.

| Question | If no → |
|----------|---------|
| Scoped to ONE repo with clear boundaries? | Design doc |
| Fully understandable without this conversation? | Memory note |
| Fresh agent can complete it with just the issue text? | Memory note |

## Required Body Template

The AI attribution line comes first — mandatory. All five sections follow and must not be left empty.

```markdown
> **AI-generated issue.** Created by an AI agent on behalf of the repo owner. For workflow details see https://github.com/SiliconSaga/yggdrasil

## Context
[What system/repo this belongs to. What was being worked on when this was identified.]

## Problem / Current State
[What's wrong or missing. Be specific.]

## Acceptance Criteria
- [ ] Specific testable outcome
- [ ] Another outcome

## Technical Notes
[Key files, approaches, gotchas already known. This is what makes the issue agent-actionable.]

## Related
[Links to other issues, design docs, PRs if any. Can be "None".]
```

## Filing the Issue

Title starts with a verb: `fix:`, `feat:`, `refactor:`, `docs:`, `test:`

```bash
gh issue create \
  --repo SiliconSaga/REPO \
  --title "verb: concise description" \
  --body "$(cat <<'EOF'
> **AI-generated issue.** Created by an AI agent on behalf of the repo owner. For workflow details see https://github.com/SiliconSaga/yggdrasil

## Context
...

## Problem / Current State
...

## Acceptance Criteria
- [ ] ...

## Technical Notes
...

## Related
...
EOF
)" \
  --label "type:chore"
# Labels: type:chore, type:bug, type:feature
```

## After Filing

If the issue blocks current or near-future work, note the URL and number in MEMORY.md.

## Common Mistakes

- **Missing AI attribution line**: every issue body must start with the `> **AI-generated issue.**` blockquote
- **Requires reading this conversation to understand**: not agent-actionable — write a memory note instead
- **Vague acceptance criteria**: a fresh agent won't know when it's done
- **Wrong repo**: always verify with `git remote -v` before filing
- **`gh` not authenticated**: set `GH_TOKEN` env var (`source yggdrasil/.env`); see `yggdrasil/docs/github-cli-setup.md`
- **Spans multiple repos**: file a design doc instead, not an issue
