# GDD GA Cleanups (B1 · B3 · B4 · B7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the four small, self-contained GA cleanups from `docs/plans/2026-06-08-gdd-ga-readiness-design.md` — target-kind residual (B1), `ws audit-permissions` de-noise (B3), help/anchor uniformity (B4), and the hoard-upgrade gate confirmation (B7) — as one batch.

**Architecture:** Pure `ws`-CLI + docs work in the yggdrasil workspace repo. B3 is test-driven against the existing bats suite (`tests/ws-audit-permissions/`); the rest are small bash edits in `scripts/ws` + `scripts/ws-audit-permissions.sh` plus markdown fixes, each verified by running a command or the suite and observing output. No new subsystems; no behavior change outside the four items.

**Tech Stack:** Bash 4+ (the `ws` CLI), bats-core (vendored at `tests/vendor/bats-core/`), `jq`/`yq`, markdown.

---

## Context the executing engineer needs

- **Run the test suite:** `ws test yggdrasil` runs every `*.bats` under `tests/`. For a focused TDD loop on one directory: `bash tests/vendor/bats-core/bin/bats tests/ws-audit-permissions/`. (Requires GNU `timeout`/`gtimeout` — present on Git Bash/Linux; `brew install coreutils` on macOS.)
- **Commit convention:** use `ws commit yggdrasil <bodyfile>` (never raw `git commit`). Write the bodyfile to `.commits/<name>.md` with `add:` frontmatter listing the files to stage (paths relative to repo root). See `templates/commit.md`. The Co-Authored-By trailer is appended automatically.
- **No hard-wrapped prose** in any markdown you add (single-line paragraphs/bullets) — `gdd-doc-writing` rule, enforced.
- **Branch:** all of this lands on one topic branch (suggested `fix/ga-cleanups-b1-b3-b4-b7`) off an up-to-date `main`, one PR via `ws cr`.
- **The resolver helper:** `ws_validate_component()` in `scripts/ws-realm.sh:48` is the misnamed-but-working multi-kind target resolver. It accepts `yggdrasil`, realm dirs, hoard dirs, and ecosystem components, and sets the global `COMPONENT_DIR`. Most subcommands already call it; `ws diagnose` is the holdout (Task 4).
- **Pre-1.0 — favor clean breaks over compat shims.** This workspace is not yet at v1.0.0, so when a change can be made cleanly (rename a function, change an error string, drop a flag), do the clean rename/replace across all call sites — including tests — rather than carrying back-compat aliases or wrappers "just in case." Less surface, less to maintain. (This is why Task 6 renames outright instead of aliasing.)

## File Structure (what gets touched)

- `scripts/ws-audit-permissions.sh` — add normalization + one watchlist entry (B3). The matcher loop is `scan_file()` at lines ~144-185; the watchlist heredoc is `WATCHLIST_RAW` at ~110-133.
- `tests/ws-audit-permissions/audit.bats` — add B3 regression tests (existing patterns: `write_settings <scope> "<entries>"`, `run_audit`).
- `scripts/ws` — add `--help` detection to `ws_issue()` (~412), route `ws_diagnose()` (~434) through the resolver (B4, B1).
- `scripts/ws-realm.sh` — unify the resolver's miss-message; optional alias for the rename (B1).
- `.agent/skills/gdd-scribe/SKILL.md` — fix the `PARA Structure`→`PARA Conventions` cross-reference (B4).
- `AGENTS.md` + `CLAUDE.md` — one line: target-taking subcommands accept realm/hoard names (B1).
- `docs/plans/2026-06-08-gdd-ga-readiness-design.md` — mark B7 ✅ and B1/B3/B4 status, add the sequencing note (final task).

---

## Task 1: B7 — Confirm `ws hoard upgrade` is ungated, mark done

**Files:**
- Modify: `docs/plans/2026-06-08-gdd-ga-readiness-design.md` (B7 section) — deferred to Task 8 so all doc-status edits land in one commit.

