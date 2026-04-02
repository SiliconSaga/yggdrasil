# BDD Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the core BDD skill and pytest-bdd runner sub-skill for the SiliconSaga workspace.

**Architecture:** Two SKILL.md files — a runner-agnostic core skill for feature authoring and conventions, and a pytest-bdd runner sub-skill for step definitions and test execution. Both follow the existing `.agent/skills/<name>/SKILL.md` convention. Registration in AGENTS.md skill table.

**Tech Stack:** Markdown (SKILL.md files), Gherkin conventions, pytest-bdd reference

**Spec:** `docs/plans/2026-03-28-bdd-skill-design.md`

---

## File Structure

```
.agent/skills/
  bdd/
    SKILL.md                  # Core BDD skill — feature authoring, conventions
  bdd-pytest/
    SKILL.md                  # pytest-bdd runner — step defs, execution
AGENTS.md                     # Add entries to skill table
```

---

### Task 1: Core BDD Skill

**Files:**
- Create: `.agent/skills/bdd/SKILL.md`

- [ ] **Step 1: Create the SKILL.md with frontmatter and Section 1 (When to Use)**

`.agent/skills/bdd/SKILL.md`:
```markdown
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
```

- [ ] **Step 2: Add Section 2 (Feature Authoring — the core)**

```markdown
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

Feature with scenarios (see Section 3 for conventions):
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
```

- [ ] **Step 3: Add Section 3 (Writing Scenarios — on demand)**

```markdown
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
block. Keep Background short (≤3 lines). If longer, the feature may
be too broad — consider splitting into multiple feature files.
```

- [ ] **Step 4: Add Section 4 (Bridging to Implementation — on demand)**

```markdown
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
```

- [ ] **Step 5: Add Section 5 (Session Retrospective)**

```markdown
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
```

- [ ] **Step 6: Verify the skill loads**

Read the complete file back and verify:
- Frontmatter is valid YAML
- All 5 sections are present
- No broken markdown
- Cross-references to other skills are correct

- [ ] **Step 7: Commit**

```bash
git add .agent/skills/bdd/SKILL.md
git commit -m "feat: add core BDD skill for feature authoring and conventions

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: pytest-bdd Runner Sub-Skill

**Files:**
- Create: `.agent/skills/bdd-pytest/SKILL.md`

- [ ] **Step 1: Create the SKILL.md**

`.agent/skills/bdd-pytest/SKILL.md`:
```markdown
---
name: bdd-pytest
description: pytest-bdd runner — step definitions, test execution, and Cucumber JSON output for Python components
---

# BDD Runner: pytest-bdd

Step definitions, test execution, and output for Python components
using pytest-bdd. Activated by the core BDD skill when pytest-bdd
is detected in the project.

## Prerequisites

The component should have `pytest-bdd` in its dependencies:
- `pyproject.toml` → `[project.optional-dependencies] dev` section
- Or `requirements.txt`

Install: `pip install pytest-bdd`

## Step Definition Structure

### File organization

Match the component's existing pattern. Common conventions:
- `tests/test_<feature>.py` — step defs alongside scenario decorators
- `tests/step_defs/test_<feature>_steps.py` — separate step def files
- Shared fixtures in `tests/conftest.py`

### Writing step definitions

```python
import pytest
from pytest_bdd import scenario, given, when, then, parsers

FEATURE = "features/<name>.feature"

@scenario(FEATURE, "Scenario name here")
def test_scenario_name():
    pass

@given(parsers.parse('a policy with band_maximum {value:d}'))
def policy_with_band(value):
    return {"band_maximum": value}

@when("the policy is evaluated", target_fixture="result")
def evaluate(policy, facts):
    engine = PolicyEngine()
    return engine.evaluate(policy, facts)

@then(parsers.parse('the result is "{expected}"'))
def check_result(result, expected):
    assert result.status == expected
```

### Key patterns

