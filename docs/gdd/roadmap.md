# Roadmap

Where GDD goes after 1.0. The release line is **Claude-first with a published roadmap**: Claude Code is the fully supported agent at GA, and the items below have designed paths — direction, not dated promises. Progress lands incrementally (the author runs several parallel workspaces, so roadmap tracks often advance alongside mainline work); the [CHANGELOG](https://github.com/SiliconSaga/yggdrasil/blob/main/CHANGELOG.md) records what has actually shipped, and [versioning.md](versioning.md) covers how releases work.

## More agents — cross-harness support

The biggest post-1.0 track. The portable layers are already agent-neutral — `AGENTS.md`, the `ws` CLI, `ws orient`, and skills as plain markdown work in any harness — while the Claude-specific pieces (the PreToolUse hook, `.claude/settings.json`) need per-agent counterparts.

- **Codex** — actively in progress: session-scoped commit attribution already works cross-agent, two focused Codex hooks ship in-repo, and the compatibility bundle (startup/skill discovery, permission semantics, auth/review/MCP, setup validation) is underway.
  - **Cross-agent hooks, shipped** — a "Kubernetes guard" preventing accidental changes is implemented both within `ws` and as harness hooks for _both_ Claude and Codex, with the required subtle differences; a second Codex hook delivers the workflow redirects (raw `git commit`/`git push`/provider commands → the `ws` wrappers) by reading the same committed `[redirect-commands]` rules the Claude hook uses — the first slice of the hook policy split below, live.
  - **Per-agent onboarding docs** — Codex-specific setup guidance lives in a `CODEX.md` sibling to `CLAUDE.md`; `AGENTS.md` stays agent-agnostic while each harness documents its own approval, sandbox, and interaction semantics.
- **Gemini and Antigravity** — next on deck once two enabling primitives land, at which point adding an agent becomes mechanical rather than bespoke:
  - **Skill cross-registration** — skills stay canonical in `.agent/skills/`; a `ws` step registers them into each installed agent's native discovery path (Claude, Codex, Cursor, Antigravity), with stale-link cleanup on realm switches.
  - **Hook policy split** — the hook's *policy* (redirects, destructive-ask patterns, corrective messages) becomes platform-neutral data, with thin per-agent enforcement adapters, so each agent gets the same training loop through its own hook mechanism. The redirect rules already work this way; the remaining sections follow as each agent's adapter needs them.
- **Cross-framework permissions** — mapping the allowlist model onto each framework's permission config; the semantics differ enough per harness that this rides with each agent's adapter. Whether an agent-agnostic permissions source under `.agent/` should anchor this is tracked in [#127](https://github.com/SiliconSaga/yggdrasil/issues/127).

## Assisted access and support — reaching non-developers

The other big post-1.0 track: lowering the barrier for people who aren't developers, and handling the support that comes with them. The throughline is *see it, say it, ship it — and get help when stuck*. Several pieces, most already prototyped or designed against real dogfood runs (see [case studies](case-studies/index.md)):

- **PR preview deploys + visual diffs** — every pull request to a gh-pages (or other static-site) component gets a live preview URL and an automatic before/after screenshot comparison posted to the PR, so a non-developer can *see* a change before it ships instead of reading a diff. Pure GitHub Actions — no third-party service, no API key — so it ports to any Pages component. The design and first implementation plan are already written.
- **Chat-channel agents** — GDD driven from a phone over chat. Claude Code's official channel plugins (Discord, Telegram, iMessage) turn a direct message into an agent session: the user describes a change, the agent opens a PR, CI builds the preview and diff, the bot replies with a link and the diff image, and a reply of "ship it" merges. The user never touches git directly; the PR remains the audit trail underneath. Voice comes free from the phone's own dictation. A **web-development concierge** persona pairs this loop with a site; and because a long-lived chat session eventually fills its context, the agent watches for that and offers a gentle *"good time to start fresh?"* — archiving the session and re-orienting from its persistent notes so nothing important is lost.
- **Release and support records** — durable, sanitized journals capture release progress, evidence, decisions, and agent-session references without embedding raw transcripts. They stay portable across harnesses and operating systems and can be published into Team Thalami for asynchronous support.
- **`ws share` — encrypted, ephemeral support handoff** — one command packages and redacts the underlying session evidence, encrypts it, and creates a short-lived handoff for an authorized helper. Searchable metadata stays separate from explicitly revealed raw material. A no-redaction escape exists for exceptional cases but is never automatic: it requires explicit human confirmation at share time plus an auditable record of the recipient and scope.
- **Guided onboarding for non-technical users** — extends the setup-wizard direction below: automate the detection, craft the prepopulated token-create URL, and leave the human only the click-and-paste that has to be theirs. A companion bootstrap capability lets GDD stand up a fresh, scoped GDD instance inside a sandbox — GDD setting up GDD — turning onboarding into a guided ceremony rather than a manual build.

## Sandboxed workspaces — containerized, trust-scaled execution

Running an always-on agent *for* someone — or simply isolating your own parallel agent sessions from each other — means putting a scoped GDD workspace inside a container. This is a general execution capability, not tied to any one user or site, and it underpins the assisted-access track above.

**A first working implementation shipped in 1.1** — [`gdd-sandbox`](https://github.com/SiliconSaga/gdd-sandbox), covering the trusted-user end of the spectrum below: the self-contained image, bring-your-own-entitlement, the supervisor, and chat-level outcome questions. See the [features tour](features.md#sandboxed-workspaces--gdd-sandbox-optional-companion) for what it does today. The rest of this track — the untrusted-user posture, the hosting spectrum, and cluster execution — remains direction:

- **Self-contained workspace image** — the container bakes the GDD toolchain in (immutable, versioned by image tag) while the workspace itself is a mutable git checkout on a volume, so GDD stays improvable from inside and the work stays git-tracked. The agent gets the full `ws` CLI, orientation, skills, and its own Thalamus — a real workspace, not a bare mount. That persistent Thalamus also makes deliberate session rotation safe: a fresh session re-orients from durable notes rather than a fragile in-memory context.
- **Trust-scaled rigor** — for a trusted user, a plain container: the workspace holds only in-scope repos, so out-of-scope simply doesn't exist to touch, and only the safe chat tools (reply/react) are ever pre-allowed — never bypassed permissions. For the untrusted case, **NVIDIA OpenShell** (Apache-2.0), whose policy engine and *egress token injection* keep raw credentials outside the container filesystem, injected only at the egress boundary under required policy-controlled routing. A prompt-injected agent therefore holds no directly-readable secret, though the boundary is only as strong as those policy controls: direct-provider paths or relaxed TLS weaken it. The same purpose-built image drops into either.
- **Bring-your-own-entitlement** — each person the sandbox serves runs on **their own** Claude plan and their own logins. Hosting (whose machine runs the container) is deliberately separate from entitlement (whose subscription and tokens it uses); nothing is shared or resold. The model is managed hosting, not a shared account, and the end goal is a user self-sufficient enough to host their own.
- **Resilient by design** — a supervisor recovers a dead session automatically (the failure being cured is precisely an agent that silently stops answering), and process-level health checks surface trouble without leaking status into a user's chat. Wiring a live container into the operator's observability stack — a ping when any hosted workspace stops responding — is the natural next step.
- **Hosting spectrum** — the same container carries a progression the end user never sees: a homelab box today, the user's own plan on operator-hosted compute next, and — further out — a **pod in a Kubernetes cluster** pulling its token from cluster secrets. "GDD-in-Kubernetes" as a general execution target is a post-OpenShell future, but the credential seam is designed now so it isn't walled out.
- **Component-level skills** — the sandbox is also GDD's first *component-scoped* skill: operator instructions living with the component rather than the workspace, a small primitive that generalizes to any component wanting to carry its own agent guidance.

## More tutorials and template flavors

The [Guarded Kubernetes tutorial](../tutorials/guarded-kubernetes.md) and the gh-pages scaffold set the two shapes (docs-page and scaffold). Planned growth:

- **A multi-phase newcomer arc** — describe GDD and its basics first, then a local-only starter tutorial (plain HTML edited and previewed in a browser — no credentials, no remote, no custom tooling), and only then "graduate" into realms, adapters, and remote workflows. The same phasing naturally starts newcomers on a single-machine local Thalamus and introduces the thalami hoard once they go multi-machine. GA testing showed the current intro reaches realm setup before a newcomer knows what GDD *is*.
- **More component template flavors** — local frontend (vanilla JS), local backend (per-language where adapters exist), a full-stack mini, and an MCP server template. Multiple flavors also let learners exercise multi-machine thalami sync by switching projects across sessions.
- **A refreshed end-to-end onboarding pass** — re-testing the newcomer path on clean machines and folding the friction findings back in (continuous — see [case studies](case-studies/index.md) for how a real dogfood run feeds the framework).
- **Progress checklists that graduate into task lists** — GA testing confirmed a simple checkbox progress view lands well early; wiring it into a formal tracked task list once a learner starts something concrete (like the gh-pages tutorial) is the natural next step.
- **Richer scaffolding** (further out) — backing `ws component init` with a real templating system rather than a copy, connecting to the template-upgrade machinery hoards already have.

## Team collaboration — Team Thalami

A solid 1.x community-oriented feature. Today's Thalamus is deliberately one human + one agent; teams need their own shared note home. The design instinct: the **realm** is the natural team tier — it already carries shared config, identity, and skills — so a team Thalamus likely lives in or beside the realm rather than as a synced mirror of anyone's personal file. The distinction to get right is *publishing for visibility* (sanitized release and support records are one early use case) versus *moving to team collaboration* (the real feature). This extends the [organization stack](organization-stack.md)'s ceremonies to multi-person seams and gets its own design cycle before code.

## Flagship writeups

The methodology docs explain how GDD works; longer-form pieces about *why* and *what it's like* are queued: an "age of personalized software" thesis piece, after-action reports from real builds, and expansion of the [case studies](case-studies/index.md). Raw material exists; writing time is the constraint.

## CLI and infrastructure ideas — waiting on evidence of need

Designed-but-deferred `ws` growth, each picked up when real usage demands it:

- `ws rebase` — script the repeatable rebase ceremony (backup branch, conflict preview, verification).
- `ws run <comp> <action>` — execute any adapter-declared action, not just test/lint/build.
- `ws changelog --stack` — stack-level change-note aggregation across the ecosystem manifest (see [versioning.md](versioning.md) § Stack-level aggregation).
- **Setup wizard** — guided token/identity/remote onboarding during orientation.
- `ws realm new` — interactive realm scaffolding (today: fork-and-edit the template on GitHub).
- **Workspace-wide diagnose** — one-shot aggregate health view across components, identity, and tools.
- **Shared lint config** — ship `.markdownlint.yaml` / `.shellcheckrc` / `.editorconfig` so local tools and review bots read the same rules.
- `ws repo-config sync` — reconcile trackable repo settings (issue-label taxonomy, branch protection) from realm config as the single source of truth: additive by default, opt-in destructive prune behind a dry-run and confirmation, mirroring the read-audit / write-apply split of the k8s guard. The label taxonomy has a third consumer to keep in step: `.github/release.yml` categorizes auto-generated release notes by label, so the reconciler (or a label-focused skill) should treat the label set, the release-note categories, and the bodyfile `labels:` validation (issue #124) as one surface that drifts together. Worth naming once two or three such reconcilers exist.
- **Remote-homes routing** — generalize the fork/internal/external homes model across `ws push` / `ws cr` / `ws diagnose`, plus the "automate detection, craft the URL, and the human does only the click that only they can do" pattern for human-authority gates.
- **`ws realm init` rename-on-init** — the template currently clones into a literal `realm-template/` directory; offering the user's own realm name at init (clone + rename + adjust in one step) beats circling back for a rename later.
- **Adapter-suggestion nudge** — when tests run raw in a component with no adapter wired, a conditional one-line nudge to consider adding a `commands.test` mapping (today the hook only redirects where an adapter already exists).
- **Streamlined repo setup with an admin-scoped PAT** — collaborator invites and repo toggles currently need the human in the provider web UI when using a bot token; a user who supplies a personal admin PAT should get the agent *preparing* those steps end-to-end, with each authorization-changing action (invites, permission toggles) individually human-confirmed rather than run unattended.
- **Permission-hook performance profiling** — the PreToolUse hook measured ~3s typical / ~9.5s worst-case per invocation on a slow laptop; profile and trim once the feature surface settles (correctness first, speed second).

## Not (yet) on the roadmap

Multi-realm inheritance chains (corp → dept → team), a realm/hoard template marketplace, and deeper scaffolding-platform integrations are acknowledged futures with reservations in the code, but they wait for someone with the concrete need.
