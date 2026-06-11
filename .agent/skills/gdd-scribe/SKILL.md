---
name: gdd-scribe
description: Use when the active role is `scribe`, when an Obsidian-style vault hoard is detected, when the user says something matching capture intent (jot in inbox, daily note, weekly synthesis, daily review, capture this idea), when a `#gdd`-tagged daily-note bullet needs to cross the vault→Thalami bridge, or when a project note's priority looks out of step with its arc.
---

# GDD Scribe Skill

Operates against Obsidian-style vaults stored as hoards under
`hoards/<name>/`. Handles capture, daily/weekly notes, inbox
processing, and PARA conventions.

## When to Load

- **Path A — `role: scribe` in Thalamus frontmatter** — orientation
  loads this skill automatically per the standard role-default flow
- **Path B — orientation discovers a vault, role is null** — orientation
  surfaces the vault and offers scribe role; if the user accepts, this
  skill loads
- **Path C — mid-session keyword dip-in** — user says something matching
  capture intent (*"jot this in my inbox"*, *"add a daily note"*,
  *"capture this idea"*) while in another role; load this skill ad-hoc
  and perform the requested action without formally swapping role
- **Path D — explicit user ask** — *"scribe role for this session"* or
  *"scribe on borgr"*

## Vault Discovery and Binding

Run `ws hoard scan --flavor vault` and parse the YAML inventory. The
`vault` meta-flavor currently maps to `obsidian` (the only vault
flavor today; the indirection is preserved for future flavors).

Apply binding rules:

| Match count | Action |
|-------------|--------|
| 0 | Tell the user no vault-flavored hoards exist. Offer `ws hoard init obsidian-vault`. Exit binding flow if declined. |
| 1 | Auto-bind to the single match. In-memory pin for the session. |
| >1 | Check Thalamus frontmatter for `active_vault: <name>`. If set and matches a scanned hoard, use it silently. Otherwise ask the user which vault for this session. |

The pin is **session-local, in-memory**. Don't write the binding to
Thalamus unless the user explicitly says *"make it permanent"* — in
which case set `active_vault: <name>` in frontmatter.

## PARA Conventions

Folder roles in a vault scaffolded by `ws hoard init obsidian-vault`:

| Folder | Role |
|--------|------|
| `00_Inbox/` | Temporary capture point. Process weekly to <20 items. |
| `10_Projects/` | Time-bound initiatives with a clear completion criterion. Each project lives in its own subfolder. |
| `20_Areas/` | Ongoing responsibilities without an end date. |
| `30_Resources/` | Reference material organized by topic. |
| `40_Archive/` | Completed projects and inactive notes. Move whole project folders here when done. Vaults using the status schema split this into `Projects/` (done/cancelled), `Backlog/` (someday), and `Daily/` (aged-out dailies) — see Project Status Schema below. |
| `50_Attachments/` | Binary attachments (images, PDFs). |
| `60_Metadata/Templates/` | Reusable note templates. |

When creating notes:
- New captures default to `00_Inbox/`
- Move to PARA folders when processing (capture → process → organize)
- Keep folder depth shallow — projects get one subfolder, not nested trees

## Frontmatter Habits

Every new note opens with YAML frontmatter:

```yaml
---
created: YYYY-MM-DD
tags: [...]
status: active   # project notes use the five-tier schema below; inbox captures use 'unprocessed'
---
```

Substitute the actual date when creating notes via Claude. The
templates in `60_Metadata/Templates/` use two different substitution
syntaxes depending on which plugin owns the template:

- **Templater syntax** (`<% tp.date.now("YYYY-MM-DD") %>`,
  `<% tp.file.title %>`) — Project Note, Area Note, Inbox Capture,
  Meeting Note, Clipping. Auto-applied via Templater on file
  creation in `10_Projects/` or `20_Areas/`.
- **Core Templates / Periodic Notes syntax** (`{{date:YYYY-MM-DD}}`,
  `{{title}}`) — Daily Note, Weekly Review. Applied by Periodic
  Notes when you open today's daily note or this week's review.

When you create notes via Claude (not the Obsidian UI), substitute
the literal date so the frontmatter is valid YAML — neither
substitution engine runs from outside Obsidian.

