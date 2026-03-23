---
name: gdd-review-triage
description: >
  Multi-reviewer PR coordination. Fetches review comments from CodeRabbit,
  Copilot, and other reviewers, deduplicates findings, triages by severity,
  and presents a consolidated action list. Use after pushing, when review
  comments arrive, or when asked to triage PR feedback.
---

# GDD Review Triage

Orchestrate feedback from multiple AI code reviewers into a single,
actionable summary. No single reviewer catches everything, and each has
blind spots — the value is in the combination, but only with a referee
who can triage across all of them.

## When to Use

- After pushing to a PR (check for new comments)
- When the user asks to review PR feedback
- When multiple reviewers have posted and findings need consolidation
- As part of a Zen-mode deep review session

## Known Reviewer Behaviors

Understanding each reviewer's quirks is essential for effective triage.

| Reviewer | Trigger | Strengths | Weaknesses |
|----------|---------|-----------|------------|
| **CodeRabbit** | Continuous (push events) | Broad coverage, lint, consistency | Over-suggests, some false positives |
| **Copilot** | On-demand or auto | Focused code-level findings | Limited context, re-files resolved findings |
| **Claude (session)** | Manual or skill-invoked | Full session context, can triage across reviewers | Requires active session |

**CodeRabbit:**
- Re-triggers on each push, refining its review incrementally
- Can over-engineer suggestions (e.g., 20+ permission patterns when one suffices)

**Copilot:**
- Does NOT re-trigger on push. Use the "Re-request review" button in GitHub's
  reviewer pane to trigger a re-review
- Asking via PR comment causes Copilot to file a separate fix PR instead of
  reviewing — avoid this
- Does NOT track resolved threads across re-reviews. It re-files the same
  findings even after they've been addressed. Expect to bulk-resolve stale
  threads after each Copilot re-review

## Fetching Comments

Use `ws review` or the GitHub API directly:

```bash
# Via ws CLI
bash scripts/ws review <pr#>
bash scripts/ws review <pr#> --since prev-push   # if a review landed between pushes

# Via gh API (for more control)
gh api repos/{owner}/{repo}/pulls/{pr}/comments
gh api repos/{owner}/{repo}/pulls/{pr}/reviews
```

## Triage Process

For each finding from any reviewer:

### 1. Verify Against Codebase

Don't take findings at face value. Read the actual code the reviewer is
commenting on. Check whether:
- The finding describes the code accurately
- The suggested fix is correct
- The issue still exists (it may have been fixed in a later commit)

### 2. Classify

| Classification | Action |
|---------------|--------|
| **Actionable** | Real issue, should be fixed. Note severity. |
| **Noise** | False positive, already addressed, or over-engineered suggestion. Resolve the thread. |
| **Conflict** | Two reviewers disagree, or suggestion conflicts with project conventions. Flag for human decision. |
| **Duplicate** | Same finding from multiple reviewers. Keep the most detailed version. |

### 3. Present Consolidated Summary

Group by severity and present to the human:

> **PR #42 Review Triage:**
> - 2 actionable findings (1 bug, 1 consistency issue)
> - 3 noise items resolved (Copilot re-filed stale findings)
> - 1 conflict: CodeRabbit suggests X, Copilot suggests Y
> - Want me to address the actionable items?

## Integration with Receiving Code Review

When processing findings, apply the `receiving-code-review` discipline
(a superpowers plugin skill loaded via the Skill tool). Key principles:

- Evaluate each finding with technical rigor, not performative agreement
- Verify claims against the actual codebase before accepting
- Push back on incorrect suggestions with reasoning
- Don't blindly implement every suggestion — some are noise

## After Triage

- Address actionable findings (fix the code, update tests)
- Resolve noise threads in GitHub
- Flag conflicts for human decision
- Push and re-check (CodeRabbit will re-trigger; Copilot needs manual
  re-request)
