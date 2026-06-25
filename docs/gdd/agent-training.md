# Agent Training — Hooks, Discipline, and Why It's Not Expensive

A user-facing companion to the technical reference at [`.claude/hooks/README.md`](../../.claude/hooks/README.md) and [`permissions.md`](permissions.md). If you've just started a session and noticed the agent getting a stream of **scary red error messages** in its first few tool calls — this doc is for you. Some errors are working as intended; they're how the workspace teaches the agent where its rails are.

---

## The progressive-disclosure buffet (L0 / L1 / L2)

The workspace trains agents through three concentric layers, each loaded only when needed. The shape is "buffet, not banquet" — agents take what's relevant when it's relevant rather than swallowing everything up front.

| Layer | Surface | Purpose |
|---|---|---|
| **L0** | [`AGENTS.md`](../../AGENTS.md) — slim menu, always loaded | The reflex contract: which `ws` verbs to use instead of raw `git`/`gh`, the meta-rule for adapter-routed verbs, hard pointers at the deeper surfaces. ~100 lines. |
| **L1** | `ws orient` — run at session start | The deterministic discovery menu: subcommands with "use when …" docstrings, active realm, per-component adapter wiring (with the resolved command surfaced), and the skill index across workspace + realm scopes. |
| **L2** | `ws <cmd> --help` — on demand | Per-subcommand depth: flags, bodyfile shapes, environment variables. Source of truth for command behavior — skills defer to it rather than restating. |

**The reflex contract** at L0 names the unconditional verbs (`ws commit`, `ws push`, `ws cr`, `ws issue`, `ws clone`, `ws exec`) and the adapter-routed verbs (`ws test`, `ws lint`, `ws build`) that consult `ws orient` first. A fresh agent's instinct is to reach for raw `git commit` / `git push` / `gh pr create` — the contract redirects that reflex to the workspace wrappers, which handle attribution, auth, remote selection, and bodyfile-driven flows that raw tools don't.

### The per-command footer keeps L1 discoverable

Every successful `ws` subcommand prints a dim one-line nudge to stderr:

```text
↪ switching tasks? `ws orient` lists available tools.
```

Suppressed for `orient` itself, `--help` variants, and under bats (so test output stays clean). Opt out per-session with `WS_FOOTER_DISABLE=1`. The footer is the mid-session reminder that L1 exists — without it, agents tend to discover `ws orient` once at session start and forget the surface mid-task.

### The hook as a Claude-only backstop

The PreToolUse hook (`.claude/hooks/gdd-permission-hook.sh`) is Claude-specific — it's a Claude Code feature, not a portable agent contract. The deny-and-correct training loop only runs in Claude sessions. For Codex, Gemini CLI, Cursor, and other agents, the load-bearing layers are the portable ones: `AGENTS.md`'s reflex contract (read at session start), `ws orient`'s discovery menu, and the per-command footer (all `ws`-wrapped, all portable). Treat the hook as "Claude's training wheels" rather than the workspace's safety floor.

---

## Errors you may see

When a fresh session begins, the agent often reaches for shell patterns that aren't allowed here — `cmd | head`, `something > out`, `grep -E 'a|b'`, `cmd 2>&1`. Each one gets blocked by the workspace's PreToolUse hook with a corrective message:

```text
File-descriptor merges like `2>&1` and `1>&2` aren't needed —
the Bash tool already captures both stdout and stderr natively.
Remove the merge; both streams will still be visible in the tool
output.
```

That **looks** like an error your terminal would emit when something crashed. It isn't. It's the hook telling the agent: *don't do that — here's why and what to do instead*. The agent reads the message on its next turn and retries with a different approach. Two or three denies in a row is normal at the start of a session. After that the agent has the local conventions cached and the noise should drop off.

Two things to know:

1. **Nothing was harmed.** A deny means the command never ran. No files were touched, no side effects occurred. The hook is a pre-execution check.
2. **The agent is supposed to see those messages.** They're the training loop. Suppressing them — by silencing the hook or relaxing the rules — removes the corrective signal that makes the agent better at working here.

If you're new and the deny stream worries you, watch what happens on the next agent turn: it'll typically rephrase the command and succeed.

---

## What the hook does

