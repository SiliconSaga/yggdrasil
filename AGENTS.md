# AI Agent Guidelines for This Workspace

Yggdrasil is the workspace root. Component repos live in `components/` (independent Git repos, cloned via `ws clone`); the merged `ecosystem.yaml` declares what's available. Per-developer overrides go in `ecosystem.local.yaml` (gitignored).

**Methodology:** [Guardian Driven Development (GDD)](docs/gdd/index.md).

This file is the **L0 menu** — the slim contract that loads into every session. Deeper content (full skills catalog, every `ws` subcommand, code style, auth, etc.) is discoverable via `ws orient` and per-subcommand `ws <cmd> --help`. The orientation skill and the docs under `docs/gdd/` carry the long-form material.

---

## Session Start

On every session start, after compaction, or when dispatched fresh, you **MUST** do BOTH:

1. **Execute `ws orient`** for initial discovery of workspace utilities, the active realm, per-component adapter wiring, and the skill index. This is the deterministic answer to "what's here right now?" — verbs, realm, adapters, skills.
2. **Read `.agent/skills/gdd-orientation/SKILL.md`** and follow its startup sequence — Thalamus parsing, trust verification, stance/role setup, staleness checks.

`ws orient` answers *what's available*; the orientation skill governs *how to work with the human*. Both are session-start prerequisites, not optional discovery aids. (On a bare machine `ws orient` self-diagnoses — if `yq` is missing it runs `ws preflight` for you, which reports every missing prerequisite; prereqs are otherwise covered in [`docs/workspace-setup.md`](docs/workspace-setup.md).)

Two conventions you need before anything else:

1. **Workspace skills are plain markdown.** Files under `.agent/skills/<name>/SKILL.md` are read with the Read tool — do not invoke them via the Skill tool. This applies to every workspace skill, not just orientation. (Plugin skills like `superpowers:executing-plans` use the Skill tool — see Companion plugin below.)

2. **Active realm skills load on demand.** If a realm is present (e.g. `realms/realm-siliconsaga/`), it carries its own `AGENTS.md` and `.agent/skills/`. Orientation preloads the realm-side index at startup; individual realm skills load when their triggering conditions match.

---

## Reflex Contract — ws first

A fresh agent's instinct is to reach for raw `git`, `gh`, `glab`, or test runners. The workspace expects the `ws` wrappers — they handle attribution, auth, remote selection, and bodyfile-driven flows that raw tools don't.

**Unconditional verbs — always use the `ws` wrapper:**

| Reach for | Use instead |
|---|---|
| `git add` + `git commit -m "…"` | `ws commit <comp> <bodyfile>` |
| `git push` | `ws push <comp> [branch]` |
| `gh pr create` / `glab mr create` | `ws cr <comp> <title> <bodyfile>` |
| `gh pr view` / `gh pr checks` / `glab mr note` (reading or replying to review) | `ws review <comp> [cr#]` |
| `gh issue create` / `glab issue create` | `ws issue <comp> [remote] <title> <label> <bodyfile>` |
| `git clone <fork>` + manual remote-wiring | `ws clone <comp>` (or `ws clone-fork <comp>` for fork-as-origin) |
| One-off command inside a component dir | `ws exec <comp> <cmd…>` |

The PreToolUse hook denies `git commit` / `git push` / `gh pr create` at Tier 2 with a corrective pointer to the `ws` wrapper. Don't bypass — use the wrapper.

**Review phase — prefer `ws review`.** Now that `ws` injects tokens, the `ws gh` / `ws glab` one-off wrappers make raw `gh pr` / `glab mr` API calls easy to reach for — but for reading or triaging code-review feedback, start with `ws review <comp> [cr#]`. It handles thread resolution, `--since <ref>` filtering, and attribution that the raw provider calls (and their `ws gh` / `ws glab` wrappers) don't. Drop to `ws gh` / `ws glab` only for something `ws review` genuinely can't express.

Subcommands that take a target (commit, push, cr, issue, review, log, diagnose, test, lint) also accept realm and hoard names, not just components.

**Adapter-routed verbs — consult `ws orient` first:** `ws test` / `ws lint` / `ws build`.

The adapter wiring per component lives in `realms/<active>/adapters/<comp>.yaml`. **Run `ws orient` to see what each component's adapter resolves to** — the output surfaces each row's executed command (`knarr → ws test [runs: python3 -m pytest --ignore=tests/features]`) so you can verify what `ws test` will actually run. When an adapter is wired, the hook redirects raw `pytest` / `ruff` / `gradle test` to the corresponding `ws` form. When no adapter exists, raw runs through with a one-time nudge.

---

## ws orient — the L1 discovery surface

