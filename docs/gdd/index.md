# Guardian Driven Development (GDD)

Guardian Driven Development is a methodology for human-AI collaboration in software projects. It wraps existing development practices — BDD, TDD, code review — in a layer of structured guidance that adapts to who's working, what role they're filling, and how much time they have.

## Calibrated Autonomy — the thesis

GDD sits deliberately in the middle of the AI-collaboration spectrum. On one end, AI as fancy auto-complete — useful, but the human still writes every meaningful decision. On the other end, vibe coding or autonomous swarms where the human launches work and comes back to an agent-provided summary plus passing tests, trusting the result without reviewing line-by-line. Both ends work for their use cases — plenty of people are happy with one or the other, and home / internal / lower-stakes software often doesn't need anything heavier than that. GDD doesn't try to replace either extreme.

What it tunes for is the middle band: software you intend to maintain, learn from while building, and grow with — your code, your agent, and (when you have one) your community evolving together. The human stays involved at a regular cadence — not every commit (the agent often increments through several before a review pause), but every PR title and merge decision is a deliberate human call; pushes to topic branches are often comfortable to auto-approve once the workflow's familiar. The [PreToolUse hook](agent-training.md), the `ws orient` discovery surface, and the wrapper-first reflex contract together support this rhythm — the structural reason a human and an agent can stay in sync without ceremony getting in the way.

This positioning enables a community angle that the other extremes don't naturally surface. An agent paired with a project and the humans around it can become a meaningful participant — not just a code generator for one human, but a collaborator that respects shared workspace integrity, flags risks that affect other contributors, and refuses to participate in actions that would compromise the project (while making clear the human is free to act on their own). That pattern is a workflow choice; GDD is built to make it natural when you want it.

## Good Enough, On Purpose

GDD is the "good enough" workspace — and that's a design statement, not an apology. It doesn't try to be a hardened security boundary: the hook tiers are training aids and confirmation checkpoints, and real authorization lives server-side in RBAC and token scopes. It doesn't try to be perfect, and it doesn't promise that every line got a deep review — the human sets the review cadence, and "merge as good enough, split the findings into follow-ups" is a first-class move here, not a lapse. What GDD does is get you 90% of the way with structure: accidents made rare, work made legible, attribution made honest.

Know your stakes. If you operate medical devices or rockets, you need regimes with harder guarantees than GDD makes — don't run those on "good enough." For a great many people, though — especially those arriving at the dawn of personalized software, building things for themselves and their communities that simply wouldn't exist otherwise — good enough is exactly enough.

