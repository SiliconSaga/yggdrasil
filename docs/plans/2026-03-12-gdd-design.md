# Guardian Driven Development (GDD) — Design

**Date:** 2026-03-12
**Status:** Draft
**Explainer:** [What is GDD?](../gdd/index.md) (reader-facing overview)

---

## What is GDD?

Guardian Driven Development is a methodology for human–AI collaboration in
software projects. It wraps existing development practices (BDD, TDD, code
review) in a layer of structured guidance that adapts to who's working, what
role they're filling, and how much time they have.

The core insight: AI agents and newer contributors need similar things —
clear boundaries, incremental tasks, safety rails, and enough context to be
productive without close supervision. A methodology that serves one can serve
both.

GDD grew out of open-source community work, where contributors range from
experienced maintainers to first-time coders, and where AI is reshaping how
people learn and contribute. As junior developers lose traditional mentorship
paths — in both OSS and commercial settings — GDD is an attempt to put
something helpful out there: a way for humans and AI to collaborate
productively, where the AI teaches alongside generating, and the framework
keeps everyone safe while they learn.

The name "Guardian" reflects three protective roles:

- **Guarding contributors** from tooling complexity and accidental damage
- **Guarding the codebase** from unsafe or unreviewed changes
- **Guarding the learning process** by making AI explain, not just generate

GDD is designed for OSS but isn't limited to it. If it's useful for a
commercial team, a classroom, or a solo developer — great.

---

## Roles and Modes

GDD doesn't assign people to fixed categories. Instead, it defines **roles**
(what you're doing right now) and **modes** (how the framework adapts its
behavior). A person can switch roles between sessions or even within one.
Multiple roles can be active simultaneously.

### Roles

Roles describe what someone is focused on in a given session:

| Role | Focus | Typical activities |
|------|-------|--------------------|
| **Developer** | Writing and shipping code | Implementation, tests, PRs, code review |
| **Designer** | Defining behavior | Writing feature files, scenarios, specs |
| **Reviewer** | Quality and safety | Code review, scenario review, testing |
| **AI Agent** | Autonomous or guided work | Any of the above, bounded by permissions |

Roles aren't skill levels. A first-time contributor and a 20-year veteran
can both be in the Developer role — they'll just have different modes active.

### Modes

Modes modify how the framework behaves, regardless of role:

**Mentoring mode** — The AI explains decisions, teaches practices in context,
and offers more scaffolding. Active when someone is learning — whether that's
a student writing their first PR or an experienced dev touching an unfamiliar
part of the stack. Not tied to seniority; anyone can request it.

**Quick mode** — Minimal ceremony for short time windows. The framework
suggests appropriately-sized tasks, recovers context fast, and skips questions
it can infer. For when you have 15 minutes on your phone between
responsibilities.

**Zen mode** — Full ceremony for deep focus sessions. The framework leans into
thorough brainstorming, comprehensive reviews, auditing accumulated debt,
triaging side items into issues for later, and completing large chunks of work
end-to-end. For when you have real time and want to make the most of it.

**Autonomous mode** — The AI works independently within permission boundaries,
producing reviewable increments. For delegating work to agents like Jules or
background Claude sessions.

Modes compose: a learning contributor might use Mentoring + Quick mode on a
busy day (short session, but still explain things). An experienced dev might
use Zen mode for a Saturday morning session. An AI agent always has Autonomous
mode active, possibly with Mentoring mode if the eventual reviewer wants to
understand the reasoning.

---

## Skill Architecture

GDD is implemented as a hierarchy of skills. The top-level `gdd` skill
detects context — active roles, modes, available time — and delegates to
the appropriate practice and mode skills.

```text
gdd (orchestrator)
│
│  Modes (modify behavior across all roles)
├── gdd-mentoring     — explanations, graduated autonomy, practice teaching
├── gdd-quick         — context recovery, session sizing, minimal ceremony
├── gdd-zen           — full ceremony, deep work, audit and triage
├── gdd-autonomous    — permission-bounded independent work
│
│  Practice skills (the actual work)
├── bdd               — Gherkin scenarios, step definitions, runner integration
│   ├── bdd-go        — godog integration for Go components
│   ├── bdd-python    — pytest-bdd or behave for Python components
│   └── bdd-kuttl     — infrastructure BDD via kuttl (already exists)
│
├── tdd               — red-green-refactor (superpowers skill, already exists)
├── gdd-workflow-audit   — detect repeated patterns (already exists)
├── gdd-branch-workflow — Git discipline (already exists)
└── creating-github-issues — issue pipeline (already exists)
```

