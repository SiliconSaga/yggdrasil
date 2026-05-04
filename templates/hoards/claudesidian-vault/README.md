# Claudesidian Vault (GDD Wrapper)

A thin wrapper around [Claudesidian](https://github.com/heyitsnoah/claudesidian)
— Noah Brier and Alephic's Claude-Code-friendly Obsidian starter kit
(MIT licensed). When you run `ws hoard init claudesidian-vault --name <name>`,
GDD clones the upstream repo into `hoards/<name>/`, strips its `.git`
directory, and overlays a small `gdd-bridge/` set of files that wire
the vault into the surrounding workspace.

## Attribution

- **Upstream:** <https://github.com/heyitsnoah/claudesidian>
- **License:** MIT (see `LICENSE` in the cloned vault)
- **Built by:** Noah Brier — see <https://every.to/podcast/how-to-use-claude-code-as-a-thinking-partner>
- **Maintained by:** [Alephic](https://alephic.com)

This template is a pointer, not a fork. The full Claudesidian
experience and any updates to it come from upstream.

## What `ws hoard init claudesidian-vault` does

1. Clones the upstream repo into `hoards/<name>/`
2. Removes the cloned `.git/` directory so the hoard can be re-init'd
   as your own repo (per existing `ws hoard init` convention)
3. Copies files from this template's `gdd-bridge/` into the new vault
   (currently `AGENTS.md` and a small `README.md` explaining the bridge)
4. Initializes a fresh git repo for the hoard
5. Prints the optional `/init-bootstrap` tip below

## Optional: run the Claudesidian onboarding once

The bridge GDD provides covers core Claudesidian conventions out of
the box, but Claudesidian's upstream `/init-bootstrap` command builds
a personalized `CLAUDE.md` (writing style, custom context, optionally
pulled from public profiles). If you want that, do it once standalone:

```bash
cd hoards/<your-vault-name>
claude
/init-bootstrap
```

Then exit and resume in your usual GDD-rooted Claude session — the
`scribe-claudesidian` skill picks up the personalized `CLAUDE.md`
automatically.

Skip this if you're happy with the generic Claudesidian conventions;
nothing important breaks. Even without `/init-bootstrap`, the
`CLAUDE-BOOTSTRAP.md` shipped by upstream provides the core PARA and
vault-handling guidance that `scribe-claudesidian` reads as a fallback.

## Optional: install Obsidian

The vault works fine from Claude Code alone, but
[Obsidian](https://obsidian.md) provides graph view, search, plugin
ecosystem, and the visual interface most Obsidian workflows assume.
Open the cloned vault folder as an Obsidian vault.

## Working from GDD vs. running Claude inside the hoard

This template's main purpose is letting you operate the vault from a
single Claude session rooted at your yggdrasil workspace, instead of
having to `cd` into the vault and start a new session there. The
`scribe-claudesidian` skill (in
`.agent/skills/scribe-claudesidian/SKILL.md`) provides equivalent
plain-text invocation of Claudesidian commands like
`/thinking-partner` and `/weekly-synthesis` from the workspace root.

If you prefer the standalone Claudesidian experience — slash-command
auto-completion, hooks, MCP servers wired up natively — just `cd` into
the hoard and run `claude` there. Both modes coexist; `gdd-bridge/`
files don't interfere with standalone use.
