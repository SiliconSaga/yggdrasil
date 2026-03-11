---
name: workflow-auditor
description: Use when you notice repeated manual workarounds (3+ instances), at session wrap-up, or when asked to check for workflow patterns
---

# Workflow Auditor

Detect repeated manual workarounds in a session and propose workspace utility
scripts or workflow improvements.

## When to Use

- **Self-trigger:** You notice 3+ instances of the same awkward pattern in a
  session (repeated `cd`, manual JSON formatting, same multi-step command
  sequence, retried commands with the same fix).
- **User-invoked:** User says "check for workflow patterns" or similar.
- **Session wrap-up:** When a session is ending, review the conversation for
  repeated patterns worth addressing.

## What to Analyze

Scan the current conversation for:

1. **Repeated `cd` or cwd workarounds** — switching directories manually,
   failed commands due to wrong cwd, `cd` + command sequences.
2. **Multi-step command sequences** — the same 2+ commands always run together
   as a logical unit.
3. **Manual formatting/transformation** — JSON reformatting, text extraction,
   output parsing done by hand.
4. **Error-recovery loops** — the same fix applied to the same error multiple
   times.
5. **Environment workarounds** — PATH exports, env var setup, tool version
   switches.
6. **Patterns across tool calls** — multiple tool invocations that achieve one
   logical operation.

## Output Format

For each detected pattern, report:

### Pattern: [short name]

- **Evidence:** List the 3+ instances (quote or summarize the commands/actions)
- **Proposed fix:** One of:
  - New `ws` subcommand (describe behavior)
  - New utility script (describe what it does)
  - CLAUDE.md instruction (draft the text)
  - Skill update (which skill, what change)
- **Effort:** trivial / small / medium
- **Recommendation:** implement now / file as issue / note for later

## Rules

- **Minimum evidence:** Do not propose a fix without at least 3 observed
  instances. Two might be coincidence; three is a pattern.
- **Propose, don't act:** Present findings to the user. Do not create scripts,
  modify CLAUDE.md, or file issues without approval.
- **Stay concrete:** Every proposal must reference specific commands or actions
  from the session. No speculative "we might need this someday."
- **Check existing tools first:** Before proposing a new script, verify that
  `ws` or an existing skill doesn't already handle it.

## Anti-Patterns to Watch For

These are especially high-value patterns to catch:

| Pattern | Likely Fix |
|---|---|
| `cd components/X && cmd` repeated | `ws exec X cmd` |
| Same git sequence across components | New `ws` subcommand |
| Manual JSON/YAML transformation | Utility script |
| Repeated PATH or env exports | CLAUDE.md instruction or ws-env |
| Same error fixed the same way 3+ times | CLAUDE.md note or pre-flight check |
