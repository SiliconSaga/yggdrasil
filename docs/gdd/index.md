# Guardian Driven Development (GDD)

Guardian Driven Development is a methodology for human-AI collaboration in
software projects. It wraps existing development practices — BDD, TDD, code
review — in a layer of structured guidance that adapts to who's working, what
role they're filling, and how much time they have.

## The Core Insight

AI agents and newer contributors need similar things: clear boundaries,
incremental tasks, safety rails, and enough context to be productive without
close supervision. A methodology that serves one can serve both.

GDD grew out of open-source community work, where contributors range from experienced maintainers to first-time coders, and where AI is reshaping how people learn and contribute. As traditional mentorship paths erode — in both OSS and commercial settings — GDD is an attempt to put something helpful out there: a way for humans and AI to collaborate productively, where the AI teaches alongside generating, and the framework keeps everyone safe while they learn.

It also encourages what researchers call the "cyborg" approach to AI collaboration ([Bhargava, 2026](https://www.businessinsider.com/ai-impact-on-thinking-cognitive-skills-researcher-2026-3); [Mollick, 2023](https://www.oneusefulthing.org/p/centaurs-and-cyborgs-on-the-jagged)) — rather than outsourcing thinking to AI or using it as an echo chamber, you develop an iterative back-and-forth where both human and agent build on each other's contributions. The [Thalamus](thalamus.md) serves as shared working memory for this collaboration. This has been the author's experience while developing the framework.

The name "Guardian" reflects this protective intent. The AI isn't just a code generator — it's a patient collaborator that explains its reasoning, flags risks, and helps people grow. In a world where it's tempting to use AI purely as a throughput amplifier, GDD asks: what if we also used it to make the experience of building software more human?

## Key Concepts

- **Filling the gap** — between AI-private memory (invisible to humans) and
  committed project instructions (formal, policy-level), GDD introduces the
  [Thalamus](thalamus.md): a shared, co-authored thinking space where
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

The name reflects several protective roles:

- **Guarding contributors** from tooling complexity and accidental damage
- **Guarding the codebase** from unsafe or unreviewed changes
- **Guarding the learning process** by having the agent mentor, not just generate
- **Guarding the AI** from nested instructions that may conflict or be unsafe
- **Helping guardians** of actual human dependents make do with "found" snippets of time

The last entry relates to the original more amusing "Dad-Driven-Development" name from the author's struggles finding meaningful development time while raising young children.

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
- [The Thalamus](thalamus.md) — shared thinking space between human and AI
- [Trust and Safety](trust-and-safety.md) — trust hierarchy, black-box pattern, community responsibility
- [The Self-Improving Loop](self-improving-loop.md) — how the framework evolves through use
- [Samples](samples/index.md) — session transcripts, Thalamus snapshots, GDD in action
- [GDD Design Doc](../plans/2026-03-12-gdd-design.md) — full methodology design
- [Thalamus Design](../plans/2026-03-22-secondbrain-design.md) — detailed spec
- [Implementation Plan](../plans/2026-03-22-gdd-implementation-plan.md) — what's built and what's next
