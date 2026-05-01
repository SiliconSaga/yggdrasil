# Scribe Role and Vault Templates — Design

**Status:** Draft, awaiting review
**Date:** 2026-05-01
**Owner:** Rasmus Praestholm
**Related:** [Realms and Hoards Design](2026-04-24-realms-and-hoards-design.md), [Component Templates Design](2026-04-25-component-templates-design.md)

## Overview

Add first-class support for working with Obsidian-style vaults from within a
Guardian Driven Development (GDD) workspace. Two flavors of vault are supported:
plain Obsidian and [Claudesidian](https://github.com/heyitsnoah/claudesidian)
(Noah Brier's Claude-Code-friendly Obsidian starter kit). Vaults live as
hoards under `hoards/<name>/`, classified by a new deterministic scanner, and
operated against by a new `scribe` role with two layered skills.

The user can run a single Claude session from the yggdrasil root and treat any
vault as a workflow surface — including invoking Claudesidian-style commands
in plain text (e.g. *"do a weekly synthesis"*) — without the harness having to
load Claudesidian's `.claude/` directory natively. Running Claude standalone
inside a Claudesidian hoard remains supported and is documented as the
"native experience" for users who prefer it.

## Goals

1. **Single-session vault work** — operate on any vault from yggdrasil root
   without `cd`-ing or restarting Claude
2. **Lightweight bridge** — no harness-level integration (no copying hooks,
   no symlinking commands into `~/.claude/commands/`); rely on plain-text
   invocation and on-demand file reads
3. **Two-template scaffold** — `obsidian-vault` (vendored, vanilla) and
   `claudesidian-vault` (thin wrapper that clones upstream on init)
4. **Respectful vendoring** — Claudesidian is referenced by URL with
   attribution and license preservation, not vendored wholesale
5. **Agent-agnostic** — primary instructions live in agent-neutral files
   (`AGENTS.md`, skill `SKILL.md` files) so non-Claude agents (e.g. Gemini)
   can also operate the same workflow
6. **Composable with existing GDD** — scribe is a peer role to developer /
   designer / reviewer; modes (zen/quick/flow/mentoring) compose orthogonally;
   no new mode required
7. **Deterministic discovery** — vault detection and classification go through
   a `ws` subcommand with structured output, not skill prose

## Non-goals

The following are explicitly out of scope for v1:

- `ws hoard inspect <name>` — single-hoard deep-dive subcommand
- `ws template upgrade` — full template-refresh tooling (likely
  Backstage-backed in a future iteration; separate brainstorm)
- MCP wiring for the Gemini Vision server bundled with Claudesidian
- Multi-Thalamus-per-workspace or multi-workspace-per-machine handling
- Curated Obsidian plugin presets in the plain-vault template
- Commit-cadence reminders for vault hoards (different model from thalami sync)
- Cross-vault search or a unified vault index

These are acknowledged as legitimate future concerns; the v1 surface should
not preclude any of them.

## Role and mode framing

GDD's mode/role split is formalized as part of this design:

| Axis | Question it answers | Examples | Persistence |
|------|---------------------|----------|-------------|
| **Mode** | *How* the session runs — ceremony level, ritual depth | zen, quick, flow, mentoring, autonomous | Thalamus default + in-memory override |
| **Role** | *What* domain you're focused on — which skill bundle is loaded | developer, designer, reviewer, **scribe** | Same — Thalamus default + ad-hoc swap |

Modes and roles compose. "Flow + scribe" and "zen + developer" are both
valid. The scribe role auto-loads its skill bundle at orientation; other
roles can dip into the scribe skill on keyword detection without formally
swapping role.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  AGENTS.md          (skill table rows + hoards section) │
│   └─ "scribe" role; keyword triggers documented         │
├─────────────────────────────────────────────────────────┤
│  Orientation skill  (new vault-scan step in Step 6)     │
│   └─ Calls `ws hoard scan`; surfaces vault inventory    │
├─────────────────────────────────────────────────────────┤
│  scribe skill                                           │
│   └─ Vault discovery (via `ws hoard scan`), PARA,       │
│      frontmatter, daily notes, wikilinks, inbox loop    │
├─────────────────────────────────────────────────────────┤
│  scribe-claudesidian skill (extends scribe)             │
│   └─ Reads vault's CLAUDE.md, surfaces command          │
│      manifest, lazy-loads commands/skills via direct    │
│      file reads                                         │
├─────────────────────────────────────────────────────────┤
│  ws hoard scan          (NEW deterministic scanner)     │
│   └─ Outputs YAML inventory of hoards w/ flavor tags    │
├─────────────────────────────────────────────────────────┤
│  templates/hoards/obsidian-vault/      (vendored)       │
│  templates/hoards/claudesidian-vault/  (thin wrapper)   │
└─────────────────────────────────────────────────────────┘
```

Skills are layered: `scribe-claudesidian` explicitly loads `scribe` first.
Templates are independent of the skills; they produce hoards whose shape
the skills already know how to recognize.

## Components

### `scripts/ws-hoard.sh` — `scan` subcommand

New subcommand. Iterates `hoards/*/` and applies three classifiers
independently — flavors stack:

- **`thalami`** — directory name matches `thalami-*` (existing convention,
  via `ws_detect_thalami_hoard()` which is reused, not rewritten)
- **`obsidian`** — has a `.obsidian/` subdirectory
- **`claudesidian`** — has `.obsidian/` AND `.claude/` AND a top-level
  `CLAUDE.md` whose first ~30 lines reference Claudesidian or PARA
  conventions (multi-signal to avoid false positives on unrelated `.claude/`
  directories)

Output (YAML, multi-record, machine-readable):

```yaml
- name: borgr
  path: /Users/cervator/dev/git_ws/yggdrasil/hoards/borgr
  flavors: [obsidian, claudesidian]
- name: nonclaudesidian
  path: /Users/cervator/dev/git_ws/yggdrasil/hoards/nonclaudesidian
  flavors: [obsidian]
- name: thalami-Cervator
  path: /Users/cervator/dev/git_ws/yggdrasil/hoards/thalami-Cervator
  flavors: [thalami]
```

Flags:

- `--flavor <name>` — filter to hoards containing the named flavor
- `--names-only` — emit just hoard names, one per line, for shell-friendly use

The existing human-friendly `ws hoard list` is unchanged. `scan` is the
machine-consumable counterpart that skills call.

### `.agent/skills/scribe/SKILL.md`

Content sections (~150 lines):

1. **When to load** — role=scribe at orientation, OR keyword detection
   mid-session for dip-in
2. **Vault discovery** — call `ws hoard scan --flavor obsidian`, parse YAML,
   apply binding rules (see "Vault binding sub-flow" below)
3. **PARA conventions** — folder roles for `00_Inbox`/`01_Projects`/
   `02_Areas`/`03_Resources`/`04_Archive`/`05_Attachments`/`06_Metadata`
4. **Frontmatter habits** — YAML frontmatter for new notes (created date,
   tags, status)
5. **Wikilinks and embeds** — `[[link]]`, `![[embed]]`, alias syntax
6. **Daily notes** — `YYYY-MM-DD - Topic` pattern, where they live
7. **Inbox processing** — capture-process-organize loop, the "<20 items"
   guideline
8. **Claudesidian extension hand-off** — if scan reports `claudesidian`
   flavor on the bound vault, also load `scribe-claudesidian/SKILL.md`
9. **Keyword calibration** — only trigger on phrases implying capture intent
   (*"jot this down"*, *"add to my inbox"*) rather than bare keyword matches
   (*"note that this fails on Windows"*)

The skill description in frontmatter advertises trigger keywords:
`vault, note, journal, inbox, daily note, obsidian, PARA, wikilink,
frontmatter, capture, jot, weekly review, thinking partner, weekly synthesis,
research assistant`. The last three are Claudesidian command names — including
them lets keyword dip-in trigger correctly when a user says *"thinking partner
mode"* without first formally entering scribe role.

### `.agent/skills/scribe-claudesidian/SKILL.md`

Content sections (~100 lines):

1. **Loads scribe first** — explicit dependency: this skill builds on the
   scribe skill's PARA/frontmatter/wikilink content
2. **Read vault CLAUDE.md once** — prefer `<vault>/CLAUDE.md`; fall back to
   `<vault>/CLAUDE-BOOTSTRAP.md` if `CLAUDE.md` is absent or its frontmatter
   looks generic. Either path works; the latter just has less personal context
3. **Command manifest** — read `<vault>/.claude/claude_config.json` to
   enumerate commands and shortcuts. Surface inventory once on activation:
   *"Claudesidian commands available: thinking-partner, inbox-processor,
   weekly-synthesis, … Type or describe any in plain text."*
4. **Plain-text invocation pattern** — when the user says e.g. *"do a weekly
   synthesis"*, read `<vault>/.claude/commands/weekly-synthesis.md` and
   follow it verbatim, citing the file path so the user can see what was
   loaded
5. **Skill manifest** — list of `.claude/skills/*/SKILL.md` available;
   lazy-read on relevance (e.g. `obsidian-bases` skill loaded only when the
   user works with Obsidian Bases)
6. **What is intentionally not adopted** — `.claude/settings.json` hooks,
   the `skill-discovery.sh` UserPromptSubmit hook (functionality replaced
   by surfacing the manifest at activation), MCP servers (handled
   separately if user opts in)

### `AGENTS.md` additions

Three small touches:

1. **Skills table** — append two rows for the new skills with one-line
   descriptions and SKILL.md links
2. **Hoards section** — append one line: *"Hoard templates ship under
   `templates/hoards/<flavor>/`. Current flavors: `thalami`, `basic`,
   `obsidian-vault`, `claudesidian-vault`."*
3. **Role list** — add `scribe` to the authoritative role list (in
   `.agent/skills/gdd/SKILL.md` per existing GDD structure)

### `.agent/skills/gdd-orientation/SKILL.md` change

One small addition to the existing Step 6 (component scan): also call
`ws hoard scan` and surface vault flavors. *"Detected vaults: borgr
(claudesidian), nonclaudesidian (obsidian). Want to start in scribe role?"*

The prompt only surfaces if at least one obsidian-flavored hoard exists
AND the Thalamus frontmatter `role:` is null. If `role: scribe` is already
set, the orientation skill loads the scribe skill directly per existing
Step 5 logic.

## Vault binding sub-flow

Called by all four trigger paths.

```
1. Run: ws hoard scan --flavor obsidian
   → returns YAML list of obsidian-flavored hoards

2. Count obsidian-flavored hoards:
   • 0  → tell user: "No vaults found. Want me to `ws hoard init
                     obsidian-vault` or `ws hoard init claudesidian-vault`?"
          → offer template choice → exit binding flow if declined
   • 1  → auto-bind (in-memory pin for session)
   • >1 → check Thalamus frontmatter for `active_vault: <name>`
          • set & matches a scanned hoard → use it (no prompt)
          • not set or mismatched → ask user which vault for this session

3. After binding, re-check that hoard's flavor list:
   • Contains `claudesidian` → also load scribe-claudesidian/SKILL.md
   • Otherwise → continue with vanilla scribe
```

Binding is **session-scoped, in-memory** by default. The optional
`active_vault: <name>` Thalamus frontmatter field provides persistence for
users with multiple vaults who don't want to be asked every session.

## Trigger paths

### Path A — Orientation, `role: scribe` in frontmatter

1. `gdd-orientation` Step 5 reads `role: scribe` → loads `.agent/skills/scribe/SKILL.md`
2. Skill runs vault-binding sub-flow
3. If bound vault has `claudesidian` flavor → also load `scribe-claudesidian/SKILL.md`

The "session named borgr / I'm in vault mode today" path. Persistent default.

### Path B — Orientation, `role: null`, vault detected

1. `gdd-orientation` Step 6 calls `ws hoard scan` as part of the new
   vault-detection addition
2. Scan reports at least one obsidian-flavored hoard
3. Role question to the user includes the discovery: *"role is null. Detected
   vault: borgr (claudesidian). Want scribe role, or another (developer /
   designer / reviewer)?"*
4. User picks → if scribe, follow Path A from step 1; if not, surface the
   vault but don't load scribe

### Path C — Mid-session keyword dip-in

1. User in some other role (e.g. developer), working on something unrelated
2. User says something matching scribe trigger keywords with capture intent:
   *"let me jot this in my inbox"*, *"add a daily note about this"*,
   *"capture this idea"*
3. Agent recognizes the phrase set (advertised in AGENTS.md role row + scribe
   skill frontmatter description)
4. Agent loads `.agent/skills/scribe/SKILL.md` ad-hoc, runs vault-binding
   sub-flow, performs the requested action
5. No formal role switch. Scribe skill stays loaded for any subsequent
   note actions in the session

The most common case for sessions focused on non-vault work that occasionally
need to capture something. Calibration emphasized in the skill itself to
avoid false positives.

**Multi-vault edge case:** if Path C triggers in a workspace with multiple
obsidian-flavored hoards and no `active_vault:` set in Thalamus frontmatter,
the binding sub-flow asks the user which vault — mid-conversation. The pin
sticks for the rest of the session, so it's a one-time prompt, but users
who frequently dip into capture from multi-vault workspaces should set
`active_vault:` once to skip the question.

### Path D — Explicit ask

1. User says *"scribe role for this session"* or *"scribe on borgr"*
2. Agent loads scribe skill, optionally pins the named vault directly
3. Session-scoped, in-memory only — does NOT update Thalamus `role:` unless
   user explicitly says *"make scribe my default"*

## Templates

### `templates/hoards/obsidian-vault/`

Vendored, vanilla, no plugins. Aligned with the `00–06` PARA + supporting
numbering for symmetry with the Claudesidian template (one set of scribe
conventions covers both).

```
templates/hoards/obsidian-vault/
├── README.md                  # what this is, install Obsidian, GDD usage
├── .gitignore                 # .trash, workspace.json, .DS_Store
├── .obsidian/                 # minimal vanilla config
│   ├── app.json
│   ├── appearance.json
│   └── core-plugins.json      # file-explorer, search, daily-notes,
│                              #  templates, command-palette only
├── 00_Inbox/
│   └── Welcome.md             # starter note with frontmatter + wikilinks
├── 01_Projects/
│   └── README.md              # one-line role description
├── 02_Areas/
│   └── README.md
├── 03_Resources/
│   └── README.md
├── 04_Archive/
│   └── README.md
├── 05_Attachments/
│   └── .gitkeep
└── 06_Metadata/
    └── Templates/
        ├── daily-note.md      # YYYY-MM-DD - Topic + sections
        ├── project-note.md    # goal, scope, deliverable, links
        ├── meeting-note.md    # attendees, agenda, decisions, actions
        ├── inbox-capture.md   # blank capture w/ frontmatter
        └── weekly-review.md   # template for the weekly review pattern
```

`README.md` covers: what this is, PARA layout reminder, optional Obsidian
install instructions, how GDD's scribe skill operates against the vault,
template usage, pointer to the Claudesidian variant.

`Templates/*.md` use Obsidian's built-in template syntax (`{{date:YYYY-MM-DD}}`)
so they work both with Obsidian's Templates plugin and with the scribe skill
when creating notes via Claude.

### `templates/hoards/claudesidian-vault/`

Thin wrapper. No upstream files vendored.

```
templates/hoards/claudesidian-vault/
├── README.md                  # install instructions, attribution,
│                              #  optional /init-bootstrap step (see below)
├── template.yaml              # manifest:
│                              #   upstream: https://github.com/heyitsnoah/claudesidian
│                              #   pin: <commit-or-tag>
│                              #   fallback: https://github.com/SiliconSaga/claudesidian-fork
│                              #             (placeholder for future fork)
│                              #   post_clone:
│                              #     - copy gdd-bridge/* into vault root
│                              #     - rm -rf .git
└── gdd-bridge/
    ├── AGENTS.md              # ~20 lines: notes that this vault sits in a
    │                          #  GDD workspace; scribe-claudesidian provides
    │                          #  equivalent functionality from yggdrasil root
    └── README.md              # explains the bridge layer for humans
```

#### Init flow

`ws hoard init claudesidian-vault <name>` extends the existing init logic:

1. Read `template.yaml`
2. `git clone <upstream> hoards/<name>` — try `upstream` first, fall back to
   `fallback` if upstream fails
3. `rm -rf hoards/<name>/.git` so subsequent `ws hoard init` flow can re-init
   it as the user's own repo per existing convention
4. Copy `gdd-bridge/*` into `hoards/<name>/` (no name conflicts — the bridge
   files use distinct names)
5. Print the README's "optional `/init-bootstrap`" tip

Implementation: small extension to `scripts/ws-hoard.sh`'s init path, reading
`template.yaml` when present (~40 lines).

#### README content sketch

The `README.md` includes an "Optional: run the Claudesidian onboarding once"
section:

> ### Optional: run the Claudesidian onboarding once
>
> The bridge GDD provides covers core Claudesidian conventions out of the
> box, but Claudesidian's upstream `/init-bootstrap` command builds a
> personalized `CLAUDE.md` (writing style, custom context, optionally pulled
> from public profiles). If you want that, do it once standalone:
>
> ```bash
> cd hoards/claudesidian-vault
> claude
> /init-bootstrap
> ```
>
> Then exit and resume in your usual GDD-rooted Claude session — the
> scribe-claudesidian skill picks up the personalized `CLAUDE.md`
> automatically.
>
> Skip this if you're happy with the generic conventions; nothing important
> breaks.

Plus attribution to Noah Brier / Alephic with link to the upstream repo, MIT
license note, and a brief "install Obsidian" section pointing at obsidian.md.

#### The fallback fork

`template.yaml`'s `fallback` field is a placeholder for a SiliconSaga-org
fork of Claudesidian that doesn't yet exist. The field documents the
intent; the fork can be created and the URL filled in whenever convenient.
This protects against upstream availability issues without requiring any
work today.

## Open questions

None blocking implementation. The following are intentionally deferred to
future iterations:

- **Plugin curation for the plain Obsidian template** — the user has plugins
  configured on another system; a curated preset can be added once the base
  template proves out
- **Multi-vault Thalamus contention** — flagged as a real concern but
  separable from this design
- **Backstage-backed `ws template upgrade`** — its own brainstorm, will
  cover obsidian-vault, claudesidian-vault, and component templates uniformly

## Implementation surface summary

| File | Change | Size estimate |
|------|--------|---------------|
| `scripts/ws-hoard.sh` | Add `scan` subcommand; extend `init` for `template.yaml` | ~90 lines added |
| `.agent/skills/scribe/SKILL.md` | New file | ~150 lines |
| `.agent/skills/scribe-claudesidian/SKILL.md` | New file | ~100 lines |
| `.agent/skills/gdd-orientation/SKILL.md` | Add vault-scan step in Step 6 | ~15 lines added |
| `.agent/skills/gdd/SKILL.md` | Add `scribe` to role list | ~5 lines added |
| `AGENTS.md` | Two new skill table rows + hoards section line | ~5 lines added |
| `templates/hoards/obsidian-vault/` | New directory tree | ~15 small files |
| `templates/hoards/claudesidian-vault/` | New directory (thin wrapper) | 4 files |
| `templates/thalamus.md` | Document optional `active_vault:` frontmatter | ~3 lines added |

Total: roughly 350 lines of code/script changes, plus ~20 small markdown
files for templates and skills.

## References

- Claudesidian upstream: <https://github.com/heyitsnoah/claudesidian>
  (MIT, by Noah Brier / Alephic)
- [Realms and Hoards Design](2026-04-24-realms-and-hoards-design.md)
- [Component Templates Design](2026-04-25-component-templates-design.md)
- [PARA Method](https://fortelabs.com/blog/para/)
