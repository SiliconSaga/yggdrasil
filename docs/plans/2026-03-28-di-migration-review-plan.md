# DI Migration Review — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix runtime correctness issues from the gestalt-di migration (PR #5299) in the `review/post-di` branch, producing a clean review-fix PR.

**Architecture:** Targeted fixes to specific files — no architectural changes. Each task is an independent commit addressing one review finding. Maintainer tests each change by running the game.

**Tech Stack:** Java 17, Gradle (Kotlin DSL), Gestalt DI (`ServiceRegistry`, `BeanContext`, `Lifetime`)

**Testing:** Manual in-game testing by the project maintainer. No meaningful automated test coverage for these runtime paths. Flag anything uncertain for hands-on verification.

**Commit convention:** Use `ws commit` via bodyfile in `.commits/`. Each task = one commit.

---

### Task 1: Bump gestalt version to 8.0.1-SNAPSHOT

**Files:**
- Modify: `settings.gradle.kts:8`
- Modify: `build-logic/build.gradle.kts:69`
- Modify: `build-logic/src/main/kotlin/terasology-module.gradle.kts:57`

All paths relative to `components/terasology/`.

- [ ] **Step 1: Update version catalog in settings.gradle.kts**

Change line 8:
```kotlin
val gestalt = version("gestalt", "8.0.1-SNAPSHOT")
```

- [ ] **Step 2: Update build-logic/build.gradle.kts**

Change line 69:
```kotlin
implementation("org.terasology.gestalt:gestalt-module:8.0.1-SNAPSHOT")
```

- [ ] **Step 3: Update build-logic terasology-module.gradle.kts**

Change line 57:
```kotlin
annotationProcessor("org.terasology.gestalt:gestalt-inject-java:8.0.1-SNAPSHOT")
```

- [ ] **Step 4: Verify Gradle resolves the new version**

Run from `components/terasology/`:
```bash
./gradlew :engine:dependencies --configuration runtimeClasspath 2>/dev/null | grep gestalt | head -5
```
Expected: all lines show `8.0.1-SNAPSHOT`

- [ ] **Step 5: Commit**

Write bodyfile `.commits/gestalt-version-bump.md`:
```yaml
---
message: "chore: bump gestalt to 8.0.1-SNAPSHOT"
add:
  - settings.gradle.kts
  - build-logic/build.gradle.kts
  - build-logic/src/main/kotlin/terasology-module.gradle.kts
---
Aligns version catalog and build-logic with the 8.0.1 gestalt branch
that contains the DI refactor changes this migration depends on.
```

Run: `bash scripts/ws commit terasology .commits/gestalt-version-bump.md`

---

### Task 2: Fix UniverseSetupScreen wrapper handoff

Both Copilot and CodeRabbit flagged this independently. `setEnvironment()` receives
a `UniverseWrapper` but never assigns it to `this.universeWrapper`. Meanwhile
`initialise()` creates a throwaway `new UniverseWrapper()` at line 146. The screen
then reads/writes the field, not the context entry, so state set by the caller
(seed, world generator, server flag) is silently discarded.

**Files:**
- Modify: `engine/src/main/java/org/terasology/engine/rendering/nui/layers/mainMenu/UniverseSetupScreen.java:385`

- [ ] **Step 1: Assign the passed wrapper to the field in setEnvironment()**

At line 386, before `prepareContext()`, add the field assignment:

```java
public void setEnvironment(UniverseWrapper universeWrapper) {
    this.universeWrapper = universeWrapper;
    prepareContext();
```

This makes the parameter the single source of truth. The `context.put()` at
line 399 also stores it, which is fine — both point to the same object now.

- [ ] **Step 2: Remove the throwaway creation in initialise()**

Line 146 creates `universeWrapper = new UniverseWrapper()` which is immediately
abandoned when `setEnvironment()` is called. However, `initialise()` runs once
when the screen is first created, and the wrapper bindings (seed field, world
generator dropdown) read from `this.universeWrapper`. If `initialise()` runs
before `setEnvironment()`, the field must not be null.

**Decision: keep line 146 as-is.** It provides a safe default so the bindings
don't NPE during initial screen setup. The real wrapper replaces it when
`setEnvironment()` is called. This is the minimal safe fix.

- [ ] **Step 3: Ask maintainer to test**

Test: Create a new game via Advanced Game Setup → Create World → Universe Setup.
Verify that the seed entered in Advanced Game Setup carries through to the
Universe Setup screen and that clicking Play creates a game with that seed.

