# Guardian Driven Development (GDD)

Guardian Driven Development is a methodology for human-AI collaboration in
software projects. It wraps existing development practices — BDD, TDD, code
review — in a layer of structured guidance that adapts to who's working, what
role they're filling, and how much time they have.

## The Core Insight

AI agents and newer contributors need similar things: clear boundaries,
incremental tasks, safety rails, and enough context to be productive without
close supervision. A methodology that serves one can serve both.

## Key Concepts

- **Filling the gap** — between AI-private memory (invisible to humans) and
  committed project instructions (formal, policy-level), GDD introduces the
  [SecondBrain](second-brain.md): a shared, co-authored thinking space where
  observations, concerns, and preferences live while they're being figured out.

- **Adaptive ceremony** — [roles and modes](roles-and-modes.md) let the
  framework meet you where you are. 15 minutes on your phone? Quick mode.
  Saturday deep dive? Zen mode. First time in the codebase? Mentoring mode.
  Modes compose freely.

- **Trust as a first-class concern** — AI agents read instructions from
  nested project components, and not all of those are trustworthy. GDD's
  [trust hierarchy and black-box safety pattern](trust-and-safety.md) ensure
  the agent logs concerns before they can be overwritten by hostile content.

- **Self-improving through use** — the framework starts minimal and
  [evolves through audit cycles](self-improving-loop.md). Observations become
  skills, friction becomes automation, and the capture heuristics themselves
  get tuned.

## Why "Guardian"?

The name reflects three protective roles:

- **Guarding contributors** from tooling complexity and accidental damage
- **Guarding the codebase** from unsafe or unreviewed changes
- **Guarding the learning process** by making AI explain, not just generate

## Getting Started

1. **Clone the repo** — `git clone` the yggdrasil workspace
2. **Start a session** — the orientation skill guides you through setup
3. **Pick a mode** — Quick for a short session, Zen for deep work,
   Mentoring if you're learning
4. **Work normally** — the framework adapts, captures observations, and
   keeps things safe
5. **Housekeep occasionally** — review what's accumulated, promote the
   good stuff, prune the rest

## Design Principles

1. **Incremental by default** — every artifact is useful on its own
2. **Meet people where they are** — adapt to the role and mode
3. **Transparency over magic** — show what the AI is doing and why
4. **Safety through structure** — prevent damage without preventing contribution
5. **Teach, don't just do** — in mentoring mode, grow the human
6. **Evolve through use** — the framework refines itself through audit cycles

## Learn More

- [Roles and Modes](roles-and-modes.md) — how GDD adapts to who you are and what you're doing
- [The SecondBrain](second-brain.md) — shared thinking space between human and AI
- [Trust and Safety](trust-and-safety.md) — trust hierarchy, black-box pattern, community responsibility
- [The Self-Improving Loop](self-improving-loop.md) — how the framework evolves through use
- [GDD Design Doc](../plans/2026-03-12-gdd-design.md) — full methodology design
- [SecondBrain Design](../plans/2026-03-22-secondbrain-design.md) — detailed spec
- [Implementation Plan](../plans/2026-03-22-gdd-implementation-plan.md) — what's built and what's next
