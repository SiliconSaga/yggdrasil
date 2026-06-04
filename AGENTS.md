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

**Three reference patterns appear in this codebase — don't confuse them:**

| Pattern | Example | How to use |
|---|---|---|
| Workspace skill path | `.agent/skills/gdd-orientation/SKILL.md` | Read the file with the Read tool. Do **not** invoke via the Skill tool. |
| Plugin skill identifier | `superpowers:executing-plans` | Invoke via the Skill tool. Requires the plugin (e.g. Obra Superpowers) installed. |
| `@<name>` cross-reference | `@gdd-orientation`, `@gdd-workflow-audit` | Informational pointer to a workspace skill in skill bodies — read the referenced file, don't invoke it as a tool. Plugin skills always use the explicit `superpowers:*` form, never `@<name>`. |

**Companion plugin (recommended):** GDD plans and several practice
skills reference [Obra Superpowers](https://github.com/obra/superpowers)
skills (e.g. `superpowers:executing-plans`,
`superpowers:subagent-driven-development`, `superpowers:brainstorming`,
`superpowers:test-driven-development`, `superpowers:receiving-code-review`).
Install Superpowers for the smoothest experience. The `gdd-orientation`
skill checks for it at session start and surfaces a one-line nudge if
not detected.

**Graceful degradation without Superpowers:** plan execution falls back
to manual step-by-step, TDD becomes implicit rather than skill-driven,
and `receiving-code-review` is read as documentation rather than
invoked. All workspace skills (under `.agent/skills/`) run without
Superpowers — only the `superpowers:*` plugin skills are unavailable.

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
| **Scribe** | Obsidian vault conventions: PARA, frontmatter, daily notes, wikilinks, inbox capture, daily review, weekly synthesis. Auto-loads for `role: scribe`; other roles dip in on capture-intent keywords. | [SKILL.md](./.agent/skills/scribe/SKILL.md) |
| **BDD** | Gherkin scenarios, feature authoring, planning features, runner integration, and BDD conventions | [SKILL.md](./.agent/skills/bdd/SKILL.md) |
| **BDD pytest Runner** | pytest-bdd step definitions, test execution, and Cucumber JSON output | [SKILL.md](./.agent/skills/bdd-pytest/SKILL.md) |
| **Creating GitHub Issues** | Pre-flight checks, issue templates, and filing process for deferring work to GitHub issues | [SKILL.md](./.agent/skills/gdd-github-issues/SKILL.md) |
| **KUTTL Testing** | Guidelines for writing and running KUTTL tests | [SKILL.md](./.agent/skills/kuttl-testing/SKILL.md) |
| **Multi-Repo Orchestration** | Session start/end discipline when a session touches more than one repo, TODO triage | [SKILL.md](./.agent/skills/multi-repo-orchestration/SKILL.md) |
| **Topic Branch Workflow** | Branch naming, commit/push workflow, utility scripts, and when direct push to main is acceptable | [SKILL.md](./.agent/skills/gdd-branch-workflow/SKILL.md) |
| **Workflow Auditor** | Detect repeated manual workarounds (3+ instances) and propose utility scripts or ws subcommands | [SKILL.md](./.agent/skills/gdd-workflow-audit/SKILL.md) |
| **Writing Yggdrasil Docs** | Documentation conventions: the Component Documentation Convention (four-Shape graduation ladder), no-hard-wrap rule, Mermaid diagram rules, terminology, and cluster layer naming | [SKILL.md](./.agent/skills/gdd-doc-writing/SKILL.md) |
| **MCP Usage** | Agent behaviour when MCP servers are present — auth patterns, tool calling, realm deferral | [SKILL.md](./.agent/skills/gdd-mcp/SKILL.md) |

---

## Workspace CLI (`ws`)

The shared interface for both humans and AI agents. Use the bare
`ws <cmd>` form; fall back to `bash scripts/ws <cmd>` if `ws` is not
on PATH. Scoped permission patterns like `ws push *` are much tighter
than `bash *` would be, so `ws` runs without prompts where raw tools
would interrupt.

### `ws`-first reflex check

**Before running any `git`, `gh`, `glab`, or test/build runner
directly: check whether `ws` has a wrapper.** A fresh agent's
training-data instinct is to reach for raw tooling; the workspace
expects the wrappers. The wrappers handle attribution, auth, remote
selection, and bodyfile-driven flows that raw tools won't.

| Reflex you'd reach for | Use this instead | What `ws` adds |
|------------------------|------------------|----------------|
| `git add` + `git commit -m "..."` | `ws commit <comp> <bodyfile>` | Bodyfile-driven staging + Co-Authored-By trailer |
| `git push` | `ws push <comp> [branch]` | Fork-remote selection from `forkOrg`; auto-sets upstream on first push |
| `git pull` | `ws pull <comp>` (or `ws pull` for all) | Walks components, realms, and hoards; rebases cleanly; skips dirty repos |
| `git status` | `ws status` | Cross-workspace view (yggdrasil + components + realms + hoards) with truncation |
| `git log` | `ws log [comp] [--oneline] [--limit N]` | Branch-vs-main, no need to remember the range syntax |
| `gh pr create` | `ws cr <comp> <title> <bodyfile>` | Bodyfile-driven; identity substitutions; right token + remote |
| `gh pr view` / fetching review threads | `ws review <comp> <cr#> [--compact] [--limit N] [--output <phrase>]` | Inline + notes + reviews in one shell view; `--compact` for headline-only triage; `--limit N` to slice; `--output <phrase>` saves snapshot to `.outputs/<ts>-<phrase>.txt` for follow-up grep |
| Reply/resolve a review thread (web UI or `gh api graphql`) | `ws review <comp> reply <cr#> <id> "msg" [--resolve]` | Auth + thread-id resolution |
| `gh issue create` | `ws issue <comp> [remote] <title> <label> <bodyfile>` | Same bodyfile pattern + identity |
| Raw test runners (`gradle test`, `pytest`, `make test`, …) | `ws test <comp> [args]` | Adapter dispatch via `realms/<active>/adapters/<comp>.yaml`; `ws actions <comp>` lists what's available. For pytest adapters, a positional path/nodeid targets that file (`ws test knarr tests/test_x.py`); a bare word becomes a `-k` filter |
| Raw linters (`ruff`, `eslint`, `golangci-lint`, …) | `ws lint <comp> [args]` | Adapter `commands.lint` dispatch (same `<comp>.yaml` as tests); args pass through (e.g. `ws lint knarr --fix`). `ws actions <comp>` shows the configured command |
| `git clone <fork-url>` + manual `git remote add upstream …` + `git fetch` | `ws clone-fork <comp>` | Ensures fork exists (creates via API if missing); SSH transport; both remotes wired; local + fork `main` synced with upstream. Idempotent. |

**Hook enforcement:** the PreToolUse hook denies the three write-side raw commands above (`git commit` / `git push` / `gh pr create`) at Tier 2 with a corrective message pointing at the `ws` subcommand. See `.claude/hooks/README.md` § Redirect tier and bypass for the bypass mechanism if a legitimate edge case requires raw access.

When in doubt: `ws help` for the full list, `ws help <subcommand>`
(or `ws <subcommand> --help`) for per-command details. Skills and
instructions defer to the help system as the source of truth.

### One command at a time — not bundled

Don't wrap `ws` calls (or auto-approved reads like `cat`, `ls`,
`hostname`) in compound shells like `ws X; ws Y; cat Z` or
`ws status && ws log`. Each piece is auto-approved individually but
compounds often trigger a prompt regardless. Same applies to:

