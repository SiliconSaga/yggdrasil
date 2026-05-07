# Thalamus Arc Dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to walk this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `arcs:` frontmatter to per-machine Thalamus files and a Dataview-rendered dashboard to the thalami hoard, with three thin skill extensions covering the propose-not-act write flow.

**Architecture:** Schema in frontmatter; rendering in Obsidian via Dataview; agent behavior in existing GDD skills (orientation, flow, housekeeping). No new infrastructure, no new skill, no validation code in v1.

**Tech Stack:** Markdown + YAML frontmatter; Obsidian Dataview plugin; existing `ws` CLI for git operations.

**Spec:** [`2026-05-07-thalamus-arc-dashboard-design.md`](2026-05-07-thalamus-arc-dashboard-design.md)

---

## Notes on this plan

- **Verification model:** doc/skill/template work has no unit tests. Each task's verification is a read-back of the change and a final manual render in Obsidian (Task 14). The TDD-shaped "write failing test first" pattern from the writing-plans skill does not apply to prose changes; verification steps are explicit reads or renders instead.
- **Two repos, two branches:**
  - Yggdrasil: feature branch `feat/thalamus-arc-dashboard` (already created from `main`).
  - Thalami hoard: directly on `main` (the documented model for thalami hoards — see `gdd-housekeeping` Multi-Thalami Review section).
- **Pre-existing dirty state in thalami hoard:** `Dionysus-thalamus.md` has uncommitted body edits from prior sessions. Task 9 commits that as a checkpoint *before* arc additions, so the arc commit's diff stays focused.
- **Avoid touching bodies of sibling thalami files** (Loki, FG4WWY622F, rasmuss-mbp-2). Frontmatter only — sibling machines may have heavy in-flight body changes the user has not yet pushed.

## File map

**Yggdrasil repo:**

- Modify: `templates/thalamus.md` — add commented `arcs: []` placeholder after `staleness_days:`
- Create: `templates/hoards/thalami/dashboard.md` — Dataview query
- Modify: `templates/hoards/thalami/README.md` — add "Opening as Obsidian vault" section
- Modify: `.agent/skills/gdd-orientation/SKILL.md` — Step 7 arc surfacing + sibling-slug grep
- Modify: `.agent/skills/gdd-flow/SKILL.md` — tangent → parked-arc nudge
- Modify: `.agent/skills/gdd-housekeeping/SKILL.md` — arc audit pass + pruning rule
- Modify: `docs/gdd/hoards.md` — arc layer mention in thalami section

**Thalami hoard:**

- Create: `dashboard.md` — copy of the template
- Modify: `Dionysus-thalamus.md` — add `arcs:` (frontmatter only)
- Modify: `Loki-thalamus.md` — add `arcs:` (frontmatter only)
- Modify: `FG4WWY622F-thalamus.md` — add `arcs:` (frontmatter only)
- Modify: `rasmuss-mbp-2-thalamus.md` — add `arcs:` (frontmatter only)
- Modify: `README.md` — short note pointing at `dashboard.md`

---

## Task 1: Add `arcs:` placeholder to `templates/thalamus.md`

**Files:**
- Modify: `templates/thalamus.md` (around the `staleness_days:` line in frontmatter)

- [ ] **Step 1: Read the current frontmatter** to confirm anchor

Run: `grep -n "staleness_days" templates/thalamus.md`
Expected: a single line near the top showing the existing field.

- [ ] **Step 2: Insert the `arcs:` placeholder after `staleness_days:`**

Insert this block after the `staleness_days: 14  # ...` line (before the closing `---`):

```yaml
arcs: []            # in-flight strands of work; see docs/plans/2026-05-07-thalamus-arc-dashboard-design.md
                    # Each entry: id (slug), name, status (active|parked|closed|promoted),
                    #             started, last_touched, next; optional: issue, tags
```

- [ ] **Step 3: Verify the file still parses as YAML frontmatter**

Run: `head -20 templates/thalamus.md`
Expected: frontmatter delimiters intact (`---` open and close), `arcs:` line visible, comment lines indented under it.

