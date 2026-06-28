---
name: gdd-k8s
description: Use when a guarded kubectl practice is requested ("practice kubectl", "test cluster access", "nervous about prod") or when GDD_K8S_CONTEXT is set for the session.
---

# GDD K8s Guard

A practice workflow that arms a small scope — a kube context plus allowed namespaces — so accidental `kubectl` commands against the wrong cluster or namespace are blocked before they execute.

## What This Is (and Is Not)

A safety scope, not a security boundary: accident-prevention for anyone who wants writes bounded to a known context + namespace — a newcomer learning the ropes, or an expert who wants a guardrail while working near production. A determined agent or human can bypass the guard via `ws hook-bypass k8s` (session-level lift) or by running `kubectl` entirely outside the harness (e.g. in a terminal not running Claude Code). Real authorization lives server-side in RBAC. The guard's job is to catch the command that slips out of habit, not to enforce cluster access control.

## When to Load

- The user says something matching practice intent ("practice kubectl", "test my cluster access", "I'm nervous about touching prod", "help me explore this cluster safely")
- `GDD_K8S_CONTEXT` is already set in the session (scope was armed before this skill loaded; explain what it means and offer to review or clear it)
- The mentoring overlay is active and a k8s topic surfaces

## Scope-Capture Flow

When the skill fires for the first time in a session (no scope set yet), walk through these steps with the user, narrating each one before running it:

1. **Explain what's about to happen and why** — the guard will intercept raw `kubectl`, redirect it through `ws k8s`, and block any write that targets a namespace outside the captured scope.
2. **Offer context discovery** — run `kubectl config get-contexts` to list available contexts and invite the user to pick one. (`ws k8s config get-contexts` works equivalently once a scope is armed.)
3. **Confirm the target namespace(s)** — for multiple namespaces, confirm each individually so the user understands what is and is not in scope. A namespace need not already exist: arming a scope on namespaces you intend to create (e.g. one per environment) is supported — `ws k8s create namespace <ns>` is in-scope and can create them.
4. **Arm the scope** — run `ws k8s scope set --context <ctx> --namespace <ns[,ns]>`. The command requires the context to exist (you can't create a context through the guard) but only WARNS on a namespace that doesn't exist yet — surfacing a likely typo without blocking the pre-create workflow.
5. **Confirm the guard is armed** — run `ws k8s scope show` and echo the result. Explain what the user will see when a command is allowed, prompted, or blocked.

## Guard Behavior (Teach This)

Once a scope is armed, the hook's scoped-redirect tier intercepts every Bash tool call:

| Situation | Result |
|-----------|--------|
| `ws k8s <read verb>` targeting in-scope context | Auto-approved silently — reads flow freely |
| `ws k8s <write verb>` targeting in-scope namespace | Prompts normally — user sees the command and approves |
| `ws k8s <write verb>` targeting out-of-scope namespace | Denied with a class-aware explanation: a namespace-scoped write says to add that namespace to the scope; a cluster-scoped/unbounded write says widening cannot help — run outside the guard or clear it |
| `ws k8s create`/`delete namespace <ns>` where `<ns>` is in scope | Allowed — you may create (or delete and recreate) your own scoped namespace(s). An out-of-scope namespace name is denied like any out-of-scope write |
| Raw `kubectl` command | Redirected to `ws k8s`; user sees the denial message |
| Temp script (bash/sh/source) whose file contains raw `kubectl` | Denied with a message pointing to `ws k8s` or `ws hook-bypass k8s` |
| `kubectl --context <other-ctx>` where other-ctx ≠ practice context | Blocked — explicit cross-context write is out of scope |
| `--all-namespaces` on a write | Blocked — unbounded writes are never scope-bounded |

Read verbs auto-approved by the guard: `get`, `describe`, `logs`, `top`, `explain`, `events`, `api-resources`, `api-versions`, `version`, `diff`, `wait`, `auth`, `config` (except `config set-context`/`use-context`/`set`, which are writes).

### Widening, Removing, and Bypassing the Scope

- **Widen the scope** — re-run `ws k8s scope set --context <ctx> --namespace <ns1,ns2>` with a broader namespace list. The previous scope is overwritten.
- **Remove the scope entirely** — `ws k8s scope clear`. The guard deactivates for the session; raw `kubectl` is no longer intercepted.
- **Lift the redirect for the session** — `ws hook-bypass k8s`. This writes a session-scoped bypass marker so the raw-kubectl redirect does not fire, but scope-set vars remain in place. Useful for running a one-off automation script that calls `kubectl` directly.

## Composability

Any stance can invoke this skill. The mentoring overlay (see `docs/gdd/roles-and-stances.md`) is the one most likely to trigger it and narrates each step of the scope-capture flow — surfacing the "why" behind each guard decision so the user internalizes the pattern, not just the commands.

In non-mentoring sessions the skill still arms the guard, but skips the narration unless the user asks.

## What This Skill Does NOT Do

- Replace server-side RBAC — bypass is always one command away, and that is by design
- Guard `kubectl` invoked outside the Claude Code harness (terminal, CI, scripts launched outside Claude)
- Prevent cluster-scoped resource writes from succeeding if the user explicitly bypasses — it blocks by default but does not own the cluster
- Persist the scope across sessions — `GDD_K8S_CONTEXT` and `GDD_K8S_NAMESPACES` live in the session file and are cleared when the session ends
