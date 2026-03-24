# Session 2: Review Threads

* **Date:** 2026-03-23/24
* **Workspace:** yggdrasil (secondary — Win11)
* **Mode:** Zen / Developer
* **Duration:** Extended session across two days

## Overview

This transcript covers a GDD session on a second workstation, implementing `ws review threads` (issue #11) — a subcommand for listing and resolving PR review threads via the GitHub GraphQL API. The session exercises the full Superpowers brainstorming-to-implementation pipeline, encounters real-world friction (missing tools, approval UX, cross-workspace conflicts), and culminates in the new tool being used on its own PR's review comments.

This is the parallel session to Session 1 (the commit bodyfile work). The two sessions deliberately created a merge conflict to test cross-workspace development.

---

## Part 1: GDD Orientation (First Use on This Machine)

*The human started a fresh session on a second workstation, mentioning they had GitHub issues to work on.*

**Agent:** I follow Guardian Driven Development conventions for this workspace — happy to explain more if you're curious. No SecondBrain.md found. Want me to create one from the template?

**Human:** Yes please! Both on initializing the second brain process and getting details from the issue about "threads." I'm going to check in here occasionally throughout the day so it'll be a bit like zen as a developer.

*The agent created SecondBrain.md with zen/developer defaults, fetched issue #11, and summarized it. The orientation was brief and human-first — no component scan, no information dump.*

> **GDD note:** This was the first session on the Win11 workstation. Orientation followed the refined instructions from Session 1's iterations — mention GDD briefly, offer SecondBrain, ask about mode, ask what to work on. The component scan and trust verification were deferred until after alignment.

---

## Part 2: Brainstorming — Design Decisions

*The agent invoked the Superpowers brainstorming skill and began asking clarifying questions one at a time.*

### Should `--resolve-all` be interactive?

**Agent:** Three options: non-interactive, interactive with confirmation, or default-interactive with `--yes` flag.

**Human:** Non-interactive is fine.

*The agent recommended non-interactive (option A) since the permission tier already gates execution and AI agents can't answer interactive prompts.*

### Should threads be a separate command or part of `ws review`?

**Human:** Curiously, is there any reason review doesn't just do positional, to keep with the pattern of other commands? How have we handled inline-vs-standalone scripts in the past?

*This question triggered a deeper investigation. The agent analyzed the full `ws` dispatcher — 622 lines, with some commands inline and others as standalone scripts.*

**Agent:** The split is chronological accident, not principled. Commands written before `ws` existed got wrapped as delegates. Commands written after `ws` were added inline. There's no architectural reason for the difference.

**Human:** Threads and reviews are very closely related — should the two of them earn a single new script file together?

*Three approaches proposed: (A) combine under `ws review` with subcommands, (B) keep separate commands backed by one script, (C) separate top-level commands with shared implementation file.*

**Agent:** My recommendation is option C — keeps the user-facing commands simple while sharing implementation.

**Human:** I'm leaning toward A. I don't feel like threads is an independent thing — it's housekeeping for reviews. I don't think a human would go into deep utility commands to interact with a code review process — they'd use the GitHub GUI.

*The agent agreed. This insight — that review tooling is agent-first, not human-first — became a key design principle captured in SecondBrain.*

### Normalizing the interface

**Human:** Is there any reason `ws review` uses `--comp` as a flag while everything else uses positional component args?

*The agent dug into git history and found the original commit — `--comp` was just how it happened to be designed, with no principled reason for diverging from the positional pattern.*

**Human:** Always require the component. Just if it is "yggdrasil" we have the special case of knowing it is the root component at a different path.

*The final command surface:*

```
ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]
ws review <comp> <pr#> [--reviewer <name>] [--since <time>]
```

### Side notes captured

Several tangential observations were captured to SecondBrain during brainstorming rather than derailing the design:

- **`ws resolve` naming collision** — ArgoCD manifest generation vs thread resolution. Future rename needed.
- **GraphQL expansion path** — this is the first GraphQL consumer; if we hit 4-5+ queries, extract to `scripts/graphql/`.
- **Spec location convention** — Superpowers defaults to `docs/superpowers/specs/` but the workspace has `docs/plans/`. Needs a decision.

---

## Part 3: Design, Spec Review, and Planning

*The agent presented the design in 5 sections, getting approval after each: command surface, file structure, GraphQL queries, permission tiers, and migration of existing code.*

**Human:** *(on the design doc section order)* If we're putting that in a doc I'd put the threads line first since we check for that case first.

*Small detail, but it reflects the principle that documentation should match code flow.*

*The spec was written and committed. A spec-review subagent was dispatched, which found two issues:*

1. **`--resolve-all` partial failure behavior unspecified** — should it stop or continue? Answer: continue and report summary.
2. **`ws_validate_component` duplication** — standalone scripts duplicate their own validation rather than sourcing the dispatcher. Note: this is the established pattern.

*Both addressed. The implementation plan was then written with 8 bite-sized tasks, reviewed by a plan-review subagent, and three more issues caught: `--help` before component parsing, thread ID regex missing `=` for base64, `echo -e` portability.*

> **GDD observation:** The two-stage review (spec reviewer, then plan reviewer) caught 5 issues before any code was written. All were real — the `--help` bug would have been a user-facing problem, and the wildcard permission patterns were a security gap.

---

## Part 4: Implementation

*The executing-plans skill wanted a git worktree for isolation.*

**Human:** Let's skip worktrees for now. They haven't been used or needed yet. That would be overkill and needs more workflow thinking first.

*The agent created a topic branch directly and executed the 8 tasks sequentially. Key moments:*

### jq not installed

*Task 3 (thread listing) failed because jq wasn't on PATH.*

**Human:** I did think we had jq installed somewhere, not sure where it went.

*The agent searched common Windows locations, found nothing. The human installed via `choco install jq`. The agent added the choco bin path and continued.*

### Real-world validation

*Thread listing was tested against PR #15 (all resolved — the "clean" case) and then against PR #19 (6 unresolved threads — the "real data" case). The compact output format worked well with actual CodeRabbit and Copilot review content.*

**Human:** Go ahead and use this automation to resolve those review comments. They have been addressed from another workspace. Let us see it work.

```
$ ws review yggdrasil threads 19 --resolve-all
Resolved 6 threads on PR #19 (SiliconSaga/yggdrasil).

$ ws review yggdrasil threads 19 --status
PR #19 (SiliconSaga/yggdrasil): 0 unresolved, 11 resolved (11 total)
```

> **Cross-workspace intersection:** PR #19 was created in Session 1 (commit bodyfile work). The review threads were left unresolved. Session 2's newly built tool resolved them — the first real cross-workspace use of the tooling.

---

## Part 5: Approval UX Friction

*Two unexpected approval prompts surfaced during PR preparation.*

### Heredoc file creation

*The agent used `cat > .prs/foo.md << 'EOF'` to create the PR body file instead of the Write tool.*

**Human:** *(via SecondBrain note)* The creation of a PR triggered an unexpected approval request. Is that because you inlined the creation of the file with mkdir, cat, etc, instead of just using a file writing tool?

**Agent:** Yes — should have used the Write tool. System instructions explicitly say to prefer Write for file creation. The heredoc syntax triggered the approval prompt because it looked like a suspicious command pattern.

### PR title as argument

**Human:** And this one — is this because we have the PR title as an argument?

**Agent:** The `ws pr` prompt was correct — it's Side-effect tier. But the observation connects to issue #16 (frontmatter in bodyfiles for stable command shapes). PR #19 is proving the pattern for `ws commit`; extending to `ws pr` would make the command shape stable and auto-approvable.

> **GDD observation:** The async SecondBrain collaboration pattern from Session 1 repeated here — the human wrote notes while the agent worked, and the agent noticed and responded on the next file read. Both sessions independently discovered this workflow.

---

## Part 6: Code Review and Conflict Setup

*CodeRabbit reviewed PR #20 with 4 findings. The agent used its own `ws review` tool to fetch them — though it initially tried to fall back to raw `gh api` out of habit.*

**Human:** Isn't this exactly the sort of thing we just added support for?

*The agent used `ws review yggdrasil threads 20` and `ws review yggdrasil 20 --reviewer coderabbitai` to triage. All 4 findings were valid:*

1. **Mutually exclusive flags** — `--status --resolve-all` silently let the last flag win
2. **Pagination warning** — >100 threads would silently truncate (added warning instead of full pagination)
3. **Non-zero exit on partial failure** — `--resolve-all` exited 0 even when some mutations failed
4. **Export GH_TOKEN** — plain `KEY=value` in `.env` (without `export`) wouldn't be visible to child processes

*Fixes committed and pushed. Meanwhile, the human had merged PR #19 from the other workspace, deliberately creating a merge conflict in `scripts/ws` to test cross-workspace development.*

---

## Key Takeaways

- **Agent-first design** — the insight that review tooling is primarily for AI agents (humans use GitHub's GUI) shaped every decision: non-interactive, compact output, composable flags
- **Archaeology reveals accidents** — investigating *why* `ws review` used `--comp` as a flag (answer: no reason, just how it was first written) led to normalizing the interface
- **Side notes prevent derailment** — SecondBrain captured 6 tangential observations during brainstorming that would have otherwise interrupted the design flow
- **Two-stage spec review caught real bugs** — the `--help` routing bug, permission security gap, and thread ID regex issue were all found before code was written
- **Eat your own cooking** — using the newly built tool to resolve threads on its own PR and fetch its own review comments validated the design against real data
- **Approval UX is a design surface** — both the heredoc and PR-title friction revealed that command shape stability matters for the agent workflow, connecting back to issue #16
- **Cross-workspace development works** — but creates merge conflicts that need a rebasing strategy (no skill exists for this yet)
