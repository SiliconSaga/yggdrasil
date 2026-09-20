# GDD Features Tour

A tour of what the yggdrasil workspace ships with. The [GDD index](index.md) covers the methodology; this doc covers the *features* — what's actually in the box and what each piece is for. For an end-to-end walkthrough rather than a feature inventory, go to [Getting Started](../getting-started.md).

> **🆕 New in 1.1 — [sandboxed workspaces](#sandboxed-workspaces-gdd-sandbox-optional-companion-new-in-11).** A scoped GDD agent in a container, reachable over chat and pointed at one component: a chat message from someone who does not write code becomes a reviewed pull request, and merging stays human.

---

## The workspace and the `ws` CLI

Yggdrasil is a *meta workspace* — a top-level directory that contains a shared CLI (`scripts/ws`), a workspace-level ecosystem config, and everything else (realms, hoards, components, templates, docs) hanging off it. Sessions run from the workspace root; all path references are relative to it.

The `ws` CLI is the shared interface for both humans and AI agents. Add `scripts/` to your PATH to run `ws <cmd>` directly; otherwise `bash scripts/ws <cmd>` works without setup. Run `ws help` to see all subcommands; `ws <subcommand> --help` for per-command details. Skills and instructions defer to the help system as the source of truth so they don't drift out of date.

The discoverability layer — `ws orient` (run at session start), the per-command stderr footer, and the wrapper-first reflex contract in [AGENTS.md](../../AGENTS.md) — keeps the CLI navigable as it grows. See [Agent Training § The progressive-disclosure buffet](agent-training.md#the-progressive-disclosure-buffet-l0-l1-l2) for the L0/L1/L2 framing.

**Common subcommands:**

- `ws orient` — Deterministic discovery menu: subcommands, active realm, per-component adapter wiring (with the resolved command surfaced), skill index. Run at session start, after compaction, or when switching tasks.
- `ws status` — Git status across the workspace (yggdrasil + components + realms + hoards).
- `ws clone <component>` — Clone a component declared in ecosystem config.
- `ws commit <component> <bodyfile>` — Bodyfile-driven commit (auto-stages, adds Co-Authored-By trailer).
- `ws checkout <component> <branch> [-b]` — Switch or create a branch. Branches only; it has no path mode, so it cannot discard working-tree changes.
- `ws push <component> [branch]` — Push to the per-developer fork remote.
- `ws cr <component> <title> <bodyfile>` — Open a pull/merge request; `ws cr <component> edit <n> <bodyfile>` updates one. `ws issue` has the same pair.
- `ws review <component> <pr#>` — Fetch CodeRabbit / Copilot review threads.
- `ws test` / `lint` / `format` / `build` / `run` / `clean <component>` — Run the component's own command for that task (see [Adapters](#adapters-one-verb-per-task-in-any-component)).
- `ws log <component>` — What is on this branch, incoming from upstream (`--incoming`), or against an explicit base (`--against <ref>`).
- `ws hoard init [template]`, `ws realm init`, `ws component init <flavor> <name>` — Scaffold new instances.

Every repo-touching verb also takes a nested target, `ws commit terasology/Health <bodyfile>`, for a component whose tree holds independent git repos.

---

## Realms — community configuration layer

A *realm* is a community's shared configuration: which components exist, what tier each is in, identity defaults, MCP server overrides, adapter commands. Realms are external git repos cloned into `realms/realm-<community>/`. The upstream `realm-template` is the tutorial scaffold; communities fork-and-edit (e.g. `realm-siliconsaga`).

The active realm is selected in `ecosystem.local.yaml` (per-developer, gitignored). You can switch realms (`ws realm use`) or run multiple side-by-side; the [three-layer config merge](../ecosystem-architecture.md#three-layer-config-merge) combines `ecosystem.yaml` (upstream) → `realms/<active>/ecosystem.yaml` (community) → `ecosystem.local.yaml` (your overrides).

Realm content is **trusted** at the same level as the workspace root itself — see [trust-and-safety.md](trust-and-safety.md) for the full hierarchy. A realm's `AGENTS.md`, `.agent/skills/`, and ecosystem config all flow into your sessions.

Future direction: multi-realm chains (corp → dept → team) for organizations with layered config. Light reservation in code; not needed for v1.

---

## Adapters — one verb per task, in any component

A realm's `adapters/<component>.yaml` maps six verbs onto whatever the component actually uses: `commands.test`, `lint`, `format`, `build`, `run` and `clean`. `ws test mimir` runs `bash scripts/test.sh`; `ws test terasology` runs `./gradlew unitTest`. The agent does not need to learn each project's toolchain, and `ws orient` prints every wired verb with the command it resolves to.

- **`ws test <comp> <name>`** runs one test. Gradle, Go, pytest and unittest filters are inferred; any other runner declares `commands.testFilter` with `{}` where the selector goes. Without one, a filter is refused, so a green full suite is never mistaken for the one test asked for.
- **`ws format` rewrites; `ws lint` checks.** A formatter's `--check` form belongs under `commands.lint`.
- **`ws run` prompts; the rest are pre-allowed.** Run targets are long-lived or interactive.
- **`nested:`** declares, by glob, independent git repos inside a component (Terasology's `modules/*`). They become addressable as `<component>/<repo>`; nothing recurses, and there is no bulk commit or push. `ws clone-fork <component>/<repo>` wires a fork remote onto the checkout in place, because a module only builds inside its host tree.
- **`ai_context:`** lists the docs an agent should read first for that component; `ws orient` marks any that no longer resolve.

Adapter commands are realm content, so they pass through realm trust review: a changed command or `nested:` list makes trust stale, and the approval prompt shows what changed. Reference: [adapters.md](adapters.md).

---

## Hoards — personal containers

A *hoard* is a personal repo for content that doesn't belong in any component or realm. The canonical hoard type is **thalami** — a per-developer container for the [Thalamus](thalamus.md) (the shared thinking space between you and the agent), with per-machine files so multiple workstations can sync their state via git.

Hoards live in `hoards/<type>-<user>/` and are independent git repos. The first session on a new machine resolves a hostname-derived `<machine>-thalamus.md` inside the active thalami hoard; subsequent sessions pick up the conversation history from there.

`ws hoard lint` validates thalamus frontmatter across every host's file: that it parses, that each arc carries the required keys, and that `next` fits the dashboard cell. A file that does not parse otherwise drops out of the cross-host Arc Dashboard without any error.

See [hoards.md](hoards.md) for the deeper dive: setup, the cadence config (`.ws-cadence.yaml`), multi-machine workflows, and where future hoard types might fit (e.g. vault-style knowledgebases).

---

## Component templates — opinionated scaffolds

`templates/components/<flavor>/` ships scaffolds for common project types. Run `ws component init <flavor> <name>` to copy one into `components/<name>/`, git-init it, register it in your local ecosystem config, and print suggested next steps (e.g. `gh repo create`).

The flagship template is **gh-pages** — a tiny GitHub Pages site designed as the new-contributor tutorial. From scaffold to live deployed page through the full GDD-and-bot-review loop is roughly 15 minutes.

Templates are opinionated where that removes friction and unopinionated where it would constrain creativity. The README inside each template is a deterministic walkthrough that someone can follow solo, without an agent.

Future direction: more flavors (local frontend, local backend, full-stack mini, MCP server template). The shape is established; each new flavor is just another `templates/components/<flavor>/` directory.

---

## The bot-driven review loop

Every component PR runs through automated review:

- **CodeRabbit** — semantic review of code, comments, structure. Posts inline comments and a top-level summary. Rate-limited per hour but otherwise reliable.
- **Copilot** — additional review (semantically distinct findings; often catches things CodeRabbit misses, and vice versa).
- **`ws review <component> <pr#>`** — fetches both reviews into a single shell view. `ws review <component> threads <pr#> --resolve <id>` for thread management; `ws review <component> reply <pr#> <thread-id> "<msg>" --resolve` for a reply-and-resolve in one go.
- **`ws review <component> comment`** posts a top-level comment (for findings outside the diff, which have no thread); **`ws review <component> edit`** rewrites a comment already posted. Replies, comments and edits all carry the AI-attribution banner.
- **`--since last-push`** narrows a review to what arrived after the latest push, so a second round shows only new findings.

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

## Stances — agent demeanor

Sessions run in one of three stances (plus an optional mentoring overlay) that shape how chatty or careful the agent is:

- **Quick** — terse, no ceremony, get-it-done.
- **Zen** — full ceremony, deep work, frequent housekeeping.
- **Flow** — the middle gear; sessions naturally drift across topics.
- **Mentoring overlay** — the agent explains decisions, teaches as it goes. Layer it on any stance for unfamiliar areas or your first session.

Stances are picked at session start (and can be re-picked mid-session). The active stance is established per session (`ws session`). Roles (developer, designer, reviewer, scribe) compose with stances — see [roles-and-stances.md](roles-and-stances.md).

---

## Permissions — what the agent can run without prompting

`.claude/settings.json`'s `permissions.allow` and `permissions.deny` control which commands run without a confirmation prompt (output streams normally either way; the question is just whether the user gets asked before execution). The two-layer defense model (subcommand-level safety + matcher-level scoping) keeps the allowlist trustworthy even if Claude Code's matcher behavior shifts.

Adding a new pattern? Read [permissions.md](permissions.md) — the **When to widen vs narrow patterns** section — first. Operational guidance for adding patterns or handling "don't ask again" prompts is in the `gdd-permissions` skill.

---

## Agent training — the PreToolUse hook

A PreToolUse hook at `.claude/hooks/gdd-permission-hook.sh` runs before every Bash tool call. It rejects shell composition (`&&`, `||`, `;`, pipes, redirects, command substitution, FD merges) with **corrective** messages — the deny is paired with a one-line explanation of what to do instead. The agent reads the message on its next turn and retries with the suggested approach, so the hook acts as a continuous training signal rather than a hard wall.

New users often see a burst of "scary red" deny output in the first few tool calls of a session as the agent's generic shell habits collide with the workspace's one-action-per-call convention. That's working as intended; nothing was harmed (the commands never ran) and the noise drops to near zero once the agent has cached the local conventions.

The hook is roughly free in API-token cost for commands that pass — splitting a `cmd | head 20` into two separate valid tool calls is still one assistant turn, not two API calls. A *denied* command does cost a retry: the agent reads the corrective message on its next turn and reissues, which is the deliberate teaching mechanism, and the denies taper off within a session as the conventions stick. Net, the hook pays off in auditability and context hygiene. See [agent-training.md](agent-training.md) for the token-cost model and what to do when a legitimate command gets denied.

Per-machine extras (opt-in): if a command you trust keeps getting denied, copy `.claude/hooks/hook-rules.local.example` to `hook-rules.local` (in the same directory) and add bash glob patterns under the `[allow-extras]` section. The live file is gitignored — patterns stay per-machine and don't leak into project policy.

Codex uses smaller feature bridges rather than importing the Claude hook wholesale: its redirect bridge consumes the same `[redirect-commands]` guidance for raw commit, push, PR-creation, and rename commands, and its Kubernetes bridge applies the shared guard policy. Both deny or defer, leaving unrelated and bypassed calls to normal Codex routing — a workflow-consistency aid, not a security boundary.

---

## Kubernetes practice guard — `ws k8s`

A safety scope for kubectl — training wheels while you learn, a guardrail near production: arm a scope (a context + one or more namespaces) and the workspace blocks accidental *writes* to anything outside it, before kubectl runs. Reads stay free cluster-wide; the guard is accident-prevention against destructive out-of-scope writes, **not** a security or confidentiality boundary (real authorization is server-side RBAC).

- `ws k8s scope set --context <ctx> --namespace <ns[,ns]>` arms the guard for the session; `ws k8s scope show` / `ws k8s scope clear` inspect and disarm. The context must exist; a namespace that doesn't exist yet only warns, so you can arm across environments and create the namespaces afterward.
- `ws k8s <kubectl args>` runs guarded: in-scope reads and writes go through (writes inject `--context`); out-of-scope, cluster-scoped, or malformed-input writes are REJECTED with a **class-aware** message naming the right next step (widen the scope, lift the guard, or fix the input). You may create/delete the very namespaces your scope covers.
- Recognized built-in mutations using `--dry-run=client` or `--dry-run=server` retain namespace and manifest validation but proceed without write friction **when run through `ws k8s`**, which is what injects the armed context. A raw `kubectl … --dry-run=…` is still redirected to the wrapper rather than auto-allowed: nothing would pin its context, so it would report on whichever cluster kubeconfig currently points at — and a dry-run answering about the wrong cluster is worse than no answer. `--dry-run=none`, duplicate modes, unsupported plugins, and dry-run-looking command data cannot enter this path.
- Claude Code and Codex have separate focused hook paths backed by the same `scripts/ws-k8s-guard.sh` policy. When a scope is armed, both catch raw `kubectl`, block out-of-scope writes with the shared message, deny in-scope raw writes with guidance to retry through `ws k8s` for context injection, and catch directly invoked scripts containing `kubectl`. The Codex bridge is deny-or-defer, so safe calls still follow normal Codex sandbox and approval routing. `ws hook-bypass k8s` lifts raw-command interception for a session (human-approved, audited) without disabling the guard inside `ws k8s`.
- A plain human terminal with no session id is still guarded by an active session's scope (ambient aggregation), so protection holds when you step in by hand.

The `gdd-k8s` skill drives the scope-capture flow; the mentoring overlay narrates each guard decision so a nervous practitioner learns the pattern, not just the commands. Harnesses without a verified pre-tool hook retain the portable `AGENTS.md` guidance plus the guarded `ws k8s` wrapper. Hands-on: the [Guarded Kubernetes tutorial](../tutorials/guarded-kubernetes.md) (needs a cluster). Reference: [skills-reference.md](skills-reference.md), [agent-training.md](agent-training.md), and the [Codex project configuration](../../.codex/README.md).

---

## Access — identities, tokens, remote operations

The parallel permission system: which **remote Git operations** the agent can perform on a repo. Mediated by token scope, collaborator status, and a deliberate **two-identity model** — the human contributor and a separate agent identity (e.g. `agent-refr`), each with its own scoped PAT.

The two-identity model gives reviewable attribution (every commit and PR is authored by one or the other), scope minimization (the agent token holds *just enough* permission for routine work), and clean revocation (compromise the agent token? revoke without disrupting your own access). The fork-or-collaborator pattern lets the agent push to repos it doesn't own:

- **Forks** for source-project contribution: `identity.homes.fork.namespace` declares the fork-home namespace, `forkRemote` names the local fork remote, and PRs/MRs target the source project from the fork.
- **Collaborator** for personal repos (typical for hoards): add the agent as a `push`-permission collaborator on your personal repo; no fork needed.

Multi-provider workflows (GitHub + GitLab + self-hosted) work without per-command configuration — `ws push` / `ws cr` / `ws review` auto-detect provider from remote URL and pick the right CLI and token.

[access.md](access.md) also covers **privilege inversion** — agent access should narrow as the driving human's access widens, because a maintainer's agent inherits their blast radius and their social weight — and the shared-versus-individual machine-account models.

Conceptual model: [access.md](access.md). Setup mechanics (installing CLIs, generating tokens, `.env` shape): [`docs/git-provider-setup.md`](../git-provider-setup.md). Diagnostic: `ws diagnose <component>` reports remote detection, token coverage, and whether there is anything to send.

---

## Agent communication — how the agent speaks in public

An agent's comments land in a community's tracker under someone's name. [agent-communication.md](agent-communication.md) names the four decisions a project makes about that — identity, register, disposition authority, privilege inversion — and gives three copyable settings. GDD names the questions; the project answers them.

- **`comms.flavor`** (`oss-wide` | `solo` | `corporate` | `none`) records the answer in ecosystem config. `ws orient` renders it first, above the subcommand survey, because it governs everything the agent writes for the rest of the session. Unset renders as a prompt to decide.
- **`comms.snippet`** is a local addition, restated every session so it is never quietly in force. An explicit empty value clears one inherited from the realm.
- **`style.changeNotes`** (`terse` | `standard` | `detailed`) sets how long commit, CR and issue bodies run — see the word budget below.

---

## Publication guards — what is checked before text goes out

A commit, a CR or an issue is permanent once published, so `ws commit`, `ws cr` and `ws issue` check the text first, on create and `edit` alike. Raw `gh pr edit --body` and its equivalents redirect to the wrappers, so the checks cannot be skipped by accident.

- **Attribution.** A CR or issue body must carry the AI-attribution banner naming the driving human, and a body with an unsubstituted `@HUMAN_ACCOUNT` or `@GDD_HOME` is refused.
- **PII guard.** An email address the repository has never held is refused — in a commit's subject, body or staged lines, or a CR or issue title or body. The filter is *novelty*, not shape: addresses already committed, RFC-reserved domains, role addresses (`noreply@`, `git@`) and entries in a staged `.gdd-pii-allow` all pass, so legitimate addresses do not raise noise. The case it exists for is an address typed into a local sample file and later carried into a published document by an agent doing unrelated work. It blocks; each command names its own one-off override, and the hook asks a human before any of them runs.
- **Word budget.** Bodies are counted in words against `style.changeNotes` (terse: 50 / 120 / 150 for commit / CR / issue) and the wrapper notes an overrun. Advisory, never blocking; fenced output does not count. `ws orient` prints the active numbers.

Reference: [ws CLI guide § Publication guards](../ws-cli-guide.md#publication-guards).

---

## The self-improving loop

Every observation captured in the Thalamus is candidate material for promotion. Housekeeping audits (default every 14 days, or on demand) walk through accumulated items and decide:

- **Promote** — to a GitHub issue, a skill update, an instruction-file edit, a gdd-workflow-audit candidate.
- **Keep** — relevant but not yet actionable.
- **Prune** — resolved, stale, or superseded.

This is how the framework refines itself through use: recurring things become formalized; resolved things drop off. See [self-improving-loop.md](self-improving-loop.md).

---

## The organization stack — capture to durable knowledge

Work in this ecosystem moves through four tiers: the **Vault** (a personal Obsidian hoard for life organization), the **Thalami** hoard (the Thalamus and in-flight arcs), component **Docs**, and **GitHub** (issues, PRs, the companion Project board). The *organization stack* names these tiers and the promotion paths between them, so nothing captured gets lost in a seam.

Two propose-then-confirm ceremonies move items across the tiers. The **scribe ceremony** triages the vault and hands GDD-bound items to a machine-agnostic `Intake.md` — the *bridge*. The **GDD ceremony** drains that intake into arcs, and graduates a closing arc's lasting value out to component docs and GitHub. A cadence ladder (daily / weekly / monthly) keeps each tier reviewed.

The model is adopt-as-you-grow: the Vault and scribe ceremony are a complete system on their own; the Thalami bridge, then the Docs and GitHub seams, layer on when the work calls for them.

Full reference: [organization-stack.md](organization-stack.md). Design and rationale: [the design doc](../plans/2026-05-19-organization-stack-design.md).

---

## Sandboxed workspaces: `gdd-sandbox` (optional companion, new in 1.1)

A scoped GDD agent in a Docker container, reachable over a chat channel (Discord today) and pointed at one target component. Someone collaborates with the agent by chat message while it does real GDD work inside the container — read, edit, commit, push, open a pull request — and the PR page is the review surface: preview link, before/after screenshots, and a merge button that stays human. The agent can open PRs; merging and releasing are denied outright, with branch protection enforcing what the permission posture promises.

What makes it safe enough to point at a non-technical person:

- **Scope by absence** — the container holds only the in-scope repositories, so out-of-scope work is impossible rather than merely forbidden.
- **Its own identity** — a dedicated code-host account with a fine-grained token scoped to the one target repo; agent-authored history stays honest, and revocation is one token.
- **Outcome-level questions** — consequential decisions are asked in chat in human terms ("here's the preview — ship it?"), never as raw tool prompts a non-technical person would learn to rubber-stamp.
- **Kept alive on purpose** — a supervisor recovers dead sessions, deliberate rotation clears stale context, and the healthcheck actively probes chat reachability, so an agent that silently stops answering cannot look healthy. When a session does block or go quiet, the supervisor says so in chat rather than leaving the person waiting.
- **No prompt without an answerer** — the workspace hook knows the session is headless, so a permission card that nobody could evaluate resolves as a refusal with a reason instead of hanging the conversation. See [Permissions § Headless sessions](permissions.md#headless-sessions-gdd_sandbox) for the tier this adds.
- **Own entitlement** — the sandbox runs on a Claude subscription setup-token; hosting (whose machine runs the container) is deliberately separate from entitlement (whose plan and logins it uses), aiming at a self-sufficient user on their own plan.

This is an **independent component**, not part of the workspace: fetch [SiliconSaga/gdd-sandbox](https://github.com/SiliconSaga/gdd-sandbox) (declare it in your ecosystem config and `ws clone gdd-sandbox`, or clone it directly under `components/`). It carries its own operator skill and README — the README's Configuration section is the authoritative setup reference. For direction, including the trust-scaled future for untrusted users, see the [roadmap's sandboxed-workspaces track](roadmap.md).

---

## Next steps

- Brand new? [Getting Started](../getting-started.md) walks you through cloning yggdrasil and a first session.
- Want the methodology before the tools? [GDD index](index.md).
- Ready to scaffold a tutorial component? `ws component init gh-pages my-page` and follow the printed README.
- Curious what's coming? The [roadmap](roadmap.md) covers post-1.0 direction; the [case studies](case-studies/index.md) show the current system on real work.
