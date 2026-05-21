# Interactive Acceptance — Tier 2 Redirect Deny + Bypass

This is a live "actor's script" the agent walks through with the human present. Bats covers the hook's emitted JSON and audit log; this script covers the prompt the human actually sees.

**Prerequisites:**

- Yggdrasil workspace cloned, current branch has the redirect tier merged.
- A throwaway clone of any harmless repo for the `git push` and `gh pr create` probes (so the script doesn't actually push to anything real). E.g.: `git clone --depth 1 <some test repo> /tmp/redirect-probe` and `cd /tmp/redirect-probe`.
- Audit log path open in a terminal: `tail -f ~/.claude/hook-audit.log`.

**The script.** Agent reads each step aloud (or echoes the announcement), runs the command, and waits for the human to confirm the prompt/output shape matches.

## Step 1 — `git commit` denies at Tier 2

Agent announces: *"I'll run `git commit -m \"acceptance probe\"`. Expect a Tier 2 deny pointing at `ws commit` and mentioning `ws hook-bypass git-commit`."*

Agent runs: `git commit -m "acceptance probe"`

Human confirms:

- [ ] Agent saw a deny output, not a silent pass
- [ ] Deny message names `ws commit`
- [ ] Deny message names `ws hook-bypass git-commit` as the escape hatch
- [ ] Audit log shows a `DENY` entry for this command

## Step 2 — `ws hook-bypass git-commit` force-prompts

Agent announces: *"Now `ws hook-bypass git-commit --reason \"acceptance test\"`. Expect a Tier 3 ask prompt (force-prompt, not a silent run), and on approval, a marker file under `.tmp/hook-bypass/git-commit.bypass`."*

Agent runs: `ws hook-bypass git-commit --reason "acceptance test"`

Human confirms:

- [ ] A permission prompt fires for the `ws hook-bypass` command
- [ ] On approval, the command exits 0 and prints `bypass marker written: ...`
- [ ] The file `.tmp/hook-bypass/git-commit.bypass` exists and contains `session_id:`, `slug: git-commit`, and `reason: acceptance test`

## Step 3 — Bypassed `git commit` now ALLOWs

Agent announces: *"Retrying `git commit -m \"acceptance probe\"` in this throwaway repo. Expect ALLOW with no prompt, and an audit line `BYPASS-ALLOW [git-commit] reason=\"acceptance test\"`."*

Agent runs: `git commit -m "acceptance probe"` (in the throwaway repo)

Human confirms:

- [ ] No prompt fired; the command ran through
- [ ] Audit log shows `BYPASS-ALLOW [git-commit] reason="acceptance test"`

## Step 4 — Slug isolation — `gh pr create` still denies

Agent announces: *"`gh pr create --title test --body test` — expect deny (the marker is for `git-commit`, not `gh-pr-create`)."*

Agent runs: `gh pr create --title test --body test`

Human confirms:

- [ ] Deny fired despite the active `git-commit` bypass
- [ ] Deny message names `ws cr` and `ws hook-bypass gh-pr-create`

## Step 5 — Composition still wins over bypass

Agent announces: *"`git commit -m \"x\" && echo done` — expect Tier 1 composition deny, NOT a Tier 2 redirect, NOT a bypass allow."*

Agent runs: `git commit -m "x" && echo done`

Human confirms:

- [ ] Deny fired with the Shell composition message
- [ ] Audit log entry is a `DENY` with "Shell composition" reason, not `BYPASS-ALLOW`

## Step 6 — Cleanup

Agent announces: *"`ws clean` to sweep the marker so the next session starts fresh."*

Agent runs: `ws clean`

Human confirms:

- [ ] `.tmp/hook-bypass/git-commit.bypass` no longer exists
- [ ] `ws clean` reported one or more files removed (the marker plus whatever else was in `.tmp/`)

## Step 7 — Marker stale after restart (optional, slow)

Skip if the human is short on time — the bats coverage covers session_id mismatch deterministically.

Agent announces: *"Re-create the marker, then we'll start a fresh Claude Code session and verify the bypass does NOT carry over."*

Agent runs: `ws hook-bypass git-commit --reason "stale test"` (approve at prompt).

Human starts a fresh Claude session in the same workspace; in that new session the agent runs `git commit -m "x"` and confirms it denies (the marker's session_id no longer matches).

## Pass criteria

All checkboxes in steps 1-6 ticked, optionally step 7. Any mismatch is a finding to surface.
