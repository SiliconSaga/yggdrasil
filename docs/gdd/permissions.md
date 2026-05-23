# GDD Permissions Reference

How `.claude/settings.json` works in a GDD workspace, what makes a
pattern safe, and how to verify the safety claims for yourself.

This doc is the source of truth for the permission system's behavior
and the empirical findings it relies on. The `permissions-management`
skill (`.agent/skills/permissions-management/`) is the operational
companion — agents invoke it for live decisions; this doc is what they
(and humans, and automated review tools) read for reference.

---

## What `.claude/settings.json` is and how it loads

Claude Code reads two settings files for each workspace:

- **`.claude/settings.json`** — project-level, committed to the repo.
  Shared across everyone working in the workspace.
- **`.claude/settings.local.json`** — per-user, gitignored. Not shared.

Both are merged at startup. Where they conflict on a single key, local
wins. The relevant top-level structure is:

```json
{
  "permissions": {
    "allow": [ "Bash(...)", "..." ],
    "deny":  [ "Bash(...)", "..." ]
  }
}
```

`permissions.allow` and `permissions.deny` are lists of pattern strings.
A command is checked against `deny` first; if it matches, it's blocked
regardless of `allow`. Otherwise, if it matches any `allow`, it's
auto-approved. Otherwise the user is prompted.

### Managed-config layer (corporate / enterprise environments)

Some environments layer additional permission rules on top of the workspace's `.claude/settings.json` via enterprise managed config — typically pushed via the OS-level managed-preferences mechanism (MDM, Group Policy, etc.) and sitting at the top of the precedence stack. These overrides can change which rules apply in either direction: auto-approving things the workspace would prompt on, or forcing prompts the workspace would auto-approve.

If you see a permission behavior that doesn't match what `.claude/settings.json` declares — same workspace, same git tree, different outcome between machines — suspect a managed config in your environment.

### Claude Hook Options

The hook script at `.claude/hooks/gdd-permission-hook.sh` was designed to encourage the agent to align with good practices in using the GDD `ws` CLI and making for clearer shorter commands that are easier for a human to digest. It will block chained commands and some kinds of redirection, which forces the agent into friendlier more auditable variants.

The hook produces three possible decisions for a Bash command:

- **deny** — shell composition or other forbidden patterns. The command is blocked and the agent receives a corrective message.
- **ask** — the command matches the `[ask-commands]` glob list in `hook-rules` (or `hook-rules.local`). The hook emits `permissionDecision: "ask"`, forcing a human-facing permission prompt regardless of the session permission mode. This overrides `acceptEdits` and `bypassPermissions` — the prompt always surfaces. The command is NOT blocked; once the human approves, it runs normally. Destructive commands like `rm -rf` and `git reset --hard` live here.
- **allow** — the command matches a `permissions.allow` pattern in `settings.json` (Tier 4) or an `[allow-extras]` glob in `hook-rules.local` (Tier 5). It proceeds without a prompt.

A secondary effect of the hook is that it can sometimes re-map GDD's "auto-approve this declared-safe pattern" behavior on machines where other config causes conflicts. This can actually be safer than giant multi-line monster commands the human is likely to just button-mash through if overly repeated.

See [`.claude/hooks/README.md`](../../.claude/hooks/README.md) for the full hook spec — including an optional extension some workspaces may enable in `settings.local.json` to suppress prompts for writes into the `Workspace-local scratch` directories and a `hook-rules.local` you can use for simple trusted patterns on specific machines when combined with GDD's chain blocking.

### Redirect tier and bypass

Tier 2 of the PreToolUse hook denies a curated list of raw commands (`git commit`, `git push`, `gh pr create`) that have a `ws` wrapper equivalent. The deny carries a corrective message pointing at the right `ws` subcommand.

This is a *training* layer, not a safety floor — the `ws` wrappers add attribution, remote selection, and bodyfile flows that AGENTS.md documents but training-data reflex drifts away from. A legitimate edge case (the `ws` subcommand doesn't yet support what's needed) escapes via `ws hook-bypass <slug>`, which writes a marker file keyed to the Claude Code session id (`$CLAUDE_CODE_SESSION_ID`). The marker is honored for the rest of the session.

The `ws hook-bypass <slug>` subcommand itself is on the ask-list — every invocation force-prompts the human. The security boundary is the ask-tier; no env-var or cryptographic gate is added.

See `.claude/hooks/README.md` § Redirect tier and bypass for the operator-facing details.

## Pattern shapes

Three shapes appear in this workspace's `.claude/settings.json`:

### Exact-form

```text
Bash(ws status)
Bash(ws status --verbose)
Bash(git -C * branch --show-current)
```

