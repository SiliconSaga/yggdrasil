# Thalami Hoard

Personal hoard holding per-machine Thalamus files. Each machine you use yggdrasil on contributes one `<machine>-thalamus.md` file. Preferences, observations, and concerns sync between machines via this repo's git history.

## Layout

```text
thalami/                    # default name (ws hoard init thalami).
                            # Override with --name; legacy `thalami-<username>`
                            # form still supported for existing hoards.
  README.md
  ArcDashboard.md           # cross-host in-flight arcs (Dataview-rendered)
  Intake.md                 # machine-agnostic pre-arc GDD staging (the bridge)
  <machine>-thalamus.md     # one per machine; e.g. win10-desktop-thalamus.md
  <machine>-thalamus.md
  ...
```

Internal layout is intentionally flat — the repo's name already says `thalami`. If subdirectory structure becomes useful later, it can be introduced via a config-level path-template override.

## Machine name

Defaults to the short hostname (the bash builtin `$HOSTNAME` with any domain suffix stripped — portable across Linux, macOS, and Windows Git Bash). Override via `machine: <name>` in `ecosystem.local.yaml` if your hostname is awkward or unstable across boots.

## Privacy posture

The hoard is **personal but committed** to a private repo of your choice. This is a different posture from the workspace-local `Thalamus.md`, which is gitignored and stays on one machine. Treat the hoard as "cross-machine, low-secrecy" content — observations about a friction point, preferences, recurring concerns. For "don't-check-in" notes, keep using a root `Thalamus.md` as a scratch file alongside the hoard.

## Pushing to your remote

The `ws hoard init` flow creates this hoard as a local git repo without a remote. To push:

```bash
gh repo create <yourname>/thalami \
  --private --source=hoards/thalami \
  --remote=<yourname> --push
```

(The `ws hoard init thalami` command prints the exact command for you, with `<yourname>` already filled in.)

The `--remote=<yourname>` flag honors the workspace convention of avoiding generic `origin` remote names. `--push` pushes the initial commit so the remote isn't empty.

Or any equivalent on GitLab / Gitea / etc.

---

## Cross-host arc dashboard

This hoard ships an `ArcDashboard.md` that renders an at-a-glance table of in-flight work across every machine using the workspace. Each per-machine `<machine>-thalamus.md` carries an `arcs:` list in its frontmatter; the dashboard projects only frontmatter — the body of each Thalamus file (Observations, Concerns, Audit Log) syncs via git like any other content but is never surfaced in the dashboard projection. See `ArcDashboard.md` for the schema and live queries.

### Setup (one-time, per machine)

Follow these steps, or better yet see the shortcut at the end.

1. **Open this folder as an Obsidian vault.** In Obsidian: `File → Open vault → Open folder as vault`, point at this hoard's directory.
2. **Install the Dataview plugin.** `Settings → Community plugins → Browse`, search for *Dataview*, install, then enable. After enabling, open `Settings → Dataview` and turn on **"Enable JavaScript Queries"** — required for the dashboard's tags and per-host one-liner blocks.
3. **Install the Meta Bind plugin.** Same `Browse` flow, search for *Meta Bind*, install, then enable. It powers the dashboard's Filter box, Sort dropdown, and Refresh button above the table.
4. **Recommended: disable readable-line-length.** `Settings → Editor → Readable line length` → toggle off. Lets the dashboard table use the full window width. The vault is single-purpose (thalamus files + dashboard); the prose-readability cap isn't useful here.
5. **Open `ArcDashboard.md`.** The query blocks render as live tables, and the controls above the table become interactive.

Obsidian creates a `.obsidian/` directory the first time you open the vault; that's gitignored by default since it's a per-machine UI preference store, not shared state.

**Shortcut:** instead of installing the two plugins by hand, `ws hoard upgrade thalami --apply` downloads and enables the pinned Dataview + Meta Bind releases into this vault's `.obsidian/` for you. You still do steps 1, 4, and 5.

---

## Intake — the GDD bridge

This hoard also carries an `Intake.md` at its root: machine-agnostic staging for pre-arc GDD work. The scribe ceremony moves `#gdd`-tagged items out of a vault daily note and into this file; the GDD ceremony (orientation surfaces it, housekeeping drains it) routes each item to a machine and promotes it to an arc when the work justifies one.

`Intake.md` is staging, not a tracker — it is meant to stay short. New hoards are scaffolded with it; existing hoards get one created on demand the first time the scribe bridge fires.