---

## Task 2: Create `templates/hoards/thalami/dashboard.md`

**Files:**
- Create: `templates/hoards/thalami/dashboard.md`

- [ ] **Step 1: Write the dashboard template**

Create the file with this exact content (the inner triple-backticks for the Dataview block must remain literal):

````markdown
# Thalami Arc Dashboard

Live cross-host view of in-flight work. Renders when this hoard is opened as an Obsidian vault with the Dataview plugin installed.

Each row is one (host, arc) pair. Arcs that span hosts share an `id` slug and appear as adjacent rows under the status sort.

```dataview
TABLE WITHOUT ID
  arc.id AS "Arc",
  arc.status AS "Status",
  arc.next AS "Next",
  file.name AS "Host",
  arc.last_touched AS "Touched",
  (date(today) - date(arc.started)).days AS "Days"
FROM "."
WHERE arcs
FLATTEN arcs AS arc
SORT arc.status ASC, arc.last_touched DESC
```

## How to view

1. Open this folder as a vault in Obsidian (`File → Open vault → this folder`).
2. Install the **Dataview** community plugin (`Settings → Community plugins → Browse → "Dataview"`).
3. Open this file. The query block above renders as a live table.

## Schema

Frontmatter shape per arc entry:

```yaml
arcs:
  - id: <kebab-case-slug>          # stable across hosts; same slug = same arc
    name: <short human label>
    status: active                 # active | parked | closed | promoted
    started: 2026-05-07
    last_touched: 2026-05-07
    next: "<one-line next step>"
    # optional:
    # issue: https://github.com/<org>/<repo>/issues/<n>
    # tags: [tag-a, tag-b]
```

See [the design doc](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/plans/2026-05-07-thalamus-arc-dashboard-design.md) for full lifecycle and skill-integration details.
````

- [ ] **Step 2: Verify the file**

Run: `head -30 templates/hoards/thalami/dashboard.md`
Expected: title, intro paragraph, opening of the Dataview block visible.

---

## Task 3: Update `templates/hoards/thalami/README.md`

**Files:**
- Modify: `templates/hoards/thalami/README.md`

- [ ] **Step 1: Read the current README to find the bottom**

Run: `tail -20 templates/hoards/thalami/README.md`
Expected: section about pushing to remote.

- [ ] **Step 2: Append a new section at the end**

Add this section (with one blank line of separation before it):

```markdown
---

## Cross-host arc dashboard

This hoard ships a `dashboard.md` that renders an at-a-glance table of
in-flight work across every machine using the workspace. Open the hoard
folder as an Obsidian vault and install the Dataview community plugin
to see it live.

Each per-machine `<machine>-thalamus.md` carries an `arcs:` list in its
frontmatter; Dataview reads them and produces the cross-host table. See
`dashboard.md` itself for the schema and how-to-view instructions.

The dashboard projects only frontmatter — the body of each Thalamus
file (Observations, Concerns, Audit Log) stays put on the host that
wrote it.
```

- [ ] **Step 3: Verify**

Run: `tail -15 templates/hoards/thalami/README.md`
Expected: new section visible, ending with the "stays put on the host that wrote it" sentence.

---

## Task 4: Extend `gdd-orientation` — Step 7 arc surfacing

**Files:**
- Modify: `.agent/skills/gdd-orientation/SKILL.md` (around line 411-417, the existing Step 7 block)

- [ ] **Step 1: Read the current Step 7**

Run: `grep -n "Step 7: Session Framing" .agent/skills/gdd-orientation/SKILL.md`
Expected: the heading line. Step 7 spans roughly lines 411-417.

- [ ] **Step 2: Insert an arc-surfacing subsection inside Step 7**

After the existing Step 7 example (`> "Picking up in Developer/Zen mode..."`) and before the `## During-Session Writes` heading, insert this subsection:

```markdown
#### Active arcs (when a thalami hoard is active)

If the active thalamus file has a non-empty `arcs:` list, surface
active arcs as part of the framing:

> "Active arcs on this host: `thalamus-arc-dashboard` (started today,
> next: 'lock schema'). Picking up an existing one or starting fresh?"

Also grep sibling thalamus files in the active hoard for slugs
matching the user's session-opening topic. If a sibling host has an
active arc with a matching slug, surface the cross-host pickup:

> "Loki has an active arc `gh-pages-tutorial` from 2026-04-25. Picking
> it up here?"

If the user agrees to pick it up, propose adding the same slug to
*this* host's `arcs:` list when the first arc-shaped write happens
later in the session. Cross-host stitching is slug-discipline: same
`id` across hosts naturally clusters in the dashboard.

If `arcs:` is empty or absent (e.g. hoard predates the arc layer),
skip this subsection silently. No nudge to populate it — that's a
housekeeping concern.
```

- [ ] **Step 3: Verify the section renders correctly**

Run: `grep -A 2 "Active arcs (when a thalami hoard" .agent/skills/gdd-orientation/SKILL.md`
Expected: heading line plus the next two lines of the subsection.

---

## Task 5: Extend `gdd-flow` — tangent handling

**Files:**
- Modify: `.agent/skills/gdd-flow/SKILL.md` (after the "Flow Patterns" section, before "Multi-Agent and Multi-Workspace")

- [ ] **Step 1: Find the insertion anchor**

Run: `grep -n "## Multi-Agent and Multi-Workspace" .agent/skills/gdd-flow/SKILL.md`
Expected: the heading on a single line.

- [ ] **Step 2: Insert a new section before that heading**

Insert this section directly before `## Multi-Agent and Multi-Workspace`:

```markdown
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
```

- [ ] **Step 3: Verify**

Run: `grep -A 1 "## Tangent handling" .agent/skills/gdd-flow/SKILL.md`
Expected: heading plus first sentence.

---

## Task 6: Extend `gdd-housekeeping` — arc audit pass

**Files:**
- Modify: `.agent/skills/gdd-housekeeping/SKILL.md` (insert a new step between Step 2 and Step 3, and add a paragraph to the existing Multi-Thalami section)

- [ ] **Step 1: Find the insertion anchor for the new step**

Run: `grep -n "### Step 3: Check for Pattern Accumulation" .agent/skills/gdd-housekeeping/SKILL.md`
Expected: the heading on a single line.

- [ ] **Step 2: Insert a new "Step 2.5" section before Step 3**

Insert this section directly before `### Step 3: Check for Pattern Accumulation`:

```markdown
### Step 2.5: Walk the arcs list

If the active Thalamus has a non-empty `arcs:` list, walk it before
moving on to Step 3:

- **Stale active arcs.** Any `active` arc whose `last_touched` is more
  than ~30 days old is a candidate to flip to `parked`. Propose the
  flip; let the human confirm or push back ("no, still active").
- **Closed/promoted arcs surviving previous audit.** Two-cycle grace
  window: arcs in `closed` or `promoted` status that already survived
  one prior audit are prunable. Check the Audit Log for prior mention
  of the slug; if present, propose removing the entry from `arcs:`.
- **Inconsistencies.** Body content describing work with no matching
  `arcs:` entry, or `arcs:` entries with no body context, should be
  flagged for the human. Don't auto-resolve — ambiguous cases are
  judgment calls.

When pruning, remove the entry from `arcs:` *and* note the slug in the
Audit Log entry (Step 4) so cross-host context survives even after the
arc itself is gone.

For arcs promoted to issues, the body content should already be
gone (it lives in the issue now); the `arcs:` entry survives one more
audit so the dashboard shows the recently-closed work, then prunes.
```

- [ ] **Step 3: Find the Multi-Thalami Review heading**

Run: `grep -n "## Multi-Thalami Review" .agent/skills/gdd-housekeeping/SKILL.md`
Expected: a single line.

- [ ] **Step 4: Add a cross-host arc paragraph at the end of the Multi-Thalami Process section**

