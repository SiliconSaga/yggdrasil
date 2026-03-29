---
name: bdd
description: Write and organize BDD feature files — planning features, scenarios, conventions, and bridging to implementation
---

# BDD — Behavior-Driven Development

Write well-structured `.feature` files for any component in the workspace.
A feature file without scenarios is a valid deliverable — it declares
planned work. Scenarios mean implementation has started.

## When to Use

- User asks to plan, spec, or define behavior for a component
- User asks to write a `.feature` file or BDD scenario
- User asks to add a capability or feature to a component
- You are about to implement a new feature and no `.feature` file exists
- GDD orchestrator (future) delegates here

**Do not use for:**
- Running existing tests (use runner sub-skill or `ws test`)
- Writing unit tests without BDD context (use TDD skill)
- Vordu roadmap tagging (future `bdd-vordu` sub-skill)

**Progressive depth:** Read only as far as needed.
- Section 2 (Feature Authoring) — always read
- Section 3 (Writing Scenarios) — only when scenarios are needed
- Section 4 (Bridging to Implementation) — only when moving to code
- Section 5 (Session Retrospective) — suggested at end of session

---

## Feature Authoring

### 1. Identify the component

From your working directory, user context, or ask. Use
`bash scripts/ws list` to see available components.

### 2. Find existing features

Scan the component for existing `.feature` files:
- Check `tests/features/` and `features/` directories
- Report what exists to the user
- Decide: new file or extend an existing one?

If the component has existing features, read them before writing.
Match the voice, step phrasing, and structure.

### 3. Write the feature file

**Placement — match existing conventions, or use defaults:**
- Python: `tests/features/<name>.feature`
- Go: `features/<name>.feature`
- Java: `src/test/resources/features/<name>.feature`
- Some components use subdirectories by subsystem — match what's there
- Naming: `kebab-case.feature`

**Structure:**

Planning feature (no scenarios):
```gherkin
Feature: <Capability name>
  As a <actor>
  I want to <action>
  So that <benefit>

  # Scenarios will be added when implementation begins.
```

Feature with scenarios (see Writing Scenarios section):
```gherkin
Feature: <Capability name>
  As a <actor>
  I want to <action>
  So that <benefit>

  Scenario: <Outcome description>
    Given <context>
    When <action>
    Then <observable result>
```

### 4. Commit

A feature file is a standalone deliverable.
- Planning feature: `feat: plan <capability> for <component>`
- With scenarios: `feat: define <behavior> scenarios for <component>`

---

## Writing Scenarios

Read this section when the user wants actual Given/When/Then scenarios.

### Scan before write

Before writing new scenarios:
- Read all existing `.feature` files in the component
- Flag if a scenario already covers the same behavior, even with
  different wording
- Match the style of existing scenarios

### Conventions

- **One behavior per scenario.** If the name has "and", split it.
- **Name describes the outcome:** "Over-band offer without VP approval
  is denied" — not "Test policy with high salary"
- **Given** = state/context, **When** = action, **Then** = observable outcome
- **Domain language, not implementation:** "When the policy is evaluated"
  — not "When I POST to /evaluate"

### Anti-patterns

- Steps referencing UI elements, CSS selectors, or API paths
- Long `And` chains in When/Then blocks (probably multiple behaviors —
  split it). Multiple Given steps for setup are fine.
- Scenarios testing the same logic with different data — use
  Scenario Outline with Examples table instead
- Steps that mirror code rather than describe behavior

### Background blocks

If 3+ scenarios share the same Given setup, extract to a Background
block. Keep Background short (3 lines or fewer). If longer, the feature
may be too broad — consider splitting into multiple feature files.

---

## Bridging to Implementation

Read this section when scenarios are written and the user wants to
implement step definitions and production code.

### Detect the runner

Check the component's project files:
- `pyproject.toml` or `requirements.txt` with `pytest-bdd`
  → activate `bdd-pytest` sub-skill
- `pom.xml` or `build.gradle` with `cucumber`
  → activate `bdd-java` sub-skill (future)
- Nothing detected → ask the user

### Hand off to TDD

Once step definitions exist, production code follows. Hand off to
the TDD skill (superpowers:test-driven-development):

> Scenarios define WHAT should happen. TDD implements HOW.
> Each scenario becomes a failing test to drive implementation.

The BDD skill does not manage red-green-refactor. That's TDD's job.

---

## Session Retrospective

Suggested (not mandatory) when `.feature` files were written or
modified in this session.

### Review what was written

1. **Pattern scan** — look across features touched this session:
   - Repeated Given steps → candidate for Background or shared step
   - Naming inconsistencies between new and existing scenarios
   - Planning features that have stayed scenario-free across sessions

2. **Convention check:**
   - Did we match the component's existing style?
   - Are files in the right place?
   - Are scenario names descriptive of outcomes?

3. **Skill improvement:**
   - Did this skill's guidance help or get in the way?
   - Anything unclear or missing?
   - Note observations for future skill updates

**Output:** 3-5 bullet points of observations. The user decides
whether to act on any of it.
