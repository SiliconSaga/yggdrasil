# Codex Kubernetes hook and cross-harness policy design

**Date:** 2026-06-29

**Status:** Awaiting written-spec review

## Goal

Add one focused Codex compatibility slice: a project-local Codex `PreToolUse` hook that preserves the guarded-Kubernetes mentoring workflow when an agent reaches for raw `kubectl`. The hook must remain small, reuse the existing platform-neutral Kubernetes evaluator, avoid importing Claude-specific permission assumptions, and establish a practical direction for converting the remaining Claude hook features later.

## Constraints

- Keep `.agent/skills/gdd-k8s/SKILL.md`, `scripts/ws-k8s.sh`, `scripts/ws-k8s-guard.sh`, and the session files under `.tmp/gdd-agent-sessions/` as the source of truth for scope semantics.
- Do not make `.claude/hooks/gdd-permission-hook.sh` the Codex hook. Its Claude settings allowlist and event-specific behavior are too broad to inherit safely.
- Do not introduce compatibility shims for older Codex releases. Project-local hooks are a current Codex capability; unsupported clients can continue relying on `AGENTS.md` and the guarded `ws k8s` wrapper.
- Treat the scope guard as accident prevention and mentoring support, not as Kubernetes authorization. Server-side RBAC remains authoritative.
- Keep the CR focused on Kubernetes interception and the cross-harness conversion design. A complete platform-neutral policy engine is follow-up work.

## Current Codex capabilities

Current Codex supports trusted project-local hooks from `.codex/hooks.json` or `.codex/config.toml`, including `PreToolUse` and `PermissionRequest`. Hooks receive tool-call context and can allow, deny, or defer an invocation. Project hooks are reviewed by hash and remain inactive until the user trusts them through `/hooks`.

Codex also supports project-local Starlark `.rules`, but rules govern requests to execute outside the sandbox. They are useful for static argument-prefix decisions and unsuitable as the primary Kubernetes guard because they cannot read the active GDD session scope or classify a kubectl operation using `scripts/ws-k8s-guard.sh`.

## Focused architecture

### Registration

Add `.codex/hooks.json` with one `PreToolUse` matcher for `Bash`. Its command resolves the repository root and invokes `.codex/hooks/gdd-k8s-hook.sh`. No `PermissionRequest` hook is needed for this slice because the Kubernetes policy must inspect every relevant Bash call before sandbox or approval routing.

Codex may begin a session below the repository root, so registration must not assume the session working directory is the root. The hook command follows Codex's documented repository-root resolution pattern.

### Adapter responsibilities

`.codex/hooks/gdd-k8s-hook.sh` is a thin Codex adapter. It will:

1. Read the Codex hook JSON payload from stdin and extract the hook event, tool name, command, working directory, and session ID.
2. Pass through when the event is not `PreToolUse`, the tool is not `Bash`, required local files are unavailable, no Kubernetes scope is active for the session, or the command is unrelated to Kubernetes.
3. Load the active scope from the exact `.tmp/gdd-agent-sessions/<session-id>.env` file rather than aggregating scopes from other sessions.
4. Source `scripts/ws-k8s-guard.sh` and use `k8s_guard_evaluate` and `k8s_render_block` for command classification and corrective text.
5. Emit Codex-native allow or deny output and write a compact audit entry under the Codex home.

The adapter does not parse Kubernetes verbs itself. Policy classification stays in `scripts/ws-k8s-guard.sh`.

### Decisions

When a scope is active, the adapter applies these decisions:

| Invocation | Guard result | Decision |
|---|---|---|
| Raw `kubectl` read | `READ_IN_SCOPE` | Allow; reads remain unrestricted by namespace, matching the existing guard contract. |
| Raw `kubectl` in-scope write | `WRITE_IN_SCOPE` | Deny with guidance to use `ws k8s`; the wrapper injects the armed context. |
| Raw `kubectl` blocked write | `BLOCK:*` | Deny with the existing class-aware guard message. |
| `ws k8s` read or write | `READ_IN_SCOPE` or `WRITE_IN_SCOPE` | Allow; the wrapper performs the guarded execution. |
| `ws k8s` blocked write | `BLOCK:*` | Deny before execution with the existing guard message. |
| `ws k8s scope set/show/clear` | Not evaluated as a kubectl operation | Pass through so the user can manage the scope. |
| Shell script whose file contains raw `kubectl` | N/A | Deny with guidance to route the Kubernetes steps through `ws k8s`. |
| Any Kubernetes command with a valid session-scoped `k8s` bypass marker | N/A | Pass through and audit the bypass. The wrapper's own guard remains active. |

The adapter intentionally does not scan arbitrary shell strings recursively beyond the existing direct-script case. Shell-composition enforcement belongs to a later generic policy slice.

### Failure behavior

Malformed input, missing `jq`, a missing repository guard script, or an absent session ID must fail open to the normal Codex sandbox and approval flow. A hook infrastructure problem must not brick every Bash call. Policy evaluation errors for a command that is positively identified as guarded Kubernetes fail closed with a concise diagnostic, because silently running a write after discovering an active scope would violate the guard's promise.

### Audit behavior

The hook records only its own allow, deny, bypass, and infrastructure-warning decisions. It does not attempt to become a general Codex tool audit log. Audit text must flatten embedded newlines so one tool call remains one log entry.

## Verification

Add focused Bats tests with synthetic Codex hook payloads covering:

- unrelated commands and inactive scopes passing through;
- raw reads allowing under an active scope;
- raw in-scope writes redirecting to `ws k8s`;
- out-of-scope and cluster-scoped writes using the shared class-aware message;
- guarded `ws k8s` reads and writes allowing;
- scope management passing through;
- direct script invocation containing `kubectl` denying;
- matching and stale bypass markers;
- malformed payload and missing dependency behavior;
- registration JSON validity and the expected `PreToolUse` matcher.

Run the focused Codex hook tests, the existing shared guard tests, and `ws test yggdrasil` before commit.

## Claude-hook conversion map

The long-term design should separate policy data and evaluators from harness adapters. A shared engine should consume a normalized event such as `{session_id, event, tool, command, cwd, project_root}` and return one of four platform-neutral outcomes: `allow`, `approval-request`, `human-required`, or `forbidden`, plus a reason and audit metadata. Each harness adapter maps only outcomes that its event can faithfully express. In particular, `human-required` must never degrade into an auto-reviewable agent prompt.

