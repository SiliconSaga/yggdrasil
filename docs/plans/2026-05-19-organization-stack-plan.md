# Organization Stack — Bridge Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the independently-shippable "bridge slice" of the organization-stack model — the machine-agnostic `Intake.md` staging file plus the scribe/GDD skill updates that populate and drain it, and the user-facing documentation.

**Architecture:** No code or scripts. The work is one new template file, three skill-prose edits, and two documentation files, all in the `yggdrasil` repo. The skills resolve `Intake.md` as a sibling of the per-machine thalamus file (root of the active thalami hoard) — no new `ws` subcommand. The scribe ceremony populates `Intake.md` from `#gdd`-tagged daily-note bullets; GDD orientation surfaces it; GDD housekeeping drains it into arcs.

**Tech Stack:** Markdown. Workspace conventions: `ws commit` with `.commits/` bodyfiles; `ws test yggdrasil` (bats) for the test suite.

**Scope boundary:** This plan covers only the bridge slice. The durable-tier sweep rides with SP-B (companion GitHub Project); the graduation-to-Docs seam rides with SP-C (component docs convention). See `docs/plans/2026-05-19-organization-stack-design.md` for the full model.

**Branch:** All commits go on the existing `docs/organization-stack-design` branch (already carries the design-doc commit `ed3e6a7`).

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `templates/hoards/thalami/Intake.md` | Create | Template for the machine-agnostic intake file; new thalami hoards get it |
| `templates/hoards/thalami/README.md` | Modify | Document `Intake.md` alongside the existing ArcDashboard section |
| `.agent/skills/scribe/SKILL.md` | Modify | Add "The GDD Bridge" section — populate `Intake.md` from `#gdd` daily-note bullets |
| `.agent/skills/gdd-orientation/SKILL.md` | Modify | Surface unclaimed `Intake.md` items at session framing |
| `.agent/skills/gdd-housekeeping/SKILL.md` | Modify | Add "Step 2.6: Drain the Intake" — promote intake items to arcs |
| `docs/gdd/organization-stack.md` | Create | User-facing reference page for the model |
| `docs/gdd/features.md` | Modify | Add an "Organization stack" section linking the new page |

The live `Intake.md` in the user's `hoards/thalami-Cervator/` is **not** a plan task — the scribe skill creates it on demand from the template shape the first time the bridge fires (Task 2 specifies this).

---

## Task 1: The `Intake.md` template + thalami README

**Files:**
- Create: `templates/hoards/thalami/Intake.md`
- Modify: `templates/hoards/thalami/README.md` (append a new section at the end of the file, after the existing "Cross-host arc dashboard" section)
- Test: `ws test yggdrasil` (bats suite)

- [ ] **Step 1: Create the `Intake.md` template**

Create `templates/hoards/thalami/Intake.md` with exactly this content:

```markdown
# Intake

Machine-agnostic staging for pre-arc GDD work. The scribe ceremony populates this file from `#gdd`-tagged daily-note bullets (the "bridge"); the GDD ceremony drains it — orientation surfaces unclaimed items, housekeeping promotes them to arcs when justified.

This file is *staging*, not a tracker. Items here have not yet been shaped into arcs or assigned to a machine. Keep it short — a growing Intake means the GDD ceremony is not draining often enough.

See the [organization-stack model](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/gdd/organization-stack.md) for how the bridge fits the wider picture.

## Items

<!-- One bullet per pre-arc item. Optional inline metadata: (from: <host or vault>, captured: YYYY-MM-DD). Drained by GDD housekeeping Step 2.6. -->
```

- [ ] **Step 2: Document `Intake.md` in the thalami README**

In `templates/hoards/thalami/README.md`, append the following section at the end of the file (after the existing "Cross-host arc dashboard" section and its setup steps):

```markdown

---

## Intake — the GDD bridge

This hoard also carries an `Intake.md` at its root: machine-agnostic staging for pre-arc GDD work. The scribe ceremony moves `#gdd`-tagged items out of a vault daily note and into this file; the GDD ceremony (orientation surfaces it, housekeeping drains it) routes each item to a machine and promotes it to an arc when the work justifies one.

