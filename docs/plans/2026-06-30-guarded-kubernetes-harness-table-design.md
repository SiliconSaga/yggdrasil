# Guarded Kubernetes harness comparison design

**Date:** 2026-06-30

**Status:** Approved for implementation

## Goal

Update the guarded Kubernetes tutorial for the current session-lifetime and Codex hook behavior while keeping the tutorial OSS-first, useful to end users, and easy to extend when another agent harness gains verified support.

## Scope

Modify only `docs/tutorials/guarded-kubernetes.md`. Treat `hoards/thalami-Cervator/TestPrimer-mentoring-k8s.md` as review evidence and a one-time validation artifact, not as user-facing documentation to maintain in this change.

## Tutorial changes

1. Correct the session-lifetime explanation: a scope is stored per session, but ended-session files can linger and affect ambient aggregation until `ws clean --sessions-all` removes stale sessions.
2. Rename the agent chapter so the heading does not expose Claude's internal “Tier 2b” terminology as a cross-harness concept.
3. Add one compact comparison table covering Claude Code and Codex hook setup, raw reads, raw writes, script catching, safe-call routing, bypass behavior, and audit location.
4. Structure the table so Gemini, Antigravity, or another harness can be added as a row only after its capabilities are verified.
5. Add a subtle, vendor-neutral note that managed environments may restrict shell network access. In that case the agent can continue mentoring while a human terminal executes guarded `ws k8s`; plain-terminal calls use the wrapper's ambient scope rather than the agent hook.
6. Replace rejection examples that assume `default` is meaningful with a named `<blocked-ns>` chosen before the exercise, while retaining concrete examples where a Kubernetes system namespace is intentionally illustrative.
7. Keep parser and edge-case validation in the TestPrimer. Do not expand the learner tutorial with attached short flags, auth/config mutation cases, or exhaustive manifest fixtures.

## Documentation behavior

The main Chapters 1–3 remain harness-neutral and teach the wrapper contract. Harness differences appear in the agent-path chapter after the learner understands the guard itself. New prose uses single-line paragraphs and maintains the tutorial's moderately formal mentoring register.

## Verification

- Search the tutorial for stale “scope clears when the session ends,” Claude-only hook assumptions, and hardcoded out-of-scope `default` examples.
- Verify all relative links resolve to existing repository files.
- Run the focused tutorial/navigation tests if present, then `ws test yggdrasil` because the workspace Bats suite is the wired root validation.
- Review the rendered Markdown structure mentally: table columns remain readable, paragraphs are not hard-wrapped, and the tutorial flow still works without an agent.

## Follow-up findings

Report but do not fold into this tutorial edit:

- The one-time TestPrimer currently says Claude and Codex both auto-allow raw reads without a prompt; Codex now defers safe calls to normal sandbox and approval routing.
- `.agent/skills/gdd-k8s/SKILL.md` still describes raw interception as Claude-only and says scope files clear automatically when a session ends. That skill should be corrected in a separate focused change or review round unless the current CR scope is explicitly expanded.
