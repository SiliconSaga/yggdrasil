# Early GDD — the first sessions

*March 2026 — GDD's first two sessions ever, just after the initial MVP.*

Raw (if condensed) session transcripts and Thalamus files, preserved verbatim. They show the shape of the collaboration — orientation, observations accumulating, housekeeping, cross-workspace hand-offs — but predate most of today's system (realms, hoards, stances, the `ws k8s` guard), so read them as artifacts of GDD's origin rather than current mechanics. Terminology reflects the vocabulary at capture time; what these transcripts call "modes" later split into stances, roles, and the mentoring overlay.

What makes them worth keeping is the contrast. Here the methodology barely exists yet: orientation has to be invented over several failed attempts, `ws commit` is being designed mid-session, and the human discovers async Thalamus collaboration by accident while the agent works on something else. Set that against the [v1.0 graduation study](terasology-contributor-review.md), where the same loop runs on an outside contributor's codebase with the human mostly on a phone — the machinery has receded far enough to be driven one-handed.

## Session transcripts

Technical implementation details (code diffs, file contents) are stubbed to focus on the human-AI collaboration flow.

- [Session 1: GDD Pilot](session-1-gdd-pilot.md) — first session of "real" GDD just after initial MVP implementation, reworked git add/commit process.
- [Session 2: Review Threads Feature](session-2-review-threads.md) — a parallel session from a workspace on another computer, refactoring code review tooling.

These two sessions ran concurrently and [intersected](#cross-workspace-intersection) when review comments on PR #19 were resolved from the other workspace.

## Thalamus snapshots

Snapshots of Thalamus files from both workspaces, showing how observations accumulate and get processed through housekeeping.

- [Thalamus: Primary Workspace](thalamus-primary.md) — the main workspace's Thalamus file at the end of the first session
- [Thalamus: Primary Processed](thalamus-processed.md) — the main workspace's Thalamus file after housekeeping
- [Thalamus: Parallel Workspace](thalamus-parallel.md) — the secondary workspace's Thalamus file where review threads were implemented

## Cross-workspace intersection

The two sessions intersected at a specific moment: PR #19 (ws commit bodyfile mode) had stale review comments from CodeRabbit and Copilot. The parallel workspace — which was implementing `ws review --resolve` — used its new feature to resolve those threads, validating the tool against a real PR from the other session.

This is documented in both transcripts at the point where it happened.

## What to look for

When reading these, notice:

- How **orientation** sets up the session with minimal friction
- How **observations** accumulate in the Thalamus during work
- How **housekeeping** processes observations into issues, skill updates, and pruned items
- How the **self-improving loop** works — the framework improving itself through use
- How **async collaboration** works — the human adding thoughts to the Thalamus while the agent works
- How **cross-workspace work** can complement each other

Then notice what is *absent* compared to the v1.0 study: no realms or adapters, no per-machine thalami hoard, no arcs, no permission tiers, no `ws review` triage flow — all of which grew out of friction visible in these very transcripts.

Transcripts don't do the process justice when condensed. Try it yourself — **[Get started here](../../getting-started.md)** — clone the workspace, turn on mentoring, and see what happens.
