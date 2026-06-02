# Team Thalami Hoard

A **shared, team-visibility** thalami. Teammates publish in-flight arcs (and the Vault notes that go with them) here so the team can see what's in flight, without exposing their chatty personal thalami.

## The model — generated, never hand-edited

This repo is a **projection**. Your personal thalami stays canonical; `ws thalami publish` (see the workspace docs) mirrors your *published* arcs + their tagged Vault notes into your own folder here. **Do not hand-edit another teammate's folder, and treat your own as machine-managed** — re-running publish overwrites it, and prunes only files a prior publish recorded (tracked in `.publish-manifest.yaml`). Note publishing is gated — a note must carry `#team/<arc-id>`, must not be on the denylist (`#private`/`#noteam`), and publish lists every file before copying. See the design: `docs/plans/2026-06-01-team-thalami-tier-design.md` in yggdrasil.

## Layout

```text
team-thalami-<team>/
  TeamArcDashboard.md          # person-keyed live table (Dataview)
  README.md
  <username>/                  # one folder per teammate — only YOUR publish writes here
    <host>-thalamus.md         # mirrored arc frontmatter (per host)
    <arc-id>/                  # one subfolder per published arc (collision-safe)
      <vault-relative-path>.md # mirrored copies of your Vault notes tagged #team/<arc-id>
    .publish-manifest.yaml     # records files your last publish wrote (scopes pruning)
```

## Setup (one-time, per machine)

1. **Open this folder as an Obsidian vault** (`File → Open vault → Open folder as vault`).
2. **Install + enable the Dataview plugin** (`Settings → Community plugins → Browse`), then in `Settings → Dataview` enable **"Enable JavaScript Queries"**.
3. **Install + enable the Meta Bind plugin** (powers the Filter / Sort / Refresh controls).
4. **Recommended:** `Settings → Editor → Readable line length` → off, so the table uses full width.
5. Open `TeamArcDashboard.md` — the query renders as a live table.

(Plugin auto-install via `ws hoard upgrade` is not wired for this flavor yet — install by hand for now.)
