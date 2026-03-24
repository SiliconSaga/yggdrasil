# Sessions

GDD in action — real session transcripts and artifacts showing how the methodology works in practice.

Note that these are raw (if condensed) transcripts and early 2nd brain files verbatim from points in time of the first two GDD sessions ever. Their content and methods will go out of date in no time and entirely vary between users of the system.

## Session Transcripts

Condensed transcripts of actual development sessions using GDD. Technical implementation details (code diffs, file contents) are stubbed to focus on the human-AI collaboration flow.

- [Session 1: GDD Pilot](session-1-gdd-pilot.md) — first session of "real" GDD just after initial MVP implementation, reworked git add/commit process.
- [Session 2: Review Threads Feature](session-2-review-threads.md) — a parallel session from a workspace on another computer, refactoring code review tooling.

These two sessions ran concurrently and [intersected](#cross-workspace-intersection) when review comments on PR #19 were resolved from the other workspace.

## SecondBrain Snapshots

Snapshots of SecondBrain files from both workspaces, showing how observations accumulate and get processed through housekeeping.

- [SecondBrain: Primary Workspace](secondbrain-primary.md) — the main workspace's 2nd brain file at the end of the first session
- [SecondBrain: Primary Processed](secondbrain-processed.md) — the main workspace's 2nd brain file after housekeeping
- [SecondBrain: Parallel Workspace](secondbrain-parallel.md) — the secondary workspace's 2nd brain file where review threads were implemented

## Cross-Workspace Intersection

The two sessions intersected at a specific moment: PR #19 (ws commit bodyfile mode) had stale review comments from CodeRabbit and Copilot. The parallel workspace — which was implementing `ws review --resolve` — used its new feature to resolve those threads, validating the tool against a real PR from the other session.

This is documented in both transcripts at the point where it happened.

## What to Look For

When reading these samples, notice:

- How **orientation** sets up the session with minimal friction
- How **observations** accumulate in the SecondBrain during work
- How **housekeeping** processes observations into issues, skill updates, and pruned items
- How the **self-improving loop** works — the framework improving itself through use
- How **async collaboration** works — the human adding thoughts to the SecondBrain while the agent works
- How **cross-workspace work** can complement each other