**Not every skill needs to be built.** The orchestrator and BDD skill are the
immediate priorities. Mode skills can start as lightweight context flags,
growing richer as we learn what each mode actually needs in practice.

---

## The Scenario Pipeline

BDD scenarios are the universal unit of work in GDD. Every role can
participate at some stage of the pipeline:

```text
  Write scenario          File issue           Implement & PR
  (Given/When/Then)  →   (GitHub issue)    →  (code + step defs)
       ↓                      ↓                     ↓
  Anyone can do this    Auto from scenario    Developer or AI agent
                        (ws issue or Jules)   picks it up
       ↓                      ↓                     ↓
  Stored as .feature    Tagged & labeled      Vordu shows progress
  in the component      "good first issue"    on the roadmap
```

**Key property:** each stage is independently useful. Writing a scenario is
a complete contribution even if nobody implements it for weeks. Filing an
issue is useful even without a scenario. The pipeline doesn't require
end-to-end completion to deliver value.

**Session sizing:** A 15-minute session might produce one scenario. A
45-minute session might implement step definitions for an existing scenario.
A 2-hour session might go end-to-end. The framework should suggest
appropriately-sized work based on available time.

---

## What Exists Today

| Layer | What's Built | Status |
|-------|-------------|--------|
| Workflow engine | `ws` CLI, permission tiers, `.claude/settings.json` | Functional |
| Process skills | TDD, gdd-workflow-audit, topic-branch, issue filing | Functional |
| BDD artifacts | 20 .feature files across ymir, mimir, vordu | Written, partial automation |
| Visualization | Vordu ingests Cucumber JSON, renders roadmap | Designed, early implementation |
| Session recovery | Memory system (MEMORY.md + memory files) | Functional |
| AI boundaries | Skill system, permission deny rules, ws exec blocked | Functional |
| Code review | Copilot (one-shot), CodeRabbit (continuous), Claude (triage) | Active on PR #8+ |

**Gaps:**
- No session orientation or trust verification of nested components
- No shared thinking space between human and AI (observations lost to chat logs)
- No mode-aware behavior (everyone gets the same experience)
- No session-sizing guidance (what can I do in 15 min?)
- No BDD skill guiding scenario writing or runner integration
- No scenario → issue automation
- No mentoring mode
- No coordinated multi-reviewer workflow (each AI reviewer acts independently)

---

## Thalamus (formerly Thalamus)

The Thalamus extends GDD with a shared, semi-persistent thinking
space between one human and one local AI agent (at a time). Named after the
brain's relay station — it processes and routes input rather than storing it.
It addresses several of the gaps above — session orientation, mode/role
selection, trust verification, and the loss of observations between sessions.

See [Thalamus Design](2026-03-22-secondbrain-design.md) for the full spec.

Key additions to GDD's architecture:

- **`gdd-orientation` skill** (cross-cutting) — session startup, Thalamus
  read/write, trust verification of nested component instructions, black-box
  safety pattern for hostile instruction detection
- **`gdd-housekeeping` skill** (cross-cutting) — audit Thalamus content,
  promote observations to issues/skills/instructions, prune resolved items,
  feed back into capture behavior
- **Thalamus.md** — gitignored file with PARA-inspired frontmatter
  (mode, role, timestamps, staleness threshold) and sections for Preferences,
  Observations, Concerns, and Audit Log
- **Self-improving loop** — sessions capture observations → housekeeping
  promotes them → updated skills change behavior → next housekeeping evaluates
  whether capture improved

---

## What's Next

*Updated 2026-03-22 to reflect Thalamus design work and revised priorities.*

**Phase 1 — Foundation:**
1. **Orientation skill + Thalamus template** — session startup, trust
   verification, mode/role from frontmatter. This unlocks everything else.