- [ ] **Step 4: Commit**

Write bodyfile `.commits/universe-setup-wrapper.md`:
```yaml
---
message: "fix: assign UniverseWrapper in UniverseSetupScreen.setEnvironment"
add:
  - engine/src/main/java/org/terasology/engine/rendering/nui/layers/mainMenu/UniverseSetupScreen.java
---
setEnvironment() received a UniverseWrapper parameter but never assigned it
to the instance field. The screen's UI bindings read from the field, not the
context, so seed/generator/server settings from AdvancedGameSetupScreen were
silently discarded.
```

Run: `bash scripts/ws commit terasology .commits/universe-setup-wrapper.md`

---

### Task 3: Fix PhysicsEngineManager DI registration

Copilot found that `registerPhysicsEngine()` registers `BulletPhysics` without
binding it to its interfaces (`PhysicsEngine`, `Physics`). The DI container
knows about the concrete class but nothing requesting the interface will find it.

Physics-enabled blocks DO drop in multiplayer testing, so something works —
likely `getNewPhysicsEngine()` (the old path) is still being called somewhere.
But the DI registration should be correct regardless.

**Files:**
- Modify: `engine/src/main/java/org/terasology/engine/physics/engine/PhysicsEngineManager.java:27-29`

- [ ] **Step 1: Examine how BulletPhysics is constructed and what it implements**

Read `BulletPhysics.java` to confirm it implements `PhysicsEngine` (which extends `Physics`), and check its constructor dependencies.

- [ ] **Step 2: Add interface bindings to registerPhysicsEngine()**

Update the registration at lines 27-29:

```java
public static void registerPhysicsEngine(ServiceRegistry serviceRegistry) {
    serviceRegistry.with(BulletPhysics.class).lifetime(Lifetime.Singleton).use(BulletPhysics.class);
    serviceRegistry.with(PhysicsEngine.class).lifetime(Lifetime.Singleton).use(BulletPhysics.class);
    serviceRegistry.with(Physics.class).lifetime(Lifetime.Singleton).use(BulletPhysics.class);
}
```

**Important:** Verify with the maintainer whether these should be three separate
singletons or one shared instance. If `Physics` and `PhysicsEngine` should
resolve to the same `BulletPhysics` instance, the registration pattern may need
to use a provider that returns the same bean. Check how other similar patterns
work in the codebase (e.g., `EntityManager`/`PojoEntityManager`).

- [ ] **Step 3: Ask maintainer to test**

Test: Start a single-player game, place blocks, verify they fall with physics.
Break blocks and verify drops. If multiplayer is testable, check physics there too.

- [ ] **Step 4: Commit**

Write bodyfile `.commits/physics-engine-binding.md`:
```yaml
---
message: "fix: register PhysicsEngine and Physics interface bindings in DI"
add:
  - engine/src/main/java/org/terasology/engine/physics/engine/PhysicsEngineManager.java
---
registerPhysicsEngine() registered BulletPhysics as a concrete class but
did not bind it to the PhysicsEngine or Physics interfaces. Code requesting
these interfaces from the DI container would fail to resolve them.
```

Run: `bash scripts/ws commit terasology .commits/physics-engine-binding.md`

---

### Task 4: Verify AutoConfigManager check (may be already resolved)

BSA commented: "This check was absolutely needed and removing it has caused
integration test failures. It will be reinstated." However, the current code
at lines 49-52 already contains the check:

```java
if (!environment.getBeans(configClass).isEmpty()) {
    continue;
}
```

This suggests BSA already reinstated it before the merge.

**Separate issue (CodeRabbit):** The catch block at lines 81-83 returns `null`
from the `use(() -> { ... })` lambda, which means a failed construction publishes
a null singleton. This is a real defect but may not cause runtime issues if
construction never fails in practice.

**Files:**
- Modify: `engine/src/main/java/org/terasology/engine/config/flexible/AutoConfigManager.java:81-83` (if we address the null issue)

- [ ] **Step 1: Confirm the BSA check is present**

Read lines 47-52 of AutoConfigManager.java. The `getBeans` check should be there.
If present, mark P1-6 as resolved in the Thalamus checklist.

- [ ] **Step 2: Assess the null singleton risk**

Lines 81-83:
```java
} catch (InstantiationException | IllegalAccessException | InvocationTargetException | NoSuchMethodException ignore) {
    return null;
}
```

This silently swallows construction failures and publishes null. The safer
approach is to log the error and skip registration entirely. However, since
`ServiceRegistry.use()` takes a lambda, we can't easily skip — the registration
has already been declared. This is Phase 2 material unless the maintainer reports
config-related crashes.

