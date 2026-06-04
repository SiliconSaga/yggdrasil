# Skills Reference

The yggdrasil workspace ships a set of **skills** — markdown files
under `.agent/skills/<name>/SKILL.md` that capture how the agent
should approach specific situations. Skills are discovered during
GDD orientation and read as plain markdown; they are *not* invoked
through plugin tools. See the [Self-Improving Loop](self-improving-loop.md)
for how the catalog evolves over time.

This page is the catalog: what ships, grouped by purpose. For
day-to-day use, the orchestrator skill (`gdd`) decides which other
skills apply at any moment based on the active mode, role, and
context.

---

## Modes — *how* to work

Modes set the ceremony level for a session. Most sessions sit in
exactly one mode; the active mode lives in the per-machine thalamus
frontmatter.

| Skill | Use when |
|---|---|
| **gdd-zen** | Deep focus on a single topic with full ceremony. Defers distractions until natural completion points. |
| **gdd-flow** | Productive drift across several topics with responsive collaboration. Often the natural default. |
| **gdd-quick** | Minimal-ceremony short sessions (≈15 minutes). Suggests appropriately small tasks. |
| **gdd-mentoring** | Agent explains decisions and teaches practices in context. For unfamiliar areas or learning new tools. |

See [Roles and Modes](roles-and-modes.md) for the full mental model.

---

## Roles — *what kind* of work

Roles scope the agent to a specific kind of work. A session has at most one role active. Today only **Scribe** has a dedicated skill file.

| Skill | Use when |
|---|---|
| **scribe** | Obsidian vault conventions — PARA, frontmatter, daily notes, wikilinks, inbox capture, daily review, weekly synthesis. |

---

## Lifecycle and orchestration

Skills that handle session-level coordination — start, end, cross-cutting work.

| Skill | Use when |
|---|---|
| **gdd** | The top-level orchestrator. Detects active mode/role and delegates to the right skills. |
| **gdd-orientation** | Session start, or when new components are discovered. Reads thalamus, verifies trust, sets mode/role. |
| **gdd-housekeeping** | Triage thalamus content — review observations and concerns, promote to issues/skills, prune resolved items. |
| **gdd-review-triage** | After pushing, when CR review comments arrive (CodeRabbit, Copilot, others). Dedupes and triages. |
| **multi-repo-orchestration** | A session touches more than one repo; deciding work-now vs defer. |
| **topic-branch-workflow** | About to commit and push; deciding direct-to-main vs topic branch. |

---

## Practice skills

Skills that capture *how* to do specific kinds of technical work.

| Skill | Use when |
|---|---|
| **bdd** | Writing Gherkin scenarios, planning features, placing `.feature` files. |
| **bdd-pytest** | Pytest-bdd runner specifics — step definitions, execution, Cucumber JSON output. |
| **kuttl-testing** | Writing or debugging kuttl e2e tests for Kubernetes (Crossplane claims, operator-managed resources, secret-dependent checks). |
| **gdd-doc-writing** | Writing or editing any yggdrasil-ecosystem documentation, including Mermaid diagrams. |

---

## Workspace operations

Skills tied to specific workspace operations.

| Skill | Use when |
|---|---|
| **creating-github-issues** | Filing a deferred task or capturing work a fresh agent should be able to complete in a single repo. |
| **permissions-management** | Adding/editing permission patterns, considering "don't ask again" offers, reviewing `.claude/settings.json` changes. |
| **mcp-usage** | Setup offers, auth, tool-calling conventions for [MCP servers](../mcp-setup.md). |
| **workflow-auditor** | At session wrap-up, after noticing 3+ instances of a manual workaround. |

---

## Where skills live

```text
.agent/skills/<name>/SKILL.md
```

Each skill has a frontmatter block (name, description) and the
markdown body. Some skills include subdirectories with reference
material (templates, examples, sub-skills).

To read a skill: open the file. To author a new skill or change an
existing one: edit the file. Skills are plain documentation —
there's no "load skill" tool to invoke. The orchestrator and
orientation skills walk this directory at session start and decide
what's relevant to surface.

---

## See also

- [Roles and Modes](roles-and-modes.md) — the model the mode and
  role skills implement.
- [Self-Improving Loop](self-improving-loop.md) — how observations
  in the thalamus become new or revised skills over time.
- [`AGENTS.md`](https://github.com/SiliconSaga/yggdrasil/blob/main/AGENTS.md)
  — the workspace-root pointer that names the skills agents read at
  orientation.