- [ ] **Step 1: Verify no gate remains**

Run: `grep -rn "WS_HOARD_UPGRADE_ENABLED" scripts/`
Expected: no output (the gate variable was removed in the hoard-upgrade-v2 work, PRs #74-76).

- [ ] **Step 2: Verify the public command runs**

Run: `ws hoard upgrade --help`
Expected: prints the upgrade usage (the `--plan`/`--apply`/`--rollback` help from `scripts/ws-hoard.sh`), exit 0 — no "disabled / set WS_HOARD_UPGRADE_ENABLED" message.

- [ ] **Step 3: Record the finding**

No code change. B7 is confirmed done; its design-doc status flips to ✅ in Task 8. (If Step 1 unexpectedly finds the gate, stop and convert this task into "remove the `WS_HOARD_UPGRADE_ENABLED` guard from `scripts/ws-hoard.sh`" before continuing.)

---

## Task 2: B4a — `ws issue --help` (and sweep sibling handlers)

`ws issue --help` currently exits 1 with a terse `Usage:` line instead of the rich help other verbs emit, because `ws_issue()` lacks the "detect `--help` anywhere in args" loop that `ws_push()`/`ws_log()` have.

**Files:**
- Modify: `scripts/ws` — `ws_issue()` (~412-432); audit siblings.
- Test: `tests/ws-issue/help.bats` (new; model on `tests/ws-commit/help.bats`).

- [ ] **Step 1: Write the failing test**

Create `tests/ws-issue/help.bats` (and `tests/ws-issue/test_helper.bash` modeled on `tests/ws-commit/test_helper.bash`):

```bash
#!/usr/bin/env bats
load test_helper

@test "ws issue --help exits 0 and prints usage" {
    run ws_cli issue --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws issue"* ]]
}

@test "ws issue -h exits 0" {
    run ws_cli issue -h
    [ "$status" -eq 0 ]
}
```

(`ws_cli` is the helper that invokes `scripts/ws` under a sandboxed `ROOT_DIR` — copy its definition from `tests/ws-commit/test_helper.bash`. If that helper proves heavyweight for a help-only check, fall back to the manual verification in Step 4 and drop the bats file.)

- [ ] **Step 2: Run it to verify failure**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-issue/`
Expected: FAIL — `ws issue --help` exits 1 today.

- [ ] **Step 3: Add the `--help` loop to `ws_issue()`**

In `scripts/ws`, at the top of `ws_issue()` (right after the `# ws:use-when` comment, before the `if [[ $# -lt 4 ... ]]` arg check), insert the same pattern `ws_push()` uses:

```bash
    for _arg in "$@"; do
        if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
            cat <<'HELP'
Usage: ws issue <component> [remote] <title> <label> <bodyfile>

  component  Component, realm, or hoard to file the issue against
  remote     Optional; auto-detects if a single remote, else uses
             identity.forkOrg
  title      Issue title
  label      Issue label (must exist on the repo)
  bodyfile   Path (relative to workspace root) to an issue bodyfile
             — see templates/issue.md

Files a tracker issue with the Co-Authored-By context via git-issue.sh.
HELP
            return 0
        fi
    done
```

- [ ] **Step 4: Verify the test passes (and manual check)**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-issue/`
Expected: PASS.
Also run: `ws issue --help` → Expected: prints the usage block, exit 0.

- [ ] **Step 5: Sweep the other target-taking handlers**

Run: `grep -n 'cat <<.HELP' scripts/ws` and cross-check against the handler list (`ws_exec`, `ws_push`, `ws_cr`, `ws_log`, `ws_issue`, `ws_diagnose`, `ws_commit` via `scripts/ws-commit.sh`, etc.). For any handler that takes a positional and lacks the `--help`/`-h` loop, add the same loop with a one-paragraph usage. Known-missing as of writing: `ws_issue` (fixed above); verify `ws_cr` and `ws_diagnose` (`ws_diagnose` is also touched in Task 4 — fold its `--help` in there). Do **not** touch handlers that already detect `--help`.

- [ ] **Step 6: Commit**

Write `.commits/b4a-ws-issue-help.md` (`add:` the two test files + `scripts/ws`) with message `fix(ws): ws issue --help prints usage instead of erroring (B4)`, then:
`ws commit yggdrasil .commits/b4a-ws-issue-help.md`

---

## Task 3: B4b — Doc anchor/reference sweep

`gdd-scribe/SKILL.md:107` says "see PARA Structure above" but the section was renamed to `## PARA Conventions` (line 44). Fix that and grep for other stale internal cross-references.

**Files:**
- Modify: `.agent/skills/gdd-scribe/SKILL.md:107`
- Audit: all `.agent/skills/**/SKILL.md` + `docs/**/*.md`

- [ ] **Step 1: Fix the known-broken reference**

In `.agent/skills/gdd-scribe/SKILL.md` line 107, change `see PARA Structure above` to `see PARA Conventions above`. (The other in-file references — "Project Status Schema above" line 54, "Ceremony Layers below" line 278 — point at real sections `## Project Status Schema` (91) and `## Ceremony Layers` (276); leave them.)

- [ ] **Step 2: Sweep for other stale internal references**

Run: `grep -rn -iE "see [^.]* (above|below)" .agent/skills/ docs/`
For each hit, confirm the referenced phrase matches an actual heading in the same file. Fix mismatches (rename the reference to the current heading text). Skip references that resolve correctly. This is judgment work — only change a reference when the target heading demonstrably doesn't exist under that name.

- [ ] **Step 3: Verify**

Run: `grep -n "PARA Structure" .agent/skills/gdd-scribe/SKILL.md`
Expected: no output (all references now say "PARA Conventions").

- [ ] **Step 4: Commit**

Write `.commits/b4b-doc-anchors.md` (`add:` the changed skill/doc files) with message `docs: reconcile stale "see X above/below" cross-references (B4)`, then `ws commit yggdrasil .commits/b4b-doc-anchors.md`.

---

## Task 4: B1a — Route `ws diagnose` through the resolver (realm/hoard support)

`ws_diagnose()` (`scripts/ws:434`) special-cases `yggdrasil` and otherwise assumes a `components/` ecosystem entry, so `ws diagnose <realm|hoard>` fails with "Not declared in ecosystem config." Route it through `ws_validate_component` so it resolves all kinds, and skip the ecosystem repo/tier lookup for non-component targets.

**Files:**
- Modify: `scripts/ws` — `ws_diagnose()` (~434-480, the target-resolution block).

- [ ] **Step 1: Read the current resolution block**

Read `scripts/ws:434-480`. The relevant logic: it sets `comp_dir` to `$ROOT_DIR` for `yggdrasil`, else looks up `repo`/`tier` from the ecosystem and sets `comp_dir="$COMPONENTS_DIR/$comp"`, returning 1 if `repo` is empty. The remotes + token-coverage sections below (lines ~482-) operate on `comp_dir` and work for any git repo.

- [ ] **Step 2: Replace the resolution block**

Resolve via the shared helper and only do the ecosystem repo/tier lookup when the target is actually a declared component. Replace the `if [[ "$comp" == "yggdrasil" ]] … else … fi` block (the part that sets `comp_dir` and prints the ecosystem line) with:

```bash
    # Resolve the target dir via the shared multi-kind helper (accepts
    # component, realm, hoard, and yggdrasil). ws_validate_component exits
    # non-zero with its own message if the name resolves to nothing.
    ws_validate_component "$comp"
    local comp_dir="$COMPONENT_DIR"

    if [[ "$comp" == "yggdrasil" ]]; then
        echo "  Workspace root (not a declared ecosystem component)"
    elif [[ "$comp_dir" == "$COMPONENTS_DIR/"* ]]; then
        # Declared component — show ecosystem repo/tier.
        local repo tier
        repo=$(COMP="$comp" yq '.components[strenv(COMP)].repo // ""' "$eco" 2>/dev/null)
        [[ "$repo" == "null" ]] && repo=""
        tier=$(COMP="$comp" yq '.components[strenv(COMP)].tier // ""' "$eco" 2>/dev/null)
        [[ "$tier" == "null" ]] && tier=""
        [[ -n "$repo" ]] && echo "  Ecosystem repo : $repo"
        [[ -n "$tier" ]] && echo "  Tier           : $tier"
    else
        # Realm or hoard — no ecosystem entry; remotes + token coverage below
        # are what matter for push/cr diagnosis.
        echo "  Realm/hoard target (not a declared ecosystem component)"
    fi
```

Keep everything below (the `if [[ -d "$comp_dir/.git" ]]` clone check, remotes, token coverage) unchanged.

- [ ] **Step 3: Add the `--help` loop (folds in B4a Step 5 for this handler)**

At the top of `ws_diagnose()`, add the same `--help`/`-h` detection loop pattern, with a one-paragraph usage noting it accepts `<component|realm|hoard|yggdrasil>`.

- [ ] **Step 4: Verify on a real component, realm, and hoard**

Run: `ws diagnose yggdrasil` → Expected: "Workspace root …" + remotes + token coverage, exit 0.
Run: `ws diagnose thalami-Cervator` (or whatever `ws hoard list` shows active) → Expected: "Realm/hoard target …" + remotes + token coverage — **not** "Not declared in ecosystem config."
Run: `ws diagnose <a-cloned-component>` → Expected: unchanged behavior (Ecosystem repo/Tier still shown).
Run: `ws test yggdrasil` → Expected: full suite still green (no regression).

- [ ] **Step 5: Commit**

Write `.commits/b1a-ws-diagnose-targets.md` (`add: scripts/ws`) with message `fix(ws): ws diagnose accepts realm/hoard targets via the shared resolver (B1)`, then `ws commit yggdrasil .commits/b1a-ws-diagnose-targets.md`.

---

## Task 5: B1b — Unify the resolver miss-message + AGENTS.md/CLAUDE.md note

**Files:**
- Modify: `scripts/ws-realm.sh` — `ws_validate_component()` (lines 73-76, 89-93, 98-102 error branches).
- Modify: `AGENTS.md` (the "Reflex Contract" / `ws orient` area) and `CLAUDE.md` ("Workspace CLI" bullet).

- [ ] **Step 1: Make the "not found" message kind-agnostic**

In `scripts/ws-realm.sh`, the resolver currently emits component-flavored errors. For the two "doesn't resolve" branches — the invalid-name branch (73-76) and the not-declared branch (89-93) — keep the specific guidance but make the headline name-kind-neutral. Change the not-declared branch message from:

```bash
        echo "ERROR: '$name' is not declared in ecosystem config." >&2
        echo "  Run 'ws list' to see available components." >&2
```

to:

```bash
        echo "ERROR: no such target '$name' (looked for a component, realm, or hoard)." >&2
        echo "  Components must be declared in ecosystem config — run 'ws list'." >&2
        echo "  Realms live under realms/, hoards under hoards/ (must be cloned)." >&2
```

Leave the "is not cloned locally" branch (98-102) as-is — it's already accurate for a declared-but-not-cloned component.

- [ ] **Step 2: Verify the message**

Run: `ws diagnose definitely-not-a-real-target` → Expected: the new "no such target … component, realm, or hoard" message, non-zero exit.
Run: `ws test yggdrasil` → Expected: suite green (check `tests/ws-test/` and `tests/ws-commit/` helpers don't assert on the old string — grep them first: `grep -rn "not declared in ecosystem" tests/`; if a fixture asserts the old text, update it).

- [ ] **Step 3: Add the doc note**

In `AGENTS.md`, in the section that lists the unconditional `ws` verbs / reflex contract, add one line: `Subcommands that take a target (commit, push, cr, issue, review, log, diagnose, test, lint) also accept realm and hoard names, not just components.`
In `CLAUDE.md`, in the "Workspace CLI" bullet, append the same clause.

- [ ] **Step 4: Commit**

Write `.commits/b1b-resolver-message-doc.md` (`add:` `scripts/ws-realm.sh`, `AGENTS.md`, `CLAUDE.md`, and any updated test fixture) with message `fix(ws): kind-neutral resolver error + document realm/hoard targets (B1)`, then `ws commit yggdrasil .commits/b1b-resolver-message-doc.md`.

---

## Task 6: B1c — Rename `ws_validate_component` → `ws_resolve_target` (clean, no alias)

The helper resolves all target kinds but its name says "component." Clean global rename for clarity. Pre-1.0, so **no back-compat alias** — rename every reference (scripts + tests) in one sweep. Lowest-priority item in the batch; a time-boxed session can drop it without affecting B1's functional fixes (Tasks 4-5).

**Files:**
- Modify: `scripts/ws-realm.sh` (definition + its `# Usage:`/`# Validate a component name` doc-comment), every `scripts/` call site, and both test helpers that reference it.

- [ ] **Step 1: Enumerate every reference**

Run: `grep -rln "ws_validate_component" scripts/ tests/`
Expected set (confirm against the grep): `scripts/ws-realm.sh`, `scripts/ws`, `scripts/ws-commit.sh`, `scripts/ws-test.sh`, `scripts/ws-lint.sh`, `scripts/ws-pull.sh`, `scripts/ws-review.sh`, `tests/ws-test/test_helper.bash`, `tests/ws-commit/test_helper.bash`.

- [ ] **Step 2: Rename across all of them**

Replace `ws_validate_component` → `ws_resolve_target` in every file from Step 1 (definition, all call sites, both test helpers — no alias, nothing left behind). Also update the doc-comment above the definition in `scripts/ws-realm.sh` (the `# Usage: ws_validate_component <name>` and `# Validate a component name against ecosystem.yaml.` lines) to describe resolving a **target** (component / realm / hoard / yggdrasil), not just a component.

- [ ] **Step 3: Verify nothing references the old name**

Run: `grep -rn "ws_validate_component" scripts/ tests/`
Expected: no output.
Run: `ws test yggdrasil` → Expected: full suite green.
Run: `ws status` and `ws diagnose yggdrasil` → Expected: normal output (smoke check that sourcing still works).

- [ ] **Step 4: Commit**

Write `.commits/b1c-resolver-rename.md` with message `refactor(ws): rename ws_validate_component → ws_resolve_target (B1)`, then `ws commit yggdrasil .commits/b1c-resolver-rename.md`.

---

## Task 7: B3 — `ws audit-permissions` de-noise (normalize + catch-all)

**The meaty one — TDD.** Today the matcher glob-matches each allow entry against the watchlist. The `Bash(bash *)` watchlist entry therefore flags *every* narrow `Bash(bash scripts/ws <subcommand>)` literal (~120 false positives on a clean config), while the genuinely-broad `Bash(bash scripts/ws:*)` catch-all (the real-world over-grant that motivated this) slips through because there's no watchlist entry for it. Fix both with a surgical normalization (`bash <path>/scripts/ws` → `ws`, mirroring the PreToolUse hook) plus one new catch-all entry — **without** changing the deliberate curl/exec flagging the existing tests assert.

**Files:**
- Test: `tests/ws-audit-permissions/audit.bats` (add cases).
- Modify: `scripts/ws-audit-permissions.sh` (`WATCHLIST_RAW` heredoc + `scan_file()`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/ws-audit-permissions/audit.bats`:

```bash
# ─── B3: ws-wrapper normalization + catch-all ───────────────────────

@test "normalize: bash scripts/ws <subcommand> literals are NOT flagged" {
    write_settings project "Bash(bash scripts/ws help)
Bash(bash scripts/ws review * *)
Bash(bash scripts/ws status)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "detect: Bash(bash scripts/ws:*) catch-all is high" {
    write_settings project-local "Bash(bash scripts/ws:*)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
    # Original (un-normalized) entry is what gets REPORTED.
    [[ "$output" == *"Bash(bash scripts/ws:*)"* ]]
}

@test "detect: normalized Bash(ws:*) catch-all is high" {
    write_settings project-local "Bash(ws:*)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "normalize: subcommand-pinned :* is NOT flagged" {
    write_settings project "Bash(bash scripts/ws commit:*)
Bash(ws commit:*)
Bash(bash scripts/ws test * *)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "normalize: ws exec danger is preserved through normalization" {
    write_settings user "Bash(bash scripts/ws exec mimir rm)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
    [[ "$output" == *"ws exec runs arbitrary commands"* ]]
}

@test "normalize: absolute-path ws wrapper literal is NOT flagged" {
    write_settings project-local "Bash(bash /d/Dev/GitWS/yggdrasil/scripts/ws status)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-audit-permissions/`
Expected: the new tests FAIL — today `Bash(bash scripts/ws help)` flags via `Bash(bash *)`, and `Bash(bash scripts/ws:*)` flags nothing.

- [ ] **Step 3: Add the catch-all watchlist entry**

In `scripts/ws-audit-permissions.sh`, in the `WATCHLIST_RAW` heredoc (after the `Bash(bash scripts/ws exec * *)` line, before `Bash(bash *)`), add:

```text
Bash(ws:*)|high|Subcommand-less ws catch-all auto-approves EVERY ws subcommand including push/cr/issue/exec. Pin the subcommand (e.g. Bash(ws commit:*)) instead.
```

Do **not** add `Bash(ws *)` — its glob would re-introduce over-matching of narrow `Bash(ws review * *)`-style allows. Only the colon-form `Bash(ws:*)` is the catch-all.

- [ ] **Step 4: Add normalization in `scan_file()`**

In `scan_file()`, inside the `while IFS= read -r entry` loop, after the CRLF strip (`entry="${entry%$'\r'}"`) and before the watchlist `while` loop, compute a normalized form used **only for matching** (the original `$entry` is still what gets reported):

```bash
        # Normalize the ws wrapper form to the bare `ws` form before
        # matching, mirroring the PreToolUse hook. This collapses
        # `Bash(bash scripts/ws <sub>)` and `Bash(bash <abs>/scripts/ws <sub>)`
        # to `Bash(ws <sub>)`, so a narrow per-subcommand allow no longer
        # trips the broad `Bash(bash *)` watchlist entry, while the
        # subcommand-less catch-all (`...ws:*` → `ws:*`) still matches the
        # new high-severity entry. Original `$entry` is preserved for output.
        local match_entry
        match_entry=$(printf '%s' "$entry" | sed -E 's#bash ([A-Za-z]:)?[^ )]*scripts/ws([ :)])#ws\2#')
```

Then change the watchlist comparison from `if [[ "$entry" == $pattern ]]` to `if [[ "$match_entry" == $pattern ]]`. Leave `FINDINGS+=("$scope|$file|$entry|…")` reporting the **original** `$entry`.

- [ ] **Step 5: Run the full audit suite**

Run: `bash tests/vendor/bats-core/bin/bats tests/ws-audit-permissions/`
Expected: ALL tests pass — the new B3 cases AND every pre-existing case (the `Bash(bash *)`, `Bash(curl *)`, `Bash(ws exec *)`, `Bash(*)`, sudo/eval, CRLF, YAML-escape, scope-label tests must stay green; normalization only touches `bash …/scripts/ws` strings, so none of them are affected).

- [ ] **Step 6: Real-world smoke check**

Run: `ws audit-permissions`
Expected: a short findings list (or `[]`) — **not** the ~120-entry flood. If the project's `settings.json` is clean of genuine broad patterns, expect `[]`/exit 0. (This is the regression that motivated B3.)

- [ ] **Step 7: Commit**

Write `.commits/b3-audit-normalize.md` (`add:` `scripts/ws-audit-permissions.sh`, `tests/ws-audit-permissions/audit.bats`) with message `fix(ws): audit-permissions normalizes ws-wrapper form + flags the ws:* catch-all (B3)`, then `ws commit yggdrasil .commits/b3-audit-normalize.md`.

---

## Task 8: Update the GA design doc + sequencing note

**Files:**
- Modify: `docs/plans/2026-06-08-gdd-ga-readiness-design.md`

- [ ] **Step 1: Flip statuses**

In the GA readiness doc: mark **B7** ✅ (gate confirmed removed; `ws hoard upgrade` runs). Update **B1** to "✅ (residual landed: `ws diagnose` routed, kind-neutral error, doc note" + note whether the optional rename was done). Mark **B4** ✅ (help uniformity + anchor sweep). Mark **B3** ✅ (normalize + catch-all, with tests).

- [ ] **Step 2: Add a one-paragraph sequencing/handoff note**

Under the "Suggested tracking" section, add a short note: this batch (B1/B3/B4/B7) landed via `docs/plans/2026-06-10-gdd-ga-cleanups-plan.md`; the remaining GA blockers are **B2** (cross-platform runs — execute the checklist on the two trial machines, no plan needed) and **B6** (SemVer/CHANGELOG — needs the versioning-unit decision then mechanical); **P\*** items are independent papercuts; **R\*** roadmap items each need their own brainstorm before a plan.

- [ ] **Step 3: Commit**

Write `.commits/ga-doc-status.md` (`add:` the design doc) with message `docs(gdd): mark B1/B3/B4/B7 done + sequencing note (GA readiness)`, then `ws commit yggdrasil .commits/ga-doc-status.md`.

---

## Open the PR

- [ ] After all tasks: `ws push yggdrasil fix/ga-cleanups-b1-b3-b4-b7`, then `ws cr yggdrasil "fix(ws): GA cleanups — B1/B3/B4/B7" .crs/ga-cleanups.md` (draft a `.crs/` body from `templates/change.md` summarizing the four items). Then triage with `ws review yggdrasil <pr#>`.

---

## Self-Review

**Spec coverage:** B1 → Tasks 4 (diagnose), 5 (error+doc), 6 (optional rename). B3 → Task 7. B4 → Tasks 2 (help), 3 (anchors). B7 → Task 1 (+ Task 8 status). GA-doc status → Task 8. All four design-doc items covered.

**Placeholder scan:** Every code step shows the actual bash/test code or the exact `grep`/run command + expected output. No "TBD"/"handle edge cases"/"similar to above".

**Consistency:** The resolver is referred to as `ws_validate_component` (current name) in Tasks 4-5; Task 6 renames it to `ws_resolve_target` everywhere as the final step, so earlier tasks' references are valid as written and the rename is one clean sweep with nothing left behind. The B3 normalization preserves the original `$entry` for reporting while matching on `$match_entry`, so the YAML-escape and scope-label tests (which assert on the reported entry) stay green.

**Known risk to watch:** the B3 `sed` regex assumes the wrapper appears as `bash [<drive>:]<path>scripts/ws<delim>`. If a settings entry uses a more exotic invocation (e.g. `sh scripts/ws`), it won't normalize — acceptable (that's a rarer/odder allow worth a prompt anyway), but note it in the PR description so it's a conscious boundary, not a silent gap.