- [ ] **Step 3: Update Thalamus**

Mark P1-6 as resolved (check already present). Add the null singleton issue to
Phase 2 list with a note about the CodeRabbit finding.

- [ ] **Step 4: Commit (only if changes were made)**

If the null issue is addressed now, commit. Otherwise, this task produces no
code changes — just Thalamus updates.

---

### Task 5: Guard AdvancedGameSetupScreen against universeWrapper NPE

Copilot flagged that `universeWrapper` is dereferenced in button handlers without
null checks. The field is set by `setEnvironment()` (line 796-798) which is
called by external code before the screen is shown.

**Files:**
- Modify: `engine/src/main/java/org/terasology/engine/rendering/nui/layers/mainMenu/advancedGameSetupScreen/AdvancedGameSetupScreen.java`

- [ ] **Step 1: Trace the call path to confirm NPE risk**

Check who calls `AdvancedGameSetupScreen.setEnvironment()` and whether there's
a code path that shows the screen without calling it. If all paths are safe,
this is Phase 2 defensive hardening, not Phase 1.

Search for: `AdvancedGameSetupScreen` creation/push in the codebase.

- [ ] **Step 2: Add guard if needed**

If there IS a path without `setEnvironment()`, add an early return in the
button handlers:

At line 509, wrap the createWorld handler:
```java
WidgetUtil.trySubscribe(this, "createWorld", button -> {
    if (universeWrapper == null) {
        return;
    }
    universeWrapper.setSeed(seed.getText());
    // ... rest of handler
```

At line 518, wrap the play handler similarly.

If all paths are safe, skip this and move to Phase 2.

- [ ] **Step 3: Commit (only if changes were made)**

Write bodyfile `.commits/advanced-game-setup-npe.md`:
```yaml
---
message: "fix: guard against null universeWrapper in AdvancedGameSetupScreen"
add:
  - engine/src/main/java/org/terasology/engine/rendering/nui/layers/mainMenu/advancedGameSetupScreen/AdvancedGameSetupScreen.java
---
Button handlers for createWorld and play dereference universeWrapper without
null checks. Added guards to prevent NPE if the screen is reached without
setEnvironment() being called first.
```

Run: `bash scripts/ws commit terasology .commits/advanced-game-setup-npe.md`

---

### Task 6: Investigate StateLoading — loading screen and multiplayer issues

BSA flags StateLoading as "the most impactful but also problematic changes" and
the likely root of multiplayer not working correctly. CodeRabbit found a specific
issue with the NUI manager swap orphaning the loading screen.

This task is investigative — we read, analyze, and propose fixes for maintainer
review before changing code.

**Files:**
- Analyze: `engine/src/main/java/org/terasology/engine/core/modes/StateLoading.java`
- Analyze: `engine/src/main/java/org/terasology/engine/core/modes/loadProcesses/JoinServer.java`
- Analyze: `engine/src/main/java/org/terasology/engine/core/modes/loadProcesses/InitialiseRemoteWorld.java`
- Analyze: `engine/src/main/java/org/terasology/engine/core/modes/loadProcesses/RegisterRemoteWorldSystems.java`

- [ ] **Step 1: Document the loading screen orphan issue**

In `init()` (line 127), a temporary `NUIManagerInternal` is created and the
loading screen is pushed onto it (line 155). At line 325 (`SwitchToContextStep`),
`context` is recreated from the serviceRegistry and `nuiManager` is replaced
with the DI-created instance (line 327). But `loadingScreen` still belongs to
the old manager.

After the context switch, `loadingScreen.updateStatus()` at line 262 updates a
screen that the active nuiManager doesn't own. `nuiManager.render()` at line 286
renders the new manager (which may not have the loading screen).

**Fix approach:** After the nuiManager swap in SwitchToContextStep, re-push the
loading screen onto the new manager, or transfer it.

- [ ] **Step 2: Analyze the client initialization path for multiplayer issues**

Compare `initClient()` (lines 161-190) with `AddClientPostLoadProcessesStep`
(lines 406-460). The pre-context-switch client path has many commented-out
steps. The post-context-switch path adds them back. Verify the ordering is
correct and that all necessary steps are present.

Key questions:
- Does `JoinServer` correctly receive the game manifest from the server?
- Does `InitialiseRemoteWorld` set up the world provider correctly for a client?
- Does `RegisterRemoteWorldSystems` register all systems the client needs?
- Is the `SwitchToContextStep` creating the right context for the client?

