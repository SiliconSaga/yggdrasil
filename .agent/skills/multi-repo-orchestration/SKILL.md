---
name: multi-repo-orchestration
description: Use when a session touches more than one repo, when accumulated TODOs need triage, or when deciding whether to work on something now or defer it
---

# Multi-Repo Orchestration

## Overview

Session discipline for the SiliconSaga multi-repo workspace: what to work on, what to defer, and how to ensure nothing important is trapped only in the current conversation.

## Workspace Layout

- Repos are sibling directories in a shared workspace: nordri, nidavellir, mimir, yggdrasil, vordu
- Each is an independent git repo under the `SiliconSaga` GitHub org
- Session memory: `.claude/projects/<project-path>/MEMORY.md`
- Skills: `yggdrasil/.agent/skills/`

## Session Start Checklist

1. Read MEMORY.md for the primary workspace
2. Scan open issues: `gh issue list --repo SiliconSaga/REPO --state open --limit 10`
3. State the session goal explicitly — don't drift without one

## Classification Framework

When something comes up that you can't or won't finish right now:

| Type | Criteria | Action |
|------|----------|--------|
| Work now | Needs current context, blocks goal, or under 15 min | Do it |
| GitHub issue | Single repo, fully describable, independent, fresh-agent-doable | Use `creating-github-issues` skill |
| Design doc | Multi-repo, needs architectural decision, underspecified | Write in appropriate repo's `docs/` |
| Memory note | Cross-session architectural knowledge | Update MEMORY.md |

**The key test for "GitHub issue"**: Could you hand just the issue body to a fresh agent in that repo's directory and have them complete it? If yes — file it. If they'd need this conversation — memory or design doc.

## Session End Discipline

Before closing any session:

1. List every deferred item accumulated during the session
2. Classify each using the table above
3. File issues for anything that qualifies (invoke `creating-github-issues` skill)
4. Update MEMORY.md with architectural knowledge from this session
5. Confirm: nothing important is trapped only in this conversation

## Cross-Repo Dependencies

When filing an issue that is blocked by or depends on work in another repo:
- Note the dependency explicitly in the Technical Notes section of the issue
- Record the relationship in MEMORY.md

## What NOT to Put in GitHub Issues

- Anything that requires reading this conversation to understand
- Vague aspirations without testable acceptance criteria
- Work that spans multiple repos (write a design doc instead)

## Related Skills

`creating-github-issues` — invoke when an item qualifies for filing
