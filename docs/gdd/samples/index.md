# Samples

Historical GDD in action — raw (if condensed) session transcripts and Thalamus files, preserved verbatim from the first two GDD sessions ever. They show the shape of the collaboration — orientation, observations accumulating, housekeeping, cross-workspace hand-offs — but they predate most of today's system (realms, hoards, stances, the `ws k8s` guard), so read them as artifacts of GDD's origin rather than examples of current mechanics.

**For GDD applied to real, recent work, see the [case studies](../case-studies.md)** — those are the better "what does this actually feel like" reading.

Honestly though: transcripts do not do the process justice when condensed, and cannot convey the sense of flow experienced. And who would have time to read an entire session log from Claude spanning hours of work? Maybe if you fed it to a different agent and told it what sort of magic you'd be interested in hearing about :-)

Sometimes the only real way is to just try it yourself. **[Get started here](../../getting-started/index.md)** — clone the workspace, turn on mentoring, and see what happens.

## Session Transcripts

Condensed transcripts of actual development sessions using GDD. Technical implementation details (code diffs, file contents) are stubbed to focus on the human-AI collaboration flow.

- [Session 1: GDD Pilot](session-1-gdd-pilot.md) — first session of "real" GDD just after initial MVP implementation, reworked git add/commit process.
- [Session 2: Review Threads Feature](session-2-review-threads.md) — a parallel session from a workspace on another computer, refactoring code review tooling.

These two sessions ran concurrently and [intersected](#cross-workspace-intersection) when review comments on PR #19 were resolved from the other workspace.

## Thalamus Snapshots

Snapshots of Thalamus files from both workspaces, showing how observations accumulate and get processed through housekeeping.

- [Thalamus: Primary Workspace](thalamus-primary.md) — the main workspace's Thalamus file at the end of the first session
- [Thalamus: Primary Processed](thalamus-processed.md) — the main workspace's Thalamus file after housekeeping
- [Thalamus: Parallel Workspace](thalamus-parallel.md) — the secondary workspace's Thalamus file where review threads were implemented

## Cross-Workspace Intersection

The two sessions intersected at a specific moment: PR #19 (ws commit bodyfile mode) had stale review comments from CodeRabbit and Copilot. The parallel workspace — which was implementing `ws review --resolve` — used its new feature to resolve those threads, validating the tool against a real PR from the other session.

This is documented in both transcripts at the point where it happened.

## What to Look For

When reading these samples, notice:

- How **orientation** sets up the session with minimal friction
- How **observations** accumulate in the Thalamus during work
- How **housekeeping** processes observations into issues, skill updates, and pruned items
- How the **self-improving loop** works — the framework improving itself through use
- How **async collaboration** works — the human adding thoughts to the Thalamus while the agent works
- How **cross-workspace work** can complement each other