Find the line `5. Append the same audit-log entry to every reviewed` (in the Process subsection) and the section ending with `Listing the machines in that entry makes it clear at a glance which / files were in scope this round.` Insert this new paragraph immediately after that last line:

```markdown
6. For arcs specifically: identify slugs that exist on multiple hosts
   and confirm they refer to the same work — if drift has happened (two
   slugs for the same topic), propose a rename so the dashboard
   collapses them into adjacent rows. Closed/promoted arcs on one host
   but still `active` on another are common during cross-host handoff;
   leave those alone unless the human confirms the work is done.
```

- [ ] **Step 5: Verify both insertions**

Run: `grep -n "Step 2.5: Walk the arcs list\|For arcs specifically" .agent/skills/gdd-housekeeping/SKILL.md`
Expected: two lines, one for each insertion.

---

## Task 7: Update `docs/gdd/hoards.md`

**Files:**
- Modify: `docs/gdd/hoards.md` (in the "Per-machine files" section, near the frontmatter list)

- [ ] **Step 1: Find the anchor**

Run: `grep -n "Frontmatter.*for per-machine state" docs/gdd/hoards.md`
Expected: a single line near the top of the per-machine-files section.

- [ ] **Step 2: Read the surrounding lines** to find the end of the frontmatter bullet list

Run: `sed -n '78,100p' docs/gdd/hoards.md`
Expected: the existing bullet list of frontmatter fields.

- [ ] **Step 3: Append an arcs-layer note after the frontmatter bullet list**

After the closing of the frontmatter bullet list (and before the next subsection), insert a short paragraph:

```markdown
Per-machine files also carry an `arcs:` list — short entries (slug,
status, next step) that surface as a live cross-host table when the
hoard is opened as an Obsidian vault with the Dataview plugin
installed. See [the arc dashboard
design](../plans/2026-05-07-thalamus-arc-dashboard-design.md) for the
schema, lifecycle, and skill integration; see the hoard's own
`dashboard.md` for the rendered view.
```

- [ ] **Step 4: Verify**

Run: `grep -A 1 "Per-machine files also carry an" docs/gdd/hoards.md`
Expected: paragraph visible.

---

## Task 8: Commit yggdrasil changes

**Files:**
- Create: `.commits/feat-thalamus-arc-dashboard.md`

- [ ] **Step 1: Write the commit bodyfile**

Create `.commits/feat-thalamus-arc-dashboard.md` with this exact content:

````markdown
---
message: "feat(gdd): thalamus arc dashboard — frontmatter projection rendered in Obsidian"

add:
  - templates/thalamus.md
  - templates/hoards/thalami/dashboard.md
  - templates/hoards/thalami/README.md
  - .agent/skills/gdd-orientation/SKILL.md
  - .agent/skills/gdd-flow/SKILL.md
  - .agent/skills/gdd-housekeeping/SKILL.md
  - docs/gdd/hoards.md
  - .commits/feat-thalamus-arc-dashboard.md
---

Add an `arcs:` list to per-machine Thalamus frontmatter, plus a Dataview-rendered `dashboard.md` template for the thalami hoard. Cross-host visibility into in-flight work without a CI pipeline, a Pages site, or any new infrastructure — Obsidian + Dataview, opened on each machine.

Three thin extensions to existing GDD skills carry the agent behavior:

- `gdd-orientation` Step 7 surfaces active arcs and grep-matches sibling-host slugs against the session-opening topic
- `gdd-flow` proposes a parked arc on tangent detection (propose-not-act)
- `gdd-housekeeping` walks arcs as Step 2.5: stale-active flip, two-cycle grace prune, drift detection across hosts

Schema is intentionally thin — `id` (slug, stable across hosts), `name`, `status`, `started`, `last_touched`, `next`; optional `issue` and `tags`. Pruning, slug discipline, and lifecycle transitions documented in the design doc and reflected in the skill prose.

Refs: docs/plans/2026-05-07-thalamus-arc-dashboard-design.md
````

- [ ] **Step 2: Run the commit**