The literal string after the command name must match exactly. The `*`
inside `git -C * branch --show-current` is a wildcard for the path
slot only; the trailing `branch --show-current` is a literal. A
command of `git -C . branch --list` does NOT match — `--list` ≠
`--show-current`. The matcher is honest about this; non-matches
produce a permission prompt.

### Prefix wildcards

```text
Bash(git -C * show *)
Bash(git -C * log *)
Bash(bash scripts/ws clone *)
Bash(bash scripts/ws review * * --since *)
```

Each `*` is a wildcard slot. The matcher binds each slot to a single
argument-shaped sequence. The space before `*` matters: `Bash(foo*)`
without the space matches `foo` followed by anything (including
`foobar`); `Bash(foo *)` requires a space, then any single argument.
For prefix matching of arguments, always include the space.

### MCP tool names

```text
mcp__slack__slack_read_thread
mcp__github__list_pull_requests
```

Full tool names, no wildcard. MCP names are already specific enough.

---

## The two-layer defense

Every allow pattern in `.claude/settings.json` should be safe even if a
single layer fails. We rely on two:

### Layer 1: subcommand-level

The chosen subcommand for each pattern is read-only at the porcelain
level. `git show`, `git log`, `git diff`, `git status`, `git ls-tree`,
`git grep` — all read-only. There is no flag combination that mutates
state. We deliberately don't grant a wildcard pattern to subcommands
that DO have mutating flag-forms — `git branch -d` (deletes branches),
`git remote add` (adds a remote), `git push` (writes to a remote).
For those, we either pin to an exact safe form (`git -C * branch
--show-current`, `git -C * remote -v`) or don't grant at all.

### Layer 2: matcher-level

The matcher scopes wildcards correctly:

- **Compound commands** (`|`, `&&`, `||`, `;`) are validated
  per-segment. `git -C . show HEAD | xxd` is two segments: the left
  matches `Bash(git -C * show *)` and is allowed; the right is `xxd`
  alone and prompts. The wildcards in the left side don't extend
  across the pipe.
- **Command substitution** (`$(...)` and backticks) is rejected by the
  matcher. `git -C $(echo .) show HEAD --stat` does NOT match
  `Bash(git -C * show *)` — the matcher prompts and offers no
  "don't ask again" option. Substitution is too dynamic for any
  static pattern to safely allowlist.
- **Exact-form pinning is literal.** `git -C . branch --list` does
  not match `Bash(git -C * branch --show-current)` because the
  trailing literals differ.
- **Stdout-redirect-to-file (`> file`, `>> file`) prompts
  regardless of the LHS.** Even when the producing command is
  read-only and individually auto-allowed, the redirect-to-file is
  treated as a side-effect operation because the destination path
  is opaque to static analysis (could be `/tmp/foo`,
  `~/.bashrc`, `/etc/...`). The right design path for "save output
  for later grep" is a wrapper-side `--output <phrase>` flag that
  validates the destination against a workspace-internal scratch
  dir like `.outputs/` — see `ws review --output` for the
  reference implementation.

Both layers must hold. If Claude Code's matcher behavior changes —
for instance, if compound commands stopped being per-segment validated
— a "safe" pattern could become unsafe. That's the case for
automated regression testing tracked at issue #46.

---

## Empirical matcher findings

Verified in interactive testing. Each row is a (pattern, attempted
command, expected outcome) triple:

| Pattern | Command | Expected outcome | Notes |
|---------|---------|------------------|-------|
| `Bash(git -C * show *)` | `git -C . show HEAD --stat` | Allowed without prompt | Baseline |
| `Bash(git -C * show *)` | `git -C . show HEAD --stat \| xxd` | Right side prompts; left is allowed | Per-segment |
| `Bash(git -C * show *)` | `git -C $(echo .) show HEAD --stat` | Prompted; no don't-ask offer | Substitution rejected |
| `Bash(git -C * branch --show-current)` | `git -C . branch --list` | Prompted; don't-ask offer is the exact command | Exact-form pinning honored |
| `Bash(git -C * remote -v)` | `git -C . remote` | Prompted; don't-ask offer is the exact command | Same — exact-form |
| `Bash(ws hoard cadence)` | `ws hoard cadence` | Allowed without prompt | Exact-form for the cadence reporter |
| `Bash(ws hoard cadence)` | `ws hoard cadence --debug` | Prompted | Exact-form pinning — extra arg doesn't match |
| `Bash(ws hoard thalamus-path)` | `ws hoard thalamus-path` | Allowed without prompt | Exact-form for path resolution |
| `Bash(ws preflight)` | `ws preflight` | Allowed without prompt | Exact-form for the bare prereq check |
| `Bash(ws preflight --soft)` | `ws preflight --soft` | Allowed without prompt | Exact-form for the soft-exit variant |
| `Bash(ws preflight)` | `ws preflight --json` | Prompted | Hypothetical flag not allowlisted; exact-form pinning honored |
| `Bash(ws review * *)` | `ws review yggdrasil 52 > /tmp/r.txt` | Prompted | Stdout redirect treated as side-effect regardless of LHS — destination opaque to static analysis |
| `Bash(ws review * * --output *)` | `ws review yggdrasil 52 --output snap` | Allowed without prompt | Wrapper-side `--output <phrase>` validates destination is under `.outputs/` — bounded blast radius |
| `Bash(ws log * *)` | `ws log --oneline --limit=5` | Allowed without prompt | Two args; equals form binds to one wildcard slot |
| `Bash(ws log * * *)` | `ws log --oneline --limit 5` | Allowed without prompt | Three args; spaced form needs the wider slot |
| `Bash(ws log * * * *)` | `ws log mimir --oneline --limit 5` | Allowed without prompt | Four args; component + flags |
| `Bash(ws log)` | `ws log --rebase` | Prompted | Hypothetical flag not allowlisted; bare-form pinning honored |
| `Bash(git fetch *)` | `git fetch siliconsaga main` | Allowed without prompt | Read-only on the working tree; only writes refs/objects under `.git/` |
| `Bash(git fetch *)` | `git fetch` | Prompted | Bare form has no trailing arg to bind to `*` — pattern requires at least one arg |

