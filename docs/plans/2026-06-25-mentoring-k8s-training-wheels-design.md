# Mentoring Training Wheels — stances, session-scoped config, and a guarded `ws k8s`

Status: Design (brainstormed, pre-plan). Date: 2026-06-25. Arc: `multi-agent-attribution` (Phase 2 + a slice of Phase 3). Supersedes the roadmap tails in [`2026-06-15-multi-agent-attribution-design.md`](2026-06-15-multi-agent-attribution-design.md) §159–160 for the work it covers.

## Motivation

Asking for "the mentor role" in GDD today does almost nothing concrete: it loads [`.agent/skills/gdd-mentoring/SKILL.md`](../../.agent/skills/gdd-mentoring/SKILL.md), which is prose-only — a behavior modifier with no tooling, the thinnest of the four mode skills. The idea here is to give mentoring *teeth*: when a newcomer is handed daunting access to a real cluster, a mentoring session should capture a small practice scope (a kube context + allowed namespaces) and then hard-wire a guard around `kubectl` so accidental commands against the wrong cluster or namespace are blocked — training wheels that come off deliberately, not by reflex.

This is the concrete payoff that motivates two pieces of plumbing the GDD GA roadmap already anticipated: moving per-session concerns out of workspace-global Thalamus frontmatter (Phase 2), and arming tool guards keyed to that session config (Phase 3). It also resolves a long-standing taxonomy muddle — mentoring is not the same *kind* of thing as quick/zen/flow.

## Background — what exists today

