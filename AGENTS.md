# AI Agent Guidelines for This Workspace

Yggdrasil is the workspace root for the SiliconSaga ecosystem. Component repos
live in `components/` as independent Git repos, cloned via `bash scripts/ws clone`.
The `ecosystem.yaml` manifest declares all components, their tiers, and configuration.
Per-developer overrides go in `ecosystem.local.yaml` (gitignored).

Full ecosystem map: [`docs/ecosystem-architecture.md`](docs/ecosystem-architecture.md)

---

## Repo Roles (quick reference)

| Repo | Tier | Role | Path |
|------|------|------|------|
| `yggdrasil` | — | Docs, skills, scripts, workspace root | `.` (this repo) |
| `nordri` | 1 | Cluster substrate (Traefik, Crossplane, Velero, ArgoCD) | `components/nordri` |
| `nidavellir` | 2 | Platform app-of-apps (Vegvísir, Mimir, Keycloak, …) | `components/nidavellir` |
| `mimir` | 2 component | Data services via Crossplane + operators | `components/mimir` |
| `vordu` | 2 component | BDD roadmap visualization | `components/vordu` |
| `heimdall` | 2 component | Observability stack | `components/heimdall` |
| `tafl` | 2 | Board game engine service | `components/tafl` |
| `bifrost` | 2 | Bridge/gateway service | `components/bifrost` |
| `ymir` | 3 | End-user platform | `components/ymir` |
| `terasology` | 3 | Voxel game (fork) | `components/terasology` |
| `destinationsol` | 3 | Space shooter game (fork) | `components/destinationsol` |

GitHub org: Avoid using a generic `origin` and use explicit remote names like `siliconsaga`

---

## Skills

Skills live in `.agent/skills/<name>/SKILL.md`.

| Skill Name | Description | Source / Reference |
| :--- | :--- | :--- |
| **ArgoCD Bootstrap on K3d** | Bootstrapping ArgoCD app-of-apps on k3d, CRD chicken-and-egg fixes, portable shell scripts | [SKILL.md](./.agent/skills/argocd-bootstrap-on-k3d/SKILL.md) |
| **Crossplane on K3d** | Guide for configuring Crossplane in local K3d clusters | [SKILL.md](./.agent/skills/crossplane-on-k3d/SKILL.md) |
| **Creating GitHub Issues** | Pre-flight checks, issue templates, and filing process for deferring work to GitHub issues | [SKILL.md](./.agent/skills/creating-github-issues/SKILL.md) |
| **KUTTL Testing** | Guidelines for writing and running KUTTL tests | [SKILL.md](./.agent/skills/kuttl-testing/SKILL.md) |
| **Multi-Repo Orchestration** | Session start/end discipline when a session touches more than one repo, TODO triage | [SKILL.md](./.agent/skills/multi-repo-orchestration/SKILL.md) |
| **Nordri Bootstrap Guide** | Bootstrapping Nordri (refr-k8s) on k3d, Mimir integration, ArgoCD sync troubleshooting | [SKILL.md](./.agent/skills/nordri-bootstrap-guide/SKILL.md) |
| **Topic Branch Workflow** | Branch naming, commit/push workflow, utility scripts, and when direct push to main is acceptable | [SKILL.md](./.agent/skills/topic-branch-workflow/SKILL.md) |
| **Workflow Auditor** | Detect repeated manual workarounds (3+ instances) and propose utility scripts or ws subcommands | [SKILL.md](./.agent/skills/workflow-auditor/SKILL.md) |
| **Writing Yggdrasil Docs** | Conventions for documentation, Mermaid diagram rules, terminology, and cluster layer naming | [SKILL.md](./.agent/skills/writing-yggdrasil-docs/SKILL.md) |

---

## Workspace CLI (`ws`)

The unified entry point for workspace operations. Use `bash scripts/ws <cmd>`
(or just `ws <cmd>` if `scripts/` is on your PATH).

| Command | Description |
|---------|-------------|
| `ws list` | List all components with tier, chart version, local status |
| `ws status [--verbose]` | Git status across all cloned components |
| `ws clone [name\|--all]` | Clone ecosystem component(s) into `components/` |
| `ws pull [name]` | Pull latest for cloned components |
| `ws push [comp] [branch]` | Push to `siliconsaga` via HTTPS (auto-sources `.env`) |
| `ws pr <comp> <title> <bodyfile>` | Open PR from current branch to main |
| `ws issue <repo> <title> <label> <bodyfile>` | File a GitHub issue with attribution check |
| `ws resolve [--dry-run]` | Generate ArgoCD Application manifests (dual-mode) |
| `ws vscode` | Generate VS Code workspace file from cloned components |
| `ws test <comp> [args...]` | Run tests (auto-detects Makefile, Go, Python) |
| `ws review <pr#> [--reviewer <name>]` | Fetch PR review comments from GitHub |
| `ws commit <comp> <message> [bodyfile]` | Commit with Co-Authored-By trailer |
| `ws log [comp] [--oneline]` | Show commits on current branch vs main |
| `ws clean` | Remove draft files from `.issues/`, `.prs/`, `.commits/` |
| `ws exec <comp> <cmd...>` | Run a command in a component directory |
| `ws help` | Show available commands |

**Adding new subcommands:** See [`docs/ws-cli-guide.md`](docs/ws-cli-guide.md)
for how to add commands and classify their permission tier.

### Standalone scripts (not wrapped by `ws`)

| Script | Usage |
|--------|-------|
| `setup-branch-protection.sh` | One-time admin op — requires admin-scoped `GH_TOKEN` |
| `validate-agent-setup.sh` | Verify GH_TOKEN, auth, repo access, branch protection |

---

## Git Workflow

Always use a topic branch. Main is protected.

```bash
# 1. Start from up-to-date main
git checkout main && git pull siliconsaga main   # pull may need HTTPS workaround — see below

# 2. Create topic branch
git checkout -b <type>/<description>             # feat, fix, docs, chore, test, refactor

# 3. Commit (include Co-Authored-By trailer identifying the AI agent)
git commit -m "type: description

Co-Authored-By: <agent-name> <agent-email>"

# 4. Push (MUST use script — plain git push fails due to GitKraken SSH rewrite)
bash scripts/ws push <component>

# 5. Draft PR body → .prs/<description>.md (gitignored)
cp .agent/pr-template.md .prs/<description>.md

# 6. Open PR
bash scripts/ws pr <component> "type: description" .prs/<description>.md
```

**Why `git-push.sh` and not plain `git push`:** GitKraken adds a global
`url."git@github.com:".insteadOf=https://github.com/` rule to `~/.gitconfig`,
silently rewriting all HTTPS remotes to SSH. The terminal shell doesn't have
GitKraken's SSH key loaded, so plain `git push siliconsaga` fails with
"Permission denied (publickey)". The script pushes to an explicit
`https://x-access-token:$GH_TOKEN@…` URL that doesn't match the insteadOf
prefix and bypasses the rewrite. GitKraken continues to push via SSH unaffected.

---

## Auth Setup

- `GH_TOKEN` in `.env` (gitignored). See `.env.example`.
- Source it: `source .env` (add to shell profile for convenience).
- `gh` CLI uses `GH_TOKEN` automatically — no browser login needed.
- Day-to-day agent PAT scopes: Contents write, Issues write, Pull requests write.
  Administration scope is NOT included; use a separate admin token for `setup-branch-protection.sh`.

Full setup guide: [`docs/github-cli-setup.md`](docs/github-cli-setup.md)

---

## Ecosystem Manifest

`ecosystem.yaml` is the central declaration of all SiliconSaga components.
It defines tiers, chart versions, namespaces, and Helm values overrides.

`ecosystem.local.yaml` (gitignored) lets developers override any field
per-machine without touching the shared manifest. Common uses:

- `forceChart: true` on a component to use its chart even with local source
- Override `values:` for local environment specifics (hostnames, feature flags)
- `disabled: false` on echo-test to validate chart-mode resolution

The `ws-resolve.sh` script merges both files and generates ArgoCD Application
manifests, choosing Git source or OCI chart per component based on what's
checked out locally (and any `forceChart` overrides).

## IDE Setup

IDE workspace files are NOT tracked in Git — they vary per developer and
per set of cloned components.

- **VS Code**: Run `bash scripts/ws vscode` to generate `yggdrasil.code-workspace`
  from your currently cloned components. Re-run after cloning more.
- **JetBrains**: Open the `yggdrasil/` directory, then attach component
  directories as modules via File > Project Structure.
- **Terminal / Neovim / etc.**: Just `cd` into `yggdrasil/` or any component
  under `components/`. The scripts work from anywhere.

---

## Issue / PR Drafts

| Path | Purpose |
|------|---------|
| `.agent/issue-template.md` | Committed template for GitHub issues |
| `.agent/pr-template.md` | Committed template for PR bodies |
| `.issues/<repo>-<name>.md` | Gitignored draft clearinghouse for issues |
| `.prs/<description>.md` | Gitignored draft clearinghouse for PRs |

All agent-filed issues must start with the AI attribution blockquote from the template.

---

## Operational Rules

1. **Check `AGENTS.md` first**: Always verify if a relevant skill exists here before starting a complex task.
2. **Read Referenced Skills**: If a task matches a skill above, read the content of the referenced file to get the latest instructions.
