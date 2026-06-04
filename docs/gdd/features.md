# GDD Features Tour

A tour of what the yggdrasil workspace ships with. The [GDD index](index.md) covers the methodology; this doc covers the *features* — what's actually in the box and what each piece is for.

If you want an end-to-end walkthrough rather than a feature inventory, go to [Getting Started](../getting-started/index.md). If you want the methodology that motivates the features, read the [GDD index](index.md) first.

---

## The workspace and the `ws` CLI

Yggdrasil is a *meta workspace* — a top-level directory that contains a shared CLI (`scripts/ws`), a workspace-level ecosystem config, and everything else (realms, hoards, components, templates, docs) hanging off it. Sessions run from the workspace root; all path references are relative to it.

The `ws` CLI is the shared interface for both humans and AI agents. Add `scripts/` to your PATH to run `ws <cmd>` directly; otherwise `bash scripts/ws <cmd>` works without setup. Run `ws help` to see all subcommands; `ws <subcommand> --help` for per-command details. Skills and instructions defer to the help system as the source of truth so they don't drift out of date.

**Common subcommands:**

- `ws status` — Git status across the workspace (yggdrasil + components + realms + hoards).
- `ws clone <component>` — Clone a component declared in ecosystem config.
- `ws commit <component> <bodyfile>` — Bodyfile-driven commit (auto-stages, adds Co-Authored-By trailer).
- `ws push <component> [branch]` — Push to the per-developer fork remote.
- `ws cr <component> <title> <bodyfile>` — Open a pull/merge request.
- `ws review <component> <pr#>` — Fetch CodeRabbit / Copilot review threads.
- `ws hoard init [template]`, `ws realm init`, `ws component init <flavor> <name>` — Scaffold new instances.

---

## Realms — community configuration layer

A *realm* is a community's shared configuration: which components exist, what tier each is in, identity defaults, MCP server overrides, adapter commands. Realms are external git repos cloned into `realms/realm-<community>/`. The upstream `realm-template` is the tutorial scaffold; communities fork-and-edit (e.g. `realm-siliconsaga`).

