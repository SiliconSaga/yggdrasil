# Guarded Kubernetes

> **You can ask your AI agent to walk you through any step below, or follow this guide directly. Both paths arrive at the same place** — the agent is non-deterministic, this guide is the deterministic version.
>
> **First time through? Turn on mentoring.** Ask your agent: *"let's turn on mentoring while I work through the guarded Kubernetes tutorial."* The mentoring overlay narrates each guard decision — *why* a command was allowed, prompted, or blocked — which is exactly what you want while the verdicts are still new. The `gdd-k8s` skill drives the flow; mentoring adds the teaching.

The `ws k8s` guard combines a **Kubernetes write safety floor** with an optional **context-and-namespace scope** — training wheels while you're learning, a guardrail the rest of the time. Agent-issued reads follow normal harness routing even before a scope exists. Unscoped writes require deliberate handling: Claude prompts before its command allowlist, while Codex denies with guidance to arm a scope or explicitly authorize a session bypass. Once you arm a scope, the workspace also blocks writes outside its context and namespaces before kubectl runs. It is **accident-prevention, not a security boundary**: a human can run plain `kubectl` outside an agent harness, and an agent session can use the audited `ws hook-bypass k8s` escape hatch. Real authorization lives in your cluster's RBAC.

The walkthrough is chaptered so you can stop after Chapter 2 with the guard in muscle memory, and come back for the agent/human paths and real workflows later.

---

## Prerequisites

