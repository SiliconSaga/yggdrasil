---
name: gdd-k8s
description: Use when a guarded kubectl practice is requested ("practice kubectl", "test cluster access", "nervous about prod") or when GDD_K8S_CONTEXT is set for the session.
---

# GDD K8s Guard

A Kubernetes write safety floor plus an optional small scope — a kube context and allowed namespaces — so writes require deliberate handling even before a scope is armed, and scoped work is blocked from the wrong cluster or namespace.

## What This Is (and Is Not)

A safety scope, not a security boundary: accident-prevention for anyone who wants writes bounded to a known context + namespace — a newcomer learning the ropes, or an expert who wants a guardrail while working near production. A human can run `kubectl` outside an agent harness, and an agent session can use the audited `ws hook-bypass k8s` escape hatch. Real authorization lives server-side in RBAC. The guard's job is to catch the command that slips out of habit, not to enforce cluster access control.

## When to Load

- The user says something matching practice intent ("practice kubectl", "test my cluster access", "I'm nervous about touching prod", "help me explore this cluster safely")
- `GDD_K8S_CONTEXT` is already set in the session (scope was armed before this skill loaded; explain what it means and offer to review or clear it)
- The mentoring overlay is active and a k8s topic surfaces

## Scope-Capture Flow

When the skill fires for the first time in a session (no scope set yet), walk through these steps with the user, narrating each one before running it:

1. **Explain what's about to happen and why** — the guard will intercept raw `kubectl`, redirect it through `ws k8s`, and block any write that targets a namespace outside the captured scope.
2. **Offer context discovery** — run `kubectl config get-contexts` to list available contexts and invite the user to pick one. (`ws k8s config get-contexts` works equivalently once a scope is armed.)
3. **Confirm the target namespace(s)** — for multiple namespaces, confirm each individually so the user understands what is and is not in scope. A namespace need not already exist: arming a scope on namespaces you intend to create (e.g. one per environment) is supported — `ws k8s create namespace <ns>` is in-scope and can create them. Also ask the user to name a second namespace they expect writes to be rejected from — using a real namespace they know makes the rejection demonstrations concrete rather than arbitrary (e.g. `default` carries no meaning to most users). This secondary namespace can later serve as the target for the scope-widening exercise.
4. **Arm the scope** — run `ws k8s scope set --context <ctx> --namespace <ns[,ns]>`. The command requires the context to exist (you can't create a context through the guard) but only WARNS on a namespace that doesn't exist yet — surfacing a likely typo without blocking the pre-create workflow. Namespace verification is a live API probe: DNS, auth, RBAC, and other probe failures are reported with a concise diagnostic but still arm the local scope; if an agent sandbox blocks cluster networking, re-run the command outside the sandbox.
5. **Confirm the guard is armed** — run `ws k8s scope show` and echo the result. Explain what the user will see when a command is allowed, prompted, or blocked.

## Guard Behavior (Teach This)

Once a scope is armed, the hook's scoped-redirect tier intercepts every Bash tool call:

| Situation | Result |
|-----------|--------|
| Kubernetes read with no scope armed | Defers to normal harness routing. |
| Kubernetes write with no scope armed | Claude force-prompts before any command allowlist. Codex denies with guidance to arm a scope or explicitly confirm a session bypass because its focused bridge cannot force an equivalent prompt. |
| `ws k8s <read verb>` targeting in-scope context | The wrapper allows it. Claude's broad hook auto-approves it; the focused Codex bridge defers to normal Codex sandbox and approval routing. |
| `ws k8s <write verb>` targeting in-scope namespace | The wrapper allows it and the harness applies its normal execution/approval routing. |
| `ws k8s <write verb>` targeting an out-of-scope namespace or unbounded resource | Denied with a class-aware explanation: a namespace-scoped write says to add that namespace to the scope; a cluster-scoped or otherwise unbounded write says widening cannot help — leave the guarded workflow, or after explicit confirmation use the audited session bypass and run the deliberate raw command |
| `ws k8s create`/`delete namespace <ns>` where `<ns>` is in scope | Allowed — you may create (or delete and recreate) your own scoped namespace(s). An out-of-scope namespace name is denied like any out-of-scope write |
| Raw `kubectl` read verb | Reads are free even via raw kubectl when a scope is armed. Claude's broad hook auto-approves the read; the focused Codex bridge defers to normal Codex routing. |
| Raw `kubectl` write (in-scope namespace) | Denied with a message instructing use of `ws k8s` — the wrapper injects `--context`, preventing writes from hitting the wrong cluster by force of habit |
| Raw `kubectl` write (out-of-scope namespace or unbounded) | Denied with the same class-aware message the `ws k8s` wrapper emits |
| Direct shell script whose file contains raw `kubectl` | Denied with a message pointing to `ws k8s` or `ws hook-bypass k8s`; relative paths resolve from the tool cwd and common shell options such as `bash -x` are skipped when locating the script |
| `kubectl --context <other-ctx>` where other-ctx ≠ practice context | Blocked — explicit cross-context write is out of scope |
| `--all-namespaces` on a write | Blocked — unbounded writes are never scope-bounded |
| `apply -k` / `--kustomize` while scoped | The guard renders an existing local Kustomize directory and checks every resource. Missing, unrenderable, cross-namespace, or cluster-scoped output fails closed. |

Read verbs accepted by the guard: `get`, `describe`, `logs`, `top`, `explain`, `events`, `api-resources`, `api-versions`, `version`, `diff`, `wait`, and standalone `kustomize`; plus `auth can-i`, `auth whoami`, `config view`, `config get-contexts`, `config current-context`, `config get-clusters`, and `config get-users`. Other `auth` and `config` operations are writes because those command families include mutations. Unknown verbs are writes by default.

The hooks normalize common transparent launch forms before classification: leading environment assignments, `env`, `command`, absolute paths ending in `kubectl`, shell options before a script path, and literal kubectl inside `bash -c`/`sh -c`. They do not claim to observe arbitrary nested execution through task runners, client libraries, Helm, or a script that constructs the kubectl executable name without the literal token; server-side RBAC remains the boundary for those cases.

### Staying Guarded, Clearing, and Bypassing

| Intent | Recommendation | Effect |
|---|---|---|
| Namespace-scoped work, especially near shared or production-shaped clusters | Keep the scope; widen it only by re-running `ws k8s scope set --context <ctx> --namespace <ns1,ns2>` when another namespace is deliberately needed. | `ws k8s` remains bounded and raw writes remain intercepted. |
| Sustained cluster-wide or highly experimental interactive work on an intentionally disposable local cluster | After explicit user confirmation, run `ws k8s scope clear`; re-arm later if the user wants namespace bounds back. | Context/namespace enforcement stops, but the unscoped write safety floor remains: Claude asks on writes and Codex denies them until bypassed. |
| A specific script or unattended tool must invoke raw `kubectl`, or unscoped Codex work is deliberately authorized | After explicit user confirmation, run `ws hook-bypass k8s`. | The write floor and raw-command interception are lifted for the rest of the agent session; an already-armed `ws k8s` wrapper remains scope-bounded. This is not a one-command exception. |

Never clear the scope or create a bypass marker merely because the guard rejects an operation. Explain why it was rejected, compare the choices above, and obtain explicit user confirmation before reducing protection. Clearing is sufficient for interactive cluster-wide work in Claude because writes still prompt; unattended automation or unscoped Codex writes additionally need the session bypass.

## Surfacing Output to the User

Tool output visibility varies by harness, version, and user preferences. In some configurations the user sees full stdout/stderr inline; in others they see only the command name and a pass/fail indicator. When uncertain, **check with the user early** — for example, after the first guard rejection, ask whether they can see the rejection message or only the result dot. Their answer should calibrate how much the agent needs to repeat for the rest of the session.

When the agent cannot confirm the user is seeing output:

- **Quote guard rejection messages verbatim** when a command is blocked. The guard's messages are written to be informative; a paraphrase loses the specific remedies they name.
- **Echo `ws k8s scope show` output** after arming, rather than just asserting "the scope is armed."
- **Surface any command output the user needs in order to make a decision** — context lists, namespace lookups, etc.

The general rule: if the output of a tool call is the point — a rejection reason, a confirmation, a list — and the agent is not certain the user is seeing it, repeat it in plain text before moving on.

## Hook Availability

Claude Code registers the broad PreToolUse hook through `.claude/settings.json`. Codex registers the focused Kubernetes bridge through `.codex/hooks.json`; the user must review and trust its current hash through `/hooks`. Both intercept raw Kubernetes writes and directly invoked scripts containing `kubectl`, but safe-call routing differs as described above. In any other harness, treat `ws k8s` as the required form until that harness's pre-tool capabilities are verified; do not assume raw `kubectl` will be caught.

## Composability

Any stance can invoke this skill. The mentoring overlay (see `docs/gdd/roles-and-stances.md`) is the one most likely to trigger it and narrates each step of the scope-capture flow — surfacing the "why" behind each guard decision so the user internalizes the pattern, not just the commands.

In non-mentoring sessions the skill still arms the guard, but skips the narration unless the user asks.

## What This Skill Does NOT Do

- Replace server-side RBAC — bypass is always one command away, and that is by design
- Guard `kubectl` invoked outside a supported agent harness (terminal, CI, or scripts launched independently)
- Prevent cluster-scoped resource writes from succeeding if the user explicitly bypasses — it blocks by default but does not own the cluster
- Persist the scope intentionally as shared configuration — it belongs to one session file, but ended-session files can linger locally until `ws clean --sessions-all` removes them
