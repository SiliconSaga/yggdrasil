---
name: gdd-quick
description: >
  Quick mode — minimal ceremony for short sessions. Suggests appropriately-sized
  tasks, recovers context fast, skips inferrable questions. Use when you have
  15 minutes between responsibilities or want to make a focused small contribution.
---

# GDD Quick Mode

A behavior modifier for short time windows. Minimal ceremony, fast context
recovery, appropriately-sized task suggestions.

## When to Use

- Short sessions (15-30 minutes)
- Phone or limited-attention contexts
- The user says "I just have a few minutes" or "quick session"
- Between meetings or other responsibilities

## Behavior Modifications

| Activity | Without Quick | With Quick |
|----------|-------------|------------|
| Orientation | Full startup sequence | Brief — surface concerns and staleness only, skip detailed content review |
| Brainstorming | Full design flow | Skip if scope is clear, go straight to implementation |
| Task selection | Open-ended | Suggest tasks sized for available time |
| Questions | Ask what's needed | Skip inferrable questions, use sensible defaults |
| Code review | Comprehensive | Focus on blockers only, defer style issues |
| Commits | Detailed messages | Minimal messages acceptable |
| Housekeeping | May suggest | Defer unless critical |

## Session Sizing

Suggest tasks appropriate to the time window:

- **15 min:** Write one BDD scenario, review one PR comment, fix one small bug
- **30 min:** Implement step definitions for an existing scenario, triage
  review findings, write a skill stub
- **45 min:** End-to-end small feature, full PR with review

## Composition

- **Quick + Mentoring:** Short session, but still explain the most unfamiliar
  parts. Trim explanations to essentials.
- **Quick + Autonomous:** Not typical — autonomous mode implies longer
  unattended work. If combined, produce the smallest useful increment.

## What This Mode Does NOT Do

- Skip safety checks or trust verification
- Rush through decisions that need thought
- Commit without proper messages (minimal is fine, empty is not)
- Prevent the user from switching to Zen if they find more time