- **A Kubernetes cluster context you can write to**, and a namespace within it that you have write access to. Creating or destroying namespaces is not required for Chapters 1–2; that is covered as optional material in Chapter 3. This is the one hard requirement — the guard operates against a real cluster.

  Don't have a cluster? Spin up a local one (any of these gives you a disposable context):

  | Tool | Start it | Context name |
  |---|---|---|
  | Docker Desktop | enable Kubernetes in Settings → Kubernetes | `docker-desktop` |
  | [kind](https://kind.sigs.k8s.io/) | `kind create cluster` | `kind-kind` |
  | [k3d](https://k3d.io/) | `k3d cluster create practice` | `k3d-practice` |
  | [minikube](https://minikube.sigs.k8s.io/) | `minikube start` | `minikube` |

- **`kubectl` on your PATH**, pointed at that cluster. Note `kubectl` is the one tool `ws preflight` does *not* check (it isn't a general workspace prerequisite) — this tutorial needs it specifically, so confirm `kubectl version` works before you start.
- **The workspace prerequisites.** From the workspace root, `ws preflight` should pass — it verifies bash, git, `yq` (the guard parses `-f` manifests with it), `jq`, and a provider CLI (`gh` or `glab`).
- **The `ws k8s` feature present.** `ws orient` should list the `gdd-k8s` skill and a `k8s` subcommand.

Throughout, substitute `<ctx>` for your chosen context, `<ns>` for the namespace you will use (e.g. `practice`), and `<blocked-ns>` for a different real namespace where you expect writes to be rejected. Choosing a namespace you recognise makes the rejection exercise easier to interpret than relying on an arbitrary default. Run everything from the workspace root.

---

## Chapter 1: Arm a guard scope

Goal: a guard scope armed and understood. Nothing is blocked yet — you're setting the boundary.

### 1. Pick a context and a namespace

List what you can reach:

```bash
kubectl config get-contexts
```

Pick a context you have write access to (`<ctx>`). You need a namespace too — use one that already exists and that you can write to freely (`<ns>`).

If you are working in a disposable environment and prefer to start with a fresh namespace, you can create one:

```bash
kubectl --context <ctx> create namespace <ns>
```

This is not required — the guard arms equally well against an existing namespace. Namespace creation and deletion are covered as optional steps in Chapter 3.

### 2. Arm the scope

```bash
ws k8s scope set --context <ctx> --namespace <ns>
```

You'll see `guard scope armed: context=<ctx> namespaces=<ns>`. The context must exist — a bogus `--context nope` errors. A namespace that doesn't exist yet only *warns* ("not found … arming anyway") and arms regardless, so you can arm across several environments up front and create the namespaces later.

Confirm it:

```bash
ws k8s scope show
```

The scope lives in a per-session file, not your kubeconfig. `ws k8s scope clear` removes it from the current session, and `ws clean --sessions-all` removes ended-session files while preserving the current session. Ended-session files can otherwise linger and continue contributing to the ambient guard. The scope changes nothing on the cluster.

> **Scope changes require a session ID.** `ws k8s scope set` writes to a session-scoped file and will fail without one. In a standalone terminal this means asking your agent to run the command — the error message will say so. Advanced users can export `GDD_SESSION_ID` directly to run scope commands outside the harness.

#### Context-only scope (pin the cluster, free up the namespaces)

On a throwaway local cluster where you're doing deep infra testing across a dozen namespaces that come and go, per-namespace scoping is constant friction. There, the safety that matters is pinning the **context** (don't accidentally hit prod), not enumerating namespaces. Arm a **context-only** scope by omitting `--namespace` (or passing `--namespace '*'` / `--namespace all`):

```bash
ws k8s scope set --context <ctx>            # context-only; all namespaces in scope for writes
ws k8s scope set --context <ctx> --namespace '*'   # equivalent (quote the * so the shell can't expand it)
```

`ws k8s scope show` reports `namespaces: (all — context-only)`. Writes to *any* namespace are allowed — there's no per-namespace rejection. The context-pin protections are unchanged: a command with an explicit different `--context` is still rejected, and context-mutating (`kubectl config use-context …`), cluster-scoped (nodes, CRDs, `clusterrole`, …), and `--all-namespaces` writes are still blocked exactly as in a namespaced scope. To go back to per-namespace scoping, just re-arm with an explicit `--namespace <ns[,ns]>` list (it overwrites).

**That's the setup.** From here on, every `ws k8s …` command is checked against this scope.

---

## Chapter 2: Feel the guard

Goal: build intuition for what's allowed, what's blocked, and — most importantly — how to *read the rejection messages*, which tell you the right next step.

### 1. Reads are free

```bash
ws k8s get pods                     # your scoped context, injected automatically
ws k8s get pods -n kube-system      # a different namespace — still fine
```

Both run. Reads are never namespace-bounded — the guard only cares about writes. Notice the wrapper injects `--context <ctx>` for you, so you can't accidentally read (or later write) against the wrong cluster.

### 2. An in-scope write runs

```bash
ws k8s run probe --image=pause --restart=Never -n <ns>
```

The pod is created. A write that lands inside your scope behaves like normal kubectl.

### 3. An out-of-scope write is blocked

```bash
ws k8s delete pod probe -n <blocked-ns>
```

REJECTED — and kubectl is never called. Read the message: it tells you the namespace is outside the scope and that you can **add that namespace to the scope** to allow it just there, or run plain `kubectl` outside the guard. This is the common case the guard exists for: you meant `<ns>`, you typed `<blocked-ns>`, nothing happened.

### 4. The three kinds of rejection

The guard tailors its advice to *why* something is blocked. Trigger each once so you recognise them:

```bash
ws k8s delete pod probe -n <blocked-ns>                     # SCOPE: a namespace you could add
ws k8s create clusterrole demo --verb=get --resource=pods   # UNBOUNDED: not namespace-bound at all
ws k8s apply -f ./nope.yaml                                  # PRECONDITION: the guard can't read the input
```

- **Scope** — the target namespace is outside the scope. Remedy: add it to the scope, or go around the guard. Widening *helps*.
- **Unbounded** — the resource isn't bound to any namespace (a `clusterrole`, a node `cordon`, `--all-namespaces`). Widening the namespace scope **cannot** help; the message points you at plain `kubectl` or dropping the guard with `ws k8s scope clear`.
- **Precondition** — the guard couldn't evaluate the command (a `-f` file that doesn't exist or won't parse). It fails closed and tells you to fix the input — this is *not* a scope decision, so it doesn't mention widening.

All three block **before** kubectl runs, so they're safe to type while you're learning.

**That's Chapter 2.** You can stop here — you've got the core: reads free, in-scope writes run, out-of-scope writes blocked, and you can read the three rejection styles. Come back for the real workflows and the agent/human paths.

---

## Chapter 3: Real practice

Goal: the workflows you'll actually use — manifests, widening, cleanup. Namespace lifecycle (create and delete) is covered as an optional step for disposable environments.

### 1. Apply a manifest

Write a Pod manifest into your scoped namespace:

```bash
cat > pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: practice-pod
  namespace: <ns>
spec:
  containers:
    - name: pause
      image: pause
EOF

ws k8s apply -f pod.yaml
```

It applies — the namespace in the manifest is in scope. Each document is scope-checked individually: a `kind: List` (or a multi-doc file) with one item in `<ns>` and one in `prod` is blocked on the `prod` item, before anything is applied.

> **Windows note:** quote the path or use forward slashes. An unquoted backslash path (`ws k8s apply -f C:\dir\pod.yaml`) is mangled by the shell into `C:dirpod.yaml` *before* `ws` ever sees it — use `"C:\dir\pod.yaml"` or `C:/dir/pod.yaml`.

### 2. Namespace lifecycle — create and recreate your own *(optional — disposable environments only)*

Skip this step if you are working in a shared or production-adjacent cluster. It requires a namespace you can freely delete and recreate without affecting other workloads.

Because `<ns>` is in your scope, the guard permits creating and deleting *that* namespace:

```bash
ws k8s delete namespace <ns>     # allowed — it's in scope
ws k8s create namespace <ns>     # allowed — recreated
```

A namespace *not* in your scope (`ws k8s delete namespace kube-public`) is still rejected. This is what makes the "arm a not-yet-existing namespace, then create it" workflow from Chapter 1 useful — handy when provisioning the same sandbox across several environments.

### 3. Widen, then narrow

Want a second namespace in scope? Re-arm with the broader list (it overwrites). Run this through your agent — `ws k8s scope set` will not work in a standalone terminal:

```bash
ws k8s scope set --context <ctx> --namespace <ns>,<blocked-ns>
```

The namespace you used as `<blocked-ns>` is now deliberately in scope, so the earlier rejection should no longer occur. This is the useful widening case: a namespace-scoped operation can become valid when you explicitly broaden the boundary.

When you're done, clear it:

```bash
ws k8s scope clear
```

### 4. Clean up

```bash
ws k8s delete pod practice-pod -n <ns>
ws k8s delete pod probe -n <ns>
```

If you created a namespace specifically for this tutorial (Chapter 1 or the optional step above), delete it before clearing the scope — the guard only allows the delete while `<ns>` is still in scope:

```bash
ws k8s delete namespace <ns>
```

Then clear the scope and remove the manifest:

```bash
ws k8s scope clear
rm pod.yaml
```

If you spun up a local cluster just for this, tear it down too (`kind delete cluster`, `k3d cluster delete practice`, `minikube delete`, or disable Docker Desktop's Kubernetes).

---

## Chapter 4+: The agent path, the human path, and going further

### The agent path

When an AI agent has a scope armed, a harness hook can extend the guard to *raw* `kubectl`, not just `ws k8s`. The shared scope rules are the same, but hook setup and safe-call routing differ:

| Behavior | Claude Code | Codex |
|---|---|---|
| Hook setup | The committed `.claude/settings.json` registers the broad PreToolUse hook. | The project `.codex/hooks.json` registers the focused Kubernetes bridge; review and trust its current hash through `/hooks`. |
| Raw Kubernetes read | The hook auto-allows the read when a scope is armed. | The bridge returns no decision, so normal Codex sandbox, network, rules, and approval routing still applies. |
| Kubernetes write with no scope | The write safety floor force-prompts before project or local command allowlists, including a blanket `kubectl:*` allow. | The focused bridge denies because Codex does not expose the same force-ask decision; arm a scope or explicitly confirm a session bypass. |
| Raw Kubernetes write | An in-scope write is denied with guidance to use `ws k8s`; an out-of-scope or unbounded write receives the shared guard rejection. | Same guard decisions; the focused bridge does not inherit Claude's broader allowlist or prompt semantics. |
| Directly invoked script containing `kubectl` | Denied whether or not a scope is active. | Denied whether or not a scope is active. |
| Guarded `ws k8s` call | The wrapper enforces scope; the broad hook may auto-allow reads or leave writes to normal prompting. | The wrapper enforces scope; safe calls defer to normal Codex routing. |
| Bypass and audit | `ws hook-bypass k8s`; decisions are recorded in `~/.claude/hook-audit.log`. | `ws hook-bypass k8s`; bridge denies and bypasses are recorded in `~/.codex/hook-audit.log`. |

> **Managed environments:** an organisation may restrict shell network access even when the project hook permits a command. The agent can still provide the mentoring narration while you run guarded `ws k8s` commands in a separate human terminal; that path uses the wrapper's ambient scope, described below. This is an environment policy distinction, not a change to the guard's scope rules.

Across both supported harnesses:

- A raw out-of-scope **write** is denied with the same class-aware message the wrapper emits.
- A raw in-scope **write** is denied with guidance to use `ws k8s` so the wrapper can inject `--context`.
- A directly invoked script that shells out to `kubectl` is caught too (the hook scans script bodies).
- Relative script paths are resolved from the command's working directory, and common transparent forms such as `bash -x script.sh`, `env KUBECONFIG=… kubectl`, absolute kubectl paths, and literal `bash -c` calls are normalized before classification. Hooks cannot see arbitrary nested execution through task runners, client libraries, Helm, or dynamically constructed command names; this remains a guardrail rather than a security boundary.
- Scoped `apply -k` and `--kustomize` render an existing local directory before execution so every rendered namespace and cluster-scoped kind can be checked. Missing, remote, plugin-dependent, or unsuccessful renders fail closed; standalone `kubectl kustomize` remains a read.

Choose how much guardrail the work actually needs:

- **Stay guarded** for namespace-scoped work, especially near shared or production-shaped clusters. Widen only when another namespace is deliberately required.
- **Clear the scope** for sustained cluster-wide or highly experimental interactive work on an intentionally disposable local cluster. After you explicitly confirm that choice, run `ws k8s scope clear`; context and namespace bounds disappear, but the unscoped write safety floor remains. Claude will still prompt for each write; Codex will deny writes until deliberately bypassed.
- **Bypass the write floor and raw-command interception** when a specific script or unattended tool must invoke raw `kubectl`, or when unscoped Codex work has been explicitly authorized. After confirmation, `ws hook-bypass k8s` writes an audited marker for the rest of the agent session. If a scope remains armed, it does **not** disable the `ws k8s` wrapper's context and namespace checks. It is not a one-command exception.

A rejection by itself is not a reason to clear or bypass the guard. Read the class-aware message first, then choose the boundary that matches the intended work.

Tool output visibility varies by harness and configuration. After the first rejection, confirm whether you can see the full guard message or only a blocked/failure indicator. When the message is collapsed, the mentoring agent should repeat the complete class-aware rejection and its remedy before continuing.

### The human path (ambient guard)

Open a separate plain terminal — no agent, no session id — while an agent session's scope is armed, and `ws k8s` is *still* guarded there: it aggregates the active session's scope. A read works; an out-of-scope write is rejected even though this terminal has no session of its own. The human terminal cannot reconfigure the guard — `ws k8s scope set` and `scope clear` require a session ID, which a plain terminal does not have. To change the scope, ask your agent to run the command (or export `GDD_SESSION_ID` manually for advanced use). The human terminal's escape from a rejection is plain `kubectl`.

Ended-session files can continue contributing to this ambient aggregation because the workspace has no session-liveness marker. If a stale scope appears, run `ws clean --sessions-all`; it removes ended-session files while preserving the current session.

### What the guard does NOT do

- Replace RBAC. The bypass is always one command away by design — server-side RBAC is the real authorization boundary.
- Guard kubectl run entirely outside the workspace (a terminal not running the agent, CI, etc.).
- Persist intentionally as shared configuration. The scope belongs to one session file; stale ended-session files may linger locally until `ws clean --sessions-all` removes them.

### Going further

- **Multiple namespaces / environments.** Arm a comma-separated list; pre-arm namespaces that don't exist yet and create them in-scope.
- **Use it for real.** The same guard protects real work — arm your sandbox namespace before a session where you'll be near production, and let it catch the slip.
- **Validate the feature end-to-end.** If you're testing the guard itself rather than learning it, the [`gdd-k8s` skill](../gdd/skills-reference.md) and [Features Tour § Kubernetes practice guard](../gdd/features.md) are the reference.
