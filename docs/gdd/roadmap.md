# Roadmap

Where GDD goes after 1.0. The release line is **Claude-first with a published roadmap**: Claude Code is the fully supported agent at GA, and the items below have designed paths — they're direction, not dated promises. Progress lands incrementally (the author runs several parallel workspaces, so roadmap tracks often advance alongside mainline work); the [CHANGELOG](https://github.com/SiliconSaga/yggdrasil/blob/main/CHANGELOG.md) records what has actually shipped, and [versioning.md](versioning.md) covers how releases work.

## More agents — cross-harness support

The biggest post-1.0 track. The portable layers are already agent-neutral — `AGENTS.md`, the `ws` CLI, `ws orient`, and skills as plain markdown work in any harness — while the Claude-specific pieces (the PreToolUse hook, `.claude/settings.json`) need per-agent counterparts.

- **Codex** — actively in progress in a parallel workspace: session-scoped commit attribution already works cross-agent, and the compatibility bundle (startup/skill discovery, permission semantics, auth/review/MCP, setup validation) is underway.
  - **First cross-agent hook** — a "Kubernetes guard" to help prevent accidental changes was implemented both within `ws` and as harness hooks for _both_ Claude and Codex, with the required subtle differences.
- **Gemini and Antigravity** — next on deck once the two enabling primitives land, at which point adding an agent becomes mechanical rather than bespoke:
  - **Skill cross-registration** — skills stay canonical in `.agent/skills/`; a `ws` step registers them into each installed agent's native discovery path (Claude, Codex, Cursor, Antigravity), with stale-link cleanup on realm switches.
  - **Hook policy split** — the hook's *policy* (redirects, destructive-ask patterns, corrective messages) becomes platform-neutral data, with thin per-agent enforcement adapters. Each agent gets the same training loop through its own hook mechanism.
- **Cross-framework permissions** — mapping the allowlist model onto each framework's permission config; the semantics differ enough per harness that this rides with each agent's adapter.

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
- **Remote-homes routing** — generalize the fork/internal/external homes model across `ws push` / `ws cr` / `ws diagnose`, plus the "automate detection, craft the URL, human does only the click only they can" pattern for human-authority gates.

## Not (yet) on the roadmap

Multi-realm inheritance chains (corp → dept → team), a realm/hoard template marketplace, and deeper scaffolding-platform integrations are acknowledged futures with reservations in the code, but they wait for someone with the concrete need.