- [ ] **Step 3: Read JoinServer.java for client-side context setup**

Check how the client joins and what it puts in the context/serviceRegistry.
Network events depend on the entity system being correctly configured.

- [ ] **Step 4: Read InitialiseRemoteWorld.java**

Check for the `WorldProviderCore` workaround type mentioned in the Copilot
review. Verify the remote world provider chain is correct.

- [ ] **Step 5: Present findings to maintainer**

Summarize what we found with specific line references and proposed fixes.
Do NOT change StateLoading without maintainer review — this is the most
sensitive file in the DI migration.

- [ ] **Step 6: Implement agreed fixes and commit**

After maintainer review, implement the agreed changes. This may be one or
multiple commits depending on what we find.

---

### Task 7: Triage CodeRabbit findings

17 CodeRabbit comments to classify as Phase 1 (runtime fix), Phase 2 (code
quality), or Noise (dismiss).

- [ ] **Step 1: Read all 17 CodeRabbit comments**

Fetch with: `gh api repos/MovingBlocks/Terasology/pulls/5299/comments --paginate`
filtered to `coderabbitai[bot]`.

- [ ] **Step 2: Classify each finding**

For each, determine:
- Is this a runtime correctness issue? → Phase 1
- Is this a code quality / pattern issue? → Phase 2 (add to Thalamus)
- Is this noise / over-engineering? → Dismiss

Already-triaged CodeRabbit findings from initial scan:

| File | Severity | Classification |
|------|----------|---------------|
| Environment.java:55 — context swap in reset() | Critical | Phase 2 (test env only) |
| HeadlessEnvironment.java:142 — BlockFamilyLibrary mismatch | Major | Phase 2 (test env) |
| WithUnittestModule.java:45 | Critical | Needs investigation |
| TerasologyTestingEnvironment.java:84 — static context leak | Major | Phase 2 (test env) |
| TerasologyTestingEnvironment.java:85 — uninitialized Game | Major | Phase 2 (test env) |
| AutoConfigManager.java:83 — nullable singleton | Major | Phase 2 (covered in Task 4) |
| ContextImpl.java:79 — parent BeanContext lost | Major | Phase 1 candidate |
| EntitySystemSetupUtil.java:88 — fresh replay status | Major | Phase 2 |
| EnvironmentSwitchHandler.java:105 — stale type handlers | Major | Phase 2 |
| StateLoading.java:130 — NUI manager swap | Major | Phase 1 (covered in Task 6) |
| ExternalApiWhitelist.java:62 — broad sandbox | Major | Phase 2 |
| LoadExtraBlockData.java:30 — instantiation timing | Major | Phase 2 |
| PojoEntityManager.java:88 — half-initialized manager | Major | Phase 1 candidate |
| AdvancedGameSetupScreen.java:515 — NPE | Critical | Phase 1 (covered in Task 5) |
| UniverseSetupScreen.java:147 — wrapper handoff | Critical | Phase 1 (covered in Task 2) |
| WorldRendererImpl.java:153 — ScreenGrabber visibility | Major | Phase 2 |
| InitialiseWorld.java:115 — storage manager path | Critical | Needs investigation |

- [ ] **Step 3: Investigate ContextImpl.java:79 — parent BeanContext**

CodeRabbit says the plain child-context constructor creates a standalone
`DefaultBeanContext` instead of inheriting the parent's. This means `@Inject`
resolution doesn't walk up the context tree. This could cause widespread DI
resolution failures. Read the file and assess impact.

- [ ] **Step 4: Investigate PojoEntityManager.java:88 — half-initialized**

CodeRabbit says DI can publish a `PojoEntityManager` with null `PrefabManager`,
`EntitySystemLibrary`, and `TypeHandlerLibrary`. These are marked `@Nullable`
(or optional injection) but the class NPEs when they're null. Read the file
and assess whether DI actually constructs this without those deps.

- [ ] **Step 5: Investigate InitialiseWorld.java:115 — storage manager path**

CodeRabbit flagged a critical issue with storage manager path wiring. Read the
file and check how `ReadWriteStorageManager` gets its save path.

- [ ] **Step 6: Update Thalamus with triage results**

Add any new Phase 1 items to the checklist. Add Phase 2 items to the backlog.
Dismiss noise findings.

- [ ] **Step 7: Commit Thalamus updates (yggdrasil root)**

This is a Thalamus-only update in the yggdrasil workspace, not the terasology
component. No `ws commit` needed — Thalamus is gitignored.
