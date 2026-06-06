# Hook ask-tier — interactive acceptance script

bats (`gdd-permission-hook.bats`) verifies the hook's *output*. It cannot verify the *prompt the human sees*. This script is the gap-filler: the agent runs it live, the human watches the prompts.

**How to run:** ask the agent to "run the hook acceptance script." The agent announces the batch, runs each command in order, and you confirm each prompt matches the expected shape.

## Preconditions

- Session permission mode: `acceptEdits` (this is the mode the original bug appeared in — step 5 is the regression check).
- A throwaway dir exists: `.tmp/acceptance-probe/` and a second `.tmp/acceptance-probe-2/`. The agent creates them first.
- A throwaway git repo for step 2: `.tmp/acceptance-repo/` with one commit. The agent sets it up.

## Sequence

| # | Command | Expected prompt |
|---|---------|-----------------|
| 1 | `rm -rf .tmp/acceptance-probe` | `ask` prompt — reason mentions the ask-list **and** carries the symlink caution |
| 2 | `git -C .tmp/acceptance-repo reset --hard HEAD` | `ask` prompt — reason mentions the ask-list, **no** symlink caution |
| 3 | `ls -la` | **not** an ask prompt. Three valid paths: Tier 6 silent auto-allow (if `ls *` is in `[allow-extras]`), normal harness prompt, or silent allow from Claude Code's session-scoped read trust if the harness has already accepted reads against the directory. The shape of the user-facing response varies; the invariant to verify is in the audit log — see "Confirmation" below. |
| 4 | `echo hi && echo bye` | composition **deny** — blocked with the shell-composition message, NOT an ask |
| 5 | `rm -rf .tmp/acceptance-probe-2` | `ask` prompt **still appears** despite `acceptEdits` mode — the core regression check |

## Confirmation

For each step the human confirms: did the prompt appear (where one is expected), and did its shape match the table? Step 5 is the pass/fail gate — if it does not prompt, the ask-tier is not overriding `acceptEdits` and the fix is incomplete.

After step 5, also skim the audit log to verify each step's *recorded* decision matches the table. This is the deterministic check that survives Claude Code's session-scoped trust (which can silently swallow step 3's prompt without involving the hook):

```bash
tail -10 ~/.claude/hook-audit.log
```

Expected entries: step 1 `ASK` with `symlinks` caution, step 2 `ASK` without it, step 3 **no entry** (passthrough is not logged) OR an `ALLOW` from `[allow-extras]`, step 4 `DENY` with the composition message, step 5 `ASK` with the `symlinks` caution. Any `ASK` against step 3's `ls -la` would be a regression — the ask-list is matching too broadly.

## Teardown

The agent removes `.tmp/acceptance-probe*` and `.tmp/acceptance-repo` after the run.
