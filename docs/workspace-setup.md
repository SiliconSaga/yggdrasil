# Workspace Setup

GDD isn't just for coding. The same workspace drives software work *and* non-developer work — personal organizing, research notes, or a knowledge base in an Obsidian-vault hoard. This page is the one-stop setup reference; for a guided first run, see [Getting Started](getting-started/index.md).

**You don't have to do this by hand.** If an AI agent is already running in the workspace, just ask it to set up the prerequisites — it can run the `winget` / `brew` / `apt` installs for you and tell you when to restart your shell. The rest of this page is what it (or you) will work through.

## Prerequisites

After cloning, run `bash scripts/ws preflight` from the workspace root — it checks each tool below, flags whether `scripts/` is on your PATH, and prints per-OS install hints for anything missing. It verifies the tools are *present*, not that any git provider is *authenticated* — provider tokens are a later step (see [`git-provider-setup.md`](git-provider-setup.md)) and are only needed once you start cloning remotes, pushing, or opening CRs. After installing any tool, open a fresh shell (or restart your editor) so PATH updates take effect — a freshly-installed tool won't appear in an already-running shell.

**Required:**

- **Bash** — On Windows, use Git Bash (bundled with Git for Windows). Run all `ws` commands from a Git Bash shell, not cmd or PowerShell.
- **Git** itself.
- **[yq v4+](https://github.com/mikefarah/yq)** — Mike Farah's Go-based YAML processor. *Not* the Python `yq` from PyPI; that's a different tool with incompatible syntax.
- **[jq](https://jqlang.github.io/jq/)** — JSON processor (used by `ws review` and several internal scripts).

**Provider CLI** (need at least one — match your hosting choice):

- **[gh](https://cli.github.com/)** — for GitHub-hosted components.
- **[glab](https://gitlab.com/gitlab-org/cli)** — for GitLab-hosted components (gitlab.com or self-hosted instances).

**Recommended companion (agent-side):**

- **[Obra Superpowers](https://github.com/obra/superpowers)** — a plugin that ships skills GDD plans reference (`superpowers:executing-plans`, `superpowers:brainstorming`, `superpowers:test-driven-development`, etc.). GDD works without it, but plan-driven and review-heavy sessions assume it's available; the `gdd-orientation` skill nudges you if it's absent. The install command is agent-specific — Claude Code: see [`CLAUDE.md`](../CLAUDE.md); other agents install the same plugin their own way.

**Optional** (only needed for specific component types):

- **[uv](https://docs.astral.sh/uv/)** — Python package manager, for MCP servers and Python components.
- **realpath** — usually present (coreutils on Linux, Git Bash on Windows); on macOS comes via `brew install coreutils`.

### Install hints by OS

| Tool | macOS (Homebrew) | Windows (winget) | Linux (Debian/Ubuntu) |
|------|------------------|------------------|-----------------------|
| Git | `brew install git` | `winget install Git.Git` | `sudo apt install git` |
| yq | `brew install yq` | `winget install MikeFarah.yq` | Download from [yq releases](https://github.com/mikefarah/yq/releases) |
| jq | `brew install jq` | `winget install jqlang.jq` | `sudo apt install jq` |
| gh | `brew install gh` | `winget install GitHub.cli` | [GitHub CLI repo setup](https://cli.github.com) |
| glab | `brew install glab` | `winget install GLab.GLab` | Download from [glab releases](https://gitlab.com/gitlab-org/cli/-/releases) |

If `winget` isn't available on your Windows version (older SKUs, locked-down environments), Chocolatey is the fallback — `choco install <tool>` from an **elevated PowerShell** (right-click → Run as administrator). `winget` doesn't need elevation.

For provider authentication setup (PATs, `.env` configuration, multi-provider workspaces), see [`git-provider-setup.md`](git-provider-setup.md).

## Add `scripts/` to your PATH

Treat this as a required step, not a nicety. Putting the workspace `scripts/` directory on your PATH lets you call `ws <command>` directly instead of `bash scripts/ws <command>` — and, more importantly, the AI-agent permission allowlist is written against the bare `ws …` form, so the shorthand keeps auto-approvals matching cleanly. `ws preflight` flags it when `scripts/` isn't on your PATH.

**macOS / Linux / Git Bash** — add it to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.), then open a fresh shell (or `source` the profile) and run `ws help` to confirm:

```bash
export PATH="/path/to/yggdrasil/scripts:$PATH"
```

**Windows** — two wrinkles worth knowing:

- **`bash` itself may not be on your *system* PATH.** Git for Windows offers a few PATH choices at install time; the common "Git from the command line and also from 3rd-party software" option adds Git's `cmd\` directory (so `git` works in cmd/PowerShell) but **not** the `bin\` / `usr\bin\` directory that holds `bash.exe`. If `bash` isn't found outside Git Bash, add `C:\Program Files\Git\bin` (or `…\usr\bin`) to your PATH.
- **Adding `scripts/` persistently.** Inside Git Bash, the `~/.bashrc` export above is enough. To also run `ws` from cmd/PowerShell, add the scripts directory to your Windows PATH via **Settings → System → About → Advanced system settings → Environment Variables**, edit **Path**, and append the full path to `…\yggdrasil\scripts`. Open a new terminal afterward.

## Workspace CLI (`ws`)

The `ws` script is the single entry point for workspace operations — it wraps the individual `ws-*.sh` scripts and adds component-aware command execution. Rather than memorize the subcommands, discover them live:

```bash
ws help            # every subcommand, one line each
ws orient          # what's wired right here: verbs, active realm, adapters, skills
ws <cmd> --help    # full flags + behavior for any subcommand
```

`ws orient` is the deterministic "what can I do here?" surface — and the thing to run at the start of any session.

## First steps

With prerequisites in place and `scripts/` on your PATH (previous step):

```bash
ws list          # what components the ecosystem declares
ws clone --all   # clone them locally (or one: ws clone <comp>)
```

For a guided, narrated first run — identity + auth setup, cloning a component, and the full edit → PR → review → deploy loop on a tiny target — follow [Getting Started](getting-started/index.md). New here? Start a session and ask the agent to **walk you through the tutorial** with mentoring on — it'll scaffold the `gh-pages` tutorial (`ws component init gh-pages …`) and narrate the whole GDD loop.

## Workspace shape

Three directories sit alongside the workspace root. Each holds independent, nested git repos — their own history, gitignored from yggdrasil itself:

- **Components** (`components/`) — the projects you actually work on, code or otherwise; each is its own repo, cloned via `ws clone`.
- **Realms** (`realms/`) — a community's or team's shared configuration (which components, identity, adapters), adopted via `ws realm`. See [`ecosystem-architecture.md`](ecosystem-architecture.md).
- **Hoards** (`hoards/`) — oddly-shaped non-code collections: per-machine Thalamus notes, or an Obsidian vault for personal organizing; scaffolded via `ws hoard`.

The [GDD Features Tour](gdd/features.md) covers all three in context.

## AI agent permissions

Claude Code permissions live in `.claude/settings.json` (committed, team-wide) and `.claude/settings.local.json` (gitignored, personal). Rather than duplicate the rules here, see:

- [`.claude/hooks/README.md`](../.claude/hooks/README.md) — the PreToolUse hook tiers (deny / redirect / ask / allow) and bypass mechanics.
- [`ws-cli-guide.md`](ws-cli-guide.md) — the permission-pattern reference for tuning your local allowlist.