- **`command | head`-style truncation** — most `ws` commands have
  a native flag for that (`ws status` truncates by default,
  `ws log --limit N`, `ws review --compact` and/or `--limit N`).
  Reach for the flag instead of piping into `head`.
- **`command > file` redirects** — Claude Code's matcher prompts
  on stdout-redirect-to-file regardless of the LHS, because the
  destination path is opaque to static analysis. For `ws review`
  specifically, use `--output <phrase>` to save into the
  workspace-internal `.outputs/` scratch dir (`ws clean` purges
  it). Then grep that file as a separate auto-approved command.
  For other commands, no native equivalent yet — accept the
  one-time prompt or argue for a flag if the pattern recurs.
- **`command | grep`-style filtering** — `ws review` already has
  `--reviewer <name>`, `--since <time>`, and `--compact` for the
  most common cuts. If you need ad-hoc grep, save with `--output`
  first then grep the file (two clean commands).

### Subcommand pointers

A few commands worth knowing exist beyond the reflex table:

- `ws gitlab-auth [--status]` — register glab credentials from
  `.env`; `--status` reports without making changes.
- `ws diagnose <comp>` — remote URLs, provider detection, token
  coverage. Run when push/cr fails with auth errors or when
  onboarding a new component.
- `ws clone-fork <comp>` — fork-aware clone: ensures the user's
  personal fork exists in `identity.forkOrg` (creates via API if
  missing), clones the fork over SSH, wires up both remotes (fork +
  upstream), and syncs local + fork `main` with upstream. Idempotent
  — re-runs are safe and re-sync. Use this instead of `ws clone`
  when a release-style workflow needs fork-as-origin remotes from
  the start.
