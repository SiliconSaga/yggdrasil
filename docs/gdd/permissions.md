# GDD Permissions Reference

How `.claude/settings.json` works in a GDD workspace, what makes a
pattern safe, and how to verify the safety claims for yourself.

This doc is the source of truth for the permission system's behavior
and the empirical findings it relies on. The `permissions-management`
skill (`.agent/skills/permissions-management/`) is the operational
companion — agents invoke it for live decisions; this doc is what they
(and humans, and automated review tools) read for reference.

---

## 1. What `.claude/settings.json` is and how it loads

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
  },
  "enableAllProjectMcpServers": false
}
```

`permissions.allow` and `permissions.deny` are lists of pattern strings.
A command is checked against `deny` first; if it matches, it's blocked
regardless of `allow`. Otherwise, if it matches any `allow`, it's
auto-approved. Otherwise the user is prompted.

`enableAllProjectMcpServers: false` means MCP servers declared by the
project don't auto-enable; users opt in per server via `/mcp`.

---

## 2. Pattern shapes

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
Bash(ws push *)
Bash(bash scripts/ws review * --since *)
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

## 3. The two-layer defense

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

Both layers must hold. If Claude Code's matcher behavior changes —
for instance, if compound commands stopped being per-segment validated
— a "safe" pattern could become unsafe. That's the case for
automated regression testing tracked at issue #46.

---

## 4. Empirical matcher findings

Verified in interactive testing. Each row is a (pattern, attempted
command, expected outcome) triple:

| Pattern | Command | Expected outcome | Notes |
|---------|---------|------------------|-------|
| `Bash(git -C * show *)` | `git -C . show HEAD --stat` | Allowed silently | Baseline |
| `Bash(git -C * show *)` | `git -C . show HEAD --stat \| xxd` | Right side prompts; left is allowed | Per-segment |
| `Bash(git -C * show *)` | `git -C $(echo .) show HEAD --stat` | Prompted; no don't-ask offer | Substitution rejected |
| `Bash(git -C * branch --show-current)` | `git -C . branch --list` | Prompted; don't-ask offer is the exact command | Exact-form pinning honored |
| `Bash(git -C * remote -v)` | `git -C . remote` | Prompted; don't-ask offer is the exact command | Same — exact-form |

When you add a new allow pattern, also add at least one positive case
(matches → allowed) and one negative case (close-but-not-quite →
prompts) to this table. Mismatches between the table and observed
behavior are PR-blocking — they indicate either a stale doc or a
matcher behavior change.

---

## 5. When to widen vs narrow patterns

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

## 6. Cross-reference rule

When you modify `.claude/settings.json`'s `permissions.allow` (or
`permissions.deny`), also update §4 above to reflect the new pattern
with at least one positive and one negative case.

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

## 7. Future Directions

- **Cross-framework porting.** Other agent frameworks (Codex, Gemini
  CLI, Cursor, etc.) have their own permission-style configs. The
  semantics differ — some are tool-name-only, some have richer
  per-tool argument matching, some have no analogue to the
  `permissions.deny` override layer. Mapping Claude Code's allowlist
  to each framework's equivalent is a future arc; the skill points
  at this thread but doesn't carry the porting guidance in v1.

- **Automated regression testing** (issue #46). Today the empirical
  findings table in §4 is the source of truth, but there's no test
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
