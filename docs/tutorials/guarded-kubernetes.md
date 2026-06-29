# Guarded Kubernetes

> **You can ask your AI agent to walk you through any step below, or follow this guide directly. Both paths arrive at the same place** — the agent is non-deterministic, this guide is the deterministic version.
>
> **First time through? Turn on mentoring.** Ask your agent: *"let's turn on mentoring while I work through the guarded Kubernetes tutorial."* The mentoring overlay narrates each guard decision — *why* a command was allowed, prompted, or blocked — which is exactly what you want while the verdicts are still new. The `gdd-k8s` skill drives the flow; mentoring adds the teaching.

The `ws k8s` guard is a **safety scope for kubectl** — training wheels while you're learning, a guardrail the rest of the time. You arm a small scope (one kube context plus one or more namespaces) and the workspace blocks accidental *writes* to anything outside it, before kubectl runs. Reads stay free cluster-wide. It's as useful to an expert who wants a boundary while working near production as to someone on their first cluster session. It is **accident-prevention, not a security boundary**: a determined human or agent can always step around it (plain `kubectl`, or `ws hook-bypass k8s`), and real authorization lives in your cluster's RBAC. The guard's job is to catch the destructive command that slips out of habit — a `delete` against prod when you meant your sandbox — not to enforce access control.

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

Throughout, substitute `<ctx>` for your chosen context and `<ns>` for the namespace you will use (e.g. `practice`). Run everything from the workspace root.

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

The scope lives in your session, not your kubeconfig — `ws k8s scope clear` removes it, and it's gone when the session ends. It changes nothing on the cluster.

> **Scope changes must go through your agent.** `ws k8s scope set` requires the agent session ID and will not work in a standalone terminal — the error message will tell you to ask your agent to run it instead.

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
ws k8s delete pod probe -n default
```

REJECTED — and kubectl is never called. Read the message: it tells you the namespace is outside the scope and that you can **add that namespace to the scope** to allow it just there, or run plain `kubectl` outside the guard. This is the common case the guard exists for: you meant `<ns>`, you typed `default`, nothing happened.

### 4. The three kinds of rejection

The guard tailors its advice to *why* something is blocked. Trigger each once so you recognise them:

```bash
ws k8s delete pod probe -n default                          # SCOPE: a namespace you could add
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
ws k8s scope set --context <ctx> --namespace <ns>,another-ns
```

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

### The agent path (Tier 2b)

When an AI agent has a scope armed, the guard extends to *raw* `kubectl`, not just `ws k8s`:

- A raw in-scope **read** (`kubectl get pods`) auto-allows — no redirect, no prompt.
- A raw out-of-scope **write** is denied with the same class-aware message the wrapper emits.
- A raw in-scope **write** is redirected to `ws k8s` so the wrapper can inject `--context`.
- A temp script that shells out to `kubectl` is caught too (the hook scans script bodies).

For the rare case where the agent genuinely needs raw kubectl (a one-off automation script), `ws hook-bypass k8s` lifts the raw-kubectl redirect for that session — human-approved and audited. It does **not** disable the `ws k8s` wrapper guard.

### The human path (ambient guard)

Open a separate plain terminal — no agent, no session id — while an agent session's scope is armed, and `ws k8s` is *still* guarded there: it aggregates the active session's scope. A read works; an out-of-scope write is rejected even though this terminal has no session of its own. The human terminal cannot reconfigure the guard — `ws k8s scope set` and `scope clear` require the agent session ID and will not work outside the harness. To change the scope, ask your agent to run the command. The human terminal's escape from a rejection is plain `kubectl`.

### What the guard does NOT do

- Replace RBAC. The bypass is always one command away by design — server-side RBAC is the real authorization boundary.
- Guard kubectl run entirely outside the workspace (a terminal not running the agent, CI, etc.).
- Persist across sessions — the scope is per-session and clears when the session ends.

### Going further

- **Multiple namespaces / environments.** Arm a comma-separated list; pre-arm namespaces that don't exist yet and create them in-scope.
- **Use it for real.** The same guard protects real work — arm your sandbox namespace before a session where you'll be near production, and let it catch the slip.
- **Validate the feature end-to-end.** If you're testing the guard itself rather than learning it, the [`gdd-k8s` skill](../gdd/skills-reference.md) and [Features Tour § Kubernetes practice guard](../gdd/features.md) are the reference.
