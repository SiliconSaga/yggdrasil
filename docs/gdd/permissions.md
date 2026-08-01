# GDD Permissions Reference

How `.claude/settings.json` works in a GDD workspace, what makes a pattern safe, and how to verify the safety claims for yourself.

This doc is the source of truth for the permission system's behavior and the empirical findings it relies on. The `gdd-permissions` skill (`.agent/skills/gdd-permissions/`) is the operational companion — agents invoke it for live decisions; this doc is what they (and humans, and automated review tools) read for reference.

---

## What `.claude/settings.json` is and how it loads

Claude Code reads two settings files for each workspace:

- **`.claude/settings.json`** — project-level, committed to the repo. Shared across everyone working in the workspace.
- **`.claude/settings.local.json`** — per-user, gitignored. Not shared.

Both are merged at startup. Where they conflict on a single key, local wins. The relevant top-level structure is:

```json
{
  "permissions": {
    "allow": [ "Bash(...)", "..." ],
    "deny":  [ "Bash(...)", "..." ]
  }
}
```

`permissions.allow` and `permissions.deny` are lists of pattern strings. A command is checked against `deny` first; if it matches, it's blocked regardless of `allow`. Otherwise, if it matches any `allow`, it's auto-approved. Otherwise the user is prompted.

### Managed-config layer (corporate / enterprise environments)

Some environments layer additional permission rules on top of the workspace's `.claude/settings.json` via enterprise managed config — typically pushed via the OS-level managed-preferences mechanism (MDM, Group Policy, etc.) and sitting at the top of the precedence stack. These overrides can change which rules apply in either direction: auto-approving things the workspace would prompt on, or forcing prompts on things it would auto-approve.

If you see a permission behavior that doesn't match what `.claude/settings.json` declares — same workspace, same git tree, different outcome between machines — suspect a managed config in your environment.

### Claude Hook Options

The hook script at `.claude/hooks/gdd-permission-hook.sh` encourages the agent toward good practices with the GDD `ws` CLI and clearer, shorter commands that are easier for a human to digest. It blocks chained commands and some kinds of redirection, forcing the agent into friendlier, more auditable variants.

The hook produces three possible decisions for a Bash command:

- **deny** — shell composition or other forbidden patterns. The command is blocked and the agent receives a corrective message.
- **ask** — the command matches the `[ask-commands]` glob list in `hook-rules` (or `hook-rules.local`). The hook emits `permissionDecision: "ask"`, forcing a human-facing permission prompt regardless of the session permission mode. This overrides `acceptEdits` and `bypassPermissions` — the prompt always surfaces. The command is NOT blocked; once the human approves, it runs normally. Destructive commands like `rm -rf` and `git reset --hard` live here, as do arbitrary-execution escape hatches like `ws exec`.
- **allow** — the command matches a `permissions.allow` pattern in `settings.json` (Tier 5) or an `[allow-extras]` glob in `hook-rules.local` (Tier 6). It proceeds without a prompt.

A secondary effect: the hook can re-map GDD's "auto-approve this declared-safe pattern" behavior on machines where other config causes conflicts — safer than giant multi-line monster commands a human is likely to button-mash through if overly repeated.

See [`.claude/hooks/README.md`](../../.claude/hooks/README.md) for the full hook spec — including an optional extension some workspaces may enable in `settings.local.json` to suppress prompts for writes into `Workspace-local scratch` directories, and a `hook-rules.local` for simple trusted patterns on specific machines when combined with GDD's chain blocking.

`hook-rules` patterns are Bash globs matched against the hook's normalized command string, not Claude Code `Bash(...)` matcher entries. For example, the committed ask-list entry `ws exec *` matches `ws exec yggdrasil git status` and `ws exec yggdrasil printf %s a b c d e f g h` alike, because the `*` spans the remaining command tail. The hook also normalizes `bash scripts/ws exec ...` to `ws exec ...` before this match, so one bare pattern covers both invocation styles — distinct from the spaced `*` forms in `.claude/settings.json`, which are Claude matcher syntax documented under [Pattern shapes](#pattern-shapes).

