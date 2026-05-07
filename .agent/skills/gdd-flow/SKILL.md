---
name: gdd-flow
description: >
  Flow mode — productive drift across multiple tasks with responsive
  collaboration. The agent surfs the current, incorporating tangents and
  async input naturally. May be the natural default when no mode is set.
  Use when working across several topics or overseeing parallel work.
---

# GDD Flow Mode

A behavior modifier for productive, multi-topic sessions where the rhythm
matters more than the destination. The agent's role is **dance partner** —
match the human's energy, incorporate tangents, keep momentum across shifts.

Flow is what naturally happens in a good working session that doesn't have
a single fixed goal. It may be the default mode — what you get when you
don't explicitly choose a mode.

## When to Use

- Sessions that span multiple topics or tasks
- The human is checking in occasionally throughout the day
- Overseeing parallel work (multiple agents, multiple workspaces)
- The user says "let's see where this goes" or doesn't specify a mode
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

Flow mode encourages:

- **Productive drift** — moving between topics isn't distraction, it's the
  rhythm. Each topic gets the depth it needs, then you move on
- **Incorporate tangents** — when the human adds a stray thought (to the
  Thalamus, or in conversation), weave it in rather than deferring it
- **Adaptive ceremony** — full brainstorming for something complex, a quick
  one-liner fix for something simple, in the same session. Match the tool
  to the task
- **Continuous light triage** — instead of batch housekeeping, handle small
  items as they arise: file an issue, update a skill, note an observation
- **Graceful context switching** — when the topic shifts, briefly acknowledge
  what you're leaving and pick up the new thread
- **No clear end** — Flow sessions may fade rather than conclude. That's fine.
  The Thalamus captures anything that matters for next time

## Tangent handling — arcs

When the human opens a thread that's clearly distinct from the current
focus, or asks for a brain-dump into Thalamus that isn't the primary
topic, propose logging it as an arc rather than just writing prose:

> "Looks like a tangent — want me to log it as a parked arc
> `<proposed-slug>`? You can come back to it later or promote it to
> an issue."

The proposal includes:

- A kebab-case `id` slug derived from the topic
- `status: parked` if the conversation will return to the original
  topic shortly, `status: active` if the session is pivoting wholesale
- A one-line `next:` pointer

If the session is pivoting wholesale, also propose flipping the
*previous* arc to `status: parked` in the same edit. Don't act
without confirmation — same propose-not-act pattern as orientation
nudges.

If the user declines, capture the tangent as a normal Observations
entry (the existing Flow behavior). Don't ask twice; respect "no."

`arcs:` is the dashboard projection — keep `next:` short and free of
sensitive operational detail (URLs of internal tools, credentials,
identifying detail about people). Keep the rich context in the body.

## Multi-Agent and Multi-Workspace

Flow is the natural mode for a human overseeing parallel work:

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

## What This Mode Does NOT Do

- Lock the session to a single topic — that's Zen
- Batch housekeeping for later — that's also Zen
- Skip everything for speed — that's Quick
- Force ceremony on every topic — adapt to what each topic needs
- Fight the human's natural working rhythm — match it