`Intake.md` is staging, not a tracker — it is meant to stay short. New hoards are scaffolded with it; existing hoards get one created on demand the first time the scribe bridge fires.
```

- [ ] **Step 3: Verify the test suite still passes**

Run: `bash scripts/ws test yggdrasil`
Expected: PASS — adding a template file and a README section does not affect the bats suite (which tests `ws` script behavior, not template inventory). If any test fails, investigate before continuing.

- [ ] **Step 4: Commit**

Create `.commits/intake-template.md`:

```markdown
---
message: "feat(hoards): add Intake.md template to thalami hoard"
add:
  - templates/hoards/thalami/Intake.md
  - templates/hoards/thalami/README.md
---

Adds the machine-agnostic Intake.md staging file to the thalami hoard template — the shared surface for the organization-stack bridge. The scribe ceremony populates it from #gdd-tagged daily-note bullets; the GDD ceremony drains it into arcs.

Part of the SP-D organization-stack bridge slice; see docs/plans/2026-05-19-organization-stack-plan.md.
```

Run: `bash scripts/ws commit yggdrasil .commits/intake-template.md`
Expected: commit created on `docs/organization-stack-design`.

---

## Task 2: Scribe skill — the bridge

**Files:**
- Modify: `.agent/skills/scribe/SKILL.md` (insert a new section between `## Ceremony Layers` and `## De-AI-ifying Text`)

- [ ] **Step 1: Add "The GDD Bridge" section**

In `.agent/skills/scribe/SKILL.md`, insert the following new section immediately after the end of the `## Ceremony Layers` section (after the "Waiting-room surface" subsection) and immediately before `## De-AI-ifying Text`:

```markdown
## The GDD Bridge

GDD-bound work captured in the vault — anything tagged `#gdd` in a daily note — does not belong in the vault long-term. It belongs in GDD-land: a per-machine Thalamus, and ultimately an arc. The **bridge** is the scribe ceremony's hand-off of those items into the thalami hoard's `Intake.md`, a machine-agnostic staging file the GDD ceremony later drains.

The scribe skill only *moves items across* the bridge — it never decides whether something becomes an arc. That judgment belongs to the GDD ceremony (orientation surfaces the Intake; housekeeping drains it). See @gdd-housekeeping Step 2.6.

### When the bridge fires

During the daily review, inbox processing, or a weekly sweep, watch for daily-note bullets tagged `#gdd`. For each one, propose moving it to the active thalami hoard's `Intake.md`:

> "`Test the updated GDD hook on the work laptop` is tagged `#gdd` — move it to the thalami-hoard Intake so the GDD ceremony can route it?"

This is propose-then-confirm like every other ceremony move — never shift an item silently.

### Locating and creating Intake.md

`Intake.md` lives at the root of the active thalami hoard, beside `ArcDashboard.md` — the same directory as the per-machine `*-thalamus.md` files. Resolve the hoard with `ws hoard thalamus-path` and take the sibling `Intake.md`. If no thalami hoard is active, tell the user the bridge has nowhere to go and leave the item in the daily note. If the hoard is active but `Intake.md` does not exist yet, create it from the `templates/hoards/thalami/Intake.md` shape before adding the first item.

### Applying a move

When the user confirms, append a bullet to the `## Items` section of `Intake.md`:

`- <item text> (from: <host or vault>, captured: YYYY-MM-DD)`

Then check off or remove the originating daily-note bullet per the vault's normal task convention. The thalami hoard is a separate git repo — the move commits with the hoard's normal commit cadence (see @gdd-orientation Step 0a), not a forced commit.
```

- [ ] **Step 2: Verify cross-references resolve**

Read the inserted section back and confirm: the `@gdd-housekeeping Step 2.6` reference matches the step added in Task 4, and `@gdd-orientation Step 0a` exists in `gdd-orientation/SKILL.md` (it does — the commit-cadence step). Confirm the section sits between `## Ceremony Layers` and `## De-AI-ifying Text`.
Expected: both references valid; section correctly placed.

- [ ] **Step 3: Commit**

Create `.commits/scribe-bridge.md`:

```markdown
---
message: "feat(scribe): add the GDD bridge — populate thalami Intake.md"
add:
  - .agent/skills/scribe/SKILL.md
---

Adds "The GDD Bridge" section to the scribe skill: during ceremonies, #gdd-tagged daily-note bullets are proposed for the thalami hoard's Intake.md (created on demand). The scribe skill only moves items across the bridge; arc-worthiness is the GDD ceremony's call.

Part of the SP-D organization-stack bridge slice.
```

Run: `bash scripts/ws commit yggdrasil .commits/scribe-bridge.md`
Expected: commit created.

---

## Task 3: GDD orientation — surface unclaimed Intake items

**Files:**
- Modify: `.agent/skills/gdd-orientation/SKILL.md` (insert a subsection into Step 7, after the "Active arcs" subsection)

- [ ] **Step 1: Add the "Unclaimed intake items" subsection**

In `.agent/skills/gdd-orientation/SKILL.md`, Step 7 ("Session Framing") contains a subsection `#### Active arcs (when a thalami hoard is active)`. Immediately after that subsection ends (after the line about skipping the subsection when `arcs:` is empty) and before `## During-Session Writes`, insert:

```markdown
#### Unclaimed intake items (when a thalami hoard is active)

The thalami hoard may carry an `Intake.md` at its root — machine-agnostic staging for pre-arc GDD work the scribe bridge has handed off. At session framing, if `Intake.md` exists and its `## Items` section is non-empty, surface a one-liner:

> "3 unclaimed items in the thalami Intake. Drain them into arcs as part of this session, or leave for housekeeping?"

This is advisory, not a gate. Draining the Intake is the GDD housekeeping skill's job (see @gdd-housekeeping Step 2.6); orientation only makes the items visible so they are not forgotten. If `Intake.md` is absent or its `## Items` section is empty, stay silent — no "intake is empty" noise.
```

- [ ] **Step 2: Verify placement**

Read the surrounding lines back. Confirm the new subsection is inside Step 7, directly after "Active arcs", and that `## During-Session Writes` still follows. Confirm the `@gdd-housekeeping Step 2.6` reference matches Task 4.
Expected: subsection correctly placed; reference valid.

- [ ] **Step 3: Commit**

Create `.commits/orientation-intake.md`:

```markdown
---
message: "feat(gdd-orientation): surface unclaimed thalami Intake items"
add:
  - .agent/skills/gdd-orientation/SKILL.md
---

Adds an "Unclaimed intake items" subsection to Step 7 session framing: when the active thalami hoard's Intake.md has non-empty Items, orientation surfaces a one-line advisory. Draining stays a housekeeping job; orientation only makes pre-arc work visible.

Part of the SP-D organization-stack bridge slice.
```

Run: `bash scripts/ws commit yggdrasil .commits/orientation-intake.md`
Expected: commit created.

---

## Task 4: GDD housekeeping — drain the Intake

**Files:**
- Modify: `.agent/skills/gdd-housekeeping/SKILL.md` (insert a new step between `### Step 2.5: Walk the arcs list` and `### Step 3: Check for Pattern Accumulation`)

- [ ] **Step 1: Add "Step 2.6: Drain the Intake"**

In `.agent/skills/gdd-housekeeping/SKILL.md`, immediately after the `### Step 2.5: Walk the arcs list` section ends (after the paragraph about arcs promoted to issues) and before `### Step 3: Check for Pattern Accumulation`, insert:

```markdown
### Step 2.6: Drain the Intake

If the active thalami hoard has an `Intake.md` with a non-empty `## Items` section, walk it with the human before Step 3. Each item is pre-arc GDD work the scribe bridge handed off — staging, not a tracker. For each item, propose one of:

- **Promote to an arc** — the item is real, scoped GDD work. Add an `arcs:` entry to the appropriate host's `*-thalamus.md` (usually this host; ask if another machine is the better home), then remove the item from `Intake.md`.
- **Fold into an existing arc** — the item is part of work already tracked. Note it on that arc's `next` or body context, then remove it from `Intake.md`.
- **Route without an arc** — the item is a one-off (a quick fix, a doc tweak) that does not justify an arc. Do it now or note it where it belongs, then remove it from `Intake.md`.
- **Leave** — not yet actionable; keep it in `Intake.md` for the next pass.

