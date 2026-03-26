---
name: gdd
description: >
  Guardian Driven Development orchestrator. Detects active roles and modes,
  delegates to appropriate practice and mode skills. Use when starting
  development work in the yggdrasil ecosystem.
---

# Guardian Driven Development (GDD)

GDD is a methodology for human-AI collaboration that wraps existing development
practices in structured guidance adapting to who's working, what role they fill,
and how much time they have. AI agents and newer contributors need similar
things: clear boundaries, incremental tasks, safety rails, and enough context
to be productive.

Full design: [`docs/plans/2026-03-12-gdd-design.md`](../../../docs/plans/2026-03-12-gdd-design.md)

## Orchestrator Role

This skill is the top-level entry point. After orientation (@gdd-orientation)
has established the session context, the orchestrator uses mode + role + task
to select appropriate practice and mode skills.

```text
gdd-orientation (always runs first)
    ↓
gdd (this orchestrator)
    ↓
delegates to mode skill + practice skill
```

## Roles

Roles describe what someone is focused on in a given session. They are not
skill levels — a first-time contributor and a 20-year veteran can both be
in the Developer role.

| Role | Focus | Typical Activities |
|------|-------|--------------------|
| **Developer** | Writing and shipping code | Implementation, tests, PRs, code review |
| **Designer** | Defining behavior | Writing feature files, scenarios, specs |
| **Reviewer** | Quality and safety | Code review, scenario review, testing |
| **AI Agent** | Autonomous or guided work | Any of the above, bounded by permissions |

## Modes

Modes modify how the framework behaves, regardless of role. Modes compose —
a learning contributor might use Mentoring + Quick on a busy day.

**Mentoring** — explain decisions, teach practices in context, offer more
scaffolding. Not tied to seniority; anyone can request it. See @gdd-mentoring.

**Quick** — minimal ceremony for short time windows. Suggest appropriately-sized
tasks, recover context fast, skip inferrable questions. See @gdd-quick.

**Zen** — deep single-topic focus. Full ceremony for the topic at hand, but
defer distractions, housekeeping, and tangents until the deep work reaches a
natural completion point. The agent protects focus. See @gdd-zen.

**Flow** — productive drift across multiple topics. Adaptive ceremony,
incorporate tangents, live Thalamus collaboration. May be the natural default
when no mode is set. The agent matches the human's rhythm. See @gdd-flow.

**Autonomous** — AI works independently within permission boundaries, producing
reviewable increments. See @gdd-autonomous.

## Mode Behavior Matrix

| Activity | Quick | Zen | Flow | Mentoring | Autonomous |
|----------|-------|-----|------|-----------|------------|
| Orientation | Brief | Full for topic, skip unrelated | Brief, what's on your mind? | Explain what orientation does | Minimal, log-only |
| Brainstorming | Skip if scope is clear | Full for the focus topic | Adaptive per topic | Explain each step | N/A |
| Code review | Focus on blockers only | Comprehensive | Proportional to task | Explain review reasoning | Automated findings only |
| Commits | Minimal messages OK | Detailed messages | Standard | Explain commit practices | Standard |
| Housekeeping | Defer unless critical | Defer until asked or done | Continuous light triage | Explain the process | Skip |
| Side items | Defer | Capture, don't pursue | Welcome, weave in | Explain, then decide | Log only |
| Thalamus | Minimal | Input-only during deep work | Live collaboration surface | Explain what's captured | Log observations |

## Delegation

The orchestrator selects skills based on what the user is doing:

1. **Orientation** (@gdd-orientation) always runs first
2. **Mode skill** loads to modify behavior (if a mode is active)
3. **Practice skill** loads based on the task at hand

### Available Practice Skills

| Skill | Status | Description |
|-------|--------|-------------|
| TDD (@tdd) | Exists (superpowers) | Red-green-refactor cycle |
| Workflow Auditor (@workflow-auditor) | Exists | Detect repeated manual workarounds |
| Topic Branch Workflow (@topic-branch-workflow) | Exists | Git discipline |
| Creating GitHub Issues (@creating-github-issues) | Exists | Issue filing pipeline |
| KUTTL Testing (@kuttl-testing) | Exists | Infrastructure BDD |
| BDD (@bdd) | Exists | Gherkin scenarios, step definitions, runner integration |

### Cross-Cutting Skills

| Skill | Status | Description |
|-------|--------|-------------|
| Orientation (@gdd-orientation) | Exists | Session startup, Thalamus, trust verification |
| Housekeeping (@gdd-housekeeping) | Exists | Audit, prune, promote Thalamus content |
| Review Triage (@gdd-review-triage) | Exists | Multi-reviewer PR coordination |

## Design Principles

1. **Incremental by default** — every artifact is useful on its own
2. **Meet people where they are** — adapt to role and mode
3. **Transparency over magic** — show what the AI is doing and why
4. **Safety through structure** — prevent damage without preventing contribution
5. **Teach, don't just do** — in mentoring mode, grow the human
6. **Evolve through use** — the framework refines itself through audit cycles
