---
created: 2026-05-15
type: resource
tags: [pkm, methodology, ceremony]
status: active
---

# Ceremony Layers

This vault's review cadence has four layers. All use propose-then-confirm — the agent surfaces; you decide; the agent writes.

## Micro (the 30-second floor)

- **Trigger:** ask the GDD agent something like *"one item"* or *"what should I look at?"* — from any session, including mobile.
- **Output:** one decision card in plain English. *"`Project X` is `active` but you haven't touched it in 18 days. Push to `next`, keep `active`, or set `waiting` with a reason?"*
- **Your response:** one line.
- **Failure mode (visible):** if nothing's stale, the agent says so. Skipped weeks become more decay candidates next time — the backlog advertises itself.

## Daily

- **Trigger:** Periodic Notes auto-creates today's daily note in `00_Inbox/`.
- **Ceremony:** none required. The daily note is capture, not review.

## Weekly (the 10-minute sweep)

- **Trigger:** ask for a *"weekly sweep"* / *"weekly synthesis"*, or the agent surfaces it when the last Weekly Review note is over a week old.
- **Flow:** walk the Weekly Review template's Project Review checklist — for each `active` project, still moving?; for each `next`, promote to `active`?; for `waiting` items, follow up?; offer the oldest `someday` items to refresh.
- **Skippable:** a missed weekly sweep just leaves more for the micro layer.

## Monthly

- **Trigger:** Periodic Notes creates the monthly note on the 1st.
- **Anchor it on one recurring, calendar-triggered, concrete task** — a monthly "pay bills" task is the classic example. That task is the lodestar: it has a visible failure mode, so it never gets skipped, and it carries the rest of the monthly review with it.
- **Scribe-extended:** tier-drift review (refresh items that drifted to `someday`), Areas check-in (any area with zero `active`/`next`?), plus the template's Themes / Energy / Next Month prompts.

## The four sticky-scaffold properties

A recurring scaffold survives long-term only if it is:

1. **Calendar-triggered** — fires without your initiative
2. **Concrete action** — one specific thing to do
3. **Template-supplied** — no thinking required to start
4. **Visible failure mode** — skipping has an external consequence

Scaffolds that can't satisfy all four don't earn a recurring slot.

For the rationale and full design, see the [obsidian-vault hoard docs](https://siliconsaga.github.io/yggdrasil/gdd/obsidian-vault).