- **`@scenario` decorator** links test function to feature/scenario
- **`parsers.parse`** for parameterized steps with `{name:type}`
- **`target_fixture`** to pass results between steps
- **Shared Given steps** go in `conftest.py` to avoid duplication
- **One test function per scenario** — the `@scenario` decorator
  creates the test; the function body can be empty (`pass`)

## Running Tests

```bash
# Run all BDD tests
pytest tests/test_<feature>.py -v

# Run a specific scenario
pytest tests/test_<feature>.py::test_scenario_name -v

# Generate Cucumber JSON (for Vordu ingestion)
pytest --cucumber-json=cucumber.json
```

## Cucumber JSON Output

pytest-bdd can output Cucumber JSON format, which is the standard
ingestion format for Vordu and CI systems:

```bash
pip install pytest-cucumber-json
pytest --cucumber-json=cucumber.json
```

This produces a `cucumber.json` file that Vordu's ingestion script
can consume to update the roadmap matrix.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `StepImplementationNotFound` | Step text in `.feature` doesn't match any `@given`/`@when`/`@then` decorator. Check spacing, quotes, parsers. |
| Scenario not collected | Missing `@scenario` decorator on test function, or wrong feature file path. |
| Steps from wrong feature match | Step decorators are global in pytest-bdd. Use unique step phrasing or scope with `conftest.py`. |
| Fixture not found | Step producing a fixture needs `target_fixture` parameter. Step consuming it needs the fixture name as a function parameter. |
```

- [ ] **Step 2: Verify the skill loads**

Read the complete file back and verify:
- Frontmatter is valid YAML
- Sections are clear and practical
- Code examples are syntactically correct
- No references to nonexistent skills or tools

- [ ] **Step 3: Commit**

```bash
git add .agent/skills/bdd-pytest/SKILL.md
git commit -m "feat: add pytest-bdd runner sub-skill

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Register in AGENTS.md

**Files:**
- Modify: `AGENTS.md` — add entries to the skill table

- [ ] **Step 1: Add BDD skills to the skill table**

Add two rows to the skill table in `AGENTS.md` after the existing entries:

```markdown
| **BDD** | Write and organize BDD feature files — planning features, scenarios, and conventions | [SKILL.md](./.agent/skills/bdd/SKILL.md) |
| **BDD pytest Runner** | pytest-bdd step definitions, test execution, and Cucumber JSON output | [SKILL.md](./.agent/skills/bdd-pytest/SKILL.md) |
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: register BDD skills in AGENTS.md

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Smoke Test — Use the Skill on a Real Component

**Files:**
- Create: `components/nornir/tests/features/release-compilation.feature` (or verify existing)

This is not a code task — it's a validation that the skill produces
good output when an agent follows it.

- [ ] **Step 1: Load the BDD skill and follow its flow**

Pretend you're an agent encountering the skill for the first time.
Follow Section 2 (Feature Authoring) for the Nornir component:
1. Identify component: nornir
2. Scan existing features in `components/nornir/tests/features/`
3. Verify existing features match the skill's conventions
4. Note any gaps between what the skill recommends and what exists

- [ ] **Step 2: Report findings**

Document:
- Did the skill provide enough guidance?
- Were the file placement conventions correct for Nornir?
- Did the scan-before-write flow work?
- Any friction or missing guidance?

- [ ] **Step 3: Fix any issues found in the skill**

If the smoke test reveals gaps, update the SKILL.md files.
Commit any fixes.

---

## Dependency Graph

```
Task 1 (core BDD skill)
  └── Task 2 (pytest-bdd runner) — independent, can parallel with Task 1
        └── Task 3 (register in AGENTS.md) — depends on Tasks 1 and 2
              └── Task 4 (smoke test) — depends on Task 3
```

Tasks 1 and 2 are independent and can be parallelized.
Task 3 registers both skills.
Task 4 validates the whole thing works.