- `ws preflight [--soft]` — workspace prerequisites (bash, git, yq
  v4+, jq, gh/glab) with per-OS install hints.
- `ws hoard init [template] [--name <name>]` / `ws hoard <url>` /
  `ws hoard list` — personal hoards. Canonical type is `thalami`
  for per-machine Thalamus sync; `basic` for generic hoards.
- `ws component init <flavor> [name]` / `ws component list` —
  scaffold a new component from a template. Flagship: `gh-pages`.
- `ws test yggdrasil` — run the workspace-root shell-script test
  suite (bats files under `tests/`). Uses a vendored `bats-core`
  runtime under `tests/vendor/bats-core/` so contributors don't
  need a system install; see `tests/vendor/README.md` for the
  refresh procedure.

**Adding new subcommands:** See [`docs/ws-cli-guide.md`](docs/ws-cli-guide.md)
for how to add commands and classify their permission tier.

### Standalone scripts (not wrapped by `ws`)

| Script | Usage |
|--------|-------|
| `setup-branch-protection.sh` | One-time admin op — requires admin-scoped `GH_TOKEN` |
| `validate-agent-setup.sh` | Verify GH_TOKEN, auth, repo access, branch protection |

---

## Hoards (personal containers)

Hoards are personal git repos under `hoards/` (gitignored, like
`components/` and `realms/`), named `<type>-<username>`. The canonical
v1 type is `thalami` (per-machine Thalamus files for preference /
observation sync across machines). Other personal stuff (an Obsidian
vault, sample projects, etc.) can live in `hoards/` but isn't
orientation-visible — those are the user's own business.

Active thalami hoard discovery: auto-detects `hoards/thalami-*` (single
match expected); set `hoards.thalami: <name>` in `ecosystem.local.yaml`
to override. Per-machine file is `<machine>-thalamus.md` where `<machine>`
defaults to the short hostname (`${HOSTNAME%%.*}` — portable on Linux,
macOS, and Windows Git Bash). Pin a stable name with `machine: <value>`
in `ecosystem.local.yaml` if needed.

Hoard templates ship under `templates/hoards/<flavor>/`. Current flavors:
`thalami`, `basic`, `obsidian-vault` (PARA-laid-out Obsidian vault with
auto-installed Templater + Periodic Notes + companion plugins).

See [Realms and Hoards Design](docs/plans/2026-04-24-realms-and-hoards-design.md)
for the full picture.

---

## Components (template-scaffolded)

Components are the third member of the template family alongside hoards
and realms. `templates/components/<flavor>/` directories ship in upstream
yggdrasil; `ws component init <flavor> <name>` copies one into
`components/<name>/`, git-inits it, and registers an entry in
`ecosystem.local.yaml` (the per-developer layer of the three-layer
config merge). The component is immediately usable from the workspace
without touching the realm; when ready to share, move the entry into the
realm's `ecosystem.yaml` with realm-appropriate fields and push.

