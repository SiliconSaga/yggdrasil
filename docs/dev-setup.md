# Developer Setup

## Prerequisites

- Git
- [yq v4+](https://github.com/mikefarah/yq) — YAML processor
- [gh](https://cli.github.com/) — GitHub CLI (optional, for issues/PRs)
- [uv](https://docs.astral.sh/uv/) — Python package manager (optional, for MCP servers and Python components)

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
| `ws commit <comp> <message> [bodyfile]` | Commit with Co-Authored-By trailer |
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
