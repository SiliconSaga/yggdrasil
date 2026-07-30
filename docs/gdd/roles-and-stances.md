# Roles and Stances

GDD defines three independent axes that shape how a session works: **roles** (what kind of work you're doing), **stances** (how the framework adapts its pace and ceremony), and **mentoring** (a composable boolean overlay that teaches as it works). These are set per session in the session file (`ws session set …`), not stored in Thalamus frontmatter.

## Roles

| Role | Focus |
|------|-------|
| **Developer** | Writing and shipping code |
| **Designer** | Defining behavior (scenarios, specs) |
| **Reviewer** | Quality and safety |
| **Scribe** | Note-taking and vault work — PARA layout, frontmatter, daily notes, capture-process-organize loop |

Roles aren't skill levels. A first-time contributor and a 20-year veteran can both be in the Developer role — they'll just have different stances active. The role describes the session's kind of work for both human and agent; the agent operates within it, bounded by the [permission](permissions.md) and [access](access.md) systems.

Today only the **Scribe** role has a dedicated skill file; the other roles are the assumed default and rely on stance and practice skills rather than a single role file.

## Stances

Stances modify the ceremony level and pace of a session. They compose freely with any role and with the mentoring overlay.

### Quick

Minimal ceremony for short time windows. 15 minutes on your phone between responsibilities? Quick stance suggests appropriately-sized tasks, recovers context fast, and skips questions it can infer.

Session sizing examples:
- **15 min:** Write one BDD scenario, review one PR comment, fix one small bug
- **30 min:** Implement step definitions, triage review findings, write a skill stub
- **45 min:** End-to-end small feature with PR

Stance philosophy: quick = minimize ceremony for small rapid interactions. A deferred future idea: quick could one day relax scoped guardrails behind loud disclaimers ("YOLO-lite") — out of scope for current GDD.

### Zen

Full ceremony for deep focus sessions. Saturday morning deep dive? Zen stance leans into thorough brainstorming, comprehensive reviews, auditing accumulated concerns, and completing large chunks of work end-to-end.

Zen stance may proactively suggest housekeeping if observations have accumulated in the Thalamus.

Stance philosophy: zen = shed ceremony for intense focus WITHOUT bypassing any guardrail. Deep work, full integrity.

### Flow

Adaptive ceremony for sessions that drift productively across multiple topics. The agent matches the human's rhythm, incorporates tangents naturally, and treats the Thalamus as a live collaboration surface rather than a session-bookend artifact. Often the natural default when no stance is set.

Stance philosophy: flow = allow meandering but nudge back toward the core objective — even one that shifts mid-session. The target shifts; the discipline of tracking it does not.

## Mentoring

Mentoring is a **boolean overlay**, not a stance. It composes with any stance (Quick + Mentoring, Zen + Mentoring, Flow + Mentoring) and with any role.

When mentoring is on, the AI explains decisions, teaches practices in context, and offers more scaffolding. Not tied to seniority; anyone can activate it. First time touching BDD? Turn on mentoring, even after a decade of coding.

The AI's job with mentoring active is to **grow the human**, not just ship the code — every interaction is an opportunity to transfer understanding.

Mentoring is also the overlay that arms tool-practice workflows. For example, `gdd-k8s` (the guarded-Kubernetes practice skill) activates when mentoring is on and the session involves Kubernetes — guiding the contributor through safe, explained cluster interactions rather than handing them raw `kubectl` commands to run without context.

## See also

- The per-stance skills under `.agent/skills/gdd-<stance>/SKILL.md` (i.e. `gdd-quick`, `gdd-zen`, `gdd-flow`) describe the specific behavior modifiers each stance applies.
- The `gdd-mentoring` overlay skill describes the mentoring composability contract and which practice workflows it arms.
