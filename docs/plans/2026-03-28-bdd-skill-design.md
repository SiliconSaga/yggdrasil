# BDD Skill — Design Spec

**Date:** 2026-03-28
**Status:** Draft
**Author:** Cervator + Claude Opus 4.6

---

## 1. Overview

A skill for Behavior-Driven Development in the SiliconSaga workspace. It
guides agents and humans through writing well-structured `.feature` files,
optionally adding scenarios, and bridging to implementation via runner
sub-skills and the TDD skill.

**Key insight:** A `.feature` file without scenarios is a valid, committable
deliverable. It makes planned work visible and trackable. Scenarios mean
implementation has started; their absence means the work is planned but not
yet underway.

### What This Skill Does

- Guides authoring of `.feature` files with proper structure and placement
- Scans existing features to avoid duplication and match conventions
- Teaches scenario writing conventions when the user wants to go deeper
- Routes to runner sub-skills (pytest-bdd) and the TDD skill for implementation
- Suggests a lightweight session retrospective to improve practices over time

### What This Skill Does Not Do

- Run tests (that's the runner sub-skill or `ws test`)
- Manage Vordu roadmap tags (that's a future `gdd-bdd-vordu` sub-skill)
- Write policy/governance BDD for Nornir (that's Nornir-specific docs)
- Implement the GDD mode system (the GDD orchestrator will wrap this later)
- Replace the TDD skill (BDD defines *what*, TDD implements *how*)

---

## 2. Skill Tree

```
.agent/skills/
  gdd-bdd/
    SKILL.md              # Core — concepts, feature authoring, conventions
  gdd-bdd-pytest/
    SKILL.md              # Runner — pytest-bdd step defs, execution, cucumber output
```

**Future additions (not in this spec):**
- `gdd-bdd-vordu/SKILL.md` — Vordu roadmap tagging integration (lives near Vordu component)
- `gdd-bdd-java/SKILL.md` — Cucumber-JVM runner (for Terasology, Destination Sol)
- `gdd-bdd-go/SKILL.md` — godog runner (if Go components adopt BDD)

The core skill is runner-agnostic. It teaches BDD as a practice and produces
`.feature` files. Runner sub-skills teach how to execute those files in a
specific language/framework.

**SKILL.md frontmatter:**

`gdd-bdd/SKILL.md`:
```yaml
---
name: gdd-bdd
description: Write and organize BDD feature files — planning features, scenarios, conventions, and bridging to implementation
---
```

`gdd-bdd-pytest/SKILL.md`:
```yaml
---
name: gdd-bdd-pytest
description: pytest-bdd runner — step definitions, test execution, and Cucumber JSON output
---
```

---

## 3. Trigger Conditions

**Activate the BDD skill when:**
- User asks to plan, spec, or define behavior for a component
- User asks to write a `.feature` file or scenario
- User asks to add a capability or feature to a component
- Agent is about to implement a new feature and no `.feature` file exists
- GDD orchestrator (future) delegates to it

**Do NOT activate for:**
- Running existing tests without writing new features (use `ws test` or runner skill directly)
- Writing unit tests without BDD context (use TDD skill)
- Policy/governance work specific to Nornir (use Nornir docs)

---

## 4. Core Skill Structure (gdd-bdd/SKILL.md)

The skill has 5 progressive sections. An agent reads only as deep as the
task requires. For the common case (writing a planning feature), only
Sections 1-2 are needed.

### Section 1: When to Use (~10 lines)

Trigger conditions (from Section 3 above). One-paragraph explanation:

> BDD in this workspace serves two purposes: defining testable behavior
> (the traditional use) and planning work (making future capabilities
> visible). A feature file without scenarios is a complete deliverable —
> it declares intent. Scenarios are added when implementation begins.

### Section 2: Feature Authoring (~40 lines, always read)

This is the core section. The authoring flow:

```
1. Identify component
   - From working directory, user context, or ask
   - Verify the component exists in the workspace

2. Find existing features
   - Scan tests/features/ and features/ in the component
   - Report what exists to the user
   - Decide: new file or extend existing?

3. Write the .feature file
   - Feature: block with descriptive name
   - Optional: As a / I want / So that narrative
   - Optional: tags (component-specific or Vordu — see sub-skills)
   - If planning only: add a comment noting scenarios will follow

4. Commit
   - A feature file is a standalone commit
   - Message: "feat: plan <capability> for <component>"
   - Or if scenarios included: "feat: define <behavior> scenarios for <component>"
```

**File placement conventions:**
- Check what the component already uses — match it
- If nothing exists, defaults:
  - Python: `tests/features/<name>.feature`
  - Go: `features/<name>.feature`
  - Java: `src/test/resources/features/<name>.feature`
- Some components organize features into subdirectories by subsystem
  (e.g., `features/percona/mongo.feature`) — match the existing structure
- Naming: `kebab-case.feature`

**Scan-before-write:**
- Before creating a new feature, read all existing `.feature` files in the
  component
- Flag if a feature or scenario already covers the same behavior, even with
  different wording
- If extending an existing feature, match its voice and structure

**Example — planning feature (no scenarios):**

```gherkin
Feature: Release compiler produces bounded execution plans
  As a governance system
  I want to compile case state into deterministic release plans
  So that no action is authorized without explicit approval

  # Scenarios will be added when implementation begins.
```

**Example — feature with scenarios (fictional domain):**

```gherkin
Feature: Inventory reorder threshold alerts
  As a warehouse manager
  I want the system to alert when stock drops below reorder thresholds
  So that I can replenish inventory before stockouts occur

  Scenario: Stock below threshold triggers alert
    Given a product with reorder threshold 50
    And current stock is 30
    When the inventory check runs
    Then an alert is generated for the product

  Scenario: Stock above threshold produces no alert
    Given a product with reorder threshold 50
    And current stock is 80
    When the inventory check runs
    Then no alert is generated
```

Note: always match the existing style of the component you're working in.
Read its `.feature` files before writing new ones.

### Section 3: Writing Scenarios (~50 lines, read on demand)

Activated when the user wants to write actual Given/When/Then scenarios.

**Conventions:**
- One behavior per scenario
- Scenario name describes the outcome ("Over-band offer without VP approval
  is denied") not the steps ("Test policy with high salary")
- Given = state/context, When = action, Then = observable outcome
- Keep steps at the domain level, not implementation level

**Style matching:**
- Read existing features in this component before writing
- Match the voice (e.g., "As a governance system" vs "As an operator")
- Match step phrasing conventions (e.g., if existing steps use "Given a case
  with fact X = Y", follow that pattern)

**Anti-patterns to flag:**
- Steps referencing UI elements, CSS selectors, or API paths (too coupled
  to implementation)
- Long `And` chains in When/Then blocks (probably multiple behaviors in one
  scenario — split it). Given blocks with multiple setup steps are fine.
- Scenarios testing the same logic with different data (use Scenario Outline
  with Examples table instead)
- Steps that restate implementation ("When I POST to /evaluate") vs domain
  language ("When the policy is evaluated")

**Background blocks:**
- If 3+ scenarios share the same Given setup, extract to a Background block
- Keep Background short (≤3 lines) — if longer, the feature may be too broad

### Section 4: Bridging to Implementation (~20 lines, read on demand)

When scenarios are written and the user wants to implement:

```
Scenarios written → need step definitions?
  ├── Yes → detect framework:
  │         ├── pyproject.toml / requirements.txt with pytest-bdd
  │         │   → activate gdd-bdd-pytest sub-skill
  │         ├── pom.xml / build.gradle with cucumber
  │         │   → activate gdd-bdd-java sub-skill (future)
  │         └── Nothing detected → ask the user
  └── No  → done (planning feature committed)

Step definitions written → need production code?
  ├── Yes → hand off to TDD skill
  │         "Scenarios define WHAT. TDD implements HOW.
  │          Each scenario becomes a failing test to drive implementation."
  └── No  → run tests, verify pass/fail
```

The BDD skill does not manage the red-green-refactor cycle. That's the TDD
skill's job. The handoff is explicit.

### Section 5: Session Retrospective (~20 lines, suggested at end of session)

Triggered when `.feature` files were written or modified in the session.

**What to review:**

1. **Pattern scan** — across features touched this session:
   - Repeated Given steps across scenarios → candidate for Background or
     shared step definition
   - Naming inconsistencies between new and existing scenarios
   - Features that have been planning-only across multiple sessions →
     flag to the user as potential stale plans

2. **Convention check** — compare what was written against skill conventions:
   - Did we match the project's existing style?
   - Did we put files in the right place?
   - Are scenario names descriptive of outcomes?

3. **Skill improvement** — the meta-question:
   - Did the skill's guidance help or get in the way?
   - Was anything unclear or missing?
   - If patterns emerge that the skill should codify, note them for a future
     skill update

**Output:** A brief summary (3-5 bullet points). Not a formal report —
just observations. The user decides whether to act on any of it.

---

## 5. Runner Sub-Skill: gdd-bdd-pytest (gdd-bdd-pytest/SKILL.md)

The first concrete runner. Activated when the BDD core skill detects
pytest-bdd in the project or the user explicitly chooses it.

**Scope:**
- How to write step definitions for pytest-bdd
- File organization (`tests/step_defs/` or `tests/test_<feature>.py`)
- Fixtures and shared steps (`conftest.py`)
- Running tests: `pytest tests/test_<feature>.py -v`
- Generating Cucumber JSON output: `pytest --cucumber-json=cucumber.json`
  (for Vordu ingestion if applicable)
- Common pytest-bdd patterns: `@scenario` decorator, `parsers.parse`,
  `target_fixture`

**Does not cover:**
- When to write features or scenarios (that's the core skill)
- BDD concepts or conventions (that's the core skill)
- Production code implementation (that's the TDD skill)

---

## 6. Future Work (Not in This Spec)

Captured here for reference. Each is a separate spec when the time comes.

### gdd-bdd-vordu Sub-Skill
- Vordu tag format: `@vordu:project=X @vordu:row=Y @vordu:phase=N`
  (Note: the workspace has inconsistent tag usage — Vordu uses `@vordu:` prefix,
  Mimir uses `@component:` / `@phase:` without prefix. The sub-skill must
  reconcile this when built.)
- Phase semantics: 0=foundation, 1=utility, 2=federation, 3=sovereignty
- Feature-without-scenarios = "planned" on roadmap, doesn't fail builds
- Scenarios present = implementation started, failures = incomplete work
- Ingestion via `vordu_ingest.py` or Jenkins shared library
- `catalog-info.yaml` defines system/row structure
- Tag inference from component metadata

### gdd-bdd-java Sub-Skill
- Cucumber-JVM with Gradle
- For Terasology and Destination Sol when headless testing is set up
- Step definition conventions for Java
- Integration with existing game test harnesses

### GDD Integration
- GDD orchestrator delegates to BDD skill based on context
- Session sizing: 15 min = planning feature, 45 min = scenarios + step defs,
  2+ hours = full BDD → TDD → implementation cycle
- Mode awareness (mentoring, quick, zen, autonomous)

### Policy-as-BDD (Nornir/Demicracy)
- Gherkin as a DSL front-end that compiles to Skuld IR
- Citizen-readable policy definitions
- Lives in Nornir component docs, not in the core BDD skill

---

## 7. Research Credits

Conceptual patterns informed by review of existing BDD skills in the
ecosystem (2026-03-28). No code was copied; ideas are not copyrightable.

- **Scan-before-write pattern** — inspired by tsipotU/gherkin-skill
  (GitHub, no license file). The practice of scanning existing `.feature`
  files for behavioral overlap before generating new scenarios.
- **Phased skill handoff** — inspired by CodeMachine0121/gti-agent-cycle-skill
  (GitHub, no license file). The pattern of chaining skills with explicit
  handoff points (spec → test → implement → verify).
- **Scenario-to-test traceability** — from the same gti-agent-cycle-skill.
  Counting scenario blocks vs test functions to detect mismatches.
- **Framework auto-detection** — from gti-agent-cycle-skill. Scanning
  project files (`pyproject.toml`, `pom.xml`, `build.gradle`, `go.mod`)
  to select the appropriate runner.
