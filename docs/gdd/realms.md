# Realms

A **realm** is a community's shared configuration as a small git repo, cloned into `realms/realm-<community>/` alongside components and hoards. Where a hoard is *yours* and a component is *the work*, a realm is the *community layer* between them — which components exist, what tier each sits in, identity defaults, MCP server overrides, adapter commands, and any community-scoped agent material (`AGENTS.md`, `.agent/skills/`).

Realms are how a group sets up the same workspace shape across all of its members' machines without forcing everyone to edit config by hand. One person curates the realm; everyone else clones it.

---

## Where realms live

```text
yggdrasil/
  realms/
    realm-template/        # upstream tutorial scaffold
    realm-siliconsaga/     # example community realm
```

Each realm is an independent git repo, gitignored from the workspace itself. The naming convention `realm-<community>` marks a directory as a realm candidate for `ws realm list` — but cloning a realm never activates it. Activation is an explicit trust decision (see below).

The upstream `realm-template` ships as a tutorial scaffold; communities fork it and edit, ending up with something like `realm-siliconsaga` or `realm-yourorg`. See [Getting Started](../getting-started/index.md) for the clone-and-go walkthrough and the realm-creation pattern.

---

## What's in a realm

A realm typically carries:

- **`ecosystem.yaml`** — component list, tiers, defaults. The community declaration of "what we work on."
- **Identity defaults** — agent identity (e.g. `agent-refr`), attribution conventions, fork-org settings.
- **MCP server overrides** — which MCP servers the community runs and how they're wired.
- **Adapter commands** — community-specific shell helpers exposed to agents.
- **`AGENTS.md`** — community-level agent instructions layered on top of the workspace root's.
- **`.agent/skills/`** — community-scoped skills that ship to every member's sessions.

Anything an individual would otherwise have to copy across machines or re-explain to a new contributor is a candidate to live in the realm.

---

## The three-layer config merge

`ws` resolves a single effective config from three sources, child overrides parent:

```text
ecosystem.yaml              (upstream — generic defaults)
  ↓
realms/<active>/ecosystem.yaml   (community)
  ↓
ecosystem.local.yaml             (per-developer, gitignored)
```

All `ws` subcommands read the merged result. The realm owns the component list and community defaults; upstream provides methodology and tooling; local overrides are for per-developer or per-machine quirks. See [Ecosystem Architecture](../ecosystem-architecture.md#three-layer-config-merge) for the full merge semantics.

---

## The `ws realm` commands

```bash
ws realm init                 # clone the upstream template realm (tutorial)
ws realm <git-url>            # clone a community realm (cloned ≠ active)
ws realm list                 # show available realms and which is active
ws realm use [--trust] <name> # review the trust summary, then activate
```

The active realm is whichever directory `ecosystem.local.yaml`'s `realm:` selector points at; with no selector, only the bundled `realm-template` is implied. A community realm never activates just by being present on disk — `ws realm use` first prints a **trust summary** (repository hosts, adapter commands, credential-mapping requests, MCP endpoints) and asks for confirmation before writing the selector. In a non-interactive session (agents, scripts) the `--trust` flag is required after reviewing the summary — and for agents that flag is itself human-gated by the permission hook, so activating a community realm always lands on a person.

---

## Trust level

A realm is an extension of your own hoards (when you author it) or of the team you joined (when you adopt one). Realm content sits at **trust level 1b** in the hierarchy — community context for the workspace, trusted alongside the workspace root for `AGENTS.md`, `.agent/skills/`, and ecosystem config — but that trust is *granted*, not assumed: the `ws realm use` trust summary is the gate, and until it's passed the cloned realm influences nothing. Two boundaries hold even after activation: a realm's `defaults.gitTokens` entries are advisory (credential mapping is only authoritative from the committed workspace config plus your `ecosystem.local.yaml` — a realm cannot attach your tokens), and the risk surface that distinguishes a realm from the root is its **adapter command strings** (`realms/<r>/adapters/*.yaml` `commands.{test,lint,build}`) — these are executable config, and `gdd-orientation`'s risk scan reads them on activation with provenance-scaled rigor (light for your own / your team's realms; heavy for community / wild realms).

Cloning a realm is a higher-trust act than cloning an arbitrary component — only clone realms from communities you're committing to. See [Trust and Safety](trust-and-safety.md) for the full hierarchy and [Adapter Trust](adapters.md#adapter-trust-executable-config-is-config-that-executes) for the executable-config-surface framing.

---

## Switching and running side-by-side

You can have multiple realms cloned simultaneously and flip between them with `ws realm use <name>`. This is mostly useful for:

- **Tutorial → real.** Start with `realm-template` to learn the workspace, then switch to your community realm when ready.
- **Cross-community contribution.** A developer who works in two communities (say, `realm-siliconsaga` and `realm-yourorg`) keeps both cloned and switches when context shifts.

Components from inactive realms aren't touched — `ws` just reads a different `ecosystem.yaml` for resolution.

---

## Future direction: realm chains

The merge generalizes to N layers. The same upstream → realm → local shape extends to corp → dept → team chains for organizations with layered config, with the same child-wins semantics. Light reservation in code; not needed for v1. See the [realms and hoards design](../plans/2026-04-24-realms-and-hoards-design.md#future-directions) for the planned shape.

---

## See also

- [GDD Features Tour](features.md) — where realms fit in the larger feature set.
- [Hoards](hoards.md) — the personal counterpart to realms.
- [Ecosystem Architecture](../ecosystem-architecture.md) — the merge semantics and dual-mode source resolution.
- [Getting Started](../getting-started/index.md) — clone-and-go walkthrough including realm setup.
- [Trust and Safety](trust-and-safety.md) — realm content's trust level and the broader hierarchy.
