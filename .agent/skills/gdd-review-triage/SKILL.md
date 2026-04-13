---
name: gdd-review-triage
description: >
  Multi-reviewer CR coordination. Fetches review comments from CodeRabbit,
  Copilot, and other reviewers, deduplicates findings, triages by severity,
  and presents a consolidated action list. Use after pushing, when review
  comments arrive, or when asked to triage CR feedback.
---

# GDD Review Triage

Orchestrate feedback from multiple AI code reviewers into a single,
actionable summary. No single reviewer catches everything, and each has
blind spots — the value is in the combination, but only with a referee
who can triage across all of them.

## When to Use

- After pushing to a CR (check for new comments)
- When the user asks to review CR feedback
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
- **May self-resolve threads** after validating a fix — if the pushed code
  addresses a finding, CodeRabbit ideally updates its comment and resolves the
  thread itself. Prefer waiting for this rather than pre-emptively resolving;
  but verify after each push — it may not always self-resolve.
- Can over-engineer suggestions (e.g., 20+ permission patterns when one suffices)
- Deduplicates across re-reviews — may note when a new finding duplicates an
  existing open thread rather than filing it again

**Copilot:**
- Does NOT re-trigger on push. Use the "Re-request review" button in GitHub's
  reviewer pane to trigger a re-review
- Asking via CR comment causes Copilot to file a separate fix CR instead of
  reviewing — avoid this
- Does NOT track resolved threads across re-reviews. It re-files the same
  findings even after they've been addressed. Expect to bulk-resolve stale
  threads after each Copilot re-review

## Fetching Comments and Threads

Use `ws review` for all review operations:

```bash
# Review comments
bash scripts/ws review <comp> <cr#>
bash scripts/ws review <comp> <cr#> --since prev-push
bash scripts/ws review <comp> <cr#> --reviewer coderabbitai

# Review threads (unresolved items, status, resolution)
bash scripts/ws review <comp> threads <cr#>              # list unresolved
bash scripts/ws review <comp> threads <cr#> --status     # counts
bash scripts/ws review <comp> threads <cr#> --resolve-all  # bulk resolve
bash scripts/ws review <comp> threads <cr#> --resolve <id> # resolve one
```

Thread resolution is a Side-effect operation (prompts for approval).

**When to resolve manually vs. let the reviewer resolve:**

| Reviewer | Resolution approach |
|---|---|
| **CodeRabbit** | Push the fix and wait — CodeRabbit may validate and self-resolve. Check status after each push and only manually resolve if it hasn't, or if disagreeing with the finding (reply with justification first). |
| **Copilot** | Manually resolve with `--resolve-all` after each re-review — Copilot re-files stale findings and does not self-resolve. |
| **Human reviewer** | Never resolve via automation. Only the author or the reviewer should resolve human threads. |

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

> **CR #42 Review Triage:**
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

1. Address actionable findings (fix the code, update tests)
2. Push — CodeRabbit re-triggers automatically; Copilot needs manual re-request
3. Wait for CodeRabbit to re-review, then check status:
   `ws review <comp> threads <cr#> --status`
4. For any threads that remain:
   - Copilot stale re-files → `ws review <comp> threads <cr#> --resolve-all`
   - Findings you're intentionally not addressing → reply with justification,
     then resolve: `ws review <comp> reply <cr#> <id> "Won't fix: ..." --resolve`
   - Human reviewer threads → do not resolve via automation; address the
     concern and let the reviewer resolve
