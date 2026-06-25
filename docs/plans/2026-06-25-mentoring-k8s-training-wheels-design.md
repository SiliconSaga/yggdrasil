# Mentoring Training Wheels — stances, session-scoped config, and a guarded `ws k8s`

Status: Design (brainstormed, pre-plan). Date: 2026-06-25. Arc: `multi-agent-attribution` (Phase 2 + a slice of Phase 3). Supersedes the roadmap tails in [`2026-06-15-multi-agent-attribution-design.md`](2026-06-15-multi-agent-attribution-design.md) §159–160 for the work it covers.

**Revision (2026-06-25, round 2 — post first review):** added the shared guard module consumed by both `ws k8s` and the hook (in-scope reads auto-approve; everything else falls to the normal permission flow); manifest *and* temp-script namespace scanning replaces the earlier "command-line only" limitation; `ws_session_set` is specified as an atomic read-modify-write; scope validation is per-namespace (least-privilege safe); the workflow moves into a dedicated `gdd-k8s` skill; migration is simplified to a direct one-pass edit (no hoard upgrade, no legacy fallback); `ws clean` is hardened against touching parallel sessions; a stance-philosophy note is added.

## Motivation

Asking for "the mentor role" in GDD today does almost nothing concrete: it loads [`.agent/skills/gdd-mentoring/SKILL.md`](../../.agent/skills/gdd-mentoring/SKILL.md), which is prose-only — a behavior modifier with no tooling, the thinnest of the four mode skills. The idea here is to give mentoring *teeth*: when a newcomer is handed daunting access to a real cluster, a mentoring session should capture a small practice scope (a kube context + allowed namespaces) and then hard-wire a guard around `kubectl` so accidental commands against the wrong cluster or namespace are blocked — training wheels that come off deliberately, not by reflex.

This is the concrete payoff that motivates two pieces of plumbing the GDD GA roadmap already anticipated: moving per-session concerns out of workspace-global Thalamus frontmatter (Phase 2), and arming tool guards keyed to that session config (Phase 3). It also resolves a long-standing taxonomy muddle — mentoring is not the same *kind* of thing as quick/zen/flow.

## Background — what exists today