The PreToolUse hook at `.claude/hooks/gdd-permission-hook.sh` runs before every Bash tool call. It rejects shell composition (`&&`, `||`, `;`, `|`, backticks, `$(...)`, `>`, `<`, FD merges like `2>&1`) with command-specific corrective messages. It denies raw `git commit` / `git push` / `gh pr create` (Tier 2 redirect) with a message pointing at the matching `ws` wrapper, with a session-scoped `ws hook-bypass` escape hatch. It forces a permission prompt (ask-tier) for destructive commands like `rm -rf` and `git reset --hard`, even in `acceptEdits` mode. It allows commands matching `.claude/settings.json` patterns or the `[allow-extras]` section of the per-machine `hook-rules.local` file. Everything else passes through to the normal Claude Code prompt. The audit log at `~/.claude/hook-audit.log` records every ALLOW / ASK / DENY decision (passthroughs are intentionally not logged — they'd balloon the log under normal use).

For the deny taxonomy, allow-pattern shape, opt-out, and the malformed-JSON / Windows-path edge cases, read the [hook README](../../.claude/hooks/README.md). The rest of this doc is about *why* the hook exists and what it costs.

---

## The ask-tier — destructive commands always prompt

Some commands — `rm -rf`, `git reset --hard`, `git clean -f`, and similar — are on the hook's ask-list. When the agent tries to run one of these, the hook doesn't deny it; instead it forces a permission prompt that surfaces to you regardless of what permission mode the session is in. That includes `acceptEdits`, which would otherwise auto-approve Bash mutations on workspace paths without showing you anything.

This is deliberate: the hook is acting as a confirmation checkpoint, not a gatekeeper. The pattern is: agent proposes → human reviews → human approves → command runs. If you approve, the command executes normally. If you decline, the agent is told to find another approach.

What you'll see when an ask-tier command fires:

- A permission prompt in the Claude Code UI with the exact command
- No red deny message — the prompt is the whole interaction
- The audit log records the hook's decision as `ASK` — the hook fires once when the command is intercepted, not again when you respond to the prompt.

The ask-list is defined in `.claude/hooks/hook-rules` (committed baseline) and can be extended — never shortened — in `hook-rules.local`. If you find yourself declining the same destructive command repeatedly, that's a signal to revisit whether the agent should be reaching for that command at all.

---

## What happens when you reach for `git commit` / `git push` / `gh pr create`

These three raw commands deny at Tier 2 with a message pointing at the workspace's `ws` wrappers. The wrappers handle work the raw commands don't:

- `ws commit` — Co-Authored-By trailer, bodyfile-driven staging
- `ws push` — fork-remote selection from `identity.forkRemote`, sets upstream
- `ws cr` — bodyfile-driven PR body, identity substitutions, right token + remote

The deny is corrective, not punitive — when you see it, retry through the named `ws` subcommand. AGENTS.md's `ws`-first reflex check table maps every raw command in this category to its wrapper.

**When you genuinely need the raw command** (e.g., `git commit --amend` and `ws commit` doesn't support amend yet): run `ws hook-bypass <slug> --reason "<why>"`. The human gets a permission prompt; on approval, a session-scoped marker is written and the next matching raw command runs through. The bypass is per-slug — bypassing `git-commit` doesn't extend to `gh-pr-create`.

**Don't loop on the deny.** If your first instinct hits a Tier 2 deny twice in the same session, that's the moment to either (a) figure out the `ws` form, (b) request a bypass with a clear `--reason`, or (c) ask the human directly. Three identical denies is not the right shape.

---

## "One action per call" — the operational principle

The hook's deny list isn't a random collection of forbidden operators. It enforces a single rule: **each Bash tool call should do exactly one thing the harness can audit, log, and (if needed) prompt on**.

Compound forms hide work from the human and the audit log:

| Compound form | What gets hidden |
|---|---|
| `cmd1 && cmd2` | `cmd2` runs only if `cmd1` succeeds — but both are inside a single tool_use block, so the user-prompt review (and the audit log) sees one approval covering two intents. |
| `cmd \| head 20` | The `head` is fine on its own, but it discards information the agent can't recover without re-running. Native `--limit` flags make the limit explicit. |
| `cmd > out` | The destination is a string — `out` could be `/tmp/foo`, `~/.bashrc`, or `/etc/something`. Static analysis can't tell. |
| `cmd $(date)` | The substituted value is dynamic. The pattern the harness sees doesn't match the command that actually runs. |
| `cmd 2>&1` | Adds nothing in this environment — both streams are captured already — but trains shell-jargon habits that the next reader has to decode. |

Forcing a separate tool call for each step gives the harness one auditable verb at a time. The reviewer (human or bot) reading a session transcript later doesn't need to mentally parse a shell pipeline to know what happened.

---

## Why this isn't more expensive

The first time someone sees the hook deny a `cmd | head 20` and nudge the agent toward two separate calls (`cmd --output snap` then `ws output read snap --limit 20`, say), the natural worry is: *"We just doubled the API calls — that has to cost more."*

It does not double API calls. Here's the actual model:

**One assistant turn = one API call to Claude.** That single response can emit multiple `tool_use` blocks. The harness executes each one, collects results, then sends them all back as `tool_result` blocks in a single follow-up. So:

- Pipe form `cmd | head 20`: 1 tool call → 1 response cycle → agent sees 20 lines.
- Split form `cmd --output snap` then `read snap --limit 20`: 2 tool calls inside the *same* assistant turn → still 1 API call to the model → agent sees 20 lines.

Where the costs actually diverge:

| Cost dimension | Pipe form | Split form |
|---|---|---|
| API calls to Claude | 1 | 1 |
| Output tokens (model emits 2 tool_use blocks vs 1) | lower | slightly higher |
| `tool_result` tokens fed back | the 20 lines | call-1 metadata + 20 lines |
| Wall-clock latency | one local round-trip | two local round-trips |
| Intermediate state on disk | none | a file in `.outputs/` |

The interesting failure mode in the split form is if the agent reads the **whole** intermediate file back instead of using `--limit` or `Read` with an offset+limit. Then the full payload materializes in the context window and you've paid for it in tokens. That's exactly why the deny messages push toward native `--limit` / `--output` flags on `ws` subcommands rather than "redirect everything to a file and re-read it." The discipline isn't "split calls into pieces"; it's "let each step explicitly bound what it produces."

So the hook is roughly free in API-cost terms when the agent follows its guidance. Where it pays off is in:

- **Auditability** — one verb per call, one approval per verb.
- **Context hygiene** — intermediate full outputs never enter the conversation unless someone asks them to.
- **Training stability** — the agent learns the workspace's conventions instead of carrying generic shell habits forward.

---

## Native flags over shell pipes — the `ws` design pattern

The `ws` subcommands grew several flags specifically so the agent doesn't need shell composition to get common results:

| Old shell form | Native flag | Why the flag |
|---|---|---|
| `ws review yggdrasil 42 \| head 30` | `ws review yggdrasil 42 --limit 30` | Limit applies to the producer, not a post-hoc trim. Cheaper and explicit. |
| `ws review yggdrasil 42 > snap.txt` | `ws review yggdrasil 42 --output snap` | Destination is constrained to `.outputs/<ts>-<phrase>.txt` — bounded blast radius, covered by `ws clean`. |
| `ws review yggdrasil 42 \| grep error` | `Grep` tool if available (or `grep` command) on the saved output (or `ws review --reviewer`) | Filtering belongs in the right tool; piping is a workaround. |
| `gh pr list \| head 5` | `gh pr list --limit 5` | Most `gh` subcommands already have `--limit`. |

When you find yourself reaching for a shell pipe inside a `ws` command and the hook denies it, that's usually a signal that a native flag belongs there — open an issue or note it in the Thalamus so the auditor skill can promote the friction.

---

## What to do when a legit command gets denied

The hook is conservative on purpose, but it's not always right. When a command you genuinely want to run gets denied, you have three escalating options:

1. **Use the substitute the deny message suggests.** Most denies point at a specific better path (`Grep` tool, `--output` flag, `Read` with offset+limit). 90% of the time the substitute works and the friction goes away.
2. **Add the command to `hook-rules.local`.** If the command is one you trust on this machine but doesn't belong in the committed `settings.json`, list it as a glob pattern in the `[allow-extras]` section of your per-machine `hook-rules.local`. A starter template ships at `.claude/hooks/hook-rules.local.example` — copy it to activate:

   ```bash
   cp .claude/hooks/hook-rules.local.example .claude/hooks/hook-rules.local
   ```

   The live `hook-rules.local` is gitignored and per-machine. Uncomment the entries you want, or add your own under `[allow-extras]` — each line is a bash glob matched against the full command string. See the [hook README](../../.claude/hooks/README.md) § "Rules configuration" for the full format spec.
3. **Disable the hook.** Set `WS_HOOK_DISABLE=1` in your shell or `.env`. Use sparingly — you give up the audit log and the corrective feedback loop.

The right escalation level depends on whether the deny is a single-session annoyance (option 1), a recurring pattern (option 2), or a fundamental disagreement with the hook's rules (option 3 — and probably file an issue too).

---

## Reviewing the audit log periodically

`~/.claude/hook-audit.log` is the receipt for every allow / deny. Worth a skim during housekeeping (the `gdd-housekeeping` skill has a dedicated step for this):

- Recurring DENY entries for the same compound form → either the agent is reflexively reaching for shell composition (write a Thalamus note) or there's a native flag missing on a `ws` subcommand (file an issue).
- Recurring ALLOW entries from the same extras-file pattern → that pattern may have earned its place; consider promoting it to the project `.claude/settings.json` so collaborators benefit. Be mindful that such patterns should be low risk.
- No DENY entries since last review → either the agent has internalized the conventions or sessions have been light.

The hook doesn't rotate the log. Use `truncate -s 0 ~/.claude/hook-audit.log` to reset it after a review.

The audit log captures the hook's *decisions* — it doesn't see commands that went to passthrough and then prompted you through the harness's own permission flow. If you find yourself clicking "yes, run it" on the same command session after session, that's the cue to add it to `hook-rules.local` under `[allow-extras]` (or to project `.claude/settings.json` for ones collaborators would also want auto-approved). The housekeeping skill prompts the agent to surface candidates during audit cycles — you don't have to track the count yourself.

---

## Related reading

- [Hook README](../../.claude/hooks/README.md) — the technical spec: tier-by-tier decision rules, `hook-rules` config format, registration, troubleshooting.
- [Permissions reference](permissions.md) — `.claude/settings.json` patterns and the two-layer defense model that allow rules rely on.
- [GDD trust & safety](trust-and-safety.md) — where the hook fits in the broader trust hierarchy.
- [`gdd-permissions` skill](../../.agent/skills/gdd-permissions/SKILL.md) — operational guide for adding or narrowing allow patterns.
