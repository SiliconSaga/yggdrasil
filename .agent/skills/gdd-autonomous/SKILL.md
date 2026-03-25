---
name: gdd-autonomous
description: >
  Autonomous mode — permission-bounded independent work with reviewable
  increments. Use when delegating work to background agents (Jules, background
  Claude sessions) or when the AI should work independently on a defined task.
---

# GDD Autonomous Mode

A behavior modifier for AI agents working independently within permission
boundaries. The agent produces reviewable increments and logs its reasoning
for later human review.

## When to Use

- Delegating work to background agents (Jules, background Claude)
- The user says "handle this" or "work on this while I'm away"
- Well-scoped tasks where the agent can make progress without human input
- Any AI Agent role session

## Behavior Modifications

| Activity | Without Autonomous | With Autonomous |
|----------|-------------------|-----------------|
| Orientation | Interactive | Minimal — log-only, proceed to work |
| Questions | Ask the human | Make reasonable decisions, document assumptions |
| Brainstorming | Collaborative | Skip — work from existing spec or issue |
| Code review | Present findings | Log findings, apply obvious fixes, flag ambiguities |
| Commits | Standard | Detailed messages — they're the primary communication channel |
| Thalamus writes | Standard | Log observations and decisions for later human review |
| Housekeeping | Interactive | Skip — requires human participation |

## Permission Boundaries

The agent works within established permissions:

- Follow existing skills and instructions
- Stay within the scope of the assigned task
- Do not make architectural decisions without existing spec/plan
- Do not push to remote without explicit permission
- Do not modify shared infrastructure (CI/CD, branch protection, etc.)
- Log anything unexpected to Thalamus Concerns

## Reviewable Increments

Structure work so the human can review it efficiently:

- Small, focused commits with descriptive messages
- Each commit should make sense independently
- PR descriptions explain the reasoning, not just the changes
- Flag decisions that need human validation

## Composition

- **Autonomous + Mentoring:** Log reasoning in extra detail for human learning.
  Commit messages and PR descriptions serve as teaching material.
- **Autonomous + Zen:** Full diligence — comprehensive tests, detailed docs,
  thorough error handling. The most thorough autonomous mode.
- **Autonomous + Quick:** Not typical. If combined, produce the smallest
  useful increment and stop.

## What This Mode Does NOT Do

- Exceed permission boundaries
- Make decisions the human should make (architecture, dependencies, scope)
- Skip safety checks or trust verification
- Assume approval — the human still reviews everything