This honesty repeats deliberately across the framework: the [Kubernetes guard](features.md#kubernetes-practice-guard--ws-k8s) is "accident-prevention, not a security boundary," the hook's redirect tier is "a training aid, not a safety floor." [Trust and Safety](trust-and-safety.md) states plainly what each rail does and doesn't promise, so you can decide where your stakes sit.

## The Core Insight

AI agents and newer contributors need similar things: clear boundaries, incremental tasks, safety rails, and enough context to be productive without close supervision. A methodology that serves one can serve both.

GDD grew out of open-source community work, where contributors range from experienced maintainers to first-time coders, and where AI is reshaping how people learn and contribute. As traditional mentorship paths erode — in both OSS and commercial settings — GDD is an attempt to put something helpful out there: a way for humans and AI to collaborate productively, where the AI teaches alongside generating, and the framework keeps everyone safe while they learn.

It also encourages what researchers call the "cyborg" approach to AI collaboration ([Bhargava, 2026](https://www.businessinsider.com/ai-impact-on-thinking-cognitive-skills-researcher-2026-3); [Mollick, 2023](https://www.oneusefulthing.org/p/centaurs-and-cyborgs-on-the-jagged)) — rather than outsourcing thinking to AI or using it as an echo chamber, you develop an iterative back-and-forth where both human and agent build on each other's contributions. The [Thalamus](thalamus.md) serves as shared working memory for this collaboration. This has been the author's experience while developing the framework.

The name "Guardian" reflects this protective intent — and it runs both ways. The AI isn't just a code generator: it's a patient collaborator that explains its reasoning, flags risks, and helps people grow. The human is equally the *agent's* guardian — reviewing its work, approving its riskier moves, and shielding it from untrusted instructions it may encounter. (GDD always expands to **Guardian Driven Development** — no other expansion is correct.) In a world where it's tempting to use AI purely as a throughput amplifier, GDD asks: what if we also used it to make the experience of building software more human?

## Key Concepts

- **Filling the gap** — between AI-private memory (invisible to humans) and committed project instructions (formal, policy-level), GDD introduces the [Thalamus](thalamus.md): a shared, co-authored thinking space where observations, concerns, and preferences live while they're being figured out.

- **Adaptive ceremony** — [roles and stances](roles-and-stances.md) let the framework meet you where you are. 15 minutes on your phone? Quick stance. Saturday deep dive? Zen stance. First time in the codebase? Turn on the mentoring overlay. Stances and overlays compose freely.

- **Trust as a first-class concern** — AI agents read instructions from nested project components, and not all of those are trustworthy. GDD's [trust hierarchy and black-box safety pattern](trust-and-safety.md) ensure the agent logs concerns before they can be overwritten by hostile content.

- **Self-improving through use** — the framework starts minimal and [evolves through audit cycles](self-improving-loop.md). Observations become skills, friction becomes automation, and the capture heuristics themselves get tuned.

## Why "Guardian"?

The name reflects several protective roles:

- **Guarding contributors** from tooling complexity and accidental damage
- **Guarding the codebase** from unsafe or unreviewed changes
- **Guarding the learning process** by having the agent mentor, not just generate
- **Guarding the AI** from nested instructions that may conflict or be unsafe
- **Helping guardians** of actual human dependents make do with "found" snippets of time

The last entry relates to the original more amusing "Dad-Driven-Development" name from the author's struggles finding meaningful development time while raising young children.

## Getting Started

The [Getting Started walkthrough](../getting-started/index.md) covers setup step by step. The shape of it:

1. **Clone the repo** — `git clone` the yggdrasil workspace
2. **Start a session** — the orientation skill guides you through setup
3. **Pick a stance** — Quick for a short session, Zen for deep work, or add the mentoring overlay if you're learning
4. **Work normally** — the framework adapts, captures observations, and keeps things safe
5. **Housekeep occasionally** — review what's accumulated, promote the good stuff, prune the rest

## Design Principles

1. **Incremental by default** — every artifact is useful on its own
2. **Meet people where they are** — adapt to the role and stance
3. **Transparency over magic** — show what the AI is doing and why
4. **Safety through structure** — prevent damage without preventing contribution
5. **Teach, don't just do** — in the mentoring overlay, grow the human
6. **Evolve through use** — the framework refines itself through audit cycles

## Learn More

**Feature tour** (start here if you want to know what's in the box):

- [Features Tour](features.md) — what GDD ships: workspace, realms, hoards, components, bot review loop, stances, permissions
- [Hoards](hoards.md) — personal containers including the canonical thalami type, cadence config, multi-machine sync

**Methodology and concepts:**

- [Roles and Stances](roles-and-stances.md) — how GDD adapts to who you are and what you're doing
- [The Thalamus](thalamus.md) — shared thinking space between human and AI
- [Trust and Safety](trust-and-safety.md) — trust hierarchy, black-box pattern, community responsibility
- [Permissions](permissions.md) — `.claude/settings.json` reference and the two-layer defense model (local shell commands)
- [Agent Training](agent-training.md) — the PreToolUse hook, the "scary red" deny output new users see early in a session, why one-action-per-call doesn't double API cost
- [Access](access.md) — identities, tokens, and remote Git operations (the companion to Permissions)
- [The Self-Improving Loop](self-improving-loop.md) — how the framework evolves through use
- [Versioning & Releases](versioning.md) — what is versioned (workspace + `ws` CLI together), the changelog workflow, and the change-note tooling decisions
- [Organization Stack](organization-stack.md) — four-tier capture model (Vault → Thalami → Docs → GitHub), the scribe and GDD ceremonies, and the Intake bridge

**Where it's going and where it's been:**

- [Roadmap](roadmap.md) — what's next after 1.0: more agents (Codex in progress; Gemini/Antigravity on deck), more tutorials, team collaboration
- [Case Studies](case-studies/index.md) — GDD on real work: reviewing a contributor's PR from a phone, a non-technical owner's campaign site, parallel-workspace development, and more
- [Early GDD](case-studies/early-gdd.md) — session transcripts and Thalamus snapshots preserved from GDD's first sessions

**Design archive** (historical — the original design documents, kept as the record of how GDD took shape; the docs above describe the current system):

- [GDD Design Doc](../plans/2026-03-12-gdd-design.md) — the original methodology design
- [Thalamus Design](../plans/2026-03-22-secondbrain-design.md) — the original spec (the concept began as "SecondBrain")
- [Implementation Plan](../plans/2026-03-22-gdd-implementation-plan.md) — the first build-out plan