### Kubernetes write safety floor

Kubernetes operation classification is independent of whether a `GDD_K8S_CONTEXT` scope exists. An unscoped read passes to normal routing; an unscoped write emits Claude's `ask` decision before `settings.json` and `hook-rules.local` allowances are consulted, so even an accidental blanket `Bash(kubectl:*)` entry cannot silently approve a write. When a scope is armed, the stronger context-and-namespace redirect policy applies. Local `-k` and `--kustomize` directories are rendered and every resulting resource is checked; an unreadable or unsuccessful render fails closed.

The Codex bridge maps the same platform-neutral classification differently because its focused `PreToolUse` policy supports deny-or-defer rather than Claude's force-ask decision: unscoped writes are denied with guidance to arm a scope or explicitly authorize the audited session bypass. This remains an accident-prevention layer, not an authorization boundary; server-side RBAC is authoritative.

### Redirect tier and bypass

Tier 2 of the PreToolUse hook denies a curated list of raw commands (`git commit`, `git push`, `gh pr create`, `git mv`) with a corrective message pointing at the friendlier equivalent — a training layer, not a safety floor. The session-scoped escape hatch is `ws hook-bypass <slug>`, itself ask-gated so every bypass force-prompts the human. Mechanics and the full redirect list: [`.claude/hooks/README.md`](../../.claude/hooks/README.md) § Redirect tier and bypass; human-facing walkthrough: [Agent Training](agent-training.md#what-happens-when-you-reach-for-git-commit--git-push--gh-pr-create).

Codex consumes the same `[redirect-commands]` rows through a focused deny-or-defer bridge. A match returns the same `ws` guidance. A valid session-scoped bypass removes the redirect decision but does not auto-allow the command; Codex still applies its sandbox, network, and approval routing.

### `ws commit` flags auto-approve

`ws commit`, `ws whoami`, `ws test`, and `ws lint` are allowlisted by default in this workspace's `.claude/settings.json`. The `ws commit` allow patterns are:

```text
Bash(ws commit:*)
Bash(bash scripts/ws commit:*)
```

The `:*` suffix here is Claude Code's *prefix* form — it matches the command plus any argument tail, not a single argument slot (see [Pattern shapes → Colon-prefix](#colon-prefix-cmd) below). Both the `ws commit` and `bash scripts/ws commit` bare forms are listed because the prefix match is anchored at the start of the string, so neither covers the other dispatch form; listing both keeps the command auto-approving under Claude Code's native matcher too — i.e. when the hook is disabled or passes through and only the literal settings patterns apply.

Because the patterns are start-anchored *prefixes*, every `ws commit` flag — `--dry-run`, `--human`, `--co-author-file <name>` — auto-approves with no extra entry. The sub-agent attribution path `ws commit --co-author-file <name> …` passes only a bare file name (no env-assignment prefix, no angle brackets), so it clears the Tier 1 redirect check and matches `Bash(ws commit:*)` directly. There is no env-prefix stripping: an env-assignment prefix (`LD_PRELOAD=…`, or any `VAR=…`) stays in the match string and fails every allow glob, so it cannot auto-approve. See [`ws commit` attribution in the CLI guide](../ws-cli-guide.md#ws-commit) for the resolution rules.

#### `ws test` / `ws lint` under the realm trust model

`ws test` and `ws lint` run adapter-defined commands (the component's own test/lint runner, resolved through the active realm's adapter). They're allowlisted under the **realm trust model**: trust is established when a realm is scanned and activated, and surfaced to the agent at session start by [`ws orient`](../ws-cli-guide.md#ws-orient) — NOT by withholding the allowlist. Treating adapter-defined runners as trusted-once-activated is the same posture as the rest of the realm's declared commands.

The trust is kept honest by `gdd-orientation`'s **adapter command risk scan** — on realm activation, the skill reads every `realms/<r>/adapters/*.yaml`'s `commands.{test,lint,build}` and flags `curl | sh`, `wget | sh`, base64 decode-execute, writes outside the component dir, outbound network in test/lint, or `eval`. Provenance scales rigor: light for your own / team realms, heavy for community / wild realms. See [Trust and Safety § Adapter Command Trust](trust-and-safety.md#adapter-command-trust).

#### Tier 3 adapter-redirect (allow-with-nudge / deny-with-bypass)

The PreToolUse hook has a separate **Tier 3 adapter-redirect** for raw test/lint runners (`pytest`, `python -m pytest`, `gradle test`, `ruff`, `black`, `mypy` — see `.claude/hooks/hook-rules` `[adapter-redirect-commands]`). When the raw command matches a pattern AND `$cwd` resolves to a component under `components/<comp>/`:

- **Wired** (`realms/<r>/adapters/<comp>.yaml` has `commands.<verb>`): hook denies with `Use \`ws <verb> <comp>\`` plus a `ws hook-bypass <slug>` pointer, reusing the existing bypass-marker machinery — every bypass creation force-prompts the human via the ask-tier.
- **Unwired** (adapter file missing OR no `commands.<verb>`): hook emits a one-line stderr nudge (`↪ No \`ws test\` adapter for <comp> yet. Wire one at realms/<r>/adapters/<comp>.yaml…`) and falls through to normal allow/ask evaluation. The raw command runs; the nudge is the audit-log breadcrumb.
- **Outside a component dir** OR **bare `components/` root**: rule doesn't fire. Raw `pytest` at the workspace root is legitimate (workspace-level test runs); the resolver rejects the bare-components edge case to avoid blank-component nudges.

Tier 3 is a separate classification from Tier 2 ([redirect-commands]) because the unwired-adapter state is a legitimate intermediate — conflating would either over-deny (force every component to wire an adapter first) or under-deny (defeat the wrapper-first reflex contract).

### Hook-owned Git reads

Read-only Git inspection with `git -C <path> ...` cannot be represented safely by a static `Bash(git -C * ...)` permission: the middle wildcard can absorb both path and command tokens. The hook instead parses the command positionally and allows only `show`, `grep`, `log`, `diff`, `ls-tree`, and `rev-parse`, plus the exact read forms of `status`, `remote -v`, and `branch --show-current`. The target must resolve physically to the workspace root or an immediate component declared by root or operator-local ecosystem configuration. Traversal, external repositories, realm-only or hoard targets, mutating shapes, pathname-expansion metacharacters in any token, and execution-capable modifiers such as `--ext-diff` and `--textconv` fall through or deny.

The same narrow parser runs before the general `ws exec *` ask rule for `ws exec <target> git ...`, preserving the wrapper-first workflow for validated root and component reads. A same-named realm or hoard disables the component exception because the current resolver gives those target kinds precedence. Other `ws exec` commands still prompt.

## Pattern shapes

Four shapes appear in this workspace's `.claude/settings.json`:

### Exact-form

```text
Bash(ws status)
Bash(ws status --verbose)
Bash(ws mcp-status)
```

The literal string after the command name must match exactly. A command of `ws status --verbose` does not match `Bash(ws status)`; it needs its own entry or an intentionally broader form. Non-matches produce a permission prompt.

### Prefix wildcards

```text
Bash(bash scripts/ws clone *)
Bash(bash tests/vendor/bats-core/bin/bats tests/*)
```

Each `*` is a wildcard slot; the matcher binds each slot to a single argument-shaped sequence. The space before `*` matters: `Bash(foo*)` without the space matches `foo` followed by anything (including `foobar`); `Bash(foo *)` requires a space, then any single argument. For prefix matching of arguments, always include the space.

### Colon-prefix (`cmd:*`)

```text
Bash(ws commit:*)
Bash(ws test:*)
Bash(bash scripts/ws commit:*)
```

The `:*` suffix is Claude Code's *prefix* form: the rule matches the literal text before the `:` followed by **anything at all** — any number of arguments, spaces included — in a single entry. `Bash(ws test:*)` matches `ws test`, `ws test knarr`, and `ws test knarr -k foo --verbose` alike. This differs from the spaced `*` wildcard above, where each `*` binds exactly one argument-shaped token (so `Bash(ws test *)` matches only `ws test <one-arg>`, and covering two args needs `Bash(ws test * *)`). Because the prefix match is anchored at the start of the command string, each dispatch form needs its own entry — `Bash(ws test:*)` does not cover `bash scripts/ws test …`, hence the separate `Bash(bash scripts/ws test:*)`. Reach for `:*` on always-trusted subcommands where any argument tail is safe; use the tighter spaced-`*` or exact forms to bound *which* arguments are allowed (e.g. a subcommand with a mutating flag-form).

A third option covers subcommands that are mostly read-only with a few side-effect forms: grant the broad `:*` allow and pin the side-effect forms on the hook's `[ask-commands]` list, which evaluates BEFORE the allow tier. `ws review` is the worked example — reads are frictionless under `Bash(ws review:*)`, while `reply` (posts to the PR) and `threads … --resolve*` (mutates thread state) force a human prompt via the committed ask entries. This gate lives in the hook: with the hook disabled, only the settings allowlist applies and the side-effect forms would auto-approve.

### MCP tool names

```text
mcp__slack__slack_read_thread
mcp__github__list_pull_requests
```

Full tool names, no wildcard. MCP names are already specific enough.

---

## The two-layer defense

Every allow pattern in `.claude/settings.json` should be safe even if a single layer fails. We rely on two:

### Layer 1: subcommand-level

The chosen subcommand for each static pattern is read-only or constrained by an earlier hook tier. Path-sensitive Git reads are not static patterns: the hook validates their target, effective subcommand, and execution-capable modifiers before allowing them. Commands with mutating flag-forms stay exact or prompt.

### Layer 2: matcher-level

The matcher scopes wildcards correctly:

- **Compound commands** (`|`, `&&`, `||`, `;`) are denied by Tier 1 before any allow pattern or Git-read fast path is considered.
- **Command substitution** (`$(...)` and backticks) is denied before matching. `git -C $(echo .) show HEAD --stat` cannot reach the read fast path.
- **Exact-form pinning is literal.** `git -C . branch --list` does not match the hook-owned `branch --show-current` read shape.
- **Stdout-redirect-to-file (`> file`, `>> file`) prompts regardless of the LHS.** Even when the producing command is read-only and individually auto-allowed, the redirect-to-file is treated as a side-effect operation because the destination path is opaque to static analysis (could be `/tmp/foo`, `~/.bashrc`, `/etc/...`). The right design path for "save output for later grep" is a wrapper-side `--output <phrase>` flag validating the destination against a workspace-internal scratch dir like `.outputs/` — see `ws review --output` for the reference implementation.

Both layers must hold. If either Claude Code's matcher behavior or the hook's normalization and tier ordering changes, a formerly safe pattern can become unsafe. Regression tests therefore cover close-but-not-quite command shapes as well as positive matches.

---

## Empirical matcher findings

Verified in interactive testing. Each row is a (pattern, attempted command, expected outcome) triple:

| Pattern | Command | Expected outcome | Notes |
|---------|---------|------------------|-------|
| Hook Git-read fast path | `git -C . show HEAD --stat` | Allowed without prompt | Physical target and read subcommand validated by the hook |
| Hook Git-read fast path | `git -C components/undeclared show HEAD` | Prompted | Target is not a root/operator-declared component |
| Hook Git-read fast path | `git -C . diff --textconv HEAD` | Denied | Text conversion can execute a configured filter |
| Hook Git-read fast path | `git -C . branch --list` | Prompted | Only `branch --show-current` is a read-approved shape |
| Hook `ws exec` Git-read fast path | `ws exec yggdrasil git status` | Allowed without prompt | Narrow exception to the general `ws exec *` ask rule |
| `Bash(ws hoard cadence)` | `ws hoard cadence` | Allowed without prompt | Exact-form for the cadence reporter |
| `Bash(ws hoard cadence)` | `ws hoard cadence --debug` | Prompted | Exact-form pinning — extra arg doesn't match |
| `Bash(ws hoard thalamus-path)` | `ws hoard thalamus-path` | Allowed without prompt | Exact-form for path resolution |
| `Bash(ws preflight)` | `ws preflight` | Allowed without prompt | Exact-form for the bare prereq check |
| `Bash(ws preflight --soft)` | `ws preflight --soft` | Allowed without prompt | Exact-form for the soft-exit variant |
| `Bash(ws preflight)` | `ws preflight --json` | Prompted | Hypothetical flag not allowlisted; exact-form pinning honored |
| `Bash(ws orient)` | `ws orient` | Allowed without prompt | Exact-form for the MUST-run session-start discovery probe (read-only) |
| `Bash(ws orient)` | `ws orient --json` | Prompted | Exact-form pinning — a hypothetical flag isn't covered |
| `Bash(ws audit-permissions)` | `ws audit-permissions` | Allowed without prompt | Exact-form for the startup permission-breadth audit (read-only; exit code = finding count) |
| `Bash(ws audit-permissions)` | `ws audit-permissions --verbose` | Prompted | Exact-form — an extra arg doesn't match |
| `Bash(ws review:*)` | `ws review yggdrasil 52 > /tmp/r.txt` | Prompted | Stdout redirect treated as side-effect regardless of LHS — destination opaque to static analysis |
| `Bash(ws review:*)` | `ws review yggdrasil 52 --output snap` | Allowed without prompt | Colon-prefix covers the wrapper-side `--output <phrase>` form, which validates destination is under `.outputs/` — bounded blast radius |
| `Bash(ws review:*)` | `ws review yggdrasil 94 --compact` | Allowed without prompt | Read-only triage is frictionless under the colon-prefix form |
| `Bash(ws review:*)` + ask `ws review * reply *` | `ws review yggdrasil reply 94 <id> "msg" --resolve` | Prompted (ask) | The hook's ask-tier runs BEFORE the settings-allow tier — outward-facing reply/resolve stays human-gated despite the broad allow |
| `Bash(ws review:*)` + ask `ws review * threads * --resolve*` | `ws review yggdrasil threads 94 --resolve-all` | Prompted (ask) | Same — bulk thread resolution is a side-effect |
| `Bash(ws review:*)` + ask `ws review * threads * --resolve*` | `ws review yggdrasil threads 94 --status` | Allowed without prompt | `--status` doesn't match the resolve ask-glob; read path unaffected |
| `Bash(ws log:*)` | `ws log --oneline --limit=5` | Allowed without prompt | Colon-prefix matches any argument tail in one entry |
| `Bash(ws log:*)` | `ws log` | Allowed without prompt | Colon form also matches the bare command |
| `Bash(git fetch *)` | `git fetch siliconsaga main` | Allowed without prompt | Read-only on the working tree; only writes refs/objects under `.git/` |
| `Bash(git fetch *)` | `git fetch` | Prompted | Bare form has no trailing arg to bind to `*` — pattern requires at least one arg |
| `Bash(ws commit:*)` | `ws commit yggdrasil .commits/x.md` | Allowed without prompt | `ws commit` allowlisted by default |
| `Bash(ws commit:*)` | `ws commit --co-author-file sess--sub yggdrasil .commits/x.md` | Allowed without prompt | The flag tail matches the start-anchored `ws commit:*` prefix; no env prefix, no angle brackets |
| (any allow) | `LD_PRELOAD=/tmp/evil.so ws status` | Prompted | An env-assignment prefix stays in the match string and fails every allow glob |
| `Bash(git commit *)` redirect-deny | `git commit -m y` | Denied (redirected to `ws commit`) | A bare denied command still hits its redirect-deny |
| `git mv*` redirect-deny | `git mv a b` | Denied (redirect to plain `mv` + bodyfile) | Start-anchored bare-form match (like `git commit*`); a `git -C <dir> mv` form isn't caught — same accepted gap as the other git redirects, and avoids over-matching `mv` in unrelated git args |
| `Bash(ws test:*)` | `ws test mimir` | Allowed without prompt | `ws test` allowlisted under the realm trust model |
| `Bash(ws lint:*)` | `ws lint mimir` | Allowed without prompt | `ws lint` allowlisted under the realm trust model |

When you add a new allow pattern, also add at least one positive case (matches → allowed) and one negative case (close-but-not-quite → prompts) to this table. Mismatches between the table and observed behavior are PR-blocking — they indicate either a stale doc or a matcher behavior change.

---

## When to widen vs narrow patterns

A decision tree for adding a new `Bash(...)` pattern:

1. **Is the command already auto-allowed by Claude Code?** (`cat`, `ls`, `pwd`, `git status`, `git log` without `-C`, `gh pr view`, etc.) If yes, don't add a pattern — it's redundant.
2. **Does the command's subcommand have any mutating or execution-capable flag-form?**
   - No: a prefix-wildcard pattern may be appropriate when every argument tail is equally trusted.
   - Yes: pin the exact safe form or add a hook-owned positional classifier. Never use a middle path wildcard for `git -C`; extend its validated read classifier instead.
3. **Is the command an arbitrary-execution shell?** (`bash *`, `python *`, `node *`, `npx *`, `bunx *`, `uvx *`, `make *`, `npm run *`, `bun run *`, `gh api *`.) Never widen these. An exact `Bash(bash -n some-specific-script.sh)` is fine; wildcards aren't.
4. **Does the command write to a shared system?** (push, deploy, publish, send). These are Side-effect tier in `docs/ws-cli-guide.md` — never auto-allow; let the user decide case-by-case.

When in doubt, narrower wins — you can always widen later. Narrowing post-hoc is harder, since you've already trained yourself to expect the wide form.

`ws exec` is intentionally ask-gated rather than broadly allowlisted. Its sole hook-owned exception is a validated read-only Git command against the workspace root or a root/operator-declared component. If another `ws exec` shape becomes common enough that you want it to run without a human prompt, treat that as a design signal: promote the behavior into an adapter-backed `ws test` / `ws lint` / `ws build` path, a focused `ws` subcommand, or a reviewed component-local script behind a narrower wrapper.

---

## Cross-reference rule

When you modify `.claude/settings.json`'s `permissions.allow` (or `permissions.deny`), also update the **Empirical matcher findings** section above to reflect the new pattern with at least one positive and one negative case.

The two artifacts are paired:
- `.claude/settings.json` is what Claude Code enforces.
- `docs/gdd/permissions.md` (this file) is what humans, automated reviewers, and the agent reason against.

Drift between them is a real bug — humans trust the doc, agents trust the doc, and a stale doc gives false confidence. PR review for `.claude/settings.json` changes should call out a missing doc update as blocking.

The `gdd-permissions` skill enforces this operationally: when an agent adds a pattern, the skill includes the doc update as part of the same change.

When you modify `.claude/hooks/hook-rules`, update this doc or [Agent Training](agent-training.md) if the user-facing policy changes, and add focused hook tests in `tests/hook/gdd-permission-hook.bats`. Hook-rule globs are not Claude matcher entries, so they need test coverage rather than rows in the empirical matcher table unless `.claude/settings.json` also changes.

---

## Future Directions

- **Cross-framework porting.** Other agent frameworks (Codex, Gemini CLI, Cursor, etc.) have their own permission-style configs. The semantics differ — some are tool-name-only, some have richer per-tool argument matching, some have no analogue to the `permissions.deny` override layer. Mapping Claude Code's allowlist to each framework's equivalent is a future arc; the skill points at this thread but doesn't carry porting guidance in v1.

- **Automated regression testing** (issue #46). Today the empirical findings table in **Empirical matcher findings** is the source of truth, but there's no test harness that re-asserts those findings against new Claude Code versions. The future regression suite will execute each (pattern, command, expected) triple and flag matcher-behavior changes.

- **Sandboxing tooling.** Personal exploration of AI-tooling sandboxing patterns lives in `realms/realm-siliconsaga/docs/agent-security/`. That research could inform a future GDD security category that sits next to permissions.
