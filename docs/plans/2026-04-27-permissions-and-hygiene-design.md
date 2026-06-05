# Permissions Documentation + Workspace Tooling Hygiene Pass — Design Spec

**Date:** 2026-04-27
**Status:** Draft

---

## Summary

A bundled hygiene pass that surfaces from the realms-and-hoards review cycle (PRs #43–#45). Nine items in one PR, grouped into four coherent threads:

- **Tooling fixes** — three small bash-script defects (`set -euo pipefail` placement, stale `Co-Authored-By` model default, router env-var clobber).
- **Workspace tooling extension** — `ws status` walks `realms/` and `hoards/` in addition to `components/`.
- **Permission system documentation** — new `docs/gdd/permissions.md` explaining the `.claude/settings.json` allowlist structure, the two-layer defense model, empirical matcher findings, and the cross-reference rule for keeping doc and config in sync.
- **Permission management skill + skill updates** — new `gdd-permissions` skill for per-pattern safety analysis and "don't ask again" judgment; `gdd-orientation` gains a Thalamus-commit-cadence nudge plus a pointer at the new skill; `gdd-housekeeping` gains a permission-related-item hook.
- **Doc cleanup** — relocate `docs/agent-security/` (predates GDD; reflects general AI-sandboxing exploration that's been superseded by internal corporate AI-sandboxing tooling) into `realms/realm-siliconsaga/docs/agent-security/` so it stays accessible but doesn't compete with the new permissions doc for shelf space.

The pass is sized to land as a single PR. None of the items individually justifies its own arc; bundled, they form a coherent "post-#45 cleanup" landing.

---

## Scope (the 9 items)

| # | Item | Type | Files touched |
|---|------|------|---------------|
| 1 | `set -euo pipefail` placement in sourceable scripts | Tooling fix | `scripts/ws-realm.sh`, `scripts/ws-hoard.sh`, `scripts/ws-component.sh` |
| 2 | Stale `Co-Authored-By: Claude Opus 4.6` default | Tooling fix | `scripts/ws-commit.sh` |
| 3 | Router env-var clobber (`scripts/ws` unconditional `ROOT_DIR`/etc) | Tooling fix | `scripts/ws` |
| 4 | Relocate `docs/agent-security/` → realm | Doc move | `git mv` of nine files; new Thalamus pointer |
| 5 | New permissions doc | New file | `docs/gdd/permissions.md` |
| 6 | New gdd-permissions skill | New file | `.agent/skills/gdd-permissions/SKILL.md` |
| 7 | `gdd-orientation` updates — permissions skill pointer + commit-cadence nudge | Skill update | `.agent/skills/gdd-orientation/SKILL.md` |
| 8 | `gdd-housekeeping` updates — permissions skill hook | Skill update | `.agent/skills/gdd-housekeeping/SKILL.md` |
| 9 | `ws status` walks realms + hoards | Tooling extension | `scripts/ws-status.sh` |

---

## Tooling fixes (items 1–3)

### 1. `set -euo pipefail` placement

**Problem:** `scripts/ws-realm.sh`, `scripts/ws-hoard.sh`, and `scripts/ws-component.sh` all run `set -euo pipefail` at the top, *before* the source-vs-execute guard `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` near the bottom. Sourcing one of these scripts (e.g. `ws-component.sh` sources `ws-realm.sh` to inherit `ws_resolve_ecosystem`) leaks strict mode into the parent shell.

**Fix:** Move `set -euo pipefail` after the source-vs-execute guard in all three scripts. Identical edit per script:

```bash
# Old (top of file):
set -euo pipefail
...
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
# (dispatch logic)

# New:
...
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
set -euo pipefail
# (dispatch logic)
```

**Verification:** Source each script in a parent shell with `set +e` set explicitly; confirm parent shell flags are unchanged after the source.

### 2. Stale `Co-Authored-By: Claude Opus 4.6` default

**Problem:** `scripts/ws-commit.sh` hardcodes `Claude ${CLAUDE_MODEL:-Opus 4.6}` for the trailer. The default is stale (sessions are running 4.7); it's also brittle to any model change.

**Fix:** Bump the default string to `Opus 4.7` so today's behavior matches the running model, and document the `$CLAUDE_MODEL` env-override path more clearly in the comment above. The Thalamus question about sub-agent / Sonnet / Haiku attribution is deferred — sub-agents currently inherit the parent's identity for commit purposes (they don't typically commit independently); that concern is real but separate from this PR.

### 3. Router env-var clobber

**Problem:** `scripts/ws` near the top sets:

```bash
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
REALMS_DIR="$ROOT_DIR/realms"
COMPONENTS_DIR="$ROOT_DIR/components"
```

These are unconditional assignments. Caller-provided env-var values (e.g. `COMPONENTS_DIR=/tmp/test ws component init …` for synthetic-fixture smoke tests) get clobbered before the dispatched script sees them. The sub-scripts use the `: "${VAR:=default}"` pattern correctly, so direct invocations (`bash scripts/ws-component.sh init …`) honor the overrides — but the router strips them.

**Fix:** Switch the four router assignments to `: "${VAR:=default}"`:

```bash
: "${ECOSYSTEM:="$ROOT_DIR/ecosystem.yaml"}"
: "${REALMS_DIR:="$ROOT_DIR/realms"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"
```

`ROOT_DIR` itself remains the same (it's derived from the script's own location).

**Verification:** Run `COMPONENTS_DIR=/tmp/test ws component init gh-pages testblog` against a synthetic fixture; confirm it lands in `/tmp/test/components/testblog/`, not the real workspace.

---

## Workspace tooling extension (item 9): `ws status` walks realms + hoards

**Today:** `ws status` walks declared ecosystem components and reports each one's git status (branch, dirty file count, untracked).

**Change:** Also walk `realms/*/.git/` and `hoards/*/.git/` directories on disk (not via ecosystem config; realms and hoards aren't in components-style declarations). Output sections:

```text
=== yggdrasil ===
  branch: main  (clean)

=== components ===
=== nordri ===
  branch: main  (clean)
=== mimir ===
  branch: main  (dirty — 2 file(s))
   M cucumber.json
   ...

=== realms ===
=== realm-siliconsaga ===
  branch: main  (clean)

=== hoards ===
=== thalami-cervator ===
  branch: main  (dirty — 1 file(s))
   M Dionysus-thalamus.md
```

Component / realm / hoard sections suppressed when empty (e.g. no realms or hoards cloned).

**Why now:** `gdd-orientation`'s commit-cadence nudge (item 7) needs cross-workspace dirty-state visibility on hoards. Building it inline inside the orientation skill duplicates `ws status`'s walk logic. Extending `ws status` is the right place for the capability AND has independent value (manually checking "what's still uncommitted across everything" is a real ask).

**Implementation note:** The hoard walk reuses the existing component-walk loop pattern. ~15-20 lines of bash. No changes to the discovery logic in `ws-realm.sh` (no need — we walk by directory presence, not active-realm/active-thalami selection).

---

## Doc relocation (item 4): `docs/agent-security/` → realm

**Files in scope (9):**

```text
docs/agent-security/advanced-capability-model.md
docs/agent-security/implementation-phases.md
docs/agent-security/openclaw-security.md
docs/agent-security/pattern-calendar.md
docs/agent-security/pattern-chat-segmentation.md
docs/agent-security/pattern-contact-management.md
docs/agent-security/pattern-email.md
docs/agent-security/pattern-gitops-staging.md
docs/agent-security/pattern-voice-pipeline.md
```

**Rationale:** These predate GDD and reflect general AI-tooling-sandboxing exploration that's been substantially superseded (internal corporate AI-sandboxing tooling addresses the same concerns more concretely). Keeping them in upstream yggdrasil's `docs/` competes with the new GDD-specific permissions doc and confuses readers about the boundary between "GDD methodology" (this repo) and "personal exploration / community-specific notes" (the realm).

**Move target:** `realms/realm-siliconsaga/docs/agent-security/` (preserving filenames). The realm already has `docs/plans/` for community-specific design plans (`bifrost-first-contact`, etc.); adding a sibling `docs/agent-security/` keeps the existing organization intact.

**Mechanism:** Move the files across two repos. Realm-side first (so the content exists in its new home before being removed from yggdrasil — minimizes the window where it exists nowhere live, even though git history would preserve it either way):

1. **Realm side first.** Copy the nine files from `docs/agent-security/` into `realms/realm-siliconsaga/docs/agent-security/`. `git add`, write a bodyfile that references the yggdrasil PR by number, `ws commit realm-siliconsaga <bodyfile>`, then `ws push realm-siliconsaga main`. Note the realm commit SHA.
2. **Yggdrasil side second.** `git rm -r docs/agent-security/` (staged via the hygiene-PR commit's `remove:` frontmatter). The yggdrasil commit message references the realm commit SHA and explains the rationale.

If any internal yggdrasil docs link to `docs/agent-security/*` (verified absent at design time via grep, but re-check during implementation), update those to either point at the new realm path or be cut.

**Cross-references:** No yggdrasil docs currently link to `docs/agent-security/*` (verified by grep before the move). If any are found at implementation time, update them to point at the new realm location.

**Thalamus pointer:** Add a single Observations entry in the user's Thalamus noting where the docs went and why, so future security-oriented work can find them.

---

## Permission system documentation (item 5): `docs/gdd/permissions.md`

**Location:** `docs/gdd/permissions.md` — sits next to GDD methodology docs. Sibling to other future GDD-specific feature docs.

**Audience (in priority order):**

1. **Security-paranoid yggdrasil users** — humans who want to verify the safety claims for themselves before trusting an AI agent with the workspace. They want enough detail to read the actual `.claude/settings.json` and reason about each pattern.
2. **Automated review tools** (CodeRabbit, etc.) — they crawl docs and use them as context when reviewing PRs that touch `.claude/settings.json`. The doc functions as a spec for what a "safe pattern" looks like.
3. **Agents reading the doc on-demand** — the `gdd-permissions` skill points here for reference content; agents pull this in when reasoning about a specific pattern.
4. **Future maintainers** — context for why patterns are scoped the way they are, so subsequent edits don't accidentally widen things.

**Sections:**

1. **What `.claude/settings.json` is and how it's loaded.** Project-level (`.claude/settings.json`, committed) vs user-level (`.claude/settings.local.json`, gitignored) — what wins, when. The `permissions.allow` / `permissions.deny` structure. The `enableAllProjectMcpServers: false` field.
2. **Pattern shapes.** Exact-form (`Bash(ws status)`, `Bash(git -C * remote -v)`); prefix wildcards (`Bash(git -C * show *)`); MCP tool names (full name, no wildcard). The space-before-`*` rule for prefix matching.
3. **The two-layer defense.** Layer 1: subcommand-level (the chosen `git` / `ws` / etc subcommands are read-only at the porcelain level). Layer 2: matcher-level (compound commands per-segment validated; `$(...)` substitution categorically rejected; exact-form pinning honored literally).
4. **Empirical matcher findings.** A table of the test cases run during this design's brainstorm (and any added during implementation), each showing pattern, attempted command, expected outcome, observed outcome. Functions as both documentation AND the seed for the automated-regression-testing work tracked at issue #46.
5. **When to widen vs narrow patterns.** Decision criteria: if the subcommand has no mutating flag-form, prefix-wildcard is fine; if it does (e.g. `git remote add`, `git branch -d`), pin to the specific safe form. The no-`bash *` and no-`bash scripts/ws *` widening rules.
6. **Cross-reference rule.** When you modify `.claude/settings.json`'s allowlist, also update this doc's empirical-findings table. When this doc says "X is rejected," the table is authority. Mismatches are PR-blocking.
7. **Future directions.** Cross-framework porting (mapping Claude Code semantics to Codex / Gemini / Cursor / etc — pulled out of this PR's skill scope but worth flagging here as an upcoming extension). Automated regression testing (issue #46). Sandboxing tools (OpenShell / NemoClaw lineage — referenced via the relocated `docs/agent-security/` content for whoever picks up that thread).

**Length target:** ~250-400 lines. Long enough to be authoritative; short enough that drift is manageable. The empirical-findings table is the densest section; everything else is prose with bullets.

---

## gdd-permissions skill (item 6): `.agent/skills/gdd-permissions/SKILL.md`

**When to use:**

- Agent is about to add or edit a permission pattern (sibling to `fewer-permission-prompts`, which handles the from-transcripts case; this skill handles per-pattern safety analysis when you already know what you want to add).
- Agent is at a permission prompt and considering whether to accept a "don't ask again" offer.
- Agent is asked to explain the permission system to a user.
- Agent is reviewing `.claude/settings.json` changes during code review.

**Skill content sections:**

1. **When to use.** The four triggers above.
2. **Pattern-form decision tree.** Quick visual: "Subcommand has no mutating flag-form? → prefix wildcard fine. Has mutating flag-form? → pin to exact safe form. Compound command (`bash *`, `python *`)? → never widen, always exact." Three or four common scenarios with the "right" answer.
3. **The "don't ask again" judgment guidance.** When Claude Code offers a "don't ask again" with a wide pattern (e.g. `Bash(xxd*)`), the skill gives the decision criteria: is this command read-only? Does the offered pattern admit any non-read-only variant? If yes to either, decline; suggest a narrower pattern manually. If both no, accept. Worked example.
4. **Scope-narrowing checklist.** Before adding a pattern: (1) Could this match a mutating subcommand? (2) Does the wildcard admit shell metacharacters that would change semantics? (3) Is there an existing auto-allowed form that covers this without a custom rule? (4) Does the pattern align with `docs/gdd/permissions.md`'s exact-form-vs-wildcard guidance for this command?
5. **The cross-reference rule.** When modifying `.claude/settings.json`'s allowlist, also update `docs/gdd/permissions.md`'s empirical-findings table — the two are paired artifacts.
6. **Pointers.** `fewer-permission-prompts` for transcript-driven bulk additions; `docs/gdd/permissions.md` for full reference content; issue #46 for the regression-testing future.

**What this skill does NOT cover (yet):**

- Cross-framework porting (mapping to Codex / Gemini / Cursor / etc.). Mentioned in the doc's Future Directions and in this skill's pointers, but not in v1's content. Substantial scope; deferred to its own arc.

**Length target:** ~80-150 lines. Mostly bullets and tables. Points at the doc for reference content; doesn't duplicate.

**Loading discipline:** On-demand only. NOT loaded by default at session start. `gdd-orientation` includes a one-line pointer ("for permission prompts during this session, consider invoking gdd-permissions") so the agent knows the skill exists; actual content loads only when invoked. Avoids preloading substantial content into every session's baseline.

---

## `gdd-orientation` updates (item 7)

Two additions:

**A. Pointer at gdd-permissions skill.** A short paragraph in the existing orientation flow noting that the `gdd-permissions` skill exists for permission-prompt decisions during the session. Doesn't preload; just primes.

**B. Thalamus commit-cadence nudge.**

Trigger condition (evaluated at session start, after thalami-hoard discovery):

```text
1. Active thalami hoard exists.
2. `git -C <hoard> diff --quiet HEAD -- <machine>-thalamus.md` returns non-zero (file is dirty).
3. (now - last_commit_timestamp) > commit_staleness_days (read from frontmatter; default 2).
```

If all three: surface a single conversational beat. Wording:

```text
Thalamus: <N> uncommitted observations. Last commit was <X> days, <Y> hours ago
(threshold: commit_staleness_days = <Z>). Want me to commit these before we
start, or save for later?
```

Mechanism: `git -C <hoard> log -1 --format=%ct <machine>-thalamus.md` returns Unix timestamp. Subtract from `date +%s`. Format elapsed time as days + hours. Honest about the actual elapsed time; don't round to "calendar days" (avoids the post-midnight false-positive case).

Below threshold or clean: silent (no mention at all in orientation; clean noise floor).

**C. New Thalamus frontmatter field:** `commit_staleness_days: 2` (default if unset; user can configure). Mirrors the existing `staleness_days: 14` for housekeeping audits.

**Update the thalamus template (`templates/thalamus.md`):** add `commit_staleness_days: 2` to the example frontmatter block with an inline comment explaining what it does.

---

## `gdd-housekeeping` updates (item 8)

Add a step to the existing housekeeping flow: when reviewing items in the Thalamus, if any item mentions permissions / `.claude/settings.json` / a permission prompt the user wants to follow up on, prompt the user to walk through it via the `gdd-permissions` skill.

This is a single short bullet inserted into the existing per-item review process. Not a new mode; just an added invocation hook.

---

## Migration / Impact

**Tooling fixes (1–3):**

- Fix #1 (`set -euo pipefail`) is invisible to users — sourcing patterns are agent-internal.
- Fix #2 (Co-Authored-By default) changes commit attribution from "Claude Opus 4.6" to "Claude Opus 4.7" by default. Cosmetic.
- Fix #3 (router env-var clobber) is also invisible in normal use; only affects synthetic-fixture smoke tests that rely on env-var overrides.

**`ws status` extension (9):**

Pure additive. Existing output for components/yggdrasil-root unchanged; realms/ and hoards/ sections appear at the bottom.

**Doc relocation (4):**

URLs to `docs/agent-security/*` from outside the repo (if any) break. Verified by grep at design time that no internal docs link there. The new realm location is referenced in the Thalamus.

**Permissions doc + skill (5–6):**

Pure additive. Nothing existed to compete with.

**Skill updates (7–8):**

`gdd-orientation` adds a new behavior (commit-cadence nudge) gated on a frontmatter field that defaults to a sensible value. Existing thalami without the field get the default-2-days behavior. The pointer-at-gdd-permissions is a short paragraph; doesn't change orientation flow.

`gdd-housekeeping` gets one new bullet in the per-item review.

---

## Future Directions

- **Cross-framework permissions porting** — map Claude Code's `.claude/settings.json` semantics to Codex / Gemini / Cursor / etc. Substantial enough to warrant its own arc; mentioned in the doc and pointed at from the skill.
- **Automated regression testing of allowlist patterns** — issue #46. Pairs with #24's Discord-based behavioral testing infrastructure. Not short-term.
- **`docs/agent-security/` revival** — the relocated content might inform a future GDD security category (sibling to permissions). Pinned in Thalamus for visibility.
- **`ws status` further extensions** — could grow flags like `--dirty-only` or `--type=hoards`. Not needed for v1; usage will indicate.
- **Configurable per-hoard cadence** — today the `commit_staleness_days` frontmatter field applies to the active thalami hoard. If users start syncing other hoard types regularly (Obsidian, claudesidian), per-hoard threshold might be warranted.
- **Thalamus commit-cadence detection in housekeeping too** — currently orientation does the check. Housekeeping could mirror it for users who skip orientation. Defer until use shows it's needed.
