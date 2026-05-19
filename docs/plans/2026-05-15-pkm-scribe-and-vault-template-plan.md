# PKM Scribe Extensions + Vault Template Propagation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Propagate the PKM Life-Organization methodology (already landed in the `borgr` vault) to the shared layer — the `obsidian-vault` hoard template so new vaults inherit the shape, and the `scribe` skill so the GDD agent knows the five-tier status schema, decay catalog, and ceremony layers.

**Architecture:** Two coupled halves in one PR. (1) Template propagation: mirror the borgr structural changes into `templates/hoards/obsidian-vault/` — PKM folders, archive sub-folders, updated Project/Area templates, dashboard changes, `WaitingRoom.md`. (2) Scribe skill: add a status-schema section, a ceremony-layers section, and reconcile the existing frontmatter guidance. Plus a docs-page refresh so `docs/gdd/obsidian-vault.md` stays accurate. The two halves ship together because a vault scaffolded by the new template with an old scribe (or vice versa) is incoherent.

**Tech Stack:** Markdown + YAML frontmatter; Obsidian Dataview/Templater (template files); agent-neutral skill prose (`SKILL.md`).

**Design source:** [`2026-05-15-pkm-life-organization-design.md`](https://github.com/Cervator/borgr/blob/main/docs/plans/2026-05-15-pkm-life-organization-design.md) (in the borgr repo). The borgr-side plan that already executed is [`2026-05-15-pkm-life-organization-plan.md`](https://github.com/Cervator/borgr/blob/main/docs/plans/2026-05-15-pkm-life-organization-plan.md).

---

## Notes on this plan

- **Verification model:** doc/template/skill work has no unit tests. Verification is read-back (`grep`/`head`) plus a final coherence review. The TDD pattern doesn't apply; verification steps are explicit reads.
- **One repo, one branch:** all work is in yggdrasil on `feat/pkm-scribe-and-vault-template` (already created from `main`). Lands as a single PR.
- **Template files are NOT copies of borgr's files.** The template uses its own conventions that differ from borgr in two ways the implementer must respect:
  - **README files** in the template use bare `# Heading` style with NO frontmatter (e.g. `templates/hoards/obsidian-vault/40_Archive/README.md` is just `# 40_Archive` + one line). borgr's archive READMEs have frontmatter — do NOT copy that style here.
  - **Project Note `tags:`** in the template is `project/<slug>` (no `#` prefix); borgr's is `"#project/<slug>"`. Match the template's existing style in each file you touch.
- **PKM methodology references must be GENERIC.** borgr's `30_Resources/PKM/` notes link to borgr's design doc and mention "the user's prior Trello list-shape." The template versions must be self-contained — no borgr design-doc link, no Trello-specific rationale. Full generic content is given in Task 1.
- **Commit cadence:** group into a few commits (template content, scribe skill, docs) — see Task 11.

## File map

**Template — create:**
- `templates/hoards/obsidian-vault/30_Resources/PKM/README.md`
- `templates/hoards/obsidian-vault/30_Resources/PKM/Status Schema.md`
- `templates/hoards/obsidian-vault/30_Resources/PKM/Ceremony Layers.md`
- `templates/hoards/obsidian-vault/40_Archive/Projects/README.md`
- `templates/hoards/obsidian-vault/40_Archive/Backlog/README.md`
- `templates/hoards/obsidian-vault/40_Archive/Daily/README.md`
- `templates/hoards/obsidian-vault/WaitingRoom.md`

**Template — modify:**
- `templates/hoards/obsidian-vault/60_Metadata/Templates/Project Note.md`
- `templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md`
- `templates/hoards/obsidian-vault/Dashboard.md`
- `templates/hoards/obsidian-vault/README.md`

**Skill — modify:**
- `.agent/skills/scribe/SKILL.md`

**Docs — modify:**
- `docs/gdd/obsidian-vault.md`

**Total:** 7 new files, 6 modifications.

---

## Task 1: Template PKM methodology references

**Files:**
- Create: `templates/hoards/obsidian-vault/30_Resources/PKM/README.md`
- Create: `templates/hoards/obsidian-vault/30_Resources/PKM/Status Schema.md`
- Create: `templates/hoards/obsidian-vault/30_Resources/PKM/Ceremony Layers.md`

Generic, self-contained methodology references. NO borgr design-doc link, NO Trello-specific content.

- [ ] **Step 1: Create the PKM folder index**

Write `templates/hoards/obsidian-vault/30_Resources/PKM/README.md` (outer four-backtick fence is this prompt's wrapper — write the inner content only):

````markdown
---
created: 2026-05-15
type: resource
tags: [pkm, methodology, index]
status: active
---

# PKM

Methodology references for this vault's Personal Knowledge Management approach.

This vault layers three concepts on top of PARA (Tiago Forte's Projects / Areas / Resources / Archive). The notes here document them; the `scribe` GDD skill applies them.

## Contents

- [[Status Schema]] — the five-tier project status enum (`active` / `next` / `soon` / `waiting` / `someday` + `done` / `cancelled`), where each lives, and how decay flips them
- [[Ceremony Layers]] — the micro / daily / weekly / monthly review cadence

## Background lenses

- **Tiered PARA** — status drift between binary `active` / `archive`. Projects decay gracefully through intermediate tiers; the system tolerates skipped review.
- **Maps-of-Content (MOC)** — Nick Milo's *Linking Your Thinking*. Area notes become queryable indices into their domain, not just folders.
- **Agentic micro-ceremony** — the 30-second floor: one item, decide. Callable from the GDD agent (including mobile). The review ceremony survives being skipped because the agent surfaces decisions one at a time whenever you have a moment.

For the rationale and full design, see the [obsidian-vault hoard docs](https://siliconsaga.github.io/yggdrasil/gdd/obsidian-vault).
````

- [ ] **Step 2: Verify**

Run: `head -20 "templates/hoards/obsidian-vault/30_Resources/PKM/README.md"`
Expected: frontmatter, `# PKM`, `## Contents` with two wikilinks, `## Background lenses` with three bullets.

- [ ] **Step 3: Create the Status Schema reference**

Write `templates/hoards/obsidian-vault/30_Resources/PKM/Status Schema.md`:

````markdown
---
created: 2026-05-15
type: resource
tags: [pkm, methodology, schema]
status: active
---

# Status Schema

The five-tier status enum carried in every project note's `status:` frontmatter, plus the two terminal states `done` and `cancelled`.

| Status | Meaning | Folder |
|---|---|---|
| `active` | Currently moving; work touched recently | `10_Projects/` |
| `next` | Top-of-mind, picking up next | `10_Projects/` |
| `soon` | Committed, queued behind `next` | `10_Projects/` |
| `waiting` | Blocked or future-scheduled (not lack of energy) | `10_Projects/` |
| `someday` | Wishful, no commitment | `40_Archive/Backlog/` |
| `done` | Finished successfully | `40_Archive/Projects/` |
| `cancelled` | Abandoned deliberately | `40_Archive/Projects/` |

## Decay

When a project goes untouched for long enough, the agent proposes a status flip (and a move when the new status implies a different folder). You confirm; nothing drifts silently.

| Transition | Threshold |
|---|---|
| `active` → `next` | 14 days untouched |
| `next` → `soon` | 28 days untouched |
| `soon` → `someday` | 42 days untouched (+ move to `40_Archive/Backlog/`) |
| `someday` → archive-propose | 84 days untouched (full archive after you confirm) |
| `waiting` → poke | 30 days untouched ("still waiting on X?" — no status change proposed) |

`waiting` is intentionally **not** on the decay path. Blocked is categorically different from low-energy. The agent surfaces stale waiting items periodically; you decide what to do with them.

## Why five tiers

Binary `active` / `archive` forces a project to be either a current commitment or dead. Most projects are neither — they have momentum that ebbs. The intermediate tiers (`next`, `soon`, `someday`) let a project lose energy gracefully without a binary "you failed" signal, and let the agent propose realistic drift instead of demanding you defend every stalled item. `waiting` is separated out because a blocked project shouldn't decay — it's parked for a reason, not for lack of will.

`done` and `cancelled` are folder destinations (`40_Archive/Projects/`), not active-query statuses — moving the file is the canonical "this is finished" signal.
````

- [ ] **Step 4: Verify**

Run: `grep -c "^|" "templates/hoards/obsidian-vault/30_Resources/PKM/Status Schema.md"`
Expected: 14 or more.

- [ ] **Step 5: Create the Ceremony Layers reference**

Write `templates/hoards/obsidian-vault/30_Resources/PKM/Ceremony Layers.md`:

````markdown
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
````

- [ ] **Step 6: Verify**

Run: `grep -n "^## " "templates/hoards/obsidian-vault/30_Resources/PKM/Ceremony Layers.md"`
Expected: five `##` headings — Micro, Daily, Weekly, Monthly, "The four sticky-scaffold properties".

---

## Task 2: Template archive sub-folders

**Files:**
- Create: `templates/hoards/obsidian-vault/40_Archive/Projects/README.md`
- Create: `templates/hoards/obsidian-vault/40_Archive/Backlog/README.md`
- Create: `templates/hoards/obsidian-vault/40_Archive/Daily/README.md`

**Template README style: bare `# Heading` + short prose, NO frontmatter** — matching the existing `templates/hoards/obsidian-vault/40_Archive/README.md` (which is just `# 40_Archive` plus one line). Do not add frontmatter.

- [ ] **Step 1: Create the Projects archive README**

Write `templates/hoards/obsidian-vault/40_Archive/Projects/README.md`:

```markdown
# 40_Archive/Projects

Completed (`done`) or abandoned (`cancelled`) projects. Move a project here when it finishes — the frontmatter `status:` flips at the same time.

Distinct from `40_Archive/Backlog/`, which holds `someday`-tier projects that may still be revived. See [[Status Schema]].
```

- [ ] **Step 2: Create the Backlog archive README**

Write `templates/hoards/obsidian-vault/40_Archive/Backlog/README.md`:

```markdown
# 40_Archive/Backlog

Projects at `status: someday` — wishful, no commitment, revivable if the stars align.

Distinct from `40_Archive/Projects/`, which holds `done` and `cancelled` terminal-state projects. Items here have a path back to `10_Projects/`: a status flip to `active` / `next` plus a move is all it takes. See [[Status Schema]] and [[Ceremony Layers]].
```

- [ ] **Step 3: Create the Daily archive README**

Write `templates/hoards/obsidian-vault/40_Archive/Daily/README.md`:

```markdown
# 40_Archive/Daily

Historical daily notes that have aged out of `00_Inbox/`. Periodic Notes creates today's daily in `00_Inbox/`; move old dailies here in monthly batches (YYYY-MM subfolders) once they're no longer the active capture surface.
```

- [ ] **Step 4: Verify**

Run: `ls templates/hoards/obsidian-vault/40_Archive/`
Expected: `Backlog/  Daily/  Projects/  README.md` (plus any pre-existing entries).

Run: `head -1 templates/hoards/obsidian-vault/40_Archive/Projects/README.md`
Expected: `# 40_Archive/Projects` (NO `---` frontmatter line).

---

## Task 3: Template Project Note — status enum comment

**Files:**
- Modify: `templates/hoards/obsidian-vault/60_Metadata/Templates/Project Note.md`

- [ ] **Step 1: Confirm the anchor**

Run: `grep -n "^status:" "templates/hoards/obsidian-vault/60_Metadata/Templates/Project Note.md"`
Expected: one line, `status: active`.

- [ ] **Step 2: Edit the `status:` line**

Find this exact line:

```yaml
status: active
```

Replace with (note the EM DASH `—`, and the wikilink double brackets):

```yaml
status: active        # active | next | soon | waiting | someday — see [[Status Schema]]
```

Nothing else changes. The Templater script block at the top and all body sections stay untouched.

- [ ] **Step 3: Verify**

Run: `grep -n "^status:" "templates/hoards/obsidian-vault/60_Metadata/Templates/Project Note.md"`
Expected: the new line with the comment.

Run: `git diff "templates/hoards/obsidian-vault/60_Metadata/Templates/Project Note.md"`
Expected: exactly one line changed (one `-`, one `+`).

---

## Task 4: Template Area Note — MOC sections

**Files:**
- Modify: `templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md`

Replace the existing `## Active Projects` block and insert two new sections, exactly as done in borgr. Final section order: `## Purpose`, `## Standards`, `## Active Projects`, `## Backlog Micro-items`, `## Someday Projects`, `## Recurring Responsibilities`, `## Resources`, `## Links`.

- [ ] **Step 1: Confirm the anchor**

Run: `grep -n "^## " "templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md"`
Expected: `## Purpose`, `## Standards`, `## Active Projects`, `## Recurring Responsibilities`, `## Resources`, `## Links`.

- [ ] **Step 2: Replace the `## Active Projects` block**

Find the block that runs from the `## Active Projects` heading through the closing ` ``` ` of its `dataview` block. The current block is:

````
## Active Projects

```dataview
TABLE status, deadline, area
FROM "10_Projects"
WHERE area = this.file.link OR area.area = this.file.link
SORT status ASC, deadline ASC
```
````

Replace that entire block with this expanded content (the outer four-backtick fence is the prompt wrapper — write the inner content):

````markdown
## Active Projects

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  status AS "Status",
  deadline AS "Due"
FROM "10_Projects"
WHERE area = this.file.link OR area.area = this.file.link
SORT
  choice(status = "active", 0,
  choice(status = "next", 1,
  choice(status = "soon", 2,
  choice(status = "waiting", 3, 4)))) ASC,
  deadline ASC
```

## Backlog Micro-items

*Small scraps that don't deserve their own file yet. Promote a row to a `someday` project note in `40_Archive/Backlog/` when it accumulates real context.*

| Item | Notes | Added |
|---|---|---|
|  |  |  |

## Someday Projects

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  (date(today) - file.mtime).days AS "Days idle"
FROM "40_Archive/Backlog"
WHERE area = this.file.link OR area.area = this.file.link
SORT file.mtime DESC
```
````

The existing `## Recurring Responsibilities`, `## Resources`, `## Links` sections below stay untouched. The Templater script block at the top stays untouched.

- [ ] **Step 3: Verify section order**

Run: `grep -n "^## " "templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md"`
Expected, in order: `## Purpose`, `## Standards`, `## Active Projects`, `## Backlog Micro-items`, `## Someday Projects`, `## Recurring Responsibilities`, `## Resources`, `## Links`.

- [ ] **Step 4: Verify Dataview blocks**

Run: `grep -c '```dataview' "templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md"`
Expected: 2.

Run: `grep -c "choice(status" "templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md"`
Expected: 4.

---

## Task 5: Template Dashboard.md — Next Up + Active Now

**Files:**
- Modify: `templates/hoards/obsidian-vault/Dashboard.md`

- [ ] **Step 1: Confirm the anchor**

Run: `grep -n "^## Due" templates/hoards/obsidian-vault/Dashboard.md`
Expected: one line, `## Due`.

- [ ] **Step 2: Insert two blocks before `## Due`**

Insert directly before the `## Due` line (keep a blank line separating the inserted content from `## Due`):

````markdown
## Next Up

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  deadline AS "Due",
  area AS "Area"
FROM "10_Projects"
WHERE status = "next"
SORT deadline ASC, file.mtime DESC
```

## Active Now

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  deadline AS "Due",
  area AS "Area"
FROM "10_Projects"
WHERE status = "active"
SORT deadline ASC, file.mtime DESC
```

````

- [ ] **Step 3: Verify**

Run: `grep -n "^## " templates/hoards/obsidian-vault/Dashboard.md`
Expected, in order: `## Next Up`, `## Active Now`, `## Due`, `## Priority`, `## Organize`, `## Projects`.

Run: `grep -c '```dataview' templates/hoards/obsidian-vault/Dashboard.md`
Expected: 3.

---

## Task 6: Template WaitingRoom.md

**Files:**
- Create: `templates/hoards/obsidian-vault/WaitingRoom.md`

- [ ] **Step 1: Write the file**

Write `templates/hoards/obsidian-vault/WaitingRoom.md` (four-backtick wrapper is the prompt's; write the inner content):

````markdown
---
type: dashboard
tags: [dashboard, waiting]
---

# WaitingRoom

Projects parked in `waiting` status — blocked, scheduled, or pinged-but-unanswered.

`waiting` is off the decay path (blocked items aren't low-energy items), so this surface exists to keep them visible. The `scribe` skill surfaces items here that have been waiting longer than 30 days during ceremony and proposes a follow-up action or a status flip back to `active` / `next`.

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  area AS "Area",
  (date(today) - file.mtime).days AS "Days waiting"
FROM "10_Projects"
WHERE status = "waiting"
SORT file.mtime ASC
```

See [[Status Schema]] for the full status enum and [[Ceremony Layers]] for how the `waiting` poke fits the review cadence.
````

- [ ] **Step 2: Verify**

Run: `head -3 templates/hoards/obsidian-vault/WaitingRoom.md`
Expected: `---`, `type: dashboard`, `tags: [dashboard, waiting]`.

---

## Task 7: Template README.md — methodology pointer

**Files:**
- Modify: `templates/hoards/obsidian-vault/README.md`

The README's `## Pointers` list should mention the methodology so a new vault owner can find it. Keep the change small — one bullet.

- [ ] **Step 1: Confirm the anchor**

Run: `grep -n "Live dashboard" templates/hoards/obsidian-vault/README.md`
Expected: one line — the `- **Live dashboard:** [[Dashboard]] ...` bullet in the `## Pointers` list.

- [ ] **Step 2: Add a methodology bullet after the Live dashboard bullet**

Find:

```markdown
- **Live dashboard:** [[Dashboard]] — pin it next to your Calendar view
```

Insert immediately after it (new line):

```markdown
- **Methodology:** [[PKM/README|PKM methodology]] — the five-tier project status schema, decay, and the micro/weekly/monthly review cadence. [[WaitingRoom]] is a second dashboard for blocked work.
```

- [ ] **Step 3: Verify**

Run: `grep -n "Methodology" templates/hoards/obsidian-vault/README.md`
Expected: the new bullet line.

---

## Task 8: Scribe skill — Project Status Schema section

**Files:**
- Modify: `.agent/skills/scribe/SKILL.md`

Add a new `## Project Status Schema` section after the existing `## Frontmatter Habits` section, and reconcile the existing frontmatter guidance which currently only knows `active` / `unprocessed` / `archived`.

- [ ] **Step 1: Read the current Frontmatter Habits section to confirm anchors**

Run: `grep -n "^## " .agent/skills/scribe/SKILL.md`
Expected: lists the section headings including `## Frontmatter Habits` and the next section `## Wikilinks and Embeds`.

- [ ] **Step 2: Reconcile the Frontmatter Habits status line**

In `## Frontmatter Habits`, find this block:

```yaml
---
created: YYYY-MM-DD
tags: [...]
status: active   # or 'unprocessed' for inbox captures, 'archived' for done items
---
```

Replace the `status:` comment line so it reads:

```yaml
---
created: YYYY-MM-DD
tags: [...]
status: active   # project notes use the five-tier schema below; inbox captures use 'unprocessed'
---
```

This keeps `unprocessed` as the capture-state for raw inbox items (a capture is not a project) and points project notes at the new schema section.

- [ ] **Step 3: Insert the Project Status Schema section**

Immediately before the `## Wikilinks and Embeds` heading, insert this new section:

````markdown
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

A project untouched long enough is a candidate for a status flip. When you spot one during any ceremony (see Ceremony Layers below), **propose** the flip — never apply it silently. A flip to `someday` also moves the file to `40_Archive/Backlog/`; a flip to `done`/`cancelled` moves it to `40_Archive/Projects/`.

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
````

- [ ] **Step 4: Verify**

Run: `grep -n "^## Project Status Schema" .agent/skills/scribe/SKILL.md`
Expected: one line.

Run: `grep -c "^| \`" .agent/skills/scribe/SKILL.md`
Expected: 7 or more (the status-table rows; other backtick-leading table rows may add to this).

---

## Task 9: Scribe skill — Ceremony Layers section

**Files:**
- Modify: `.agent/skills/scribe/SKILL.md`

Add a `## Ceremony Layers` section after the existing `## Weekly Synthesis` section. This carries the micro-ceremony prompt routing and the waiting-room surface.

- [ ] **Step 1: Confirm the anchor**

Run: `grep -n "^## Weekly Synthesis\|^## De-AI" .agent/skills/scribe/SKILL.md`
Expected: two lines — `## Weekly Synthesis` and the `## De-AI-ifying Text` section that follows it.

- [ ] **Step 2: Insert the Ceremony Layers section**

Immediately before the `## De-AI-ifying Text` heading, insert this new section:

````markdown
## Ceremony Layers

Vaults using the five-tier status schema (see Project Status Schema above) have a layered review cadence. All layers are **propose-then-confirm** — surface a decision, let the user choose, then write. Never flip a status or move a file without an explicit yes.

### Micro ceremony — the 30-second floor

When the user asks *"one item"*, *"what should I look at?"*, or similar, run the micro-ceremony:

1. Gather decay candidates: `active` projects untouched >14d, `next` >28d, `soon` >42d, `someday` >84d, `waiting` >30d, plus unprocessed inbox items.
2. Pick **one** by priority: oldest stale `active` first, then stale `next`, then `waiting` >30d, then oldest unprocessed inbox item.
3. Surface it as a single plain-English decision — no Dataview tables, no markdown tables in the response. Status names in backticks, file names in plain text, choices enumerated. Example: *"`Garden Planning` is `active` but untouched 21 days. Push to `next`, keep `active`, or set `waiting`?"*
4. Apply the user's one-line answer: flip the frontmatter `status:`, and move the file if the new status changes its folder.
5. Offer *"another one?"* — loop if they want.

If nothing is stale and the inbox is clear, say so plainly (*"nothing stale — all clear"*). That visible all-clear is the point: skipped weeks just surface more candidates next time.

This micro-ceremony is designed to work from a phone (e.g. Claude RC) with the vault open in Obsidian mobile — keep responses short and chat-shaped.

### Weekly sweep

On *"weekly sweep"* / *"weekly synthesis"*, in addition to the existing Weekly Synthesis workflow: walk `active` projects (still moving? else propose `next`), `next` projects (promote 1-3 to `active`?), `waiting` items older than a week (propose a follow-up), and offer the oldest few `someday` items for possible refresh.

### Monthly

On the monthly review, in addition to the template's prompts: review projects that drifted to `someday` over the month (offer one refresh-back chance), and flag any Area with zero `active` or `next` projects.

### Waiting-room surface

`WaitingRoom.md` (a second dashboard at the vault root, alongside `Dashboard.md`) lists every `waiting`-status project. During any ceremony, call out `waiting` items older than 30 days — *"still waiting on X?"* — and propose either a concrete follow-up or a status flip back to `active`/`next`. Because `waiting` never decays automatically, this poke is the only thing keeping blocked work from rotting silently.
````

- [ ] **Step 3: Verify**

Run: `grep -n "^## Ceremony Layers\|^### Micro ceremony\|^### Waiting-room surface" .agent/skills/scribe/SKILL.md`
Expected: three lines.

Run: `grep -n "^## " .agent/skills/scribe/SKILL.md`
Expected: `## Ceremony Layers` appears between `## Weekly Synthesis` and `## De-AI-ifying Text`.

---

## Task 10: Docs page — obsidian-vault.md

**Files:**
- Modify: `docs/gdd/obsidian-vault.md`

Two updates so the docs page stays accurate: a note in the PARA conventions section about the archive sub-folders and the PKM folder, and a new section documenting the status schema + ceremony cadence.

- [ ] **Step 1: Confirm anchors**

Run: `grep -n "^## PARA conventions\|^## Daily / weekly / monthly cadence\|^## Dashboard.md" docs/gdd/obsidian-vault.md`
Expected: three section headings.

- [ ] **Step 2: Add a note after the PARA conventions folder table**

In `## PARA conventions`, find the line:

```markdown
The capture-process-organize loop lives in the `scribe` skill, which the agent loads when you say things like *"jot this in my inbox"* or *"process my inbox"*.
```

Insert this paragraph immediately before it:

```markdown
Three `40_Archive/` sub-folders carry the project lifecycle: `40_Archive/Projects/` (`done` and `cancelled` projects), `40_Archive/Backlog/` (`someday`-tier projects that may be revived), and `40_Archive/Daily/` (historical daily notes). A `30_Resources/PKM/` folder holds the methodology references — see the status-schema section below.

```

- [ ] **Step 3: Add a new section after `## Dashboard.md`**

The `## Dashboard.md` section ends with a line about Dataview/Tasks query docs. Immediately before the next `##` heading (`## Web clipping`), insert this new section:

```markdown
## Status schema and review cadence

Vaults scaffolded by this template use a five-tier project status schema beyond plain `active`/`archived`:

| Status | Meaning | Folder |
|--------|---------|--------|
| `active` | Currently moving | `10_Projects/` |
| `next` | Picking up next | `10_Projects/` |
| `soon` | Committed, queued | `10_Projects/` |
| `waiting` | Blocked or scheduled | `10_Projects/` |
| `someday` | Wishful, no commitment | `40_Archive/Backlog/` |
| `done` / `cancelled` | Finished | `40_Archive/Projects/` |

Projects decay through the tiers when untouched (14 / 28 / 42 / 84 days); `waiting` is exempt. The `scribe` skill proposes decay flips during review — it never applies them silently.

The review cadence has four layers: a **micro** ceremony (ask the agent *"one item"* for a single 30-second decision, mobile-friendly), an optional **weekly** sweep, a **monthly** review, and the daily note as pure capture. `WaitingRoom.md` is a second root-level dashboard surfacing blocked work. Full reference: `30_Resources/PKM/Status Schema.md` and `30_Resources/PKM/Ceremony Layers.md` inside any scaffolded vault.

```

- [ ] **Step 4: Verify**

Run: `grep -n "^## Status schema and review cadence" docs/gdd/obsidian-vault.md`
Expected: one line, positioned between `## Dashboard.md` and `## Web clipping`.

Run: `grep -n "40_Archive/Backlog" docs/gdd/obsidian-vault.md`
Expected: at least two lines (the PARA note and the new section table).

---

## Task 11: Commit and open the PR

**Files:**
- Create: `.commits/pkm-template.md`, `.commits/pkm-scribe.md`, `.commits/pkm-docs.md` — one bodyfile per commit

Three commits keep the diff legible — template content, scribe skill, docs — then one PR.

- [ ] **Step 1: Write the template-content commit bodyfile**

Create `.commits/pkm-template.md`:

````markdown
---
message: "feat(obsidian-vault): propagate PKM 5-tier status schema to the hoard template"

add:
  - templates/hoards/obsidian-vault/30_Resources/PKM/README.md
  - templates/hoards/obsidian-vault/30_Resources/PKM/Status Schema.md
  - templates/hoards/obsidian-vault/30_Resources/PKM/Ceremony Layers.md
  - templates/hoards/obsidian-vault/40_Archive/Projects/README.md
  - templates/hoards/obsidian-vault/40_Archive/Backlog/README.md
  - templates/hoards/obsidian-vault/40_Archive/Daily/README.md
  - templates/hoards/obsidian-vault/WaitingRoom.md
  - templates/hoards/obsidian-vault/60_Metadata/Templates/Project Note.md
  - templates/hoards/obsidian-vault/60_Metadata/Templates/Area Note.md
  - templates/hoards/obsidian-vault/Dashboard.md
  - templates/hoards/obsidian-vault/README.md
---

Bring the PKM Life-Organization methodology — proven in the borgr vault — into the `obsidian-vault` hoard template so newly scaffolded vaults inherit it.

- Five-tier project status schema (`active`/`next`/`soon`/`waiting`/`someday` + `done`/`cancelled`) with generic methodology references under `30_Resources/PKM/`
- Archive sub-folders: `Projects/` (done/cancelled), `Backlog/` (someday), `Daily/` (aged-out dailies)
- Area Note template gains Backlog Micro-items + Someday Projects sections; Active Projects sorts by status priority
- Dashboard gains Next Up + Active Now; new `WaitingRoom.md` surfaces blocked work

Existing vaults are unaffected — `ws hoard upgrade` only touches plugin code, not content. New vaults get the shape; borgr already has it.
````

- [ ] **Step 2: Commit the template content**

Run: `bash scripts/ws commit yggdrasil .commits/pkm-template.md`

- [ ] **Step 3: Write the scribe-skill commit bodyfile**

Create `.commits/pkm-scribe.md`:

```markdown
---
message: "feat(scribe): teach the 5-tier status schema, decay catalog, and ceremony layers"

add:
  - .agent/skills/scribe/SKILL.md
---

Extend the scribe skill so the GDD agent understands the PKM methodology:

- New Project Status Schema section — the five-tier enum, folder placement, and the decay catalog (14/28/42/84-day thresholds; `waiting` exempt)
- New Ceremony Layers section — the micro 30-second-floor prompt routing, weekly sweep, monthly review, and the waiting-room surface
- Frontmatter Habits reconciled — `unprocessed` stays the capture-state for raw inbox items; project notes use the five-tier schema

The skill degrades gracefully: vaults without a `30_Resources/PKM/Status Schema.md` keep their existing convention untouched.
```

- [ ] **Step 4: Commit the scribe skill**

Run: `bash scripts/ws commit yggdrasil .commits/pkm-scribe.md`

- [ ] **Step 5: Write the docs commit bodyfile**

Create `.commits/pkm-docs.md`:

```markdown
---
message: "docs(obsidian-vault): document the status schema and review cadence"

add:
  - docs/gdd/obsidian-vault.md
---

Add a Status schema and review cadence section to the obsidian-vault hoard docs, and note the new `40_Archive/` sub-folders + `30_Resources/PKM/` in the PARA conventions section.
```

- [ ] **Step 6: Commit the docs**

Run: `bash scripts/ws commit yggdrasil .commits/pkm-docs.md`

- [ ] **Step 7: Verify the three commits**

Run: `git log --oneline -4`
Expected: the three new commits on top of the branch point.

- [ ] **Step 8: Push and open the PR**

Run: `bash scripts/ws push yggdrasil`

Then open a PR against `main` titled `feat: PKM methodology — obsidian-vault template + scribe skill` with a body summarizing the three commits and noting that borgr already runs this methodology (this PR generalizes it). Use `gh pr create` or `bash scripts/ws cr yggdrasil` per the workspace convention.

---

## Self-review (run after writing the plan)

- [x] **Spec coverage** (design doc § Scribe skill extensions + § Methodology framing, generalized):
  - Decay-drift catalog → Task 8
  - Micro-ceremony prompt routing → Task 9
  - Waiting-room surface → Task 9
  - Status schema as a vault convention → Tasks 1, 3, 4, 8
  - Template propagation (folders, dashboards, templates) → Tasks 1-7
  - Docs accuracy → Task 10
- [x] **No placeholders.** Every new file's full content is in the plan; every modification gives exact find/replace text.
- [x] **Type/name consistency.** Status values (`active`/`next`/`soon`/`waiting`/`someday`/`done`/`cancelled`) and thresholds (14/28/42/84/30) identical across template references, scribe skill, and docs. Folder paths (`40_Archive/Backlog/` etc.) consistent.
- [x] **Template-vs-borgr divergence handled.** Plan explicitly flags the bare-heading README style and the `project/<slug>` (no `#`) tag style, and that PKM references must be generic (no borgr design-doc link, no Trello specifics).
- [x] **Graceful degradation.** Scribe changes (Task 8 final paragraph) explicitly handle vaults that don't use the schema.
- [x] **One repo, one branch.** All on `feat/pkm-scribe-and-vault-template`; three commits; one PR.

No issues found.
