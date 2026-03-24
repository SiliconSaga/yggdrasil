# SecondBrain: Parallel Workspace

Snapshot of the SecondBrain file from the parallel workspace at the end of the review threads session (Session 2).

# SecondBrain frontmatter — read by orientation skill on session start

```
last_session: 2026-03-23
last_audit: null
mode: zen
role: developer
staleness_days: 14
```

# SecondBrain

Shared thinking space between one human and one local AI agent (at a time).
Created from `.agent/secondbrain-template.md`. This file is gitignored —
it is local to this workspace instance.

## Preferences
<!-- Mode defaults, interaction style, session habits -->
- Zen mode / Developer role as default
- Checking in occasionally throughout the day — async-friendly pacing

## Observations
<!-- Patterns noticed, friction points, things that worked well -->
- **ws script architecture (2026-03-23):** The inline-vs-standalone split in `ws` is chronological accident, not principled. `ws` is 622 lines and growing. Need to formalize criteria for when a command earns its own script. Related: `ws commit` is being refactored in another workspace, `ws test` could be split out later. Small delegators (push, issue) are fine inline. File a GitHub issue to track this — candidate for `docs/ws-cli-guide.md` update.
- **ws review is agent-first (2026-03-23):** Deep review utility commands (threads, comments, resolve) are primarily for AI agents, not humans (who use the GitHub GUI). Design decisions should optimize for agent ergonomics — non-interactive, clear output, composable flags.
- **GraphQL expansion path (2026-03-23):** `ws review threads` is the first GraphQL consumer. If we accumulate 4-5+ queries, consider migrating to Approach 3 (queries in `scripts/graphql/*.graphql`, loaded at runtime). Doc this in the design spec.
- **Rename `ws resolve` (2026-03-23):** `ws resolve` (ArgoCD manifest generation) collides conceptually with `ws review ... --resolve` (review thread resolution). Consider renaming to something ArgoCD-specific — `ws render`, `ws generate`, `ws materialize`? File as a separate issue.
- **Spec location convention (2026-03-23):** Superpowers defaults to `docs/superpowers/specs/` but the workspace already has `docs/plans/` for design docs. Need to pick one and document the convention. Candidate: keep `docs/plans/` as the workspace standard, override the Superpowers default.
- **Worktrees (2026-03-24):** Not yet used in this workspace. Superpowers skill wants them for isolation but feels overkill at current scale. Revisit when feature work gets complex enough to warrant parallel branches. Need to decide: `.worktrees/` (project-local) vs global location, and add gitignore entry before first use.
- Human note: I saw a "● Bash(git checkout main && git pull siliconsaga main)" when switching into plan execution / implementation. That's a good practice to keep up to date, but I wonder what would happen if there were upstream changes causing conflicts (I am actively using workspaces on two different systems and almost trying to cause conflicts as a test anyway). It would certainly be abrupt if nothing else (went from "creating topic branch" to pulling, without any real word other than an assumption we should do that). I also wonder in general how we would handle conflicts and rebasing in a busy workspace (even without considering worktrees)
- **Agent response (2026-03-24):** Valid concern. The agent should (1) announce intent before switching branches/pulling, (2) check for uncommitted work first, (3) handle pull conflicts gracefully rather than assuming clean-merge. Multi-system conflict handling and rebasing strategy deserves its own discussion — could become a skill or at least documented in the topic-branch-workflow skill.
- Human note: Hmm, the creation of a PR triggered an unexpected approval request. From "mkdir -p .prs && cat > .prs/ws-review-threads.md << 'PREOF'" to "Command contains quoted characters in flag names" as the request. Is that because you inlined the creation of the file with mkdir, cat, etc, instead of just using a file writing tool?
- **Agent response (2026-03-24):** Yes — should have used the Write tool instead of `cat` with heredoc. System instructions explicitly say to prefer Write for file creation. The heredoc syntax triggered the approval prompt because it looked like a suspicious command pattern.
- And this one -  is this because we have the PR title as an argument, or does that count as one since quotes and we just don’t have a single * for that parameter position yet? In the other workspace we just improved the commit process to use a bodyfile for the commit title and file list. Is it time yet to add that for PRs? Maybe we have an issue for that already. You could even check the content of PR 19 to learn what we’re doing in the other workspace.
  - `Yes, and don’t ask again for: bash scripts/ws pr yggdrasil "feat(ws): add threads subcommand for PR review thread management" .prs/ws-review-threads.md`
- **Agent response (2026-03-24):** The `ws pr` prompt was correct — it’s Side-effect tier, so it should prompt. PR #19 in the other workspace adds bodyfile-only mode for `ws commit` (title in frontmatter). Same pattern could work for `ws pr` — title in the bodyfile frontmatter, avoiding quoted-string-as-argument. Good candidate for a follow-up issue (which it turns out we already have as #16).

## Concerns
<!-- Trust issues, suspicious instructions, safety flags — write IMMEDIATELY -->

## Audit Log
<!-- When was the last review? What was promoted/pruned? -->