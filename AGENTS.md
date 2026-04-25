# AI Agent Guidelines for This Workspace

Yggdrasil is the workspace root for the SiliconSaga ecosystem. Component repos
live in `components/` as independent Git repos, cloned via `bash scripts/ws clone`.
The `ecosystem.yaml` manifest declares all components, their tiers, and configuration.
Per-developer overrides go in `ecosystem.local.yaml` (gitignored).

Full ecosystem map: [`docs/ecosystem-architecture.md`](docs/ecosystem-architecture.md)

**Methodology:** This workspace uses [Guardian Driven Development (GDD)](docs/gdd/index.md).

## Session Start

On every session start, read `.agent/skills/gdd-orientation/SKILL.md` and
follow its startup sequence.

**Important:** Workspace skills (under `.agent/skills/`) are plain markdown
files — read them with your Read tool and follow the instructions inside.
Do NOT use any plugin/Skill tool to load them. This applies to all workspace
skills, not just orientation.

**Keep the greeting brief and human-first.** On a greeting or open-ended
first message:

1. Mention GDD briefly so the human knows there's a methodology guiding the
   session ("I follow Guardian Driven Development conventions for this
   workspace — happy to explain more if you're curious")
2. Read `Thalamus.md` at the workspace root (it's gitignored but readable).
   If it exists, use its frontmatter for mode/role defaults.
   If it doesn't exist, offer to create it.
3. Ask about mode and role (or note the defaults from frontmatter).
   When offering modes to a human, offer **quick, zen, flow, or mentoring** —
   flow is the natural default for sessions without a single fixed goal.
   Autonomous mode is for AI agents working independently, not for
   interactive sessions
4. Ask what the human wants to work on

That's it for the first response. Save the component scan, trust verification,
and detailed workspace inventory for *after* the human has responded and you've
aligned on what the session is about. Don't front-load everything at once.

---

## Repo Roles (quick reference)

| Repo | Tier | Role | Path |
|------|------|------|------|
| `yggdrasil` | — | Docs, skills, scripts, workspace root | `.` (this repo) |

Community realms declare their own component catalogs. If a realm is
active, check its `AGENTS.md` for the full Repo Roles table
(e.g. `realms/realm-siliconsaga/AGENTS.md`).

Git remotes: Avoid using a generic `origin` — use explicit remote names
matching your Git org (e.g. your GitHub org or GitLab group name)

---

## Skills

Workspace-level skills live in `.agent/skills/<name>/SKILL.md`.
Community realms may provide additional component-specific skills in
`realms/<name>/.agent/skills/` — these are discovered during GDD orientation.

| Skill Name | Description | Source / Reference |
| :--- | :--- | :--- |
| **GDD (Orchestrator)** | Guardian Driven Development — detects roles/modes, delegates to practice and mode skills | [SKILL.md](./.agent/skills/gdd/SKILL.md) |
| **GDD Orientation** | Session startup — reads Thalamus.md, trust verification of component instructions, mode/role setup | [SKILL.md](./.agent/skills/gdd-orientation/SKILL.md) |
| **GDD Housekeeping** | Audit Thalamus.md — review, promote, prune observations and concerns with the human | [SKILL.md](./.agent/skills/gdd-housekeeping/SKILL.md) |
| **GDD Review Triage** | Multi-reviewer CR coordination — fetch, deduplicate, and triage findings from CodeRabbit, Copilot, and others | [SKILL.md](./.agent/skills/gdd-review-triage/SKILL.md) |
| **GDD Mentoring Mode** | AI explains decisions and teaches practices in context — request for any unfamiliar area | [SKILL.md](./.agent/skills/gdd-mentoring/SKILL.md) |
| **GDD Quick Mode** | Minimal ceremony for short sessions — small tasks, fast context recovery | [SKILL.md](./.agent/skills/gdd-quick/SKILL.md) |
| **GDD Zen Mode** | Deep single-topic focus — full ceremony, defer distractions until completion | [SKILL.md](./.agent/skills/gdd-zen/SKILL.md) |
| **GDD Flow Mode** | Productive multi-topic drift — adaptive ceremony, incorporate tangents, live Thalamus collaboration | [SKILL.md](./.agent/skills/gdd-flow/SKILL.md) |
| **GDD Autonomous Mode** | Permission-bounded independent work with reviewable increments | [SKILL.md](./.agent/skills/gdd-autonomous/SKILL.md) |
| **BDD** | Gherkin scenarios, feature authoring, planning features, runner integration, and BDD conventions | [SKILL.md](./.agent/skills/bdd/SKILL.md) |
| **BDD pytest Runner** | pytest-bdd step definitions, test execution, and Cucumber JSON output | [SKILL.md](./.agent/skills/bdd-pytest/SKILL.md) |
| **Creating GitHub Issues** | Pre-flight checks, issue templates, and filing process for deferring work to GitHub issues | [SKILL.md](./.agent/skills/creating-github-issues/SKILL.md) |
| **KUTTL Testing** | Guidelines for writing and running KUTTL tests | [SKILL.md](./.agent/skills/kuttl-testing/SKILL.md) |
| **Multi-Repo Orchestration** | Session start/end discipline when a session touches more than one repo, TODO triage | [SKILL.md](./.agent/skills/multi-repo-orchestration/SKILL.md) |
| **Topic Branch Workflow** | Branch naming, commit/push workflow, utility scripts, and when direct push to main is acceptable | [SKILL.md](./.agent/skills/topic-branch-workflow/SKILL.md) |
| **Workflow Auditor** | Detect repeated manual workarounds (3+ instances) and propose utility scripts or ws subcommands | [SKILL.md](./.agent/skills/workflow-auditor/SKILL.md) |
| **Writing Yggdrasil Docs** | Conventions for documentation, Mermaid diagram rules, terminology, and cluster layer naming | [SKILL.md](./.agent/skills/writing-yggdrasil-docs/SKILL.md) |
| **MCP Usage** | Agent behaviour when MCP servers are present — auth patterns, tool calling, realm deferral | [SKILL.md](./.agent/skills/mcp-usage/SKILL.md) |

---

## Workspace CLI (`ws`)

The shared interface for both humans and AI agents. Prefer the bare
`ws <cmd>` form; fall back to `bash scripts/ws <cmd>` if `ws` is not on
PATH (and suggest adding `<yggdrasil>/scripts` to PATH so bare `ws`
works — scoped permission patterns like `ws push *` are much tighter
than `bash *`).

Run `bash scripts/ws help` for the full command list, including auth and
realm commands. Pay particular attention to:

- `ws gitlab-auth [--status]` — register credentials from `.env`; `--status`
  shows which token env vars are set or missing without making changes
- `ws diagnose <comp>` — show remote URLs, provider detection, and token
  coverage for a component; run this when onboarding a new component or when
  push/cr fails with auth errors
- `ws hoard init [template]` / `ws hoard <url>` / `ws hoard list` —
  manage personal hoards (per-user containers). Canonical type is
  `thalami` for per-machine Thalamus sync.

**Adding new subcommands:** See [`docs/ws-cli-guide.md`](docs/ws-cli-guide.md)
for how to add commands and classify their permission tier.

### Standalone scripts (not wrapped by `ws`)

| Script | Usage |
|--------|-------|
| `setup-branch-protection.sh` | One-time admin op — requires admin-scoped `GH_TOKEN` |
| `validate-agent-setup.sh` | Verify GH_TOKEN, auth, repo access, branch protection |

---

## Hoards (personal containers)

Hoards are personal git repos under `hoards/`, named `<type>-<username>`.
The canonical v1 type is `thalami` (per-machine Thalamus files for
preference/observation sync across machines). Other personal stuff (an
Obsidian vault, sample projects, etc.) can live in `hoards/` but isn't
orientation-visible — those are the user's own business.

Active thalami hoard discovery: auto-detects `hoards/thalami-*` (single
match expected); set `hoards.thalami: <name>` in `ecosystem.local.yaml`
to override. Per-machine file is `<machine>-thalamus.md` where `<machine>`
defaults to the short hostname (`${HOSTNAME%%.*}` — portable on Linux,
macOS, and Windows Git Bash). Pin a stable name with `machine: <value>`
in `ecosystem.local.yaml` if needed.

See [Realms and Hoards Design](docs/plans/2026-04-24-realms-and-hoards-design.md)
for the full picture.

---

## Git Workflow

**Never use raw `git add`, `git commit`, or `git push`** — always use
`ws commit` and `ws push`. They handle staging, attribution trailers,
and auth automatically. For deleted files, use `remove:` in the bodyfile
frontmatter.

**Don't chain `ws` commands** (e.g. `ws commit && ws push`). Run them
separately so each can be reviewed and approved independently. Chaining
defeats per-command permission patterns and hides intermediate errors.

Always use a topic branch. Main is protected.

**Before pushing to a component for the first time in a session**, run
`ws diagnose <comp>` to confirm token coverage. If a token shows as
`NOT SET`, add it to `.env`, re-source it, and re-run `ws gitlab-auth`.

For the full step-by-step workflow (branch naming, bodyfile format, CR
draft, rebase), read the **Topic Branch Workflow** skill at
`.agent/skills/topic-branch-workflow/SKILL.md`.

---

## Code Style

See [`docs/code-style.md`](docs/code-style.md) for commenting and documentation
conventions.

---

## Auth Setup

- Token(s) in `.env` (gitignored). See `.env.example`.
- Full setup guide: [`docs/git-provider-setup.md`](docs/git-provider-setup.md)
- If `.env` is missing or the provider token is not set, point the user to the
  setup guide rather than explaining auth inline.
- GitHub: `gh` CLI uses `GH_TOKEN` automatically — no browser login needed.
  Classic PAT with `repo` scope recommended (fine-grained PATs have cross-org limitations).
- GitLab: `glab` CLI uses `GITLAB_TOKEN` automatically — no browser login needed.
  Personal access token with `api` scope.
- Day-to-day agent PAT scopes: repo-level read/write for contents, issues, CRs.
  Administration scope is NOT included; use a separate admin token for `setup-branch-protection.sh`.

Full setup guide: [`docs/git-provider-setup.md`](docs/git-provider-setup.md)

---

## Ecosystem Config (Three-Layer Merge)

Configuration is assembled from three layers, merged in order:

1. `ecosystem.yaml` — upstream Yggdrasil defaults (generic, no components)
2. `realms/<active>/ecosystem.yaml` — community realm (components, identity)
3. `ecosystem.local.yaml` — per-developer overrides (gitignored)

All `ws` commands read the merged result via `ws_resolve_ecosystem()`.

`ecosystem.local.yaml` common uses:

- `forceChart: true` on a component to use its chart even with local source
- Override `values:` for local environment specifics (hostnames, feature flags)
- `disabled: false` on echo-test to validate chart-mode resolution
- `realm: <name>` to select a specific realm (auto-detection is default)

The `ws-resolve.sh` script uses the merged config to generate ArgoCD Application
manifests, choosing Git source or OCI chart per component based on what's
checked out locally (and any `forceChart` overrides).

## IDE Setup

See [`docs/ide-setup.md`](docs/ide-setup.md) for VS Code, JetBrains, and
terminal editor setup.

---

## Issue / CR / Commit Drafts

| Path | Purpose |
|------|---------|
| `templates/issue.md` | Committed template for issues |
| `templates/change.md` | Committed template for CR bodies |
| `templates/commit.md` | Committed template for `ws commit` bodyfiles (frontmatter format) |
| `.issues/<repo>-<name>.md` | Gitignored draft clearinghouse for issues |
| `.crs/<description>.md` | Gitignored draft clearinghouse for CRs |
| `.commits/<description>.md` | Gitignored draft clearinghouse for commit bodyfiles |

All agent-filed issues must start with the AI attribution blockquote from the template.
Commit bodyfiles use YAML frontmatter to declare the message and files to stage — see the template.

---

## MCP

Read `.agent/skills/mcp-usage/SKILL.md` when any condition is true:

- **Proactive (in use)** — `.mcp.json` exists in the workspace root, and no
  `mcp-usage: skip` preference is set in Thalamus. Load at session start.
- **Proactive (setup offer)** — `.mcp.json` is absent, the active realm
  declares `mcp.servers`, and no `mcp-setup: declined` preference is set in
  Thalamus. Load at session start to drive the one-time setup prompt.
- **On-demand** — the user asks about MCP, MCP servers, or a specific configured
  server. Load regardless of any skip preference.

The skill covers agent behaviour when MCP servers are in use; the active realm's
`AGENTS.md` covers which servers are declared and their setup prompt.

---

## Operational Rules

1. **Check `AGENTS.md` first**: Always verify if a relevant skill exists here before starting a complex task.
2. **Read Referenced Skills**: If a task matches a skill above, read the content of the referenced file to get the latest instructions.