Flagship flavor is `gh-pages` — a tutorial-friendly GitHub Pages site
with a README that walks a solo user through the full edit → PR →
bot-review → merge → see-it-live loop.

See [Component Templates Design](docs/plans/2026-04-25-component-templates-design.md)
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
`.agent/skills/gdd-branch-workflow/SKILL.md`.

---

## Code Style

See [`docs/code-style.md`](docs/code-style.md) for commenting and documentation
conventions.

### Prose line wrapping

**Don't hard-wrap prose at any character count.** Write each paragraph as a single line and let editors / renderers handle wrap.

This applies to all prose: markdown documents, READMEs, issue bodies, CR/PR descriptions, commit message bodies, hoard notes (Obsidian vault content), Thalamus entries, design docs.

It does *not* apply to:

- Code blocks (use whatever wrap fits the language)
- Tables (one row per line)
- Lists (one bullet per line — bullets are list items, not prose)
- YAML frontmatter

**Why:** GitHub renders some hard-wrapped contexts as visible line breaks; Obsidian/markdown editors wrap automatically; reflowing after every edit is friction. Specific code or tooling may have its own wrap conventions — follow those when they exist (e.g. Mermaid diagrams have their own rules in the gdd-doc-writing skill).

### Bash usage enforcement (PreToolUse hook)

This workspace ships a PreToolUse hook at `.claude/hooks/gdd-permission-hook.sh`, registered in `.claude/settings.json`. It fires on every Bash tool call and denies shell composition (`&&`, `||`, `;`, pipes, command substitution, redirects) with corrective messages that train the agent toward separate tool calls + native `ws` flags. It allows anything matching the project's `permissions.allow` patterns (symmetric normalization between bare `ws ...` and verbose `bash scripts/ws ...` forms) or per-machine allow patterns in `.claude/hooks/hook-rules.local` (copy from `hook-rules.local.example` and add glob patterns under `[allow-extras]`).

Full operational details — what each tier does, how to add personal safe-command patterns, how to disable the hook on a specific machine via `WS_HOOK_DISABLE=1`, what to do if a command stalls — live in [`.claude/hooks/README.md`](./.claude/hooks/README.md).

### Prefer write-then-execute over inline shell scripts

When you need to run anything more than a few lines (Python, JS, complex bash, anything with control flow), **write the script to `.tmp/<name>` via the Write tool first, then invoke it via Bash**. Don't pack the whole script into a `bash -c "..."` or `python -c "..."` one-liner.

Why:

- **Observability:** the Write tool's diff shows the full content in the transcript — easy for the human to scan before approving the execute. A long inline command is hard to read and often gets clipped.
- **Reviewability:** the file persists in `.tmp/` (gitignored) for post-hoc inspection. An inline one-liner disappears into the command history.
- **Hook compatibility:** non-trivial scripts almost always involve `&&`, `;`, pipes, or substitution — all of which the PreToolUse hook denies inline. The same operators inside a file body are fine; only the outer `bash <file>` invocation sees the hook, and `<file>` is one segment.
- **Cleanup:** `ws clean` removes `.tmp/` entries alongside the other workspace draft directories — no orphaned scratch files accumulate.

Inline `bash -c "..."` and `python -c "..."` are still fine for genuinely one-line workloads where inline is more readable than a file (a single `echo`, a quick math expression). Use judgment: if the inline form is longer than a sentence, it's a file.

Note: write-then-execute doesn't change the security boundary — a malicious script content is still a problem regardless of the vehicle. The human reviews the Write content as the canonical safety checkpoint; the hook adds visibility, not invulnerability.

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

Read `.agent/skills/gdd-mcp/SKILL.md` when any condition is true:

- **Proactive (in use)** — `.mcp.json` exists in the workspace root, and no
  `gdd-mcp: skip` preference is set in Thalamus. Load at session start.
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
