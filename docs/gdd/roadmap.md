# Roadmap

Where GDD goes after 1.0. The release line is **Claude-first with a published roadmap**: Claude Code is the fully supported agent at GA, and the items below have designed paths — they're direction, not dated promises. Progress lands incrementally (the author runs several parallel workspaces, so roadmap tracks often advance alongside mainline work); the [CHANGELOG](https://github.com/SiliconSaga/yggdrasil/blob/main/CHANGELOG.md) records what has actually shipped, and [versioning.md](versioning.md) covers how releases work.

## More agents — cross-harness support

The biggest post-1.0 track. The portable layers are already agent-neutral — `AGENTS.md`, the `ws` CLI, `ws orient`, and skills as plain markdown work in any harness — while the Claude-specific pieces (the PreToolUse hook, `.claude/settings.json`) need per-agent counterparts.

- **Codex** — actively in progress: session-scoped commit attribution already works cross-agent, two focused Codex hooks now ship in-repo, and the compatibility bundle (startup/skill discovery, permission semantics, auth/review/MCP, setup validation) is underway.
  - **Cross-agent hooks, shipped** — a "Kubernetes guard" to help prevent accidental changes was implemented both within `ws` and as harness hooks for _both_ Claude and Codex, with the required subtle differences; a second Codex hook delivers the workflow redirects (raw `git commit`/`git push`/provider commands → the `ws` wrappers) by reading the same committed `[redirect-commands]` rules the Claude hook uses — the first slice of the hook policy split below, live.
  - **Per-agent onboarding docs** — Codex-specific setup guidance will live in a `CODEX.md` sibling to `CLAUDE.md` when Codex onboarding is written up; `AGENTS.md` stays agent-agnostic.
- **Gemini and Antigravity** — next on deck once the two enabling primitives land, at which point adding an agent becomes mechanical rather than bespoke:
  - **Skill cross-registration** — skills stay canonical in `.agent/skills/`; a `ws` step registers them into each installed agent's native discovery path (Claude, Codex, Cursor, Antigravity), with stale-link cleanup on realm switches.
  - **Hook policy split** — the hook's *policy* (redirects, destructive-ask patterns, corrective messages) becomes platform-neutral data, with thin per-agent enforcement adapters. Each agent gets the same training loop through its own hook mechanism. The redirect rules already work this way (see above); the remaining sections follow as each agent's adapter needs them.
