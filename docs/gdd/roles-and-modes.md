# Roles and Modes

GDD doesn't assign people to fixed categories. Instead, it defines **roles**
(what you're doing right now) and **modes** (how the framework adapts its
behavior). A person can switch roles between sessions or even within one.

## Roles

| Role | Focus |
|------|-------|
| **Developer** | Writing and shipping code |
| **Designer** | Defining behavior (scenarios, specs) |
| **Reviewer** | Quality and safety |
| **Scribe** | Note-taking and vault work — PARA layout, frontmatter, daily notes, capture-process-organize loop |
| **AI Agent** | Any of the above, bounded by permissions |

Roles aren't skill levels. A first-time contributor and a 20-year veteran
can both be in the Developer role — they'll just have different modes active.

Today only the **Scribe** role has dedicated skill files (`scribe`
plus the auto-loaded `scribe-claudesidian` extension); the other
roles are the assumed default and rely on mode and practice skills
rather than a single role file.

## Modes

Modes modify how the framework behaves. They compose freely.

### Mentoring

The AI explains decisions, teaches practices in context, and offers more
scaffolding. Not tied to seniority; anyone can request it. First time
touching BDD? Ask for Mentoring mode, even if you've been coding for a decade.

The AI's job in Mentoring mode is to **grow the human**, not just ship the
code. Every interaction is an opportunity to transfer understanding.

### Quick

Minimal ceremony for short time windows. You have 15 minutes on your phone
between responsibilities? Quick mode suggests appropriately-sized tasks,
recovers context fast, and skips questions it can infer.

Session sizing examples:
- **15 min:** Write one BDD scenario, review one PR comment, fix one small bug
- **30 min:** Implement step definitions, triage review findings, write a skill stub
- **45 min:** End-to-end small feature with PR

### Zen

Full ceremony for deep focus sessions. Saturday morning deep dive? Zen mode
leans into thorough brainstorming, comprehensive reviews, auditing accumulated
concerns, and completing large chunks of work end-to-end.

Zen mode may proactively suggest housekeeping if observations have accumulated
in the Thalamus.

### Flow

Adaptive ceremony for sessions that drift productively across multiple topics.
The agent matches the human's rhythm, incorporates tangents naturally, and
treats the Thalamus as a live collaboration surface rather than a
session-bookend artifact. Often the natural default when no mode is set.

Modes compose freely — a learning contributor might run Mentoring + Quick on
a busy day, or Zen + Mentoring for a deep teaching session. The per-mode
skills under `.agent/skills/gdd-<mode>/SKILL.md` describe the specific
behavior modifiers each mode applies.