- **Roles vs modes.** [`docs/gdd/roles-and-modes.md`](../gdd/roles-and-modes.md) splits *roles* (developer/designer/reviewer/scribe — what kind of work) from *modes* (mentoring/quick/zen/flow — how the framework adapts). Only Scribe has a real role skill with tooling; the rest are assumed defaults.
- **Mentoring is mis-bucketed.** Quick/zen/flow are mutually-exclusive *tempos* — you are in exactly one. Mentoring *composes* with them (the orientation and mode skills speak of "mentoring + quick", "mentoring + zen"). The "four modes" framing lumps one teaching overlay together with three tempos, which is why "mentor role" feels natural to say.
- **Mode/role storage.** Both live in per-machine Thalamus YAML frontmatter ([`templates/thalamus.md`](../../templates/thalamus.md) keys `mode:`/`role:`), read at session start by [`.agent/skills/gdd-orientation/SKILL.md`](../../.agent/skills/gdd-orientation/SKILL.md) (§"Parse Thalamus frontmatter"). This is workspace-global state — it clashes between parallel sessions (e.g. an open Scribe session shouldn't force the whole workspace to Scribe while other work runs).
- **The session file (Phase 1, shipped — PR #103).** [`2026-06-15-multi-agent-attribution-design.md`](2026-06-15-multi-agent-attribution-design.md) introduced a per-session file `.tmp/gdd-agent-sessions/<session-id>.env`, keyed by session id (`GDD_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` > `CODEX_THREAD_ID`), established fresh at every `ws orient`. It currently carries one line, `GDD_CO_AUTHOR=…`, and is read as data (not sourced) by [`scripts/ws-session.sh`](../../scripts/ws-session.sh). Its format is deliberately extensible; Phase 2/3 were explicitly deferred to "their own brainstorm → spec." This doc is that brainstorm.
- **The hook.** [`.claude/hooks/gdd-permission-hook.sh`](../../.claude/hooks/gdd-permission-hook.sh) intercepts Bash/PowerShell tool calls. Its redirect rules are *data*, parsed from [`.claude/hooks/hook-rules`](../../.claude/hooks/hook-rules) sections (`[redirect-commands]` etc.). It already resolves the session id and reads per-session markers under `.tmp/hook-bypass/<slug>.bypass` (written by `ws-hook-bypass.sh`). It does **not** read the Thalamus.
- **`ws` dispatch.** [`scripts/ws`](../../scripts/ws) is a single dispatcher: a `case` routes each subcommand either to a sibling `ws-<name>.sh` or to an in-file `ws_<name>` function. Adding a subcommand is documented in [`docs/ws-cli-guide.md`](../../docs/ws-cli-guide.md). No kubectl/k8s wrapper exists anywhere today — `ws k8s` is greenfield.

## Decisions (brainstorm outcomes)

1. **Scope:** one combined, k8s-driven spec — the session-config move is pulled in only as far as this feature needs, with `ws k8s` + the hook redirect as the vertical slice that proves the whole idea.
2. **Taxonomy:** rename the *mode* axis to **stance** (quick/zen/flow); make **mentoring** a separate composable boolean overlay; keep **role**. Be exhaustive about reworking every old `mode`/`role` reference pre-GA.
3. **Storage:** stance/role/mentoring move into the session file and are established fresh each session. They are **retired entirely** from Thalamus frontmatter — no per-machine default (what work happens where moves around; re-asking per session is the honest default).
4. **Guard strictness:** out-of-scope namespace on a write → **hard block**; widen only by deliberately re-running `ws k8s scope set`. A wrong *context* is an **absolute** block with no override.
5. **Hook breadth:** raw `kubectl` redirects to `ws k8s` **only when a practice scope is active** for the session (keyed on scope-present, not on the mentoring toggle).
6. **Read/write split:** on a matching context, **reads are allowed anywhere**; **writes** must target an in-scope namespace. "Look anywhere on the right cluster, change only your sandbox."
7. **Generalization:** build `ws k8s` concrete now; keep only the hook *redirect* layer declarative. Defer a per-tool "guard adapter" schema until 2–3 real tools reveal the common shape.

## Design

### 1. Taxonomy: role / stance / mentoring

Three distinct concepts, three distinct words:

- **role** — what kind of work: `developer` / `designer` / `reviewer` / `scribe`. Unchanged.
- **stance** — how the framework adapts the pace/verbosity: `quick` / `zen` / `flow`. (Formerly "mode".) Mutually exclusive.
- **mentoring** — a teaching overlay, boolean. Composes with any stance and any role. (Formerly the fourth "mode".)

`gdd-quick` / `gdd-zen` / `gdd-flow` become the **stance** skills; their prose changes "mode" → "stance". `gdd-mentoring` stays the mentoring overlay skill and gains the tool-driven workflow in §5. `docs/gdd/roles-and-modes.md` is renamed to `roles-and-stances.md` and rewritten around the three concepts.

### 2. Session-config layer

The session file grows from one line to carry the live, per-session values:

```
GDD_CO_AUTHOR=Claude Opus 4.8 <noreply@anthropic.com>
GDD_STANCE=flow
GDD_ROLE=developer
GDD_MENTORING=true
GDD_K8S_CONTEXT=kind-practice
GDD_K8S_NAMESPACES=alice-sandbox,shared-dev
```

- **Orient establishes** `GDD_STANCE` / `GDD_ROLE` / `GDD_MENTORING` per session — by asking when unset, or applying a hardcoded baseline (`flow` / `developer` / `false`) when the human wants to move fast. They are no longer read from, or written to, the Thalamus.
- **`ws k8s scope set`** writes `GDD_K8S_CONTEXT` / `GDD_K8S_NAMESPACES`; `scope clear` removes them.
- All keys are read as data via the existing `ws-session.sh` helpers (extend `ws_read_identity_file` into a general `ws_session_get <KEY>` / `ws_session_set <KEY> <VALUE>`; the file stays parse-as-data, never sourced).
- `ws clean` already spares the live session's file; the new keys ride that protection unchanged.

Consumers that read mode/role today (orientation, the stance/mentoring skills) switch to reading the session file. The Thalamus loses its `mode:`/`role:` frontmatter keys entirely (see Migration).

### 3. `ws k8s` — command surface and guard

```
ws k8s scope set --context <ctx> --namespace <ns>[,<ns>…]   # validate, then write session file
ws k8s scope show                                            # print active scope (or "none")
ws k8s scope clear                                           # remove scope (wheels off)
ws k8s <any kubectl args…>                                   # guarded passthrough
```

`ws k8s scope set` validates the context exists (`kubectl config get-contexts`) and each namespace exists on that context (`kubectl --context <ctx> get ns`) before writing, so a typo fails loudly at setup rather than silently blocking every later command.

**Guard algorithm** for the passthrough:

1. **No scope set** → exec `kubectl "$@"` unchanged. `ws k8s` is then just a thin wrapper a human can use everywhere harmlessly.
2. **Scope set:**
   1. **Force the context.** The wrapper injects `--context <scoped>` into the kubectl invocation. If the args already carry a conflicting `--context` (≠ scoped) → **hard block, no override** — you cannot address another cluster through `ws k8s`.
   2. **Classify the verb** (first non-flag token): *read* (`get`, `describe`, `logs`, `top`, `explain`, `events`, `api-resources`, `version`, `auth can-i`, `config view`/`get-contexts`/`current-context`, `diff`, `wait`) vs *write* (`apply`, `create`, `delete`, `patch`, `replace`, `edit`, `scale`, `autoscale`, `rollout`, `annotate`, `label`, `set`, `expose`, `run`, `exec`, `cp`, `attach`, `port-forward`, `cordon`/`uncordon`/`drain`/`taint`, `config set-context`/`use-context`/`set`). **Unknown verb → treated as write** (fail-safe). The authoritative lists live in the implementation.
   3. **Reads** → allowed (the context is already pinned). `--all-namespaces`/`-A` on a read is allowed.
   4. **Writes** → resolve the target namespace: explicit `-n`/`--namespace`, else the scoped context's default namespace (`kubectl config view --minify` for that context, falling back to `default`). If the resolved namespace is in `GDD_K8S_NAMESPACES` → allow. Otherwise — out-of-scope, `--all-namespaces`, or a cluster-scoped / namespace-indeterminate write → **hard block** with: *"namespace `<x>` is outside your practice scope (`<list>`); re-run `ws k8s scope set` to widen."*

**Known v1 limitation (documented, not fixed):** namespaces embedded in manifests (`apply -f`) are not parsed — the guard enforces on the command-line namespace only. Acceptable for a sandbox practice; noted in the wrapper's help and in §8.

### 4. Scoped hook redirect

Raw `kubectl` must redirect to `ws k8s`, but **only when a scope is active** — experienced, non-practice sessions should see no kubectl friction. Today's `[redirect-commands]` fire unconditionally, so we add a small, generic, forward-looking section to [`hook-rules`](../../.claude/hooks/hook-rules):

```
[scoped-redirect-commands]
# slug | pattern | session-key | suggestion   (fires only when session-key is set in the session file)
k8s | kubectl* | GDD_K8S_CONTEXT | Use `ws k8s <args>` — a practice scope is active; raw kubectl bypasses the namespace guard. `ws hook-bypass k8s` to lift for this session.
```

The hook gains a parser arm for this section and, before denying, checks the resolved session file for `session-key`. It already resolves the session id and reads `.tmp/` markers, so this reuses existing machinery. The slug is auto-bypassable via `ws hook-bypass k8s` (the generic bypass path). This section is the *one* deliberately generic seam — it is the natural place a future second guarded tool plugs in.

### 5. Mentoring gets teeth — the scope-capture flow

[`gdd-mentoring/SKILL.md`](../../.agent/skills/gdd-mentoring/SKILL.md) gains its first tool-driven workflow. When the mentoring overlay is on and a k8s-practice signal fires ("I want to practice kubectl", "test my cluster access", "I'm nervous about prod"), the skill:

1. explains what is about to happen and why (training wheels, not a security boundary);
2. offers `kubectl config get-contexts` and helps the human pick the practice context;
3. offers `kubectl --context <ctx> get ns` and helps pick the target namespace(s);
4. runs `ws k8s scope set --context … --namespace …`;
5. confirms the guard is armed, and explains that raw `kubectl` will now be redirected to `ws k8s` and out-of-scope writes blocked — including how to widen (`scope set` again) and how to take the wheels off (`scope clear`, or `ws hook-bypass k8s`).

This mirrors how Scribe is the one role today with real tooling: mentoring stops being prose-only and becomes a concrete, teachable safety workflow.

## Migration plan (exhaustive, one-time, pre-GA)

The taxonomy rename touches *prose/concept* references (no lingering config schema, since stance/role are retired from frontmatter):

- **Docs:** rename `docs/gdd/roles-and-modes.md` → `roles-and-stances.md`; rewrite around role/stance/mentoring. Sweep `docs/gdd/skills-reference.md`, `docs/gdd/thalamus.md`, `docs/gdd/index.md`, and the GA-readiness doc (its B5 "mentoring-mode refresh" item is subsumed here).
- **Skills:** `.agent/skills/gdd-orientation` (frontmatter-read → session-file read; mode→stance language; mentoring offer), `gdd`, `gdd-quick`/`gdd-zen`/`gdd-flow` (now stance skills), `gdd-mentoring` (overlay + new flow), and any other skill referencing "mode"/"role" prose. Realm skills under `realms/*/.agent/skills/` swept too.
- **Templates:** remove `mode:`/`role:` from `templates/thalamus.md` frontmatter; document that stance/role/mentoring are now session-established.
- **Scripts:** extend `ws-session.sh` (generic get/set), add `ws-k8s.sh` + dispatch arm + help line + permission-tier entries per the CLI guide, teach `ws-orient.sh`/orientation to establish session stance/role/mentoring, add the hook's `[scoped-redirect-commands]` arm.
- **Live thalami hoard files** (which carry `mode:`/`role:` today) migrate via a **hoard template v3 upgrade** — the thalami hoard is already versioned (`.hoard.yaml applied_version: 2`) and the `gdd-hoard-upgrade` skill exists for exactly this. The upgrade strips the retired keys.
- **Transition safety:** during the upgrade window, orientation honors a legacy `mode:` as `stance` if `GDD_STANCE` is unset, so a not-yet-upgraded machine still behaves. Removed once upgrades land.

## Testing

- **`ws k8s` guard** — bash tests against a **stubbed `kubectl`** (resolved via an overridable command/env var so no real cluster is needed). Cases: no-scope passthrough; context force-injection; conflicting `--context` block; read allowed anywhere; write in-scope allowed; write out-of-scope blocked; `--all-namespaces` write blocked; unknown verb treated as write; default-namespace resolution for write with no `-n`.
- **Scoped hook redirect** — payload tests asserting the `kubectl*` redirect fires only when `GDD_K8S_CONTEXT` is present in the session file, and that `ws hook-bypass k8s` lifts it.
- **Session layer** — `ws_session_get`/`set` round-trips; orient establishes stance/role/mentoring; values are read-as-data (a `$`/quote in a value is never executed).
- **Real-world dogfood** — the author plus a coworker, both with live k8s skills and a real cluster, run a mentoring practice end-to-end.

## Non-goals & framing

- **This is accident-prevention, not a security boundary.** A determined agent or human can bypass it (`ws hook-bypass k8s`, or invoking `kubectl` outside the harness). It is training wheels, not RBAC; the wrapper's help and the mentoring flow say so plainly. Real authorization stays server-side.
- Out of scope: a general per-tool "guard adapter" schema (deferred — see Future work); guarded wrappers for other dangerous tools (terraform/aws/gcloud); cross-session persistence of the practice scope; deep parsing of manifest-embedded namespaces; the broader Phase-3 allowlist-flavor framework beyond this k8s slice.

## Future work

- **Guard adapters.** Once a second or third dangerous tool wants training wheels, extract the common shape (modeled on the existing component-adapter pattern) into a declarative per-tool guard config. The `[scoped-redirect-commands]` section is the seam it grows from. Deliberately *not* designed from the single kubectl example here.
- **Session-config Phase 3.** Allowlist "flavors" keyed to session stance/mentoring, per the multi-agent-attribution roadmap §160.
