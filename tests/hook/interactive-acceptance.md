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
| 3 | `ls -la` | no ask prompt (Tier 4 `[allow-extras]` if `ls *` is enabled locally; otherwise a normal harness prompt) |
| 4 | `echo hi && echo bye` | composition **deny** — blocked with the shell-composition message, NOT an ask |
| 5 | `rm -rf .tmp/acceptance-probe-2` | `ask` prompt **still appears** despite `acceptEdits` mode — the core regression check |

## Confirmation

For each step the human confirms: did the prompt appear, and did its shape match the table? Step 5 is the pass/fail gate — if it does not prompt, the ask-tier is not overriding `acceptEdits` and the fix is incomplete.

## Teardown

The agent removes `.tmp/acceptance-probe*` and `.tmp/acceptance-repo` after the run.
