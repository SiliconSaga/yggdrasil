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
- As part of a Zen-stance deep review session

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
  thread itself (see resolution table below).
- Can over-engineer suggestions (e.g., 20+ permission patterns when one suffices)
- Deduplicates across re-reviews — may note when a new finding duplicates an
  existing open thread rather than filing it again

**Copilot:**
- Does NOT re-trigger on push. Use the "Re-request review" button in GitHub's
  reviewer pane to trigger a re-review
- Asking via CR comment causes Copilot to file a separate fix CR instead of
  reviewing — avoid this
- Does NOT track resolved threads across re-reviews — re-files the same
  findings even after they've been addressed (see resolution table below)

## Fetching Comments and Threads

### Context budget warning

`ws review <comp> <cr#>` fetches everything (inline comments, full bodies, and
top-level notes) without truncation. On active CRs this can be thousands of
tokens — bot walkthrough notes, analysis chains, internal state blobs, resolved
threads. **If your agent supports sub-agents, delegate the initial fetch to one
to keep the main context clean.**

**Initial triage** — if sub-agents are available, delegate:
```text
Spawn a sub-agent with this prompt:
  "Run 'bash scripts/ws review <comp> <cr#>' and return only actionable
   findings: file, line, issue description, and suggested fix. Ignore
   resolved threads, walkthrough summaries, and internal state blobs.
   Return a numbered list."
```
If sub-agents are not available, run the command directly and skim past
resolved/walkthrough content — focus on ⚠️ Potential issue and 🧹 Nitpick
markers.

**Targeted follow-up** — run directly in main context (small output):
```bash
bash scripts/ws review <comp> <cr#> --since prev-push   # since last push
bash scripts/ws review <comp> notes <cr#>               # bot summaries only
bash scripts/ws review <comp> threads <cr#> --status    # resolved/unresolved counts
bash scripts/ws review <comp> threads <cr#>             # unresolved thread list
bash scripts/ws review <comp> threads <cr#> --resolve-all
bash scripts/ws review <comp> threads <cr#> --resolve <id>
bash scripts/ws review <comp> reply <cr#> <id> "message" --resolve
bash scripts/ws review <comp> comment <cr#> <bodyfile>   # top-level comment, not tied to a thread
```

`reply` and `comment` both prepend the GDD AI-attribution banner automatically
— don't hand-type it, and don't fall back to raw `gh`/`glab` for a top-level
PR/MR comment (that bypasses the banner). `ws review <comp> <cr#>` (the "run
this first" command) also warns if the CR's base branch has moved ahead since
the branch was cut — rebase per `gdd-branch-workflow` if it does.

Thread resolution is a Side-effect operation (prompts for approval).

**Note:** Bot summaries and nitpicks (CodeRabbit walkthrough, Copilot summary)
appear as top-level notes, not inline comments. The default `ws review <comp>
<cr#>` command fetches both. For targeted access to summaries only, use
`ws review <comp> notes <cr#>`.

**When to resolve manually vs. let the reviewer resolve:**

| Reviewer | Resolution approach |
|---|---|
| **CodeRabbit** | Push the fix and wait — CodeRabbit may validate and self-resolve. Check status after each push and only manually resolve if it hasn't, or if disagreeing with the finding (reply with justification first). |
| **Copilot** | Manually resolve with `--resolve-all` after each re-review — Copilot re-files stale findings and does not self-resolve. |
| **Human reviewer** | Never resolve via automation. Only the author or the reviewer should resolve human threads. |

**When to reply per-thread vs resolve silently.** Per-thread replies
are friction — both for the author writing them and for anyone
scanning the PR conversation later. Reserve them for cases where the
reply carries information the resolution alone doesn't:

| Situation | Reply individually? | Why |
|---|---|---|
| Standard fix matching the reviewer's suggestion | No — resolve silently | The commit hash already documents what changed; a "fixed in abc123" comment adds no information past what the diff shows. |
| Disagreeing with the finding ("won't fix") | **Yes** | The reasoning needs to live next to the thread so a future re-review (or a human) can see why this was a conscious decision. |
| Fix is substantially different from the suggested approach | **Yes** | Reviewers (especially bots) may otherwise re-file the original suggestion. A short "addressed differently: <reason>" prevents that. |
| Large fix-set covering many threads | Optional: one batched comment | A single top-level summary comment listing what each commit addressed is friendlier than per-thread chatter. Keep individual replies for the disagreement / different-approach cases above. |
| Nit you intentionally aren't fixing | **Yes** | Without the reply the reviewer's tool will re-flag it next round. A one-line "skipping — out of scope" prevents the loop. |

Default: **resolve silently** — the commit body is the durable record; per-thread replies should only add information that isn't already there.

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
— a Superpowers plugin skill: invoke via the Skill tool when the
plugin is installed, or read the principles below as a fallback when
it isn't. Key principles:

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
