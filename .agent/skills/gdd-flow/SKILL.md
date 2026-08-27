---
name: gdd-flow
description: >
  Flow stance — productive drift across multiple tasks with responsive collaboration. The agent surfs the current, incorporating tangents and async input naturally. May be the natural default when no stance is set. Use when working across several topics or overseeing parallel work.
---

# GDD Flow Stance

A behavior modifier for productive, multi-topic sessions where the rhythm
matters more than the destination. The agent's role is **dance partner** —
match the human's energy, incorporate tangents, keep momentum across shifts.

Flow is what naturally happens in a good working session with no single fixed goal — often the default when no stance is explicitly chosen.

## When to Use

- Sessions that span multiple topics or tasks
- The human is checking in occasionally throughout the day
- Overseeing parallel work (multiple agents, multiple workspaces)
- The user says "let's see where this goes" or doesn't specify a stance
- The Thalamus is being used as a live collaboration surface

## Behavior Modifications

| Activity | Without Flow | With Flow |
|----------|-------------|-----------|
| Orientation | Standard | Brief — ask what's on your mind, surface anything new from Thalamus |
| Brainstorming | Full ceremony | Adaptive — full for topics that need it, skip for quick pivots |
| Code review | Standard | Proportional to the task — thorough for complex, quick for simple |
| Commits | Standard messages | Standard — don't over-invest in ceremony for small items |
| Housekeeping | On request | Continuous light triage — promote or defer items on the fly as they come up |
| Side items | Note and continue | Welcome — incorporate if relevant, note if not, don't fight the drift |
| Thalamus | Capture for later | Live collaboration surface — read and respond to human's async notes |
| Task switching | Ask about it | Natural — match the human's shifts, maintain context across pivots |

## Flow Patterns

Flow stance encourages:

- **Productive drift** — moving between topics is the rhythm, not distraction. Each topic gets the depth it needs, then you move on
- **Incorporate tangents** — when the human adds a stray thought (Thalamus or conversation), weave it in rather than deferring it
- **Adaptive ceremony** — full brainstorming for something complex, a one-liner fix for something simple, in the same session
- **Continuous light triage** — handle small items as they arise: file an issue, update a skill, note an observation
- **Graceful context switching** — when the topic shifts, briefly acknowledge what you're leaving before picking up the new thread
- **No clear end** — Flow sessions may fade rather than conclude. The Thalamus captures anything that matters for next time

## Tangent handling — arcs

When the human opens a thread that's clearly distinct from the current focus, or asks for a brain-dump into Thalamus that isn't the primary topic, propose logging it as an arc rather than just writing prose:

> "Looks like a tangent — want me to log it as a parked arc `<proposed-slug>`? You can come back to it later or promote it to an issue."

The proposal includes:

- A kebab-case `id` slug derived from the topic
- `status: parked` if the conversation will return to the original topic shortly, `status: active` if the session is pivoting wholesale
- A one-line `next:` pointer

If the session is pivoting wholesale, also propose flipping the *previous* arc to `status: parked` in the same edit. Don't act without confirmation — same propose-not-act pattern as orientation nudges.

If the user declines, capture the tangent as a normal Observations entry (the existing Flow behavior). Don't ask twice; respect "no."

`arcs:` is the dashboard projection — keep `next:` short and free of sensitive operational detail (URLs of internal tools, credentials, identifying detail about people). Keep the rich context in the body.

**Whenever you edit an arc, stamp its `last_touched` to today in the same edit.** That includes rewriting `next:`, flipping `status:`, and adding body context under the slug — not arcs you only read. Nothing computes this field, and both the ArcDashboard's decay icons and housekeeping's stale-arc check depend on it, so an unstamped edit leaves a moving arc looking abandoned.

Two habits keep `next:` renderable, both learned from arcs that drifted: it is one line of **10–20 words**, and it is a *next step*, not a status report. The moment it starts accumulating "DONE X, then Y, OLD NOTE: …" it has become a status dump — move that history into the body and leave the pointer. Quote the value and avoid embedding a `"` inside it; an unescaped quote closes the YAML scalar early and takes the **whole file's** frontmatter down with it, silently removing every arc on that host from the dashboard. `ws hoard lint` catches all three.

## Multi-Agent and Multi-Workspace

Flow is the natural stance for a human overseeing parallel work:

- Two agent sessions on different machines working on related features
- Checking in on one session while another runs in the background
- Cross-referencing work between sessions (like resolving CR comments from
  one workspace using tools built in another)

The Thalamus serves as the coordination surface — each workspace has its
own, but the human carries context between them.

## Composition

- **Flow + Mentoring:** The agent explains things as they come up naturally,
  not as a structured curriculum. Teaching happens in context of whatever
  the current topic is.

## What This Stance Does NOT Do

- Lock the session to a single topic — that's Zen
- Batch housekeeping for later — that's also Zen
- Skip everything for speed — that's Quick
- Force ceremony on every topic — adapt to what each topic needs
- Fight the human's natural working rhythm — match it