- **Cross-framework permissions** — mapping the allowlist model onto each framework's permission config; the semantics differ enough per harness that this rides with each agent's adapter. Whether an agent-agnostic permissions source under `.agent/` should anchor this is tracked in [#127](https://github.com/SiliconSaga/yggdrasil/issues/127).

## Assisted access and support — reaching non-developers

The other big post-1.0 track: lowering the barrier for people who aren't developers, and handling the support that comes with them. The throughline is *see it, say it, ship it — and get help when stuck*. Several pieces, most already prototyped or designed against real dogfood runs (see [case studies](case-studies.md)):

- **PR preview deploys + visual diffs** — every pull request to a gh-pages (or other static-site) component gets a live preview URL and an automatic before/after screenshot comparison posted to the PR, so a non-developer can *see* a change before it ships instead of reading a diff. Pure GitHub Actions — no third-party service, no API key — so it ports to any Pages component. Design and first implementation plan are written.
- **Chat-channel agents** — GDD driven from a phone over chat. Claude Code's official channel plugins (Discord, Telegram, iMessage) turn a direct message into an agent session: the user describes a change, the agent opens a PR, CI builds the preview and diff, the bot replies with a link and the diff image, and a reply of "ship it" merges. The user never touches git directly; the PR remains the audit trail underneath. Voice comes free from the phone's own dictation — no bespoke voice feature needed. A **web-development concierge** persona pairs this loop with a site; and because a long-lived chat session eventually fills its context, the agent watches for that and offers a gentle *"good time to start fresh?"* — archiving the session and re-orienting from its persistent notes so nothing important is lost.
- **`ws share` — encrypted, ephemeral support handoff** — one command to share a session transcript with a helper when a user is stuck: `ws share` redacts secrets first, encrypts, uploads to a short-TTL / single-view store, and returns a link; `ws share-raw` is the deliberate no-redaction escape. A split-knowledge option — the agent delivers the link, the human delivers the password over a separate channel — keeps the transport alone from being enough to read it. Remote assistance for agent sessions.
- **Guided onboarding for non-technical users** — extends the setup-wizard direction below: automate the detection, craft the prepopulated token-create URL, and leave the human only the click-and-paste that has to be theirs. A companion bootstrap capability lets GDD stand up a fresh, scoped GDD instance inside a sandbox — GDD setting up GDD — turning onboarding into a guided ceremony rather than a manual build.

## Sandboxed workspaces — containerized, trust-scaled execution

Running an always-on agent *for* someone — or simply isolating your own parallel agent sessions from each other — means putting a scoped GDD workspace inside a container. This is a general execution capability, not tied to any one user or site, and it underpins the assisted-access track above:

- **Self-contained workspace image** — the container bakes the GDD toolchain in (immutable, versioned by image tag) while the workspace itself is a mutable git checkout on a volume, so GDD stays improvable from inside and the work stays git-tracked. The agent gets the full `ws` CLI, orientation, skills, and its own Thalamus — a real workspace, not a bare mount. That persistent Thalamus is also what makes deliberate session rotation safe: a fresh session re-orients from durable notes rather than a fragile in-memory context.
- **Trust-scaled rigor** — for a trusted user, a plain container: the workspace holds only in-scope repos, so out-of-scope simply does not exist to touch, and only the safe chat tools (reply/react) are ever pre-allowed — never bypassed permissions. For the untrusted case, **NVIDIA OpenShell** (Apache-2.0), whose policy engine and *egress token injection* keep real credentials outside the container entirely, so a prompt-injected agent has nothing to leak. The same purpose-built image drops into either.
- **Bring-your-own-entitlement** — each person the sandbox serves runs on **their own** Claude plan and their own logins. Hosting (whose machine runs the container) is deliberately separate from entitlement (whose subscription and tokens it uses); nothing is shared or resold. The model is managed hosting, not a shared account — and the end goal is a user self-sufficient enough to host their own.
- **Resilient by design** — a supervisor recovers a dead session automatically (the failure being cured is precisely an agent that silently stops answering), and process-level health checks surface trouble without leaking status into a user's chat. Wiring a live container into the operator's observability stack — a ping when any hosted workspace stops responding — is the natural next step.
- **Hosting spectrum** — the same container carries a progression the end user never sees: a homelab box today, the user's own plan on operator-hosted compute next, and — further out — a **pod in a Kubernetes cluster** pulling its token from cluster secrets. "GDD-in-Kubernetes" as a general execution target is a post-OpenShell future, but the credential seam is designed now so it isn't walled out.
- **Component-level skills** — the sandbox is also GDD's first *component-scoped* skill: operator instructions that live with the component rather than the workspace, a small primitive that generalizes to any component wanting to carry its own agent guidance.

## More tutorials and template flavors

The [Guarded Kubernetes tutorial](../tutorials/guarded-kubernetes.md) and the gh-pages scaffold set the two shapes (docs-page and scaffold). Planned growth:

- **More component template flavors** — local frontend (vanilla JS), local backend (per-language where adapters exist), a full-stack mini, and an MCP server template. Multiple flavors also let learners exercise the multi-machine thalami sync by switching projects across sessions.
- **A refreshed end-to-end onboarding pass** — re-testing the newcomer path on clean machines and folding the friction findings back in (this is continuous — see the [case studies](case-studies.md) for how a real dogfood run feeds the framework).
- **Richer scaffolding** (further out) — backing `ws component init` with a real templating system rather than a copy, connecting to the template-upgrade machinery hoards already have.

## Team collaboration — Team Thalami

A solid 1.x community-oriented feature. Today's Thalamus is deliberately one human + one agent; teams need their own shared note home. The design instinct: the **realm** is the natural team tier — it already carries shared config, identity, and skills — so a team Thalamus likely lives in or beside the realm rather than as a synced mirror of anyone's personal file. The distinction to get right is *publishing for visibility* (easy — a read-only view of personal notes) versus *moving to team collaboration* (the real feature). This extends the [organization stack](organization-stack.md)'s ceremonies to multi-person seams and gets its own design cycle before any code.

## Flagship writeups

The methodology docs explain how GDD works; longer-form pieces about *why* and *what it's like* are queued: an "age of personalized software" thesis piece, after-action reports from real builds, and expansion of the [case studies](case-studies.md). Raw material exists; writing time is the constraint.

## CLI and infrastructure ideas — waiting on evidence of need

Designed-but-deferred `ws` growth, each picked up when real usage demands it:

- `ws rebase` — script the repeatable rebase ceremony (backup branch, conflict preview, verification).
- `ws run <comp> <action>` — execute any adapter-declared action, not just test/lint/build.
- `ws changelog --stack` — stack-level change-note aggregation across the ecosystem manifest (see [versioning.md](versioning.md) § Stack-level aggregation).
- **Setup wizard** — guided token/identity/remote onboarding during orientation.
- `ws realm new` — interactive realm scaffolding (today: fork-and-edit the template on GitHub).
- **Workspace-wide diagnose** — one-shot aggregate health view across components, identity, and tools.
- **Shared lint config** — ship `.markdownlint.yaml` / `.shellcheckrc` / `.editorconfig` so local tools and review bots read the same rules.
- `ws repo-config sync` — reconcile trackable repo settings (issue-label taxonomy, branch protection) from realm config as the single source of truth: additive by default, opt-in destructive prune behind a dry-run and confirmation, mirroring the read-audit / write-apply split of the k8s guard. Worth naming once two or three such reconcilers exist.
- **Remote-homes routing** — generalize the fork/internal/external homes model across `ws push` / `ws cr` / `ws diagnose`, plus the "automate detection, craft the URL, human does only the click only they can" pattern for human-authority gates.

## Not (yet) on the roadmap

Multi-realm inheritance chains (corp → dept → team), a realm/hoard template marketplace, and deeper scaffolding-platform integrations are acknowledged futures with reservations in the code, but they wait for someone with the concrete need.
