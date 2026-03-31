# DI Migration Review — Design

**Date:** 2026-03-28
**PR under review:** MovingBlocks/Terasology#5299 (feat!: gestalt-di migration)
**Branch:** `review/post-di` (off local `develop` with DI merge applied)
**Goal:** Address review findings in a clean PR containing only the review-fix delta.

## Context

PR #5299 is a 137-file refactor migrating Terasology from `CoreRegistry`/manual
wiring to Gestalt DI. It has been open for ~2 years. The PR has been merged
locally into `develop`, and `review/post-di` branches off that merge point.

Review comments exist from:
- **BSA (BenjaminAmos)** — PR author, 14 inline comments on #5299 (high signal)
- **Copilot** — 3 blocking findings, no inline comments
- **CodeRabbit** — 17 inline comments (not yet triaged)
- **BSA on PR #5304** — secondary PR (Gemini-generated, low-quality code but
  useful review discussion, especially around DI patterns and test conventions)

Review threads on PR #5299 will NOT be resolved — kept for future reference.

## Approach: Hybrid severity-first

**Phase 1 — Runtime correctness fixes** (this PR)
Things that affect whether the game works correctly at runtime.

**Phase 2 — Code quality and pattern enforcement** (future PR)
Cleanup, naming, convention enforcement, Context injection migration.

## Testing

Terasology is a 15-year-old game with extensive tech debt and emergent "quirk
features." Automated tests provide limited signal for this refactor. The primary
testing method is hands-on in-game testing by the project maintainer, including
multiplayer connectivity. The maintainer is the test oracle — flag uncertain
changes for manual verification rather than assuming correctness from code
reading alone.

## Phase 1 — Runtime Correctness Fixes

### P1-1: Gestalt version bump
Bump `8.0.0-SNAPSHOT` to `8.0.1-SNAPSHOT` in `settings.gradle.kts` and
`build-logic/` references. The 8.0.1 branch contains DI refactor changes
that the game depends on.

### P1-2: StateLoading.java
BSA flags this as "the most impactful but also problematic changes" and the
likely cause of multiplayer not working correctly. Certain changes were "not
entirely backwards compatible with the previous implementation." This is the
highest-priority investigation target.

### P1-3: PhysicsEngineManager — missing binding
Copilot found that `registerPhysicsEngine()` does not actually register a
constructible physics engine (missing `.use(...)`, no binding for
`Physics`/`PhysicsEngine`). Physics-enabled blocks DO drop in multiplayer
testing, so the impact may be partial — needs investigation and manual testing.

### P1-4: UniverseSetupScreen — wrapper handoff broken
Copilot found that `initialise()` creates a new `UniverseWrapper` and ignores
the one passed via `setEnvironment()`. Breaks seed/settings handoff from
`AdvancedGameSetupScreen`.

### P1-5: AdvancedGameSetupScreen — NPE risk
Copilot found `universeWrapper` is dereferenced without null guard. If screen
is opened through any path that doesn't call `setEnvironment()` first, NPE.

### P1-6: AutoConfigManager — reinstate removed check
BSA: "This check was absolutely needed and removing it has caused integration
test failures. It will be reinstated."

### P1-7: CodeRabbit triage
17 comments to triage. Actionable findings get slotted into Phase 1 or Phase 2.

## Phase 2 — Code Quality (Parked)

Items tracked in Thalamus with links to review comments:

- **ConsoleImpl** — injecting full `Context`, should inject `NetworkSystem` +
  `PermissionManager` instead
- **BlockFamilyLibrary** — injecting `Context` directly, unnecessary
- **WorldRendererImpl** — context param should be replaced with explicit deps
- **ReadWriteStorageManager** — constructor should be deprecated, implicit
  `CoreRegistry` deps
- **UniverseSetupScreen** — `Context.put()` still used, migrate to
  `ServiceRegistry`
- **NUIManagerInternal** — nonsensical method name `timedContextForModulesWidgets`
- **RegisterRemoteWorldSystems** — dead commented-out code to remove
- **ModuleManager** — document implementation requirement
- **InitialiseBlocks** — verify downcast safety
- **InitialiseWorld** — clarify where seed is being set now

## DI Patterns — Living Reference

Harvested from BSA's review comments on PRs #5299 and #5304. These are
observed conventions, not prescriptive rules. They grow as we work through
the review and will eventually graduate to a skill or CONTRIBUTING section.

### Injection style
- **Prefer constructor parameter injection** for clean, testable code
- **`@javax.inject.Inject` on protected members** is the agreed compromise
  when constructor injection isn't feasible
- **`@In` on private members** is legacy — do not add new uses
- **Never inject `Context` directly** — inject the specific dependencies needed

### Context and registry usage
- **`ServiceRegistry`** for the registration phase (pre-init, init)
- **`ImmutableContextImpl`** after registration is complete — prevents rogue
  writes. Use in tests to catch classes that still write to context.
- **`Context.put()` should not be called** under most circumstances — migrate
  to `ServiceRegistry`-based initialization
- **`CoreRegistry` is being eliminated** — do not add new uses (test
  environment is a reluctant exception)

### Test conventions
- Use `ImmutableContextImpl` in tests to catch rogue context writes
  (example: `ComponentSerializerTest.java` L59-79)
- `ServiceRegistry` example: same file
- `ImmutableContextImpl` in engine: `TerasologyEngine.java` L260

### References
- PR #5299: https://github.com/MovingBlocks/Terasology/pull/5299
- PR #5304 discussion: https://github.com/MovingBlocks/Terasology/pull/5304
- BSA's ServiceRegistry example: https://github.com/MovingBlocks/Terasology/blob/ce52b17/engine-tests/src/test/java/org/terasology/engine/persistence/ComponentSerializerTest.java#L59-L79
- BSA's ImmutableContextImpl example: https://github.com/MovingBlocks/Terasology/blob/ce52b17/engine/src/main/java/org/terasology/engine/core/TerasologyEngine.java#L260
