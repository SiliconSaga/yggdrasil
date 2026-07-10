# Focused Codex Redirect Hook Design

Status: approved design

## Context

Yggdrasil asks agents to use `ws` wrappers for operations where the wrapper adds behavior that raw provider commands do not: commit attribution and bodyfile staging, fork-remote selection, token injection, provider selection, and review-request metadata. Claude currently reinforces that contract through the `[redirect-commands]` tier in `.claude/hooks/hook-rules`. Codex reads the same root instructions but only has a focused Kubernetes hook, so a training-data reflex can still reach raw `git commit`, `git push`, `gh pr create`, or `git mv`.

Raw `git push` is the highest-cost example. It bypasses `ws push` token injection and destination selection, which can route authentication through an IDE askpass or the operating-system credential helper and produce avoidable Keychain prompts. The desired response is not a broader Codex allowlist or a port of the Claude permission monolith. It is one focused deny-or-defer hook for the existing redirect policy.

## Goals

- Give Codex the same corrective redirect messages for the committed `[redirect-commands]` rules.
- Keep the hook independent from Claude's allowlist, ask tier, shell-composition policy, adapter redirects, scratch paths, and PermissionRequest behavior.
- Preserve the existing `ws hook-bypass <slug>` escape hatch without auto-allowing the bypassed command in Codex.
- Defer unrelated commands to Codex's normal sandbox, approval, and network handling.
- Keep rule additions data-driven: adding a valid `[redirect-commands]` row should affect both Claude and Codex without editing either hook.
- Use the feature as a second data point for deciding how cross-agent hook portability should evolve.

## Non-Goals

- Port the Claude hook wholesale.
- Reproduce `.claude/settings.json` allow behavior in Codex.
- Translate Claude's human-required ask tier into Codex prompt rules.
- Handle `[adapter-redirect-commands]` or `[scoped-redirect-commands]`; those have different context and enforcement semantics.
- Expand the current redirect rule set or invent a general Git command parser.
- Treat redirects as a security boundary. They are a training and workflow-correctness layer; provider authorization remains authoritative.

## Immediate Design

### Registration and isolation

Add `.codex/hooks/gdd-redirect-hook.sh` as a second command hook under the existing `PreToolUse` Bash matcher in `.codex/hooks.json`. The Kubernetes and redirect hooks remain separate executables:

- The Kubernetes hook evaluates Kubernetes candidates and defers unrelated commands.
- The redirect hook evaluates only `[redirect-commands]` candidates and defers unrelated commands.

The feature sets do not overlap today. A raw Git or GitHub provider command is invisible to the Kubernetes hook; a Kubernetes command is invisible to the redirect hook. No dispatcher or cross-feature precedence layer is needed.

### Input contract

The redirect hook reads one JSON payload from stdin and acts only when all of the following are true:

- `hook_event_name` is `PreToolUse`.
- `tool_name` is `Bash`.
- `tool_input.command` is non-empty.
- `WS_HOOK_DISABLE` is not `1`.

Malformed JSON, unavailable `jq`, non-Bash tools, unrelated events, and empty commands return no decision.

### Rule discovery

Resolve the project root from the hook's own location, following the pattern established by the focused Kubernetes hook. Read:

1. `.claude/hooks/hook-rules` as the committed baseline.
2. `.claude/hooks/hook-rules.local`, when present, as an additive per-machine layer.

Although the file currently lives under `.claude/`, `[redirect-commands]` is platform-neutral policy data. Moving the entire rules file is deliberately deferred because most other sections remain Claude-specific. The Codex README and Claude hook README will state that this one section is shared.

### Focused parser

Parse only content inside `[redirect-commands]`. Ignore all other known or unknown sections rather than attempting to validate the whole rules file. Each redirect row has the existing shape:

```text
<slug> | <bash-glob pattern> | <suggestion text>
```

Parser behavior:

- Ignore blank lines and comments.
- Split on the first two ` | ` separators so suggestion text may contain additional pipes.
- Trim the slug and pattern.
- Require slug shape `^[a-z][a-z0-9-]*$`.
- Require non-empty pattern and suggestion.
- Skip malformed rows, write one warning to `~/.codex/hook-audit.log`, and continue parsing later rows.

This small parser intentionally duplicates the format boundary instead of extracting code from the stable Claude monolith. Cross-harness parity tests, not shared implementation, guard the format in this first iteration.

### Matching

Normalize the command and configured pattern with the existing wrapper-path rules:

- `bash ./scripts/<command>` becomes `<command>`.
- `bash scripts/<command>` becomes `<command>`.
- `./scripts/<command>` becomes `<command>`.
- `scripts/<command>` becomes `<command>`.

Then apply Bash glob matching exactly as the Claude redirect tier does. The hook does not broaden patterns to infer Git subcommands behind arbitrary `env`, `git -C`, `git -c`, aliases, or shell wrappers. Those can be added as explicit policy rows if real usage demonstrates a need.

### Deny response

When a rule matches and no bypass is active, return Codex-compatible `PreToolUse` deny JSON using the rule's suggestion as `permissionDecisionReason`. Record a concise deny entry in `~/.codex/hook-audit.log` with the slug and normalized command.

The hook never emits an allow decision. A non-match simply exits successfully with no JSON output so Codex retains its normal policy path.

### Session-scoped bypass

