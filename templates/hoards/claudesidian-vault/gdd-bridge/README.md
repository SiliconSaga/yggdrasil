# `gdd-bridge/` — Why this directory is here

This is a small overlay of files that GDD adds to a freshly cloned
Claudesidian vault. They land in the vault root after the clone:

- `AGENTS.md` — explains the bridged-vs-standalone distinction to
  any agent operating from inside the vault
- `README.md` (this file) — explains why `gdd-bridge/` exists, kept
  for human navigation

Nothing here modifies upstream Claudesidian files. If you ever
re-vendor by re-cloning upstream, the bridge files will be re-applied
automatically by `ws hoard init`.