## Project Status Schema

Project notes in `10_Projects/` (and dormant ones in `40_Archive/Backlog/`) carry a five-tier `status:` value. This is distinct from the capture-state `unprocessed` used by raw inbox items — capture-state and project-status are different axes.

| Status | Meaning | Folder |
|--------|---------|--------|
| `active` | Currently moving; touched recently | `10_Projects/` |
| `next` | Top-of-mind, picking up next | `10_Projects/` |
| `soon` | Committed, queued behind `next` | `10_Projects/` |
| `waiting` | Blocked or future-scheduled — not low-energy | `10_Projects/` |
| `someday` | Wishful, no commitment | `40_Archive/Backlog/` |
| `done` | Finished successfully | `40_Archive/Projects/` |
| `cancelled` | Abandoned deliberately | `40_Archive/Projects/` |

### Decay catalog

A project untouched long enough is a candidate for a status flip. When you spot one during any ceremony (see Ceremony Layers below), **propose** the flip — never apply it silently. A flip to `someday` also moves the whole project folder to `40_Archive/Backlog/`; a flip to `done`/`cancelled` moves it to `40_Archive/Projects/`. The unit of motion is the project's subfolder (see PARA Conventions above — "Each project lives in its own subfolder"), not just the note file.

| Transition | Threshold (days untouched) |
|------------|----------------------------|
| `active` → `next` | 14 |
| `next` → `soon` | 28 |
| `soon` → `someday` (+ move to `40_Archive/Backlog/`) | 42 |
| `someday` → propose full archive | 84 |
| `waiting` → poke ("still waiting on X?", no status change) | 30 |

`waiting` is **not** on the decay path — blocked work is parked deliberately and must not auto-drift. Surface stale `waiting` items but let the user decide.

These thresholds are the v1 defaults baked into this skill. A vault may tune them later via a per-vault config; until then, use these numbers.

Not every vault adopts this schema — it ships with vaults scaffolded by the `obsidian-vault` template (look for `30_Resources/PKM/Status Schema.md`). If a vault has no such file and its project notes use only `active`/`archived`, treat the schema as absent and don't impose it; just follow the vault's existing convention.

## Wikilinks and Embeds

| Syntax | Result |
|--------|--------|
| `[[Note Name]]` | Link to another note in the vault |
| `[[Note Name\|Display Text]]` | Wikilink with custom display text |
| `![[Note Name]]` | Embed (transclude) another note's content |
| `![[image.png]]` | Embed an image |
| `[[Note Name#Heading]]` | Link to a specific heading |

Prefer wikilinks over markdown links inside the vault — they survive
note renames and Obsidian auto-updates them.

## Daily Notes

