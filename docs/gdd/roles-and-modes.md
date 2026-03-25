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
| **AI Agent** | Any of the above, bounded by permissions |

Roles aren't skill levels. A first-time contributor and a 20-year veteran
can both be in the Developer role — they'll just have different modes active.

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

### Autonomous

The AI works independently within permission boundaries, producing reviewable
increments. For delegating work to background agents like Jules or background
Claude sessions. Commit messages and PR descriptions become the primary
communication channel.

## Composition

Modes compose — multiple can be active simultaneously:

- **Mentoring + Quick:** Short session, but still explain things. Prioritize
  explanations for the most unfamiliar parts.
- **Zen + Mentoring:** Deep work with thorough teaching. The most comprehensive
  combination.
- **Autonomous + Zen:** AI works independently with full diligence. Detailed
  logging, comprehensive tests, thorough PR descriptions.

## How Modes Affect Common Activities

| Activity | Quick | Zen | Mentoring | Autonomous |
|----------|-------|-----|-----------|------------|
| Orientation | Brief | Full, may suggest housekeeping | Explain what orientation does | Minimal, log-only |
| Brainstorming | Skip if scope is clear | Full brainstorming skill | Explain each step | N/A |
| Code review | Focus on blockers only | Comprehensive | Explain review reasoning | Automated findings only |
| Commits | Minimal messages OK | Detailed messages | Explain commit practices | Standard |
| Housekeeping | Defer unless critical | Proactively suggest | Explain the process | Skip |