`Intake.md` is meant to stay short. If it keeps growing audit-over-audit, the GDD ceremony is not draining often enough — surface that to the human as a process observation.
```

- [ ] **Step 2: Verify placement and numbering**

Read the surrounding lines back. Confirm the new step is numbered `2.6`, sits between Step 2.5 and Step 3, and that no other step numbering needs to shift (Step 3 onward is unchanged).
Expected: step correctly placed; numbering consistent.

- [ ] **Step 3: Commit**

Create `.commits/housekeeping-intake.md`:

```markdown
---
message: "feat(gdd-housekeeping): add Step 2.6 — drain the thalami Intake"
add:
  - .agent/skills/gdd-housekeeping/SKILL.md
---

Adds Step 2.6 to the housekeeping process: walk the thalami hoard's Intake.md with the human, promoting pre-arc items to arcs, folding them into existing arcs, routing one-offs, or leaving them. Closes the GDD-ceremony end of the organization-stack bridge.

Part of the SP-D organization-stack bridge slice.
```

Run: `bash scripts/ws commit yggdrasil .commits/housekeeping-intake.md`
Expected: commit created.

---

## Task 5: The `organization-stack.md` reference page

**Files:**
- Create: `docs/gdd/organization-stack.md`

This page is the user-facing retelling of the committed design doc. Source: `docs/plans/2026-05-19-organization-stack-design.md`. House style: match `docs/gdd/thalamus.md` and `docs/gdd/self-improving-loop.md` — explanatory prose, no implementation/meta sections. Drop the design doc's "Problem", "Open questions", "Facet boundaries", and "Documentation" sections; keep the model.

- [ ] **Step 1: Create the page**

Create `docs/gdd/organization-stack.md` with these sections, in order:

1. **`# The Organization Stack`** + a 2-3 sentence intro: work in this ecosystem lives across an Obsidian vault, the Thalamus/arcs, component docs, and GitHub; the organization stack is the model that names those tiers and the promotion paths between them.
2. **`## The four tiers`** — reproduce the four-tier table from the design doc's "The four tiers" section (Vault / Thalami / Docs / GitHub, with Audience/purpose and Horizon columns), plus the design doc's follow-up paragraph about both Vault and Thalami being cross-machine.
3. **`## The two ceremonies`** — the scribe ceremony and GDD ceremony, the seams each owns, and the bridge (the process of populating/draining `Intake.md`). Reproduce the Mermaid flow diagram from the design doc's "The seams" section verbatim (it already satisfies the Mermaid rules — no `\n`, no fill colors).
4. **`## Capture wide, route narrow`** — the two capture surfaces and the three routing questions (Horizon / Audience / Durability) from the design doc's "Routing rule" section, plus the "belongs in two places dissolves" paragraph.
5. **`## Graduation`** — the three-way split of a closing arc's residue (knowledge → Docs, trackable work → GitHub, process residue → pruned) and the "companions, not redundant" paragraph, from the design doc's "Graduation" section.
6. **`## The cadence ladder`** — reproduce the cadence-ladder table and the durable-tier-sweep / weekly-vs-monthly paragraphs from the design doc.
7. **`## Start small`** — the incremental-adoption path (Vault only → + Thalami → + Docs/GitHub) from the design doc's "Incremental adoption" section.
8. A closing line linking the full design doc: `Full design and rationale: [organization-stack design doc](../plans/2026-05-19-organization-stack-design.md).`

Do not invent new content — every section is a restatement of the named design-doc section in user-facing prose. Keep prose unwrapped (one paragraph per line) per the writing-yggdrasil-docs convention.

- [ ] **Step 2: Verify links and diagram**

Confirm: the relative link `../plans/2026-05-19-organization-stack-design.md` resolves from `docs/gdd/`; the Mermaid block has no `\n` in labels and no `style ... fill:` lines. Read the page top to bottom for internal consistency.
Expected: links resolve, diagram clean, no contradictions.

- [ ] **Step 3: Commit**

Create `.commits/organization-stack-doc.md`:

