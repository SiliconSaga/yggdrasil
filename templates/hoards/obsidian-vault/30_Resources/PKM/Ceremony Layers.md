---
created: 2026-05-15
type: resource
tags: [pkm, methodology, ceremony]
status: active
---

# Ceremony Layers

This vault's review cadence has four layers, plus one cross-cutting bridge for GDD-bound work. All use propose-then-confirm — the agent surfaces; you decide; the agent writes.

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
- **Cross-tier (when GDD is in the picture):** the weekly sweep is also where the **durable-tier sweep** attaches — a quick walk of the companion GitHub Project board to surface promoted issues that have stalled. The weekly focus is *review* (what's on the board, what's stalled). See the [organization-stack model](https://siliconsaga.github.io/yggdrasil/gdd/organization-stack) for the full cadence ladder.

## Monthly

- **Trigger:** Periodic Notes creates the monthly note on the 1st.
- **Anchor it on one recurring, calendar-triggered, concrete task** — a monthly "pay bills" task is the classic example. That task is the lodestar: it has a visible failure mode, so it never gets skipped, and it carries the rest of the monthly review with it.
- **Scribe-extended:** tier-drift review (refresh items that drifted to `someday`), Areas check-in (any area with zero `active`/`next`?), plus the template's Themes / Energy / Next Month prompts.
- **Cross-tier (when GDD is in the picture):** the monthly pass is the *grooming* end of the durable-tier sweep — re-prioritize the GitHub Project board, check component `docs/` for freshness, close dead items. Distinct focus from the weekly *review*.

## The GDD Bridge (cross-cutting)

For vaults that sit inside a GDD workspace, one additional ceremony runs orthogonal to the four cadence layers above: the **scribe bridge**. It moves GDD-bound items out of the vault and into the GDD working memory so the right ceremony picks them up later.

- **Trigger:** during any scribe ceremony (micro, daily review, or weekly sweep), the agent spots a daily-note bullet tagged `#gdd` and proposes moving it to the thalami hoard's `Intake.md` — a machine-agnostic staging file beside the per-machine Thalamus files.
- **Your response:** confirm or skip, like any other ceremony move.
- **What happens next:** the GDD ceremony (orientation surfaces, housekeeping drains) routes the item to the right machine and promotes it to an arc when the work justifies one. The vault never holds it long.
- **If you don't use GDD:** ignore — the bridge fires only on `#gdd` tags. Untagged work stays in the vault as normal.

See the [organization-stack model](https://siliconsaga.github.io/yggdrasil/gdd/organization-stack) for the full picture of how the vault, the Thalami hoard, component docs, and GitHub fit together.

## The four sticky-scaffold properties

A recurring scaffold survives long-term only if it is:

1. **Calendar-triggered** — fires without your initiative
2. **Concrete action** — one specific thing to do
3. **Template-supplied** — no thinking required to start
4. **Visible failure mode** — skipping has an external consequence

Scaffolds that can't satisfy all four don't earn a recurring slot.

For the rationale and full design, see the [obsidian-vault hoard docs](https://siliconsaga.github.io/yggdrasil/gdd/obsidian-vault).