The active realm is selected in `ecosystem.local.yaml` (per-developer, gitignored). You can switch realms (`ws realm use`) or run multiple side-by-side; the [three-layer config merge](../ecosystem-architecture.md#three-layer-config-merge) combines `ecosystem.yaml` (upstream) → `realms/<active>/ecosystem.yaml` (community) → `ecosystem.local.yaml` (your overrides).

Realm content is **trusted** at the same level as the workspace root itself — see [trust-and-safety.md](trust-and-safety.md) for the full hierarchy. A realm's `AGENTS.md`, `.agent/skills/`, and ecosystem config all flow into your sessions.

Future direction: multi-realm chains (corp → dept → team) for organizations with layered config. Light reservation in code; not needed for v1.

---

## Hoards — personal containers

A *hoard* is a personal repo for content that doesn't belong in any component or realm. The canonical hoard type is **thalami** — a per-developer container for the [Thalamus](thalamus.md) (the shared thinking space between you and the agent), with per-machine files so multiple workstations can sync their state via git.

Hoards live in `hoards/<type>-<user>/` and are independent git repos. The first session on a new machine resolves a hostname-derived `<machine>-thalamus.md` inside the active thalami hoard; subsequent sessions pick up the conversation history from there.

See [hoards.md](hoards.md) for the deeper dive: setup, the cadence config (`.ws-cadence.yaml`), multi-machine workflows, and where future hoard types might fit (e.g. vault-style knowledgebases).

---

## Component templates — opinionated scaffolds

`templates/components/<flavor>/` ships scaffolds for common project types. Run `ws component init <flavor> <name>` to copy one into `components/<name>/`, git-init it, register it in your local ecosystem config, and print suggested next steps (e.g. `gh repo create`).

The flagship template is **gh-pages** — a tiny GitHub Pages site designed as the new-contributor tutorial. From scaffold to live deployed page through the full GDD-and-bot-review loop is roughly 15 minutes.

Templates are designed to be opinionated where it removes friction and unopinionated where it constrains creativity. The README inside each template is a deterministic walkthrough that someone can follow solo, without an agent.

Future direction: more flavors (local frontend, local backend, full-stack mini, MCP server template). The shape is established; each new flavor is just another `templates/components/<flavor>/` directory.

---

## The bot-driven review loop

Every component PR runs through automated review:

- **CodeRabbit** — semantic review of code, comments, structure. Posts inline comments and a top-level summary. Rate-limited per hour but otherwise reliable.
- **Copilot** — additional review (semantically distinct findings; often catches things CodeRabbit misses, and vice versa).
- **`ws review <component> <pr#>`** — fetches both reviews into a single shell view. `ws review <component> threads <pr#> --resolve <id>` for thread management; `ws review <component> reply <pr#> <thread-id> "<msg>" --resolve` for a reply-and-resolve in one go.

The agent + the bots together form the review apparatus. You can work fully via the agent (which reads the bot output and proposes fixes) or step in manually — the `ws review` CLI is shaped for both.

Skills involved:

- `gdd-review-triage` — fetches and consolidates review findings.
- `requesting-code-review` — pre-merge review template (when you want a final pass before pushing).

---

## The Thalamus — shared thinking

A *Thalamus* file (`Thalamus.md` in the workspace root, OR `<machine>-thalamus.md` in the active thalami hoard) is the shared thinking space between you and the agent: observations, preferences, concerns, and audit log. The agent writes immediately on safety concerns (the "black-box pattern"); other writes happen at natural pauses.

The orientation skill reads it at session start. The housekeeping skill audits it periodically (defaults to every 14 days; configurable via `staleness_days` frontmatter). The cadence skill nudges you to commit accumulated changes when they age past a threshold (defaults to 2 days; configured per-hoard in `.ws-cadence.yaml`).

Full design: [thalamus.md](thalamus.md). Operational mechanics: [hoards.md](hoards.md).

---

## Modes — agent demeanor

Sessions run in one of four modes that shape how chatty or careful the agent is:

- **Quick** — terse, no ceremony, get-it-done.
- **Zen** — full ceremony, deep work, frequent housekeeping.
- **Flow** — the middle gear; sessions naturally drift across topics.
- **Mentoring** — the agent explains decisions, teaches as it goes. This is the right first-session mode for new contributors.

Modes are picked at session start (and can be re-picked mid-session). The default lives in your Thalamus frontmatter (`mode:`). Roles (developer, designer, reviewer, scribe) compose with modes — see [roles-and-modes.md](roles-and-modes.md).

---

## Permissions — what the agent can run without prompting

`.claude/settings.json`'s `permissions.allow` and `permissions.deny` control which commands run without a confirmation prompt (output still streams normally either way; the question is just whether the user gets asked before execution). The two-layer defense model (subcommand-level safety + matcher-level scoping) keeps the allowlist trustworthy even if Claude Code's matcher behavior shifts.

Adding a new pattern? Read [permissions.md](permissions.md) — the **When to widen vs narrow patterns** section — first. Operational guidance for adding patterns or handling "don't ask again" prompts is in the `gdd-permissions` skill.

---

## Agent training — the PreToolUse hook

A PreToolUse hook at `.claude/hooks/gdd-permission-hook.sh` runs before every Bash tool call. It rejects shell composition (`&&`, `||`, `;`, pipes, redirects, command substitution, FD merges) with **corrective** messages — the deny is paired with a one-line explanation of what to do instead. The agent reads the message on its next turn and retries with the suggested approach, so the hook acts as a continuous training signal rather than a hard wall.

New users often see a burst of "scary red" deny output in the first few tool calls of a session as the agent's generic shell habits collide with the workspace's one-action-per-call convention. That's working as intended; nothing was harmed (the commands never ran) and the noise drops to near zero once the agent has cached the local conventions.

The hook is roughly free in API-token cost — splitting a `cmd | head 20` into two separate tool calls is still one assistant turn, not two API calls — and pays off in auditability and context hygiene. See [agent-training.md](agent-training.md) for the full explanation, including the token-cost model and what to do when a legitimate command gets denied.

Per-machine extras (opt-in): if a command you trust keeps getting denied, copy `.claude/hooks/hook-rules.local.example` to `hook-rules.local` (in the same directory) and add bash glob patterns under the `[allow-extras]` section. The live file is gitignored — patterns stay per-machine and don't leak into project policy.

---

## Access — identities, tokens, remote operations

The parallel permission system: which **remote Git operations** the agent can perform on a repo. Mediated by token scope, collaborator status, and a deliberate **two-identity model** — the human contributor and a separate agent identity (e.g. `agent-refr`), each with its own scoped PAT.

The two-identity model gives reviewable attribution (every commit and PR is clearly authored by one or the other), scope minimization (the agent token holds *just enough* permission for routine work), and clean revocation (compromise the agent token? revoke without disrupting your own access). The fork-or-collaborator pattern lets the agent push to repos it doesn't own:

- **Forks** for upstream contribution: `forkOrg` configures where the agent forks; PRs target the upstream from the fork.
- **Collaborator** for personal repos (typical for hoards): add the agent as a `push`-permission collaborator on your personal repo; no fork needed.

Multi-provider workflows (GitHub + GitLab + self-hosted) work without per-command configuration — `ws push` / `ws cr` / `ws review` auto-detect provider from remote URL and pick the right CLI and token.

Conceptual model: [access.md](access.md). Setup mechanics (installing CLIs, generating tokens, `.env` shape): [`docs/git-provider-setup.md`](../git-provider-setup.md). Diagnostic: `ws diagnose <component>` reports per-component remote detection and token coverage.

---

## The self-improving loop

Every observation captured in the Thalamus is candidate material for promotion. Housekeeping audits (default every 14 days, or on demand) walk through accumulated items and decide:

- **Promote** — to a GitHub issue, a skill update, an instruction-file edit, a gdd-workflow-audit candidate.
- **Keep** — relevant but not yet actionable.
- **Prune** — resolved, stale, or superseded.

This is how the framework refines itself through use: the things that recur become formalized; the things that resolve drop off. See [self-improving-loop.md](self-improving-loop.md).

---

## The organization stack — capture to durable knowledge

Work in this ecosystem moves through four tiers: the **Vault** (a personal Obsidian hoard for life organization), the **Thalami** hoard (the Thalamus and in-flight arcs), component **Docs**, and **GitHub** (issues, PRs, the companion Project board). The *organization stack* is the model that names these tiers and the promotion paths between them, so nothing captured gets lost in a seam.

Two propose-then-confirm ceremonies move items across the tiers. The **scribe ceremony** triages the vault and hands GDD-bound items to a machine-agnostic `Intake.md` — the *bridge*. The **GDD ceremony** drains that intake into arcs, and graduates a closing arc's lasting value out to component docs and GitHub. A cadence ladder (daily / weekly / monthly) keeps each tier reviewed.

The model is adopt-as-you-grow: the Vault and scribe ceremony are a complete system on their own; the Thalami bridge, then the Docs and GitHub seams, layer on when the work calls for them.

Full reference: [organization-stack.md](organization-stack.md). Design and rationale: [the design doc](../plans/2026-05-19-organization-stack-design.md).

---

## Next steps

- Brand new? [Getting Started](../getting-started/index.md) walks you through cloning yggdrasil and a first session.
- Want the methodology before the tools? [GDD index](index.md).
- Ready to scaffold a tutorial component? `ws component init gh-pages my-page` and follow the printed README.
