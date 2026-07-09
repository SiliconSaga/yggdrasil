# PR 126 Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve four verified review findings in the Codex redirect and Kubernetes context-only scope behavior.

**Architecture:** Tighten validation at the two existing boundaries: Codex payload admission and Kubernetes scope normalization. Keep `*` as the single context-only representation and preserve all downstream guard decisions through existing helpers.

**Tech Stack:** Bash, jq, Bats

---

### Task 1: Add regression coverage

**Files:**
- Modify: `tests/hook/codex-redirect-hook.bats`
- Modify: `tests/ws-k8s/wrapper.bats`

- [ ] **Step 1: Add a missing-event test**

Add a parseable Bash payload with no `hook_event_name` and assert the redirect hook emits no decision.

- [ ] **Step 2: Add Kubernetes normalization tests**

Assert `alice-sandbox,*` displays as context-only, `all` remains a literal namespace, and context-only scope permits named namespace create and delete operations.

- [ ] **Step 3: Verify the tests fail for the intended reasons**

Run: `ws test yggdrasil tests/hook/codex-redirect-hook.bats tests/ws-k8s/wrapper.bats`

Expected: the missing-event payload is denied, mixed wildcard output is not canonical, `all` displays as context-only, and namespace lifecycle coverage passes against the existing intended behavior.

### Task 2: Tighten the implementation and docs

**Files:**
- Modify: `.codex/hooks/gdd-redirect-hook.sh`
- Modify: `scripts/ws-k8s.sh`
- Modify: `docs/tutorials/guarded-kubernetes.md`

- [ ] **Step 1: Require the explicit hook event**

Change the jq fallback for `hook_event_name` from `PreToolUse` to the empty string.

- [ ] **Step 2: Canonicalize wildcard scope**

Reuse `_k8s_ns_in_csv` to detect a `*` element and normalize the namespace CSV to the `*` sentinel. Do not treat `all` specially.

- [ ] **Step 3: Update user-facing guidance**

Remove `--namespace all` as a context-only alias from usage, help, and tutorial text.

- [ ] **Step 4: Verify focused and full behavior**

Run: `ws test yggdrasil tests/hook/codex-redirect-hook.bats tests/ws-k8s/wrapper.bats tests/hook/codex-k8s-hook.bats`

Expected: all focused tests pass.

Run: `ws test yggdrasil`

Expected: all workspace tests pass.

### Task 3: Publish the review fix

**Files:**
- Create: `.commits/pr-126-review-fixes.md`

- [ ] **Step 1: Verify repository state**

Run `git diff --check` and `ws status yggdrasil`; expect no formatting defects and only the intended files changed.

- [ ] **Step 2: Commit once**

Use `ws commit yggdrasil .commits/pr-126-review-fixes.md` with every implementation, test, doc, design, and plan file listed in the bodyfile.

- [ ] **Step 3: Push to GitHub**

Run `ws push yggdrasil --remote siliconsaga feat/codex-redirect-hook` and verify the existing PR branch updates.
