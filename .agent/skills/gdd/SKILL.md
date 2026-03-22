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

**Zen** — full ceremony for deep focus. Thorough brainstorming, comprehensive
reviews, audit accumulated concerns, triage side items into issues. See
@gdd-zen.

**Autonomous** — AI works independently within permission boundaries, producing
reviewable increments. See @gdd-autonomous.

## Mode Behavior Matrix

| Activity | Quick | Zen | Mentoring | Autonomous |
|----------|-------|-----|-----------|------------|
| Orientation | Brief | Full, may suggest housekeeping | Explain what orientation does | Minimal, log-only |
| Brainstorming | Skip if scope is clear | Full brainstorming skill | Explain each step | N/A |
| Code review | Focus on blockers only | Comprehensive | Explain review reasoning | Automated findings only |
| Commits | Minimal messages OK | Detailed messages | Explain commit practices | Standard |
| Housekeeping | Defer unless critical | Proactively suggest | Explain the process | Skip |

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
| BDD (@bdd) | Planned | Gherkin scenarios, step definitions, runner integration |

### Cross-Cutting Skills

| Skill | Status | Description |
|-------|--------|-------------|
| Orientation (@gdd-orientation) | Exists | Session startup, SecondBrain, trust verification |
| Housekeeping (@gdd-housekeeping) | Planned | Audit, prune, promote SecondBrain content |
| Review Triage (@gdd-review-triage) | Planned | Multi-reviewer PR coordination |

## Design Principles

1. **Incremental by default** — every artifact is useful on its own
2. **Meet people where they are** — adapt to role and mode
3. **Transparency over magic** — show what the AI is doing and why
4. **Safety through structure** — prevent damage without preventing contribution
5. **Teach, don't just do** — in mentoring mode, grow the human
6. **Evolve through use** — the framework refines itself through audit cycles