When you add a new allow pattern, also add at least one positive case
(matches → allowed) and one negative case (close-but-not-quite →
prompts) to this table. Mismatches between the table and observed
behavior are PR-blocking — they indicate either a stale doc or a
matcher behavior change.

---

## When to widen vs narrow patterns

A decision tree for adding a new `Bash(...)` pattern:

1. **Is the command already auto-allowed by Claude Code?** (`cat`, `ls`,
   `pwd`, `git status`, `git log` without `-C`, `gh pr view`, etc.) If
   yes, don't add a pattern — it's redundant.
2. **Does the command's subcommand have any mutating flag-form?**
   - No (e.g. `git show`, `git diff`, `git ls-tree`): a prefix-wildcard
     pattern (`Bash(<command> <subcommand> *)`) is fine.
   - Yes (e.g. `git branch -d`, `git remote add`): pin to the exact
     safe form (`Bash(git -C * branch --show-current)`).
3. **Is the command an arbitrary-execution shell?** (`bash *`,
   `python *`, `node *`, `npx *`, `bunx *`, `uvx *`, `make *`,
   `npm run *`, `bun run *`, `gh api *`.)  Never widen these. An exact
   `Bash(bash -n some-specific-script.sh)` is fine; wildcards aren't.
4. **Does the command write to a shared system?** (push, deploy,
   publish, send). These are Side-effect tier in
   `docs/ws-cli-guide.md` — never auto-allow; let the user decide
   case-by-case.

When in doubt, narrower wins. You can always widen later. Narrowing
post-hoc is harder (you've already trained yourself to expect the
wide form).

---

## Cross-reference rule

When you modify `.claude/settings.json`'s `permissions.allow` (or
`permissions.deny`), also update the **Empirical matcher findings**
section above to reflect the new pattern with at least one positive
and one negative case.

The two artifacts are paired:
- `.claude/settings.json` is what Claude Code enforces.
- `docs/gdd/permissions.md` (this file) is what humans, automated
  reviewers, and the agent reason against.

Drift between them is a real bug — humans trust the doc, agents trust
the doc, and a stale doc gives false confidence. PR review for
`.claude/settings.json` changes should call out a missing doc update
as blocking.

The `permissions-management` skill enforces this rule operationally:
when an agent adds a pattern, the skill includes the doc update as
part of the same change.

---

## Future Directions

- **Cross-framework porting.** Other agent frameworks (Codex, Gemini
  CLI, Cursor, etc.) have their own permission-style configs. The
  semantics differ — some are tool-name-only, some have richer
  per-tool argument matching, some have no analogue to the
  `permissions.deny` override layer. Mapping Claude Code's allowlist
  to each framework's equivalent is a future arc; the skill points
  at this thread but doesn't carry the porting guidance in v1.

- **Automated regression testing** (issue #46). Today the empirical
  findings table in **Empirical matcher findings** is the source of
  truth, but there's no test
  harness that re-asserts those findings against new Claude Code
  versions. The future regression suite will execute each (pattern,
  command, expected) triple and flag matcher-behavior changes.

- **Sandboxing tooling.** Personal exploration of AI-tooling
  sandboxing patterns lives in
  `realms/realm-siliconsaga/docs/agent-security/` (relocated from
  this repo's `docs/` in the same hygiene PR that introduced this
  doc). Some of that work — particularly Nvidia's OpenShell /
  NemoClaw lineage — could inform a future GDD security category
  that sits next to permissions.