**Phase 2 — Orchestration:**
2. **GDD orchestrator skill** — detects context, delegates to mode and
   practice skills. Builds on orientation to know who's working and how.
3. **Scenario → issue automation** — extend `ws` or add a skill that converts
   a .feature scenario into a GitHub issue with proper labels.

**Phase 3 — Housekeeping:**
4. **Housekeeping skill** — audit/prune/promote cycle for Thalamus content.
   Fundamental to the self-improving loop.

**Phase 4 — Documentation:**
5. **Static GDD explainer** — "What is GDD?" docs for newcomers, blog
   references, external audiences. Not operational artifacts, but published
   content explaining the methodology.

**Phase 5 — Review coordination:**
6. **Review triage skill** — orchestrates `ws review --since last-push` with
   the `receiving-code-review` discipline. Fetches new comments, deduplicates
   against already-addressed findings, triages by severity, presents a
   consolidated action list.

**Implemented (initial stubs, evolving through use):**
- **Mentoring mode** — AI explains decisions, teaches practices in context.
- **Quick mode** — session sizing, context recovery, phone-friendly workflows.
- **BDD skill** — how to write scenarios, where to put them, how to run them
  per language (godog, pytest-bdd, kuttl). One of potentially many practice
  skills that plug into the orchestrator.

**Later:**
- **Session collaboration skill** — captures the natural working rhythm between
  human and AI: when to switch from coding to triage to planning, shorthand
  for known tools/reviewers, running audits at session boundaries, filing
  issues for deferred work instead of over-scoping. Adapts communication
  density to the user's current mode and role.
- **Designer onboarding** — low-barrier scenario writing that doesn't require
  local tooling or Git knowledge.

---

## Multi-Reviewer Pattern

GDD embraces multiple AI reviewers with different strengths, coordinated by
a human or a session-context-aware agent (the "referee"):

| Reviewer | Trigger | Strengths | Weaknesses |
|----------|---------|-----------|------------|
| **CodeRabbit** | Continuous (push events) | Broad coverage, lint, consistency | Over-suggests, some false positives |
| **Copilot** | On-demand or auto | Focused code-level findings | Limited context, re-files resolved findings, may go rogue (files PRs instead of reviewing) |
| **Claude (session)** | Manual or skill-invoked | Full session context, can triage across reviewers | Requires active session |

**The workflow:**
1. Automated reviewers (CodeRabbit, Copilot) post findings on the PR
2. The session agent pulls findings via `gh api`
3. Applies the `receiving-code-review` discipline to triage: verify each
   finding against the actual codebase, accept or push back with reasoning
4. Presents a consolidated summary to the human: what's real, what's noise

**Observed behaviors (PR #8):**
- CodeRabbit re-triggers on each push, refining its review incrementally
- Copilot does not re-trigger on push. Use the "Re-request review" button
  in GitHub's reviewer pane to trigger a re-review. Asking via PR comment
  causes Copilot to file a separate fix PR instead of reviewing (#9)
- Copilot does not track resolved threads across re-reviews. It re-files the
  same findings even after they've been addressed and resolved. Expect to
  bulk-resolve stale threads after each Copilot re-review. Use
  `ws review --since prev-push` if a review landed between pushes.
- Some findings conflict (CodeRabbit suggested 20+ mirror permission patterns
  that would over-engineer the config)
- Multiple reviewers *did* catch complementary issues: Copilot found the yq
  hyphen bug, CodeRabbit found the `<body>`/`<bodyfile>` inconsistency

**Key insight:** No single reviewer catches everything, and each has blind
spots. The value is in the combination — but only with a referee who can
triage across all of them. This is a natural fit for the Reviewer role in GDD.

---

## Design Principles

1. **Incremental by default** — every artifact is useful on its own.
2. **Meet people where they are** — adapt to the role and mode, don't force
   everyone through the same ceremony.
3. **Transparency over magic** — show what the AI is doing and why.
4. **Safety through structure** — boundaries that prevent damage without
   preventing contribution.
5. **Teach, don't just do** — in mentoring mode, the AI's job is to grow the
   human, not just ship the code.
6. **Evolve through use** — the framework starts minimal and grows through
   audit cycles. Each housekeeping session refines the skills, templates,
   and capture behavior.
