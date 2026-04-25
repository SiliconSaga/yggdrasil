# Thalami Hoard

Personal hoard holding per-machine Thalamus files. Each machine you use
yggdrasil on contributes one `<machine>-thalamus.md` file. Preferences,
observations, and concerns sync between machines via this repo's git
history.

## Layout

```text
thalami-<username>/
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
gh repo create <yourname>/thalami-<yourname> \
  --private --source=hoards/thalami-<yourname> \
  --remote=<yourname> --push
```

The `--remote=<yourname>` flag honors the workspace convention of
avoiding generic `origin` remote names. `--push` pushes the initial
commit so the remote isn't empty.

Or any equivalent on GitLab / Gitea / etc.
