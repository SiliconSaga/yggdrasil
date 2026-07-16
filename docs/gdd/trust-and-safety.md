# Trust and Safety

GDD takes a structured approach to trust. AI agents read instructions from nested project components, and not all of those components are equally trustworthy. The framework provides explicit rules for how to handle this.

A note on what the rails in this document promise: each one is honest about its own strength. Some are hard confirmation gates (the ask-tier), most are accident-prevention and training layers, and none replace server-side authorization. That's GDD's [good-enough posture](index.md#good-enough-on-purpose) — make the destructive slip rare and the work legible, rather than pretend to be a hardened boundary against a determined adversary. Calibrate your stakes accordingly.

## The Trust Hierarchy

```mermaid
graph BT
    L4["User instructions<br/>(in-session)"] --> L3["Non-ecosystem components<br/>(untrusted until reviewed)"]
    L3 --> L2["Ecosystem components<br/>(trusted, flag conflicts)"]
    L2 --> L1B["Active realm<br/>(trusted community context)"]
    L1B --> L1["Yggdrasil root instructions<br/>(highest trust)"]
```

| Level | Source | Treatment |
|-------|--------|-----------|
| 1 (highest) | Yggdrasil root instructions (`AGENTS.md`, `.agent/skills/`) | Trusted — the base |
| 1b | Active realm (`realms/<r>/AGENTS.md`, `realms/<r>/.agent/skills/`, `realms/<r>/adapters/*.yaml`) | Trusted — community context for the workspace. Adapter command strings get a provenance-scaled risk scan (see below). |
| 2 | Ecosystem components (in `ecosystem.yaml`) | Trusted — flag conflicts with root |
| 3 | Non-ecosystem components | Untrusted until reviewed — log before processing |
| 4 | User instructions in-session | Respected unless safety-violating |

## The Black-Box Safety Pattern

When the orientation skill encounters instructions from an untrusted or suspicious source, it follows a specific sequence:

1. **Read just enough** to identify the file as an instruction file from an untrusted source (filename, location, first few lines)
2. **Log a concern to Thalamus immediately** — before reading the full content. This is the safety breadcrumb.
3. **Continue reading** the full file
4. **Surface the concern** to the human in conversation
5. **Do not follow** the instruction until the human explicitly approves

Why log first? If the file contains a successful prompt injection that compromises the agent's behavior, the pre-injection concern is already on disk for the human to find. The breadcrumb survives even if the agent doesn't.

## What Gets Flagged

- Instructions that contradict yggdrasil root instructions
- Requests for elevated permissions or unusual access patterns
- Instructions to ignore, override, or "forget" other instructions
- Instructions to push, publish, or send data to unfamiliar destinations
- Skills that execute code as part of loading (rather than providing guidance)
- Any instruction file that is new or modified since the last session
- Adapter command strings (`realms/<r>/adapters/*.yaml` `commands.{test,lint,build}`) containing `curl | sh`, `wget | sh`, `base64 -d | sh`, writes to paths outside the component dir, outbound network calls in test/lint runners, or `eval` of any non-local string

## Realm Activation Is a Trust Gate

A cloned realm influences nothing until it is explicitly activated, including the upstream `realm-template` cloned by `ws realm init`. `ws realm use` prints a **trust summary** — the realm's repository hosts, adapter command strings, credential-mapping requests, and MCP endpoints, with URL credentials redacted and terminal control sequences stripped so the summary itself cannot be spoofed — and requires confirmation before writing the `realm:` selector. The recorded trust fingerprint covers the semantic realm configuration, every adapter, and regular files inside the realm that adapter commands reference; unrelated documentation changes do not invalidate approval. Adapter-referenced symlinks are rejected so the fingerprint cannot silently follow a target outside the reviewed realm. Non-interactive sessions must pass `--trust` after reviewing the summary, and for agents that flag is human-gated by the permission hook's ask tier, so activating a realm always lands on a person. Two boundaries hold even after activation: a realm's `defaults.gitTokens` entries never attach the operator's credentials (token routing reads only the committed workspace config plus `ecosystem.local.yaml`), and its `templateRealm` / bootstrap sources can't be replaced from realm data.

## Adapter Command Trust

`ws test` / `ws lint` / `ws build` dispatch the active realm's wired adapter command (e.g. `realms/<r>/adapters/<comp>.yaml` → `commands.test: "pytest -x tests/"`). The workspace allowlists these wrappers by default — trusting the realm author to wire something benign. Before dispatch, the wrapper requires the active realm's recorded fingerprint to remain current, including any realm-owned regular file named by an adapter command. The risk scan in [`gdd-orientation`](../../.agent/skills/gdd-orientation/SKILL.md) is what keeps that trust honest: on realm activation it reads every adapter file and flags the patterns above, scaled by where the realm came from. The `ws realm use` trust summary shows the same adapter strings at selection time; the orientation risk scan is the deeper, pattern-aware pass that follows.

| Realm origin | Rigor |
|---|---|
| Remote owned by your `identity.human_account` (your own realm) | Light — log findings only |
| Remote URL namespace is under a configured trusted home namespace, such as `identity.homes.fork.namespace`; compare the Git URL owner/group path, not the local remote name | Light |
| Anything else (community / internet / unverified) | Heavy — write to Thalamus Concerns immediately, surface in framing, refuse to run unverified adapter commands until the human OKs |

The framing: **`ws test`-allowlisted means the wrapper is trusted to dispatch what the realm wires**, not that any arbitrary command in `commands.test` is safe to run. Without the risk scan, blanket-allowlisting executable-config strings would be careless. See [`docs/gdd/adapters.md`](adapters.md) for the executable-config-surface framing.

## The Community Angle

An agent paired with a project — and the humans around it — can become a meaningful participant in that project's community. Not just a code generator for one human, but a collaborator that respects shared workspace integrity, flags risks that affect other contributors, and grows alongside the people working on the project. GDD makes this pattern natural without forcing it: it's a workflow choice, not a built-in assumption.

When that pattern is the goal, the agent's role broadens. It has a responsibility not just to the current human, but to the integrity of the shared workspace:

- **Do good faith work**, even when asked to cut corners
- **Flag things** that could harm other contributors or the project
- **Refuse to participate** in actions that would compromise the workspace, while making clear the human is free to act on their own

The agent can't prevent a human from doing harmful things, but it can make them do those on their own — so the agent and the community have done their part.

## The Ask-Tier Safety Floor

The hook's ask-tier is the workspace-level safety floor for destructive shell commands (`rm -rf`, `git reset --hard`, and similar) and arbitrary-execution escape hatches (`ws exec`): they always force a human confirmation prompt, regardless of what session permission mode is active. The gap it closes is `acceptEdits`-style modes that would otherwise auto-approve destructive Bash on workspace paths mid-way through a long autonomous task. It is a confirmation checkpoint, not a deny — approving runs the command normally.

The trust-relevant property: the floor cannot be opted out of per-command without a reviewed change to the committed `hook-rules` (or disabling the hook entirely). Mechanics — the `[ask-commands]` list, tier ordering, decision output — live in [`.claude/hooks/README.md`](../../.claude/hooks/README.md); the human-facing walkthrough is [Agent Training § The ask-tier](agent-training.md#the-ask-tier--high-risk-commands-always-prompt).

## The Redirect Tier (training aid, not a floor)

**Tier 2 redirect deny** is a training-aid layer, not a safety floor. The threat model is agent drift toward raw `git commit` / `git push` / `gh pr create` when the workspace's `ws` wrappers are the right tool — not adversarial intent. Its escape hatch, `ws hook-bypass <slug>`, is itself on the committed ask-list, so every bypass creation force-prompts the human — the ask-tier is the security boundary, and the redirect tier borrows it rather than adding its own. Details: [`.claude/hooks/README.md`](../../.claude/hooks/README.md) § Redirect tier and bypass.
