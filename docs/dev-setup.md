# Developer Setup

## Prerequisites

After cloning, run `bash scripts/ws preflight` from the workspace root —
it checks each tool below and prints per-OS install hints for anything
missing.

**Required:**

- **Bash** — On Windows, use Git Bash (bundled with Git for Windows).
  Run all `ws` commands from a Git Bash shell, not cmd or PowerShell.
- **Git** itself.
- **[yq v4+](https://github.com/mikefarah/yq)** — Mike Farah's
  Go-based YAML processor. *Not* the Python `yq` from PyPI; that's a
  different tool with incompatible syntax.
- **[jq](https://jqlang.github.io/jq/)** — JSON processor (used by
  `ws review` and several internal scripts).

**Provider CLI** (need at least one — match your hosting choice):

- **[gh](https://cli.github.com/)** — for GitHub-hosted components.
- **[glab](https://gitlab.com/gitlab-org/cli)** — for GitLab-hosted
  components (gitlab.com or self-hosted instances).

**Recommended companion (agent-side):**

- **[Obra Superpowers](https://github.com/obra/superpowers)** — a
  Claude Code plugin that ships skills GDD plans reference
  (`superpowers:executing-plans`, `superpowers:subagent-driven-development`,
  `superpowers:brainstorming`, `superpowers:test-driven-development`,
  `superpowers:receiving-code-review`, etc.). GDD works without it,
  but plan-driven and review-heavy sessions assume it's available.
  The `gdd-orientation` skill checks for it at session start and
  surfaces a nudge if absent.

**Optional** (only needed for specific component types):

- **[uv](https://docs.astral.sh/uv/)** — Python package manager,
  for MCP servers and Python components.
- **realpath** — usually present (coreutils on Linux, Git Bash on
  Windows); on macOS comes via `brew install coreutils`.

### Install hints by OS

| Tool | macOS (Homebrew) | Windows (winget) | Linux (Debian/Ubuntu) |
|------|------------------|------------------|-----------------------|
| Git | `brew install git` | `winget install Git.Git` | `sudo apt install git` |
| yq | `brew install yq` | `winget install MikeFarah.yq` | Download from [yq releases](https://github.com/mikefarah/yq/releases) |
| jq | `brew install jq` | `winget install jqlang.jq` | `sudo apt install jq` |
| gh | `brew install gh` | `winget install GitHub.cli` | [GitHub CLI repo setup](https://cli.github.com) |
| glab | `brew install glab` | `winget install GLab.GLab` | Download from [glab releases](https://gitlab.com/gitlab-org/cli/-/releases) |

If `winget` isn't available on your Windows version (older SKUs,
locked-down environments), Chocolatey is the fallback —
`choco install <tool>` from an **elevated PowerShell** (right-click
→ Run as administrator). `winget` doesn't need elevation.

For provider authentication setup (PATs, `.env` configuration,
multi-provider workspaces), see
[`docs/git-provider-setup.md`](git-provider-setup.md).

## Getting Started

```bash
git clone https://github.com/SiliconSaga/yggdrasil.git
cd yggdrasil
bash scripts/ws list          # See what's available
bash scripts/ws clone --all   # Clone all components
```

## Workspace CLI (`ws`)

The `ws` script is a unified entry point for workspace operations. It wraps
the individual `ws-*.sh` scripts and adds component-aware command execution.

### Usage

```bash
# From the yggdrasil root (always works):
bash scripts/ws <command> [args...]

# With PATH setup (optional shorthand):
ws <command> [args...]
```

### Commands

| Command | Description |
|---|---|
| `ws list` | List all ecosystem components and local status |
| `ws status [--verbose]` | Git status across all cloned components |
| `ws clone <comp>\|--all` | Clone one or all components |
| `ws pull [comp]` | Pull latest for all or one component |
| `ws push [comp] [branch]` | Push via HTTPS (auto-sources .env) |
| `ws cr <comp> <title> <bodyfile>` | Open a CR (change request/PR/MR) to main |
| `ws issue <comp> [remote] <title> <label> <bodyfile>` | File an issue |
| `ws resolve` | Generate ArgoCD Application manifests |
| `ws vscode` | Generate VS Code workspace file |
| `ws test <comp> [args...]` | Run tests (auto-detects runner: Makefile, Go, Python) |
| `ws review <comp> <cr#\|threads> [options]` | CR review comments and thread management |
| `ws commit <comp> <bodyfile>` | Commit with Co-Authored-By trailer (bodyfile-driven) |
| `ws log [comp] [--oneline]` | Show commits on current branch vs main |
| `ws clean` | Remove draft files from `.issues/`, `.crs/`, `.commits/` |
| `ws exec <comp> <cmd...>` | Run a command in a component directory |
| `ws help` | Show help |

### Examples

```bash
# Check what's available
bash scripts/ws list

# Run tests for a component (auto-detects runner)
bash scripts/ws test mimir

# Check git status of a specific component
bash scripts/ws exec mimir git status

# Push mimir to remote
bash scripts/ws push mimir

# Show branch commits vs main
bash scripts/ws log --oneline
```

### Optional: Add to PATH

For shorter commands in your terminal, add to your shell profile
(`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export PATH="/path/to/yggdrasil/scripts:$PATH"
```

Then you can use `ws` directly:

```bash
ws exec mimir make test
ws list
ws push mimir
```

### AI Agent Permissions

Claude Code permissions are configured at two levels:

- **Project** (`.claude/settings.json`, committed) — safe commands auto-approved,
  `exec` always requires human approval.
- **Local** (`.claude/settings.local.json`, gitignored) — your personal overrides.

To set up local permissions for bulk operations, create
`.claude/settings.local.json` (gitignored) and add auto-approve patterns
for side-effect commands you use frequently.
See `docs/ws-cli-guide.md` for the full pattern reference.