For a matching slug, inspect:

```text
<project-root>/.tmp/hook-bypass/<slug>.bypass
```

Honor the bypass only when the marker's `session_id` exactly matches the hook payload's non-empty session ID. A matching bypass writes a `BYPASS-REDIRECT` audit entry and exits with no decision. This differs intentionally from Claude's explicit allow response: in Codex, bypassing the training redirect should still leave sandbox, network, and approval review intact.

Missing, malformed, stale, or cross-session markers do not weaken the redirect; the command remains denied.

### Failure behavior

The bridge fails open only for infrastructure failures where it cannot classify the request: malformed payload, missing `jq`, missing rules file, or unreadable configuration. It audits the missing-rule or parse condition when possible. Once a valid rule matches, unexpected bypass-reading failures fail closed for that redirect and return the normal corrective deny.

## Tests

Add `tests/hook/codex-redirect-hook.bats` with focused cases for:

- Unrelated Bash and non-Bash calls defer with no output.
- Malformed payload and `WS_HOOK_DISABLE=1` defer.
- Every committed redirect row denies a representative command and returns its configured suggestion.
- Command and pattern normalization match Claude's current behavior.
- Suggestion text containing additional pipes is preserved.
- Malformed rows are skipped and audited without hiding later valid rows.
- A valid local redirect is additive.
- Matching-session bypass defers and audits; missing, malformed, stale, and mismatched markers still deny.
- The hook never emits an allow decision.
- `.codex/hooks.json` registers both focused hooks under Bash `PreToolUse`.

Update the existing Codex Kubernetes registration assertion so it verifies coexistence rather than requiring exactly one command hook. Run both focused hook suites and the full Yggdrasil Bats suite.

## Documentation

Update:

- `.codex/README.md` to describe the two focused bridges, trust review, audit output, and troubleshooting.
- `.claude/hooks/README.md` to identify `[redirect-commands]` as shared policy data while the remaining monolith stays Claude-specific.
- `docs/gdd/agent-training.md`, `docs/gdd/permissions.md`, and `docs/gdd/features.md` where they currently say Codex only has the Kubernetes bridge.

Public documentation remains organization-agnostic and continues to describe redirects as workflow training, not cybersecurity enforcement.

## Incremental Cross-Agent Architecture

The redirect hook should not predetermine a single universal hook engine. Cross-agent support can evolve feature by feature, using the smallest sharing boundary earned by each feature.

### Pattern A: fully split agent-specific scripts

Claude and Codex each implement a focused feature from shared declarative policy or a shared behavioral contract. This is the starting pattern for redirects.

Use it when:

- The feature is small.
- Harness output and lifecycle semantics differ materially.
- Sharing implementation would force conditionals for each agent.
- One implementation is already stable and changing it would add regression risk.

Trade-off: parser or matching fixes may need to be applied twice. Parity tests and a narrow data format keep that cost visible.

### Pattern B: shared feature evaluator with thin agent forwarders

Extract one platform-neutral evaluator for a single feature, then keep tiny Claude/Codex forwarders responsible for payload decoding and decision encoding. The Kubernetes guard already approximates this pattern: `scripts/ws-k8s-guard.sh` owns the verdict while each harness bridge maps it to local behavior.

Use it when:

- The same classification bug or parser change has been fixed in multiple harnesses.
- A third harness needs the feature.
- The feature's inputs and verdicts can be expressed without harness-specific concepts.
- Shared tests can exercise the evaluator directly.

For redirects, a future evaluator might accept `(command, session_id, project_root)` and return `NO_MATCH`, `REDIRECT:<slug>:<suggestion>`, or `BYPASS:<slug>`. Agent-specific scripts would remain responsible for audit locations and hook JSON.

### Pattern C: one generic policy engine

A universal engine would parse all policy sections, establish cross-feature precedence, manage bypasses and audit events, and return platform-neutral verdicts for thin harness adapters.

Do not build it merely to reduce file count. Consider it only when several focused features demonstrate actual shared needs such as:

- Ordering conflicts between independent hooks.
- Repeated payload normalization and audit code causing defects.
- Three or more harnesses consuming the same policy sections.
- A stable common verdict model spanning redirect, ask, allow, and scoped guard behavior.
- Hook startup cost or trust review becoming meaningfully burdensome.

The main risk is flattening different safety semantics into a lowest-common-denominator abstraction. Claude's force-ask behavior, Codex's deny-or-defer bridge, and provider/sandbox approvals are not interchangeable. A generic engine is useful only if it preserves those distinctions rather than hiding them.

### Iteration rule

Default to focused hooks. After each new cross-agent feature, review whether implementation duplication is still cheaper than abstraction. Extract a shared feature evaluator when evidence supports it; introduce a dispatcher or engine only when independent hooks need explicit ordering or common lifecycle management.

This keeps portability incremental: each feature delivers value and supplies another concrete data point for the eventual architecture.

## Decision Summary

- Build a second focused Codex hook for `[redirect-commands]`.
- Read the existing committed and local rule files directly.
- Preserve exact current matching semantics and suggestions.
- Honor session-scoped bypasses by deferring, never auto-allowing.
- Leave the Claude monolith unchanged except for documentation and parity expectations.
- Treat feature-by-feature bridges as the default architecture; earn shared evaluators and any wider engine through repeated evidence.
