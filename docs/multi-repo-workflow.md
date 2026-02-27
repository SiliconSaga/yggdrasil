# Multi-Repo Workflow

How to manage deferred work across the Yggdrasil workspace without losing it between sessions.

## The Problem

The workspace at `/Users/cervator/dev/git_ws/` contains multiple independent git repos — nordri, nidavellir, mimir, yggdrasil, vordu, and others — all part of the same ecosystem. During a session, work surfaces across repos: a fix in nordri reveals a gap in nidavellir, a mimir schema change unblocks a vordu feature, etc.

Three failure modes:
1. **TODOs die in chat.** Work noted in conversation context is gone when the session ends.
2. **Context is not portable.** A fresh agent starting a new session has no access to what was discussed.
3. **Notes without action.** Vague "remember to..." entries accumulate without enough specificity for anyone (human or agent) to act on them.

## The Principle

If a fresh agent could pick up a piece of work without needing anything from the current session's context, it belongs in a GitHub issue — not a chat note, not a memory file.

Memory files (MEMORY.md) are for architectural knowledge that is true across sessions. Issues are for discrete work items. Design docs are for decisions that are underspecified or multi-repo in scope.

## Classification Table

When work surfaces during a session, decide where it goes:

| Situation | Where it goes |
|-----------|--------------|
| Needs current session context, coupled to in-progress work, or takes less than 5 minutes | Do it now |
| Isolated to one repo, fully describable, independent, could be done by a fresh agent | GitHub issue |
| Spans multiple repos, needs an architectural decision, or is underspecified | Design doc (in `docs/plans/`) |
| Cross-session architectural knowledge that any agent working in this ecosystem needs | MEMORY.md |

When in doubt between an issue and a design doc: if you can write a clear acceptance criterion, it's an issue. If the first step is "figure out the approach," it's a design doc.

## Session Discipline

### Session start

1. Read `MEMORY.md` in the relevant repo (if one exists).
2. Scan open GitHub issues for repos you expect to touch:
   ```bash
   gh issue list --repo SiliconSaga/nordri --limit 10
   gh issue list --repo SiliconSaga/nidavellir --limit 10
   gh issue list --repo SiliconSaga/mimir --limit 10
   ```
3. Check if any open issues are now unblocked by recent work.

### Session end

1. Identify any loose ends from the session.
2. For each one, classify it using the table above.
3. File GitHub issues for anything delegatable. Be specific: include what the problem is, what the expected outcome is, and any relevant file paths or context a fresh agent would need.
4. Update MEMORY.md if you learned something architectural (a constraint, a dependency, a decision that shouldn't be re-litigated).
5. If work spans repos, note the dependency explicitly (see below).

## Cross-Repo Dependencies

When work in repo A is blocked on or unblocks work in repo B:

- Reference the blocking issue in the blocked issue body: `Blocked by SiliconSaga/nordri#42`
- Add a note to MEMORY.md: `mimir#7 is unblocked once nordri#42 is merged`
- When the blocking work completes, update the blocked issue to reflect the new status

This keeps the dependency visible to both humans reviewing issues and agents scanning MEMORY.md at session start.

## Agent Skills

Two agent skills in `.agent/skills/` support this workflow:

- **`multi-repo-orchestration`** — guides the agent through coordinating work that touches multiple repos in a single session: scoping, sequencing, and handoff
- **`creating-github-issues`** — guides the agent through writing well-formed GitHub issues: title conventions, body structure, label selection, and cross-repo references

These skills are invoked by the agent automatically when the task matches. The workflow described in this doc is the human-facing equivalent of what those skills enforce on the agent side.

## Related Docs

- `docs/ecosystem-architecture.md` — repo map and tier structure
- `docs/github-cli-setup.md` — installing and authenticating `gh`
- `project-constellation.md` — narrative description of each project