```markdown
---
message: "docs(gdd): add organization-stack reference page"
add:
  - docs/gdd/organization-stack.md
---

Adds the user-facing organization-stack reference page under docs/gdd/ — the four tiers, the two ceremonies and the bridge, capture-wide/route-narrow, graduation, the cadence ladder, and the start-small adoption path. Restates the committed design doc for newcomers.

Part of the SP-D organization-stack bridge slice.
```

Run: `bash scripts/ws commit yggdrasil .commits/organization-stack-doc.md`
Expected: commit created.

---

## Task 6: Features tour section

**Files:**
- Modify: `docs/gdd/features.md` (insert a section before `## Next steps`)

- [ ] **Step 1: Add the "Organization stack" section**

In `docs/gdd/features.md`, immediately before the `## Next steps` section, insert:

```markdown
## The organization stack — capture to durable knowledge

Work in this ecosystem moves through four tiers: the **Vault** (a personal Obsidian hoard for life organization), the **Thalami** hoard (the Thalamus and in-flight arcs), component **Docs**, and **GitHub** (issues, PRs, the companion Project board). The *organization stack* is the model that names these tiers and the promotion paths between them, so nothing captured gets lost in a seam.

Two propose-then-confirm ceremonies move items across the tiers. The **scribe ceremony** triages the vault and hands GDD-bound items to a machine-agnostic `Intake.md` — the *bridge*. The **GDD ceremony** drains that intake into arcs, and graduates a closing arc's lasting value out to component docs and GitHub. A cadence ladder (daily / weekly / monthly) keeps each tier reviewed.

The model is adopt-as-you-grow: the Vault and scribe ceremony are a complete system on their own; the Thalami bridge, then the Docs and GitHub seams, layer on when the work calls for them.

Full reference: [organization-stack.md](organization-stack.md). Design and rationale: [the design doc](../plans/2026-05-19-organization-stack-design.md).
```

- [ ] **Step 2: Check the GDD docs index**

Read `docs/gdd/index.md`. If it contains an enumerated list or table of the `docs/gdd/` pages, add an `organization-stack.md` entry consistent with the existing entries' format. If it has no such list, make no change.
Expected: index updated only if it indexes the gdd pages.

- [ ] **Step 3: Verify links**

Confirm both links in the new features.md section resolve: `organization-stack.md` (same directory) and `../plans/2026-05-19-organization-stack-design.md`.
Expected: links resolve.

- [ ] **Step 4: Commit**

Create `.commits/features-org-stack.md`:

```markdown
---
message: "docs(gdd): add organization-stack section to the features tour"
add:
  - docs/gdd/features.md
---

Adds an "organization stack" section to the GDD Features Tour, introducing the four-tier model, the two ceremonies and the bridge, and the adopt-as-you-grow path. Links the organization-stack reference page and the design doc.

Part of the SP-D organization-stack bridge slice.
```

If `docs/gdd/index.md` was modified in Step 2, add it to the `add:` list and mention it in the body.

Run: `bash scripts/ws commit yggdrasil .commits/features-org-stack.md`
Expected: commit created.

---

## After the plan

All six tasks land on `docs/organization-stack-design` alongside the design-doc commit. When the user is ready, push and open a CR:

- `bash scripts/ws diagnose yggdrasil` — confirm token coverage (first push of the session).
- `bash scripts/ws push yggdrasil`
- Draft the CR body from `templates/change.md` into `.crs/organization-stack.md`, then `bash scripts/ws cr yggdrasil "feat: organization-stack model + bridge slice" .crs/organization-stack.md`.

The CR description should note it contains both the SP-D design doc (the whole model) and the bridge-slice implementation (the buildable subset), with the durable-tier sweep and Docs-graduation seam explicitly deferred to SP-B and SP-C.

## Verification summary

There is no automated test for prose changes. Verification per task is: cross-reference validity (skill `@`-references and relative doc links resolve), correct placement of inserted sections, and `ws test yggdrasil` green after the template change (Task 1). The functional proof is exercising the bridge in a real session — capture a `#gdd` item, run the scribe ceremony, confirm it lands in `Intake.md`, then run housekeeping and confirm it drains to an arc.