Run: `bash scripts/ws commit yggdrasil .commits/feat-thalamus-arc-dashboard.md`
Expected: a single new commit on `feat/thalamus-arc-dashboard` with the seven file changes.

- [ ] **Step 3: Verify**

Run: `git log --oneline -3`
Expected: the new commit on top, then the design-doc commit, then the prior tip of `main`.

---

## Task 9: Checkpoint dirty state in thalami hoard

**Files:**
- Create: `.commits/thalami-checkpoint-dionysus.md` (in yggdrasil's `.commits/` — the bodyfile lives here even when committing into a hoard)

This task commits the *existing* dirty body content in `Dionysus-thalamus.md` (accumulated across prior sessions) so that Task 11's arc-only commit has a clean diff.

- [ ] **Step 1: Confirm what's dirty**

Run: `git -C hoards/thalami-Cervator status -s`
Expected: a single line `M Dionysus-thalamus.md`.

- [ ] **Step 2: Pull/rebase first** (single-main-branch hoard, multiple writers)

Run: `bash scripts/ws pull thalami-Cervator`
Expected: rebase succeeds (no other host has likely pushed since last sync, but check for completeness). If a conflict appears, stop and surface it to the user.

- [ ] **Step 3: Write the checkpoint bodyfile**

Create `.commits/thalami-checkpoint-dionysus.md`:

```markdown
---
message: "chore: checkpoint Dionysus-thalamus.md from prior sessions"

add:
  - Dionysus-thalamus.md
---

Save accumulated body edits from sessions 2026-05-02 through 2026-05-07 before introducing the `arcs:` frontmatter layer. Diff is body-only (Observations, Upcoming Work, audit notes); no frontmatter fields touched in this commit.
```

- [ ] **Step 4: Run the commit**

Run: `bash scripts/ws commit thalami-Cervator .commits/thalami-checkpoint-dionysus.md`
Expected: a single new commit on the hoard's `main`.

- [ ] **Step 5: Verify**

Run: `git -C hoards/thalami-Cervator log --oneline -3`
Expected: checkpoint commit on top.

---

## Task 10: Identify arcs to seed in each thalami file

**Files (read-only):**
- `hoards/thalami-Cervator/Dionysus-thalamus.md`
- `hoards/thalami-Cervator/Loki-thalamus.md`
- `hoards/thalami-Cervator/FG4WWY622F-thalamus.md`
- `hoards/thalami-Cervator/rasmuss-mbp-2-thalamus.md`

This is the analysis task: read each file, extract candidate arcs from the body content, build the per-host arc lists. **No file writes in this task.**

- [ ] **Step 1: Re-read each thalami file in full**

Run: read each file with the Read tool (already done for Dionysus during planning; refresh the others).

- [ ] **Step 2: For each file, extract 2-5 arc candidates** based on these heuristics:

- Sections explicitly framed as "Upcoming Work", "Active focus", "Next session" → likely active arcs
- Bulleted brain-dumps under Observations describing in-flight ideas → parked arcs
- Items mentioning "design doc next session" / "ready to write" / "pending" → active arcs
- Recently merged or closed PR mentions → candidates for closed/promoted arcs (low priority for v1 seed)
- Status of each: derive from the surrounding language ("ready for design" → active; "future direction" → parked)
- `started:` and `last_touched:` dates: pull from the closest dated context in the body; default `started:` to the file's earliest mention of the topic, `last_touched:` to today's date if the topic is currently active, otherwise the most recent mention

- [ ] **Step 3: Write the arc lists to a scratch file** for use in Tasks 11-14

Create `.outputs/seeded-arcs.yaml` with one section per host containing the proposed `arcs:` list. Use it as the source-of-truth for the four file edits in Tasks 11-14. Format:

```yaml
# Dionysus-thalamus.md
arcs:
  - id: <slug>
    name: <name>
    status: <status>
    started: <date>
    last_touched: <date>
    next: <one-line>

# Loki-thalamus.md
arcs:
  ...
```

The scratch file is gitignored under `.outputs/` — it's working notes only, not part of the commit.

---

## Task 11: Add `arcs:` to `Dionysus-thalamus.md`

**Files:**
- Modify: `hoards/thalami-Cervator/Dionysus-thalamus.md` — frontmatter only

- [ ] **Step 1: Locate the frontmatter** (lines 1-8)

Run: `head -10 hoards/thalami-Cervator/Dionysus-thalamus.md`
Expected: the frontmatter block.

- [ ] **Step 2: Insert the `arcs:` block before the closing `---` on line 8**

Use the Dionysus arc list from `.outputs/seeded-arcs.yaml` (Task 10).

- [ ] **Step 3: Verify** the body is unchanged

Run: `git -C hoards/thalami-Cervator diff Dionysus-thalamus.md | head -40`
Expected: only frontmatter additions visible in the diff; no body changes.

---

## Task 12: Add `arcs:` to `Loki-thalamus.md`

**Files:**
- Modify: `hoards/thalami-Cervator/Loki-thalamus.md` — frontmatter only

- [ ] **Step 1: Locate the frontmatter** (lines 1-8)

Run: `head -10 hoards/thalami-Cervator/Loki-thalamus.md`

- [ ] **Step 2: Insert the `arcs:` block before the closing `---`**

Use the Loki arc list from `.outputs/seeded-arcs.yaml`.

- [ ] **Step 3: Verify body is untouched**

Run: `git -C hoards/thalami-Cervator diff Loki-thalamus.md | grep "^[-+]" | grep -v "^[-+]+++\|^[-+]---" | head -40`
Expected: only `+` lines in the frontmatter region. Zero `-` lines (body content unchanged).

---

## Task 13: Add `arcs:` to `FG4WWY622F-thalamus.md`

**Files:**
- Modify: `hoards/thalami-Cervator/FG4WWY622F-thalamus.md` — frontmatter only

- [ ] **Step 1: Locate the frontmatter**

Run: `head -10 hoards/thalami-Cervator/FG4WWY622F-thalamus.md`

- [ ] **Step 2: Insert the `arcs:` block** using the FG4 arc list from `.outputs/seeded-arcs.yaml`

- [ ] **Step 3: Verify body untouched**

Run: `git -C hoards/thalami-Cervator diff FG4WWY622F-thalamus.md | grep "^-" | grep -v "^---" | head`
Expected: empty output (no body deletions).

---

## Task 14: Add `arcs:` to `rasmuss-mbp-2-thalamus.md`

**Files:**
- Modify: `hoards/thalami-Cervator/rasmuss-mbp-2-thalamus.md` — frontmatter only

- [ ] **Step 1: Locate the frontmatter**

Run: `head -10 hoards/thalami-Cervator/rasmuss-mbp-2-thalamus.md`

- [ ] **Step 2: Insert the `arcs:` block** using the rasmuss-mbp-2 arc list from `.outputs/seeded-arcs.yaml`

- [ ] **Step 3: Verify body untouched**

Run: `git -C hoards/thalami-Cervator diff rasmuss-mbp-2-thalamus.md | grep "^-" | grep -v "^---" | head`
Expected: empty output.

---

## Task 15: Copy `dashboard.md` and update README in thalami hoard

**Files:**
- Create: `hoards/thalami-Cervator/dashboard.md` (copy of the template)
- Modify: `hoards/thalami-Cervator/README.md` (add a one-line pointer at the top)

- [ ] **Step 1: Copy the template into the hoard**

Run: `cp templates/hoards/thalami/dashboard.md hoards/thalami-Cervator/dashboard.md`
Expected: file created.

- [ ] **Step 2: Verify the copy**

Run: `head -20 hoards/thalami-Cervator/dashboard.md`
Expected: same content as the template.

- [ ] **Step 3: Add a pointer line to the hoard's README.md**

Read `hoards/thalami-Cervator/README.md`, find a sensible location near the top (after the introductory paragraph, before the Layout section), and insert:

```markdown
**Dashboard:** open this folder as an Obsidian vault with the Dataview
plugin installed; `dashboard.md` renders a live cross-host table of
in-flight arcs from each `<machine>-thalamus.md` frontmatter.
```

- [ ] **Step 4: Verify**

Run: `head -15 hoards/thalami-Cervator/README.md`
Expected: the new pointer paragraph visible near the top.

---

## Task 16: Commit thalami arc additions

**Files:**
- Create: `.commits/thalami-add-arcs.md`

- [ ] **Step 1: Write the commit bodyfile**

Create `.commits/thalami-add-arcs.md`:

```markdown
---
message: "feat: seed arcs frontmatter across all hosts; add dashboard.md"

add:
  - Dionysus-thalamus.md
  - Loki-thalamus.md
  - FG4WWY622F-thalamus.md
  - rasmuss-mbp-2-thalamus.md
  - dashboard.md
  - README.md
---

Initial seed of in-flight arcs across the four host thalamus files. Frontmatter-only edits — bodies untouched (sibling hosts may have unpushed body changes from concurrent workspaces).

Adds `dashboard.md` rendering the cross-host table via Obsidian Dataview, plus a pointer line in the hoard README.

Refs: yggdrasil docs/plans/2026-05-07-thalamus-arc-dashboard-design.md
```

- [ ] **Step 2: Run the commit**

Run: `bash scripts/ws commit thalami-Cervator .commits/thalami-add-arcs.md`
Expected: single commit with six files modified/created.

- [ ] **Step 3: Verify**

Run: `git -C hoards/thalami-Cervator log --oneline -5`
Expected: the new commit on top, the checkpoint commit beneath, then prior history.

- [ ] **Step 4: Push**

Run: `bash scripts/ws push thalami-Cervator`
Expected: success. (If push fails non-fast-forward, run `ws pull thalami-Cervator` first to rebase, then re-push.)

---

## Task 17: Hand off to user for Obsidian-render validation

This is the natural test point. The user installs/configures Obsidian and confirms the dashboard renders.

- [ ] **Step 1: Surface to the user**

Send this message:

> "All edits in. Ready for the render test:
>
> 1. Open `hoards/thalami-Cervator/` as an Obsidian vault (`File → Open vault`)
> 2. Settings → Community plugins → Browse → search 'Dataview' → install + enable
> 3. Open `dashboard.md` — the Dataview block should render a table with one row per (host, arc) pair.
>
> If anything looks off (rows missing, columns wrong, sort order ugly), let me know and I'll iterate on the query."

- [ ] **Step 2: Wait for feedback** before opening the yggdrasil PR

The yggdrasil branch is not yet pushed. Hold off on `ws push yggdrasil` and `ws cr yggdrasil` until the user has confirmed the render works — if the query needs tweaking, the change lives in `templates/hoards/thalami/dashboard.md` and should ride the same PR rather than land as a follow-up.

---

## Self-review (run after writing the plan)

- [x] Spec coverage:
  - Schema (Section "Schema") → Tasks 1, 11-14
  - Skill integrations (orientation, flow, housekeeping) → Tasks 4, 5, 6
  - Cross-host slug discipline → Tasks 4 (orientation grep), 6 (housekeeping drift detection)
  - Lifecycle and pruning → Task 6 (housekeeping)
  - Dashboard query → Tasks 2, 15
  - Components and files touched → covered by file map and Tasks 1-7, 11-15
  - Testing and validation → Task 17 (manual render check)
  - All non-goals respected (no static-page renderer, no `ws hoard arc` CLI, no autonomous bookkeeping, no migration tooling)

- [x] No placeholders. Every step has concrete content, an exact command, or a precise insertion specification.

- [x] Type/name consistency. `arcs:` field name used uniformly across schema, queries, skill prose, and commit messages. Slug examples consistent (`thalamus-arc-dashboard`, `gh-pages-tutorial`).

- [x] Two-repo flow. Yggdrasil (Tasks 1-8) lands first; thalami hoard (Tasks 9-16) follows; render-test gate (Task 17) before yggdrasil PR.

No issues found.
