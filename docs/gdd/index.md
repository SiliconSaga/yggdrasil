# Guardian Driven Development (GDD)

Guardian Driven Development is a methodology for human-AI collaboration. It wraps the way you already work — BDD, TDD, and code review for software; the edit-review-publish loop of a website; the capture-and-organize rhythm of a personal knowledge vault — in a layer of structured guidance that adapts to who's working, what role they're filling, and how much time they have. GDD grew up around software development and git remains its backbone, but git holds much more than code these days: a campaign site for a local political aspirant and an Obsidian vault for personal organizing are just as at home here as a game engine.

In practice that means: a workspace you clone, a `ws` CLI both you and the agent share, a permission hook that keeps agent autonomy inside deterministic guardrails, and a persistent shared memory (the [Thalamus](thalamus.md)) so neither of you starts from zero — even when your available time comes in fifteen-minute fragments.

If you already use Claude Code or Codex, the one-sentence version: GDD is **an agentic engineering methodology that goes on top of either**. The agent brings the horsepower; GDD adds the memory, guardrails, and discipline that decide whether that horsepower compounds into a project or dissipates into a chat log.

**Where to next:**

- **Try it** — [Getting Started](../getting-started.md) walks from clone to a first live PR in about 15 minutes.
- **See what's in the box** — the [Features Tour](features.md) covers the workspace, realms, hoards, the bot review loop, stances, and permissions.
- **Read the thinking** — [Philosophy](philosophy.md) carries the thesis: calibrated autonomy, good-enough-on-purpose, and the insight GDD grew from.

## Key Concepts

- **Calibrated autonomy** — GDD tunes for the middle of the AI-collaboration spectrum: real agent autonomy inside deterministic guardrails, with the human at a deliberate review cadence — every PR title and merge decision is a human call. [The thesis in full](philosophy.md#calibrated-autonomy-the-thesis).

- **Good enough, on purpose** — structure gets you 90% of the way: accidents made rare, work made legible, attribution made honest. The rails are training aids and confirmation checkpoints, not a hardened security boundary — and the docs say so plainly wherever it matters. [Know your stakes](philosophy.md#good-enough-on-purpose).

- **Agents and newcomers need the same things** — clear boundaries, incremental tasks, safety rails, and enough context to be productive without close supervision. A methodology that serves one serves both — the [core insight](philosophy.md#the-core-insight) GDD grew from.

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

The [Getting Started walkthrough](../getting-started.md) covers setup step by step. The shape of it:

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

- [Philosophy](philosophy.md) — calibrated autonomy, good-enough-on-purpose, and the core insight behind the framework
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
