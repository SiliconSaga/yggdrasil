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

Community overlays declare their own component catalogs. If an overlay is
active, check its `AGENTS.md` for the full Repo Roles table
(e.g. `overlays/overlay-yggdrasil-live/AGENTS.md`).

Git remotes: Avoid using a generic `origin` — use explicit remote names
matching your Git org (e.g. your GitHub org or GitLab group name)

---

## Skills

Workspace-level skills live in `.agent/skills/<name>/SKILL.md`.
Community overlays may provide additional component-specific skills in
`overlays/<name>/.agent/skills/` — these are discovered during GDD orientation.

| Skill Name | Description | Source / Reference |
| :--- | :--- | :--- |
| **GDD (Orchestrator)** | Guardian Driven Development — detects roles/modes, delegates to practice and mode skills | [SKILL.md](./.agent/skills/gdd/SKILL.md) |
| **GDD Orientation** | Session startup — reads Thalamus.md, trust verification of component instructions, mode/role setup | [SKILL.md](./.agent/skills/gdd-orientation/SKILL.md) |
| **GDD Housekeeping** | Audit Thalamus.md — review, promote, prune observations and concerns with the human | [SKILL.md](./.agent/skills/gdd-housekeeping/SKILL.md) |
| **GDD Review Triage** | Multi-reviewer PR/MR coordination — fetch, deduplicate, and triage findings from CodeRabbit, Copilot, and others | [SKILL.md](./.agent/skills/gdd-review-triage/SKILL.md) |
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

---

## Workspace CLI (`ws`)

The shared interface for both humans and AI agents. Use `bash scripts/ws <cmd>`
(or just `ws <cmd>` if `scripts/` is on your PATH).

| Command | Description |
|---------|-------------|
| `ws list` | List all components with tier, chart version, local status |
| `ws status [--verbose]` | Git status across all cloned components |
| `ws clone [name\|--all]` | Clone ecosystem component(s) into `components/` |
| `ws pull [name]` | Pull latest for cloned components |
| `ws push [comp] [branch]` | Push to `siliconsaga` via HTTPS (auto-sources `.env`) |
| `ws pr <comp> <title> <bodyfile>` | Open PR/MR from current branch to main |
| `ws issue <repo> <title> <label> <bodyfile>` | File an issue with attribution check |
| `ws resolve [--dry-run]` | Generate ArgoCD Application manifests (dual-mode) |
| `ws vscode` | Generate VS Code workspace file from cloned components |
| `ws test <comp> [args...]` | Run tests (auto-detects Makefile, Go, Python) |
| `ws review <comp> <pr#\|threads> [options]` | PR/MR review comments and thread management (see `ws review --help`) |
| `ws commit <comp> <bodyfile\|message>` | Commit with Co-Authored-By trailer (bodyfile mode preferred) |
| `ws log [comp] [--oneline]` | Show commits on current branch vs main |
| `ws clean` | Remove draft files from `.issues/`, `.prs/`, `.commits/` |
| `ws exec <comp> <cmd...>` | Run a command in a component directory |
| `ws overlay init` | Clone template overlay for tutorials |
| `ws overlay <url>` | Clone a community overlay |
| `ws overlay use <name>` | Set active overlay in ecosystem.local.yaml |
| `ws overlay list` | Show available overlays and which is active |
| `ws actions <comp>` | List adapter commands for a component |
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

**Never use raw `git add`, `git commit`, or `git push`** — always use
`ws commit` and `ws push`. They handle staging, attribution trailers,
and auth automatically. For deleted files, use `remove:` in the bodyfile
frontmatter.

Always use a topic branch. Main is protected.

```bash
# 1. Start from up-to-date main
git checkout main && git pull siliconsaga main   # pull may need HTTPS workaround — see below

# 2. Create topic branch
git checkout -b <type>/<description>             # feat, fix, docs, chore, test, refactor

# 3. Commit (use ws commit — stages files listed in add: and appends Co-Authored-By trailer)
#    Write a bodyfile to .commits/ with frontmatter:
#      ---
#      message: "type: description"
#      add:                              # paths relative to component root
#        - path/to/file1.md
#        - path/to/file2.md
#      remove:                           # deleted files to stage for removal
#        - path/to/old-file.md
#      ---
#      Extended commit body here.
bash scripts/ws commit <component> .commits/my-change.md

# 4. Push (use ws push — handles auth and workarounds automatically)
bash scripts/ws push <component>
# Only use --force immediately after a rebase (which rewrites history).
# Normal commits on a topic branch use regular push.

# 5. Draft PR/MR body → .prs/<description>.md (gitignored)
cp .agent/change-template.md .prs/<description>.md

# 6. Open PR/MR
bash scripts/ws pr <component> "type: description" .prs/<description>.md
```

**Why `ws push` and not plain `git push`:** The push script auto-detects
the correct remote (by org name, not `origin`) and includes safety checks
(e.g., refusing to force-push `main`). See [`docs/git-provider-setup.md`](docs/git-provider-setup.md)
for auth setup details. Always use `ws push` for pushing.

---

## Code Style

**Comments and docs describe current state, not history.** Code comments,
test names, and Javadoc should be grounded in what the code does now — not
what it used to do or what bug it fixed. Historical context belongs in commit
messages and PR/MR descriptions, which are the record of change.

Good: `// CoreRegistry is set in initialize() after rootContext is created`
Bad: `// The previous call here passed null`

Good: `@DisplayName("should resolve parent beans")`
Bad: `@DisplayName("before the fix, this was broken")`

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
- Day-to-day agent PAT scopes: repo-level read/write for contents, issues, PRs/MRs.
  Administration scope is NOT included; use a separate admin token for `setup-branch-protection.sh`.

Full setup guide: [`docs/git-provider-setup.md`](docs/git-provider-setup.md)

---

## Ecosystem Config (Three-Layer Merge)

Configuration is assembled from three layers, merged in order:

1. `ecosystem.yaml` — upstream Yggdrasil defaults (generic, no components)
2. `overlays/<active>/ecosystem.yaml` — community overlay (components, identity)
3. `ecosystem.local.yaml` — per-developer overrides (gitignored)

All `ws` commands read the merged result via `ws_resolve_ecosystem()`.

`ecosystem.local.yaml` common uses:

- `forceChart: true` on a component to use its chart even with local source
- Override `values:` for local environment specifics (hostnames, feature flags)
- `disabled: false` on echo-test to validate chart-mode resolution
- `overlay: <name>` to select a specific overlay (auto-detection is default)

The `ws-resolve.sh` script uses the merged config to generate ArgoCD Application
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

## Issue / PR/MR Drafts

| Path | Purpose |
|------|---------|
| `.agent/issue-template.md` | Committed template for issues |
| `.agent/change-template.md` | Committed template for PR/MR bodies |
| `.issues/<repo>-<name>.md` | Gitignored draft clearinghouse for issues |
| `.prs/<description>.md` | Gitignored draft clearinghouse for PRs/MRs |

All agent-filed issues must start with the AI attribution blockquote from the template.

---

## Operational Rules

1. **Check `AGENTS.md` first**: Always verify if a relevant skill exists here before starting a complex task.
2. **Read Referenced Skills**: If a task matches a skill above, read the content of the referenced file to get the latest instructions.