- **Roles vs modes.** [`docs/gdd/roles-and-modes.md`](../gdd/roles-and-modes.md) splits *roles* (developer/designer/reviewer/scribe — what kind of work) from *modes* (mentoring/quick/zen/flow — how the framework adapts). Only Scribe has a real role skill with tooling; the rest are assumed defaults.
- **Mentoring is mis-bucketed.** Quick/zen/flow are mutually-exclusive *tempos* — you are in exactly one. Mentoring *composes* with them (the orientation and mode skills speak of "mentoring + quick", "mentoring + zen"). The "four modes" framing lumps one teaching overlay together with three tempos, which is why "mentor role" feels natural to say.
- **Mode/role storage.** Both live in per-machine Thalamus YAML frontmatter ([`templates/thalamus.md`](../../templates/thalamus.md) keys `mode:`/`role:`), read at session start by [`.agent/skills/gdd-orientation/SKILL.md`](../../.agent/skills/gdd-orientation/SKILL.md). This is workspace-global state — it clashes between parallel sessions (e.g. an open Scribe session shouldn't force the whole workspace to Scribe while other work runs).
- **The session file (Phase 1, shipped — PR #103).** [`2026-06-15-multi-agent-attribution-design.md`](2026-06-15-multi-agent-attribution-design.md) introduced a per-session file `.tmp/gdd-agent-sessions/<session-id>.env`, keyed by session id (`GDD_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` > `CODEX_THREAD_ID`), established fresh at every `ws orient`. It currently carries one line, `GDD_CO_AUTHOR=…`, and is read as data (not sourced) by [`scripts/ws-session.sh`](../../scripts/ws-session.sh). Its format is deliberately extensible; Phase 2/3 were explicitly deferred to "their own brainstorm → spec." This doc is that brainstorm.
- **The hook.** [`.claude/hooks/gdd-permission-hook.sh`](../../.claude/hooks/gdd-permission-hook.sh) intercepts Bash/PowerShell tool calls. Its redirect rules are *data*, parsed from [`.claude/hooks/hook-rules`](../../.claude/hooks/hook-rules) sections (`[redirect-commands]` etc.). It already resolves the session id and reads per-session markers under `.tmp/hook-bypass/<slug>.bypass`. It is plain bash and can both `deny` and `allow` (auto-approve) a call. It does **not** read the Thalamus.
- **`ws` dispatch.** [`scripts/ws`](../../scripts/ws) is a single dispatcher: a `case` routes each subcommand either to a sibling `ws-<name>.sh` or to an in-file `ws_<name>` function. Adding a subcommand is documented in [`docs/ws-cli-guide.md`](../../docs/ws-cli-guide.md). No kubectl/k8s wrapper exists anywhere today — `ws k8s` is greenfield.

## Decisions (brainstorm outcomes)

1. **Scope:** one combined, k8s-driven spec — the session-config move is pulled in only as far as this feature needs, with `ws k8s` + the hook integration as the vertical slice that proves the whole idea.
2. **Taxonomy:** rename the *mode* axis to **stance** (quick/zen/flow); make **mentoring** a separate composable boolean overlay; keep **role**. Exhaustive rework of every old `mode`/`role` reference pre-GA.
3. **Storage:** stance/role/mentoring move into the session file, established fresh each session, and are **retired entirely** from Thalamus frontmatter.
4. **Guard strictness:** out-of-scope namespace on a write → **hard block**; widen only by deliberately re-running `ws k8s scope set`. A wrong *context* is an **absolute** block with no override.
5. **Read/write split:** on a matching context, **reads are allowed anywhere**; **writes** must target an in-scope namespace.
6. **Shared guard, hook-evaluated:** one guard module is the single source of truth, consumed by both `ws k8s` (enforce) and the hook (permission decision). The hook **auto-approves in-scope reads** of `ws k8s`; everything else falls to the normal permission flow (writes prompt; known-bad denies). No kubectl/`ws k8s` entry is added to the gdd-global allowlist.
7. **Coverage beyond the command line:** the guard parses namespaces from `-f` manifests, and the hook blocks execution of temp scripts that contain raw `kubectl` while a scope is active — closing the reflexive "write a script to dodge the guard" bypass.
8. **Hook breadth:** raw `kubectl` redirects to `ws k8s` **only when a practice scope is active**.
9. **Dedicated skill:** the practice workflow lives in a new `gdd-k8s` skill that mentoring (or any stance) invokes; `gdd-mentoring` stays a generic overlay.
10. **Generalization:** build `ws k8s` concrete now; keep only the hook *redirect* layer declarative. Defer a per-tool "guard adapter" schema until 2–3 real tools reveal the common shape.

## Design

### 1. Taxonomy: role / stance / mentoring

Three distinct concepts, three distinct words:

- **role** — what kind of work: `developer` / `designer` / `reviewer` / `scribe`. Unchanged.
- **stance** — how the framework adapts the pace/verbosity: `quick` / `zen` / `flow`. (Formerly "mode".) Mutually exclusive.
- **mentoring** — a teaching overlay, boolean. Composes with any stance and any role. (Formerly the fourth "mode".)

`gdd-quick` / `gdd-zen` / `gdd-flow` become the **stance** skills; their prose changes "mode" → "stance". `gdd-mentoring` stays the mentoring overlay skill. `docs/gdd/roles-and-modes.md` is renamed to `roles-and-stances.md` and rewritten around the three concepts.

**Stance philosophy (illustrative — shapes future stance design, not all built here).** The three stances differ in how they treat ceremony and focus: **zen** sheds ceremony for intense focus *without bypassing* any guardrail; **flow** allows meandering but nudges back toward the core objective (even one that shifts mid-session); **quick** minimizes ceremony for small, rapid interactions. A deliberately-deferred future example that the guard work makes thinkable: **quick** could one day be allowed to *relax* scoped guardrails behind loud, explicit disclaimers — a measured "YOLO-lite" for throwaway work — but that is **not** in this spec and is recorded only to illustrate why stance is its own axis with real behavioral weight.

### 2. Session-config layer

The session file grows from one line to carry the live, per-session values:

```bash
GDD_CO_AUTHOR=Claude Opus 4.8 <noreply@anthropic.com>
GDD_STANCE=flow
GDD_ROLE=developer
GDD_MENTORING=true
GDD_K8S_CONTEXT=kind-practice
GDD_K8S_NAMESPACES=alice-sandbox,shared-dev
```

- **Orient establishes** `GDD_STANCE` / `GDD_ROLE` / `GDD_MENTORING` per session — by asking when unset, or applying a hardcoded baseline (`flow` / `developer` / `false`) when the human wants to move fast. They are no longer read from, or written to, the Thalamus.
- **`ws k8s scope set`** writes `GDD_K8S_CONTEXT` / `GDD_K8S_NAMESPACES`; `scope clear` removes them.
- **`ws_session_set <KEY> <VALUE>` is an atomic read-modify-write.** Because both orient and `ws k8s scope set` mutate the same file, a key write must preserve all other keys: read the existing file, replace-or-append the one key, write to a temp file in the same directory, then `mv` into place (atomic rename) so a concurrent reader never sees a half-written file. `ws_session_get <KEY>` reads a single key as data (never sourced — a `$` or quote in a value is never executed). These generalize the existing `ws_read_identity_file`.
- `ws clean` already spares the live session's file; the new keys ride that protection unchanged.

**`ws clean` hardening.** Routine/default `ws clean` must *never* remove any session file — not just the live one. Pruning ended-session files moves behind an explicit full-system-housekeeping flag (e.g. `ws clean --sessions-all`), so a routine clean can never bowl over a parallel session whose "ended" detection is imperfect (a still-running sibling agent must keep its identity + scope).

Consumers that read mode/role today (orientation, the stance skills) switch to reading the session file. The Thalamus loses its `mode:`/`role:` frontmatter keys entirely (see Migration).

### 3. `ws k8s` — command surface and the shared guard

```text
ws k8s scope set --context <ctx> --namespace <ns>[,<ns>…]   # validate, then write session file
ws k8s scope show                                            # print active scope (or "none")
ws k8s scope clear                                           # remove scope (wheels off)
ws k8s <any kubectl args…>                                   # guarded passthrough
```

`ws k8s scope set` validates the context exists (`kubectl config get-contexts`) and that each requested namespace exists via a **per-namespace** check (`kubectl --context <ctx> get namespace <ns>`, falling back to `auth can-i get namespace/<ns>`). It deliberately does **not** enumerate all namespaces (`get ns`), which requires cluster-wide list permission and would fail under least-privilege RBAC where the practitioner can use a namespace but not list the cluster's.

**The guard is a shared module** — `scripts/ws-k8s-guard.sh`, sourced by both `ws-k8s.sh` and the permission hook. It exposes one pure function, `k8s_guard_evaluate <scope> <command…>`, returning a single verdict so the two callers can never drift:

| Verdict | Meaning |
|---|---|
| `NOT_K8S` | not a kubectl / `ws k8s` invocation |
| `NO_SCOPE` | a scope is not set — plain passthrough |
| `READ_IN_SCOPE` | matching context, a read verb |
| `WRITE_IN_SCOPE` | matching context, a write verb, namespace(s) all in scope |
| `BLOCK:<reason>` | wrong context, out-of-scope/indeterminate write |

Evaluation logic:

1. **Force the context.** When a scope is set the wrapper injects `--context <scoped>`. A conflicting explicit `--context` (≠ scoped) → `BLOCK` (absolute, no override) — you cannot address another cluster through `ws k8s`.
2. **Classify the verb** (first non-flag token): *read* (`get`, `describe`, `logs`, `top`, `explain`, `events`, `api-resources`, `version`, `auth can-i`, `config view`/`get-contexts`/`current-context`, `diff`, `wait`) vs *write* (`apply`, `create`, `delete`, `patch`, `replace`, `edit`, `scale`, `autoscale`, `rollout`, `annotate`, `label`, `set`, `expose`, `run`, `exec`, `cp`, `attach`, `port-forward`, `cordon`/`uncordon`/`drain`/`taint`, `config set-context`/`use-context`/`set`). **Unknown verb → treated as write** (fail-safe). Authoritative lists live in the module.
3. **Reads** → `READ_IN_SCOPE`. `--all-namespaces`/`-A` on a read is fine.
4. **Writes** → resolve every target namespace and require all be in scope:
   - explicit `-n`/`--namespace`, else the scoped context's default namespace (`kubectl config view --minify`, fallback `default`);
   - **`-f` manifests are parsed** (local files, via `yq`): each document's `metadata.namespace` is collected; a namespaced resource with no manifest namespace falls back to `-n`. Any namespace out of scope, or any input the parser can't resolve (remote `-f <URL>`, `-f -`/stdin, a namespaced resource with neither manifest ns nor `-n`) → `BLOCK`;
   - `--all-namespaces` on a write, or a cluster-scoped/indeterminate target → `BLOCK`;
   - otherwise → `WRITE_IN_SCOPE`.

**`ws k8s` enforces** the verdict: `BLOCK` → reject with the reason and "re-run `ws k8s scope set` to widen"; everything else → exec `kubectl` (with the forced `--context` when a scope is set). `NO_SCOPE` is a plain passthrough, so a human can use `ws k8s` everywhere harmlessly.

### 4. Hook integration — scoped redirect, read auto-approve, script scan

The hook calls the same `k8s_guard_evaluate` and acts on the verdict. When a scope is active:

- **Raw `kubectl`** is redirected to `ws k8s` via a new, generic, forward-looking section in [`hook-rules`](../../.claude/hooks/hook-rules) — it fires only when the session key is present, so non-practice sessions see no friction:

  ```text
  [scoped-redirect-commands]
  # slug | pattern | session-key | suggestion   (fires only when session-key is set in the session file)
  k8s | kubectl* | GDD_K8S_CONTEXT | Use `ws k8s <args>` — a practice scope is active; raw kubectl bypasses the namespace guard. `ws hook-bypass k8s` to lift for this session.
  ```

- **`ws k8s` calls** are routed by verdict: `READ_IN_SCOPE` → **auto-approve** (allow, frictionless reads); `BLOCK` → **deny** with the guard reason (cleaner than prompting then having the wrapper reject); `WRITE_IN_SCOPE` / `NO_SCOPE` → fall through to the normal permission flow (an in-scope write still earns a human prompt — a mutation deserves one nod even inside the sandbox). No `Bash(ws k8s:*)` entry is added to the gdd-global allowlist; a machine may still opt in via local additive config.
- **Temp-script scan.** Agents reach for a throwaway script the moment they can't chain commands — the path by which a newcomer drops the prod database. So under an active scope the hook inspects script-execution calls (`bash <file>`, `sh <file>`, `./<file>`, `source <file>`) and, if the referenced local file contains a raw `kubectl` token, **denies** with guidance to use `ws k8s` per command. This is a bounded heuristic (the directly-referenced file only, scope active only), not a parser; deeper obfuscation stays a documented residual (see §8).
- **Composition** is unchanged: chained/complex commands are still hard-denied by the existing Tier-1 composition rules.

The new slug is auto-bypassable via `ws hook-bypass k8s`. The `[scoped-redirect-commands]` section is the *one* deliberately generic seam — where a future second guarded tool plugs in.

### 5. The `gdd-k8s` skill — and how mentoring gets teeth

A new `.agent/skills/gdd-k8s/SKILL.md` owns the practice workflow, so `gdd-mentoring` stays a generic teaching overlay (and the pattern generalizes to future tool-practice skills). Mentoring's "teeth" become: *it is the overlay that recognizes a k8s-practice signal and invokes `gdd-k8s`.* When the mentoring toggle is on and a signal fires ("I want to practice kubectl", "test my cluster access", "I'm nervous about prod"), `gdd-k8s`:

1. explains what is about to happen and why (training wheels, not a security boundary);
2. offers `kubectl config get-contexts` to pick the practice context;
3. offers a per-namespace existence check to confirm the target namespace(s);
4. runs `ws k8s scope set …`;
5. confirms the guard is armed and explains the behavior: reads flow freely and auto-approve, writes prompt and must stay in-scope, raw `kubectl` and kubectl-bearing scripts are redirected/blocked, and how to widen (`scope set` again), take the wheels off (`scope clear`), or lift the redirect (`ws hook-bypass k8s`).

Any stance can invoke `gdd-k8s`; mentoring is just the overlay most likely to, and the one that narrates each step.

## Migration (direct, one-pass, pre-GA)

Two users total, pre-GA — so migrate everything in one pass, no compatibility machinery:

- **Docs:** rename `docs/gdd/roles-and-modes.md` → `roles-and-stances.md`; rewrite around role/stance/mentoring. Sweep `docs/gdd/skills-reference.md`, `docs/gdd/thalamus.md`, `docs/gdd/index.md`, and the GA-readiness doc (its B5 "mentoring-mode refresh" item is subsumed here).
- **Skills:** `.agent/skills/gdd-orientation` (frontmatter-read → session-file read; mode→stance language; the mentoring/`gdd-k8s` offer), `gdd`, `gdd-quick`/`gdd-zen`/`gdd-flow` (now stance skills), `gdd-mentoring` (overlay; invokes `gdd-k8s`), the new `gdd-k8s` skill, and any other skill referencing "mode"/"role" prose. Realm skills swept too.
- **Templates:** remove `mode:`/`role:` from `templates/thalamus.md` frontmatter; document that stance/role/mentoring are now session-established.
- **Scripts:** extend `ws-session.sh` (atomic get/set), add `ws-k8s.sh` + `ws-k8s-guard.sh` + dispatch arm + help line + permission-tier entries per the CLI guide, teach orientation to establish session stance/role/mentoring, add the hook's `[scoped-redirect-commands]` arm, the guard-verdict routing, and the temp-script scan.
- **Live thalami:** a single direct edit across every `*-thalamus.md` in this hoard now (strip the retired `mode:`/`role:` keys); the one coworker updates his single Thalamus file by hand. **No hoard-template version bump and no transitional `mode:`-as-`stance` fallback** — change everything everywhere at once.

## Testing

- **Shared guard (`ws-k8s-guard.sh`)** — unit tests on `k8s_guard_evaluate` covering every verdict: `NOT_K8S`, `NO_SCOPE` passthrough, `READ_IN_SCOPE`, `WRITE_IN_SCOPE`, conflicting-`--context` `BLOCK`, out-of-scope-`-n` `BLOCK`, `--all-namespaces` write `BLOCK`, unknown-verb-as-write, default-namespace resolution, and `-f` manifest parsing (in-scope manifest allowed; out-of-scope manifest blocked; remote/stdin/indeterminate blocked).
- **`ws k8s` enforcement** — against a **stubbed `kubectl`** (resolved via an overridable command/env var, no real cluster): forced-context injection, block messaging, passthrough when no scope.
- **Hook** — payload tests: `kubectl*` redirect fires only with `GDD_K8S_CONTEXT` set; `ws k8s` read auto-approves; `ws k8s` `BLOCK` denies; in-scope write falls through; a `bash script.sh` containing `kubectl` is denied under scope and ignored without scope; `ws hook-bypass k8s` lifts the redirect.
- **Session layer** — `ws_session_set` preserves sibling keys (merge write) and is atomic; values read as data; orient establishes stance/role/mentoring.
- **Real-world dogfood** — the author plus a coworker, both with live k8s skills and a real cluster, run a mentoring practice end-to-end.

## Non-goals & framing

- **This is accident-prevention, not a security boundary.** It closes the *reflexive* bypasses (raw `kubectl`, a kubectl-bearing temp script, an out-of-scope `-f` manifest), which is what stops a nervous newcomer's honest mistake. It does **not** withstand a determined adversary: obfuscated/dynamic kubectl (base64, full binary path, a script that builds the command at runtime), `ws hook-bypass k8s`, or invoking kubectl entirely outside the harness all remain possible. Real authorization stays server-side (RBAC); the wrapper help and the `gdd-k8s` skill say so plainly.
- Out of scope: a general per-tool "guard adapter" schema (deferred — see Future work); guarded wrappers for other dangerous tools (terraform/aws/gcloud); cross-session persistence of the practice scope; deep static analysis of arbitrary scripts beyond the single-file raw-`kubectl` scan; the broader Phase-3 allowlist-flavor framework beyond this k8s slice; the future "quick stance relaxes guardrails" idea (illustrative only, §1).

## Future work

- **Guard adapters.** Once a second or third dangerous tool wants training wheels, extract the common shape (modeled on the existing component-adapter pattern) into a declarative per-tool guard config. The `[scoped-redirect-commands]` section and `ws-k8s-guard.sh`'s verdict interface are the seams it grows from. Deliberately *not* designed from the single kubectl example here.
- **Session-config Phase 3.** Allowlist "flavors" keyed to session stance/mentoring, per the multi-agent-attribution roadmap §160.
- **Declarative label taxonomy + repo-config reconcile.** A separate captured idea (thalami Intake, 2026-06-25): realm-config-driven org-wide label sets, bodyfile-declared labels for `ws cr`/`issue`, a per-session label audit, and a human-run sync script mirroring `setup-branch-protection.sh` — its own brainstorm → spec.