Already MUST-run at session start (see above). Also run it mid-session when switching tasks, picking up a new component, or unsure what's available. Output is deterministic and frontmatter-only for skill bodies (cheap even with dozens of skills). Sections:

- **Subcommand survey** ("use when …" per ws verb)
- **Active realm** name + pointer at its `AGENTS.md`
- **Per-component adapter wiring** with the resolved command surfaced
- **Skill index** across workspace + active realm scopes

Per-command depth: `ws <cmd> --help`. The help system is the source of truth for flags and per-command behavior — skills and prose defer to it rather than restating.

A post-dispatch stderr footer fires after every `ws` subcommand to keep `ws orient` discoverable mid-session. Opt out with `WS_FOOTER_DISABLE=1` if you want quiet stderr.

---

## Companion plugin (recommended)

Several GDD plans and practice skills reference [Obra Superpowers](https://github.com/obra/superpowers) skills via the `superpowers:*` namespace: `superpowers:executing-plans`, `superpowers:subagent-driven-development`, `superpowers:brainstorming`, `superpowers:test-driven-development`, `superpowers:receiving-code-review`. Install Superpowers for the smoothest experience — the orientation skill checks at startup and surfaces a one-line nudge if not detected. The install command is agent-specific (it differs between Claude Code and Codex), so it lives in your agent's overrides file rather than here — Claude Code: [`CLAUDE.md`](CLAUDE.md).

Reference forms in skill bodies:

| Pattern | Example | How to use |
|---|---|---|
| Workspace skill path | `.agent/skills/gdd-orientation/SKILL.md` | Read with the Read tool. Do **not** invoke via the Skill tool. |
| Plugin skill identifier | `superpowers:executing-plans` | Invoke via the Skill tool (requires the plugin installed). |
| `@<name>` cross-reference | `@gdd-housekeeping`, `@gdd-workflow-audit` | Informational pointer to a workspace skill — read the referenced file, don't invoke as a tool. |

**Graceful degradation without Superpowers:** plan execution falls back to manual step-by-step, TDD becomes implicit, `receiving-code-review` is read as documentation. All workspace skills (under `.agent/skills/`) run without Superpowers.

---

## Operational Rules

1. **MUST run `ws orient` AND read the orientation skill** at session start, after compaction, or when dispatched fresh. Both are prerequisites — see Session Start.
2. **`ws orient`** when switching tasks or unsure what's available — it's the discovery surface.
3. **`ws <cmd>`** in preference to raw `git` / `gh` / `glab` / runners (see Reflex Contract).
4. **One command at a time.** Don't bundle with `;` `&&` `|`. The PreToolUse hook denies shell composition — use separate tool calls and native `ws` flags (`--compact`, `--limit N`, `--output <phrase>`) instead of pipes.
5. **No raw `git`/`gh`/`glab`** for the unconditional verbs above. Wrappers handle attribution, auth, remote selection — raw tools won't.
6. **No hard-wrapped prose.** Write each paragraph as a single line and let editors / renderers handle wrap. Code blocks, tables, lists, and YAML frontmatter are exempt.

---

## Deeper References

The orientation skill is the right starting point; these pointers are here so a human or fresh agent reading AGENTS.md knows where the long-form content lives.

- [`docs/gdd/index.md`](docs/gdd/index.md) — Guardian Driven Development overview.
- [`docs/ecosystem-architecture.md`](docs/ecosystem-architecture.md) — three-tier model, workspace structure, config merge.
- [`docs/ws-cli-guide.md`](docs/ws-cli-guide.md) — full `ws` CLI reference + how to add new subcommands.
- [`docs/workspace-setup.md`](docs/workspace-setup.md) — prerequisites, PATH setup, workspace shape (components/realms/hoards), agent permissions.
- [`docs/git-provider-setup.md`](docs/git-provider-setup.md) — auth, token scopes, `.env` setup.
- [`docs/code-style.md`](docs/code-style.md) — commenting + documentation conventions.
- [`docs/ide-setup.md`](docs/ide-setup.md) — VS Code, JetBrains, terminal editor setup.
- [`.claude/hooks/README.md`](.claude/hooks/README.md) — PreToolUse hook tiers, redirect/bypass mechanics.
- [`docs/plans/2026-04-24-realms-and-hoards-design.md`](docs/plans/2026-04-24-realms-and-hoards-design.md) — realms + hoards model.
- [`docs/plans/2026-04-25-component-templates-design.md`](docs/plans/2026-04-25-component-templates-design.md) — `ws component init` flavors.

Issue / CR / commit draft templates live in `templates/`; gitignored draft clearinghouses live in `.issues/` `.crs/` `.commits/`. The `ws clean` subcommand purges them when stale.
