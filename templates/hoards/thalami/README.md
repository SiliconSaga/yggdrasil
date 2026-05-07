# Thalami Hoard

Personal hoard holding per-machine Thalamus files. Each machine you use
yggdrasil on contributes one `<machine>-thalamus.md` file. Preferences,
observations, and concerns sync between machines via this repo's git
history.

## Layout

```text
thalami/                    # default name (ws hoard init thalami).
                            # Override with --name; legacy `thalami-<username>`
                            # form still supported for existing hoards.
  README.md
  <machine>-thalamus.md     # one per machine; e.g. win10-desktop-thalamus.md
  <machine>-thalamus.md
  ...
```

Internal layout is intentionally flat — the repo's name already says
`thalami`. If subdirectory structure becomes useful later, it can be
introduced via a config-level path-template override.

## Machine name

Defaults to the short hostname (the bash builtin `$HOSTNAME` with any
domain suffix stripped — portable across Linux, macOS, and Windows Git
Bash). Override via `machine: <name>` in `ecosystem.local.yaml` if your
hostname is awkward or unstable across boots.

## Privacy posture

The hoard is **personal but committed** to a private repo of your choice.
This is a different posture from the workspace-local `Thalamus.md`, which
is gitignored and stays on one machine. Treat the hoard as
"cross-machine, low-secrecy" content — observations about a friction
point, preferences, recurring concerns. For "don't-check-in" notes,
keep using a root `Thalamus.md` as a scratch file alongside the hoard.

## Pushing to your remote

The `ws hoard init` flow creates this hoard as a local git repo without
a remote. To push:

```bash
gh repo create <yourname>/thalami \
  --private --source=hoards/thalami \
  --remote=<yourname> --push
```

(The `ws hoard init thalami` command prints the exact command for
you, with `<yourname>` already filled in.)

The `--remote=<yourname>` flag honors the workspace convention of
avoiding generic `origin` remote names. `--push` pushes the initial
commit so the remote isn't empty.

Or any equivalent on GitLab / Gitea / etc.

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