Naming pattern: `YYYY-MM-DD.md` (the Periodic Notes plugin's default; matches the H1 template entry below so Filename Heading Sync stays happy). Lives in `00_Inbox/` per the obsidian-vault template's Periodic Notes config, unless the user has reconfigured. The `YYYY-MM-DD - Topic.md` longer form is still fine when capture-with-topic is more useful — just rename after the fact, and accept that Filename Heading Sync will adjust the H1 to match.

When the user says *"start a daily note"* or *"jot something for today"*, use the `60_Metadata/Templates/Daily Note.md` shape if it exists, otherwise create with this minimal frontmatter:

```yaml
---
created: YYYY-MM-DD
tags: [daily]
status: active
---

# YYYY-MM-DD

## Today

## Captures

## Links

```

Templates always include a `# H1` mirroring the filename as the first line after the frontmatter. Filename Heading Sync (bundled, enabled) keeps them in sync — without a matching H1, FHS picks the first body heading and renames the file. When Claude creates a note for the user, follow the same convention.

## Inbox Processing

The capture-process-organize loop:

1. **Capture** — anything new lands in `00_Inbox/` with `status: unprocessed`
2. **Process** — weekly (or on demand), iterate inbox items
3. **Organize** — keep `00_Inbox/` under 20 items; if it's growing,
   processing cadence is too slow

When the user says *"process my inbox"* or *"sort the inbox"*, list
the inbox files, exclude obvious dailies/weekly/monthly review files
and the Dashboard, then for each remaining item produce a **decision
card** the user can ack/edit before applying:

```text
File: <filename>
Type: <project / area / resource / archive / delete / leave>
Destination: <PARA folder> (or 'leave in inbox')
Reason: <why this categorization>
Related to: <wikilinks to existing notes if any connections show up>
```

Categorization rules:

| Trigger | Destination |
|---------|-------------|
| Has deadline + specific outcome | `10_Projects/<name>/` |
| Ongoing responsibility, no end date | `20_Areas/<area>/` |
| Reference material / knowledge | `30_Resources/<topic>/` |
| Old / completed / no longer active | `40_Archive/<topic>/` |
| Clearly noise (duplicate, expired) | delete (with confirmation) |
| Quick capture / daily / fragment | leave in inbox |

After the user reviews the cards, apply the moves:

- Update each moved note's frontmatter (`status: active`, add tags)
- Update wikilinks if names change
- **Never auto-delete user content silently** — uncertain items
  always go to Archive, not the trash. Confirm deletes individually.

**Restraint principle:** some items *legitimately* belong in the
Inbox (daily notes, quick captures, in-progress thoughts). Don't
over-organize — sometimes "good enough" is perfect. Lean toward
"leave it" when the categorization isn't obvious.

**Pattern recognition:** while iterating, surface combination
opportunities ("these three notes are about the same project, want
to merge?") and missing connections ("this note's topic is also
covered in [[X]] — link them?").

## Daily Review

When the user says *"do a daily review"* or *"end-of-day review"*,
build out today's daily note (already created by Periodic Notes at
`00_Inbox/YYYY-MM-DD.md`, or create it if missing) with this richer
structure on top of whatever the user already captured:

- **Accomplished** — completed items today
- **Progress** — what advanced, by project / area
- **Insights** — realizations, learnings, surprises
- **Blocked / stuck** — obstacles and reasons
- **Discovered questions** — new inquiries that emerged
- **Tomorrow's focus** — pick three priorities, no more
- **Open loops** — checkbox follow-ups for tomorrow

Inputs to gather:

- Files in the vault modified today (use vault-relative mtime)
- Projects with activity (notes touched in `10_Projects/`)
- Today's daily note's existing capture sections

Three framing questions: *What was accomplished? What got stuck?
What unexpected discoveries emerged?*

Side actions (offer, don't do silently):

- Move completed `- [x]` items in projects to their archive section
- Update `status:` on project notes that finished today
- Add wikilinks from today's discoveries to existing concept notes

## Weekly Synthesis

When the user says *"do a weekly synthesis"* or *"weekly review"*,
either open this week's review note (Periodic Notes creates it as
`00_Inbox/<YYYY-[W]ww>.md` from the Weekly Review template) or
create it if missing. The template already scaffolds Wins (via
Tasks query), Project Review checklist, Themes, Connections, and
Next Week's 3 big rocks — fill them in.

Inputs to gather:

- Notes created this week (vault-relative ctime)
- Notes modified this week
- Projects with activity
- Tasks completed this week (the template's Tasks query auto-fills
  this — read it back as part of the review)

Synthesis moves:

- **Recurring themes** — what showed up in multiple notes this week?
- **Common challenges** — repeated obstacle patterns
- **Breakthrough moments** — where understanding shifted
- **Energy patterns** — when focused vs scattered (rough; user
  judgment)
- **Connections made** — explicitly map relationships between
  notes / concepts surfaced this week. This is the move that turns
  the review from *summary* into *synthesis*.

Side actions (offer):

- Archive completed projects → `40_Archive/`
- Clean up inbox if items have aged
- Update project statuses
- Plan next week's 3 big rocks

## Ceremony Layers

Vaults using the five-tier status schema (see Project Status Schema above) have a layered review cadence. All layers are **propose-then-confirm** — surface a decision, let the user choose, then write. Never flip a status or move a project folder without an explicit yes.

### Micro ceremony — the 30-second floor

When the user asks *"one item"*, *"what should I look at?"*, or similar, run the micro-ceremony:

1. Gather decay candidates: `active` projects untouched >14d, `next` >28d, `soon` >42d, `someday` >84d, `waiting` >30d, plus unprocessed inbox items.
2. Pick **one** by priority: oldest stale `active` first, then stale `next`, then stale `soon`, then stale `someday`, then `waiting` >30d, then oldest unprocessed inbox item.
3. Surface it as a single plain-English decision — no Dataview tables, no markdown tables in the response. Status names in backticks, file names in plain text, choices enumerated. Example: *"`Garden Planning` is `active` but untouched 21 days. Push to `next`, keep `active`, or set `waiting`?"*
4. Apply the user's one-line answer: flip the frontmatter `status:`, and move the whole project folder if the new status changes its location.
5. Offer *"another one?"* — loop if they want.

If nothing is stale and the inbox is clear, say so plainly (*"nothing stale — all clear"*). That visible all-clear is the point: skipped weeks just surface more candidates next time.

This micro-ceremony is designed to work from a phone (e.g. Claude RC) with the vault open in Obsidian mobile — keep responses short and chat-shaped.

### Weekly sweep

On *"weekly sweep"* / *"weekly synthesis"*, in addition to the existing Weekly Synthesis workflow: walk `active` projects (still moving? else propose `next`), `next` projects (promote 1-3 to `active`?), `waiting` items older than 30 days (propose a follow-up — matching the poke threshold in the decay catalog), and offer the oldest few `someday` items for possible refresh.

### Monthly

On the monthly review, in addition to the template's prompts: review projects that drifted to `someday` over the month (offer one refresh-back chance), and flag any Area with zero `active` or `next` projects.

### Waiting-room surface

`WaitingRoom.md` (a second dashboard at the vault root, alongside `Dashboard.md`) lists every `waiting`-status project. During any ceremony, call out `waiting` items older than 30 days — *"still waiting on X?"* — and propose either a concrete follow-up or a status flip back to `active`/`next`. Because `waiting` never decays automatically, this poke is the only thing keeping blocked work from rotting silently.

## The GDD Bridge

GDD-bound work captured in the vault — anything tagged `#gdd` in a daily note — does not belong in the vault long-term. It belongs in GDD-land: a per-machine Thalamus, and ultimately an arc. The **bridge** is the scribe ceremony's hand-off of those items into the thalami hoard's `Intake.md`, a machine-agnostic staging file the GDD ceremony later drains.

The scribe skill only *moves items across* the bridge — it never decides whether something becomes an arc. That judgment belongs to the GDD ceremony (orientation surfaces the Intake; housekeeping drains it). See @gdd-housekeeping Step 2.6.

### When the bridge fires

During the daily review, inbox processing, or a weekly sweep, watch for daily-note bullets tagged `#gdd`. For each one, propose moving it to the active thalami hoard's `Intake.md`:

> "`Test the updated GDD hook on the Nvidia laptop` is tagged `#gdd` — move it to the thalami-hoard Intake so the GDD ceremony can route it?"

This is propose-then-confirm like every other ceremony move — never shift an item silently.

### Locating and creating Intake.md

`Intake.md` lives at the root of the active thalami hoard, beside `ArcDashboard.md` — the same directory as the per-machine `*-thalamus.md` files. Resolve the hoard with `ws hoard thalamus-path` and take the sibling `Intake.md`. If no thalami hoard is active, tell the user the bridge has nowhere to go and leave the item in the daily note. If the hoard is active but `Intake.md` does not exist yet, create it from the `templates/hoards/thalami/Intake.md` shape before adding the first item.

### Applying a move

When the user confirms, append a bullet to the `## Items` section of `Intake.md`:

`- <item text> (from: <host or vault>, captured: YYYY-MM-DD)`

Then check off or remove the originating daily-note bullet per the vault's normal task convention. The thalami hoard is a separate git repo — the move commits with the hoard's normal commit cadence (see @gdd-orientation Step 0a), not a forced commit.

## Arc-linked Project Priority

When a vault project note is linked to a GDD arc (the arc's optional `project:` field names the project), the project's lightweight `priority:` field can be hand-set from the arc's richer `impact:` × `urgency:` read.

The collapse is **drift-tolerant** — no mechanical sync, no live binding. It surfaces only at ceremony touch, propose-then-confirm:

During any scribe ceremony (micro, daily review, weekly sweep), if a project note is being touched and the agent can see a linked arc with `impact:` / `urgency:` set, check whether the project's current `priority:` looks out of step with the arc's read. If it does, propose an update:

> "`Garden Planning` has `priority: low`, but its linked arc is `impact: high, urgency: next` — bump to `high`?"

Suggested mapping (illustrative, not binding):

| Arc `impact:` × `urgency:` | → Project `priority:` |
|---|---|
| any × `asap`, or `high` × `next` | `high` |
| `high` × `soon`/`later`, or `medium` × `asap`/`next` | `medium` |
| otherwise | `low` |

The same proposal can come from the other direction during GDD housekeeping (@gdd-housekeeping Step 2.5). Either ceremony surfaces the move when convenient; drift between them is fine and gets reconciled on the next touch — the Thalamus's own posture, applied to a smaller artifact.

If the linked arc has no `impact:` or `urgency:` set, stay silent. If the arc's `project:` link names a note that does not exist in the active vault, mention it once for the human's attention rather than acting silently.

## De-AI-ifying Text

When the user says *"de-AI-ify this"*, *"strip the AI tells from
this"*, or *"make this sound less LLM"*:

1. Read the source file.
2. Write a transformed copy at `<original-stem>-HUMAN.md`. Don't
   overwrite the original.
3. Generate a `<original-stem>-HUMAN.changelog.md` next to it
   listing each substitution made.

Patterns to flag and rewrite:

| Category | Examples to remove or replace |
|----------|------------------------------|
| Empty transitions | "Moreover," "Furthermore," "Additionally," excessive "However," "Importantly," |
| Clichés | "In today's fast-paced world," "Let's dive deep," "Unlock your potential," "It's worth noting that" |
| Hedging | "It's important to note," vague "various / numerous / myriad" |
| Corporate words | utilize→use, facilitate→help, optimize→improve, leverage→use, demonstrate→show |
| Robotic structure | rhetorical-question-then-answer, rigid parallel structure ("First… Second… Third…" without need), announcements of emphasis ("Importantly,") |

Style restoration goals: varied sentence lengths, conversational
tone, direct statements, natural transitions, confident assertions
over hedged ones, specific examples over vague generalizations.

Don't strip the user's actual voice — if they wrote "however" twice
in a 2000-word piece, that's fine. The flag is for *patterns*
(every paragraph starts with "Furthermore"), not isolated words.

## Keyword Calibration

Trigger keywords advertised in this skill's frontmatter description
include `note`, `journal`, `inbox`, `capture`, `jot`, etc. — but
those words appear in many non-vault contexts.

**Trigger this skill only on phrases implying capture intent:**

| Trigger | Don't trigger |
|---------|---------------|
| *"jot this in my inbox"* | *"note that this fails on Windows"* |
| *"capture this idea"* | *"capture group in the regex"* |
| *"add a daily note about X"* | *"daily standups are at 10"* |
| *"start a meeting note"* | *"meeting notes from 2025 are gone"* |
| *"do a weekly synthesis"* | *"weekly all-hands"* |

The distinction is **capture intent** — the user wants to record
something into a vault — versus **incidental keyword match** — the
word appeared but the user is talking about something unrelated. When
in doubt, ask: *"sounds like you want to capture this — should I add
it to your vault inbox?"* before loading the skill and binding to a
vault.

## Multi-vault Edge Case

If Path C (keyword dip-in) triggers in a workspace with multiple
vault-flavored hoards and no `active_vault:` is set, the binding
sub-flow asks the user which vault — mid-conversation. The pin sticks
for the rest of the session, so it's a one-time prompt. Users who
frequently dip into capture from multi-vault workspaces should set
`active_vault:` in Thalamus frontmatter once to skip the question.

## What This Skill Does NOT Do

- Set `role: scribe` in Thalamus permanently — only the user can do
  that
- Auto-commit the vault — vault hoards are independent git repos;
  the user commits when they want
- Modify the sparse-numbered folder prefixes (`00`, `10`, `20`, `30`, `40`, `50`, `60`) — those are PARA structural invariants
- Force any specific filename pattern beyond the daily-note convention