| Claude hook piece | Codex-compatible shape | Shared-engine fit | Capability risk or caveat |
|---|---|---|---|
| Input payload parsing and project-root discovery | Small Codex adapter normalizes the Codex payload and trusted project root. | Adapter boundary, not policy. | Field names and lifecycle scope are harness contracts. |
| Tier 1 shell-composition denial | Codex `PreToolUse` hook over Bash commands; Codex `.rules` shell splitting is complementary but does not cover every advanced shell form. | High: tokenize once, return `forbidden` with corrective guidance. | Harnesses expose different shell tools and may pre-parse compound commands differently. PowerShell needs a separate grammar. |
| Whole-tool PowerShell denial and narrow kuttl exception | Codex hook matcher for a PowerShell tool if that tool exists; otherwise command-level matching inside Bash. | Medium: tool policy and exception data are shareable. | Some harnesses have no distinct PowerShell tool, so capability discovery must precede registration. |
| Tier 2 raw-command redirects (`git commit`, `git push`, provider CR creation, `git mv`) | Codex `PreToolUse` hook for deterministic corrective denial. `.rules` can reinforce commands that already require outside-sandbox execution but cannot cover workspace-local commands by itself. | High: redirect rows, suggestions, and bypass slugs are platform-neutral data. | A Codex `allow` or `prompt` rule is not equivalent to a training redirect. |
| Tier 2b Kubernetes scoped redirect | Dedicated Codex hook in this CR, backed by `ws-k8s-guard.sh`. | Very high: scope lookup contract, evaluator, and messages are already mostly neutral. | Requires session identity and full command arguments; static rules are insufficient. |
| Tier 3 adapter-aware test/lint/build redirect | Codex `PreToolUse` hook resolves component and active-realm adapter before choosing deny-with-bypass or nudge-and-pass. | High: component resolution and redirect policy should be shared. | Needs reliable cwd and trusted realm configuration in every harness. |
| Destructive and arbitrary-execution ask list | Prefer Codex `PermissionRequest` for commands already escalating; use `PreToolUse` only when the policy requires a guaranteed human gate before normal routing. | High for pattern data and risk classification. | Codex `.rules` `prompt` applies only outside the sandbox. A harness that permits automatic approval cannot represent `human-required` unless its hook can force a real user decision. |
| Claude `settings.json` allowlist | Replace with Codex sandbox/permission profiles and narrowly reviewed `.rules`; do not translate entries mechanically. | Low: the intent can be classified, but syntax and trust effects are platform-specific. | Claude allow may bypass a prompt, while Codex allow authorizes outside-sandbox execution. Mechanical conversion could broaden authority. |
| Per-machine `[allow-extras]` | Codex user-level `.rules` or user-level hooks, not a committed project conversion. | Medium for recommendations and audit metadata; low for storage format. | User-level policy must remain user-owned and cannot weaken managed requirements. |
| Scratch-directory Edit/Write auto-allow | Codex filesystem permission profile for workspace scratch paths where appropriate; hook only if event-specific review remains necessary. | Medium: scratch path data is shareable. | Filesystem write permission and permission-request approval are different grants. Keep sensitive subpaths denied explicitly. |
| Session-scoped bypass markers | Make `ws hook-bypass` use the agent-neutral session resolver and let each adapter compare its payload session ID. | High: marker format, slug validation, expiry model, and audit event are neutral. | Environment variable names differ; some harnesses may not expose a stable session ID to subprocesses. |
| Audit logging | Shared structured audit helper with adapter and event fields; render text for human grep as a view. | High. | Log locations, privacy expectations, and managed retention differ by harness. |
| Hook opt-out | Harness-native feature disable plus a shared `WS_HOOK_DISABLE=1` emergency passthrough. | Medium. | Managed configuration may prohibit local disablement; documentation must distinguish local and managed policy. |
| Optional `PermissionRequest` Edit/Write handling | Codex `PermissionRequest` supports Bash and edit tools; register only for a separately designed ergonomic slice. | Medium: scratch decision policy is neutral. | Multiple Codex hooks run concurrently, so one hook cannot prevent another handler from starting. |

## Policy-engine direction

A later platform-neutral engine should be extracted incrementally, not by moving the current monolith wholesale. Each conversion should first isolate one policy evaluator behind a stable shell interface, give it harness-independent tests, and leave only payload and decision serialization in the adapter. The Kubernetes guard is the first example: the evaluator already exists, so this CR adds only the Codex adapter.

Suggested extraction order:

1. Kubernetes scoped redirects and shared audit helpers.
2. Static raw-command redirect rows and session bypass handling.
3. Adapter-aware test/lint/build redirects.
4. Shell-composition classification, with separate Bash and PowerShell grammars.
5. Destructive-command risk classes and per-harness human-gate mapping.
6. Allowlist and scratch-path recommendations, which should remain mostly harness configuration rather than executable shared policy.

For Gemini or Antigravity, the onboarding probe should record whether the harness provides pre-tool hooks, permission-request hooks, stable session IDs, argument-level tool payloads, project trust, user-versus-project policy layers, and a non-auto-reviewable human decision. The shared engine can be reused only where those capabilities exist; otherwise `AGENTS.md`, `ws` wrappers, sandboxing, and server-side authorization remain the portable fallback.

## Out of scope

- Refactoring the existing Claude hook.
- Registering generic Codex command redirects or destructive-command prompts.
- Translating `.claude/settings.json` into Codex permissions or `.rules`.
- Changing Kubernetes guard semantics or mentoring content.
- Claiming Gemini or Antigravity support before their hook capabilities are verified.
