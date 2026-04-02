---
name: bdd
description: >
  Behavior Driven Development practice skill. Guides writing Gherkin scenarios,
  placing .feature files, and bridging to implementation via runner sub-skills
  and TDD. Use when writing scenarios, planning features, implementing step
  definitions, or setting up BDD infrastructure in any component.
---

# BDD (Behavior Driven Development)

BDD scenarios are the universal unit of work in GDD. Every role can
participate at some stage of the pipeline. A feature file without scenarios
is a valid deliverable — it declares planned work. Scenarios mean
implementation has started.

## The Scenario Pipeline

```text
Write scenario          File issue           Implement & PR
(Given/When/Then)  →   (GitHub issue)    →  (code + step defs)
     ↓                      ↓                     ↓
Anyone can do this    Manual or future       Developer or AI agent
                      automation             picks it up
                      (@creating-github-issues)
     ↓                      ↓                     ↓
Stored as .feature    Tagged & labeled      Vordu shows progress
in the component      "good first issue"    on the roadmap
```

Each stage is independently useful. Writing a scenario is a complete
contribution even if nobody implements it for weeks. Writing a feature
without scenarios is a complete contribution — it makes the work visible.

## When to Use

- User asks to plan, spec, or define behavior for a component
- User asks to write a `.feature` file or BDD scenario
- User asks to add a capability or feature to a component
- You are about to implement a new feature and no `.feature` file exists
- GDD orchestrator delegates here

**Do not use for:**
- Running existing tests (use runner sub-skill or `ws test`)
- Writing unit tests without BDD context (use TDD skill)
- Vordu roadmap tagging (future `bdd-vordu` sub-skill)

**Progressive depth:** Read only as far as needed.
- Feature Authoring — always read
- Writing Scenarios — only when scenarios are needed
- Bridging to Implementation — only when moving to code
- Session Retrospective — suggested at end of session

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
- Infrastructure (kuttl): `tests/e2e/` per @kuttl-testing conventions
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

  Scenario: <Outcome description>
    Given <context>
    When <action>
    Then <observable result>
```

The `As a / I want / So that` narrative is optional. Some components
use it, others don't. Match the existing style in the component.

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
- **Declarative, not imperative** — describe *what*, not *how*
- **Business language** — scenarios should be readable by non-developers
- **Concrete examples** — use specific values, not abstractions

```gherkin
# Good — declarative, specific, domain language
Scenario: Expired session redirects to login
  Given a user with an expired session token
  When they request the dashboard
  Then they are redirected to the login page

# Bad — imperative, implementation-leaking
Scenario: Test login redirect
  Given I set the cookie "session" to "expired-token-123"
  When I send a GET request to "/api/dashboard"
  Then I receive a 302 status code with Location header "/login"
```

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
- `go.mod` with `godog` → use godog conventions (see below)
- Infrastructure components → see @kuttl-testing skill
- `pom.xml` or `build.gradle` with `cucumber`
  → activate `bdd-java` sub-skill (future)
- Nothing detected → ask the user

### Quick runner reference

**Go (godog):**
```bash
godog ./features/              # all scenarios
godog ./features/auth.feature  # specific feature
godog --tags="@smoke"          # by tag
```
Step definitions go in `*_test.go` files alongside features or in `steps/`.

**Python (pytest-bdd):** See the `bdd-pytest` sub-skill for full guidance.

**Infrastructure (kuttl):** See @kuttl-testing for conventions. KUTTL uses
directory-based structure rather than `.feature` files.

### Hand off to TDD

Once step definitions exist, production code follows. Hand off to
the TDD skill:

> Scenarios define WHAT should happen. TDD implements HOW.
> Each scenario becomes a failing test to drive implementation.

The BDD skill does not manage red-green-refactor. That's TDD's job.

---

## Session Sizing

What's achievable in a given time window:

| Time | Suggested Activity |
|------|--------------------|
| 15 min | Write a planning feature or 1-2 scenarios |
| 30 min | Write scenarios + implement step definitions for one feature |
| 45 min | End-to-end: scenarios → issue → implementation → PR |
| 2+ hours | Multiple features, runner setup, CI integration |

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

---

## Relationship to Other Skills

- **@creating-github-issues** — convert a scenario into a GitHub issue
- **@kuttl-testing** — infrastructure BDD uses kuttl conventions
- **@bdd-pytest** — pytest-bdd runner sub-skill (step defs, execution)
- **@gdd** — BDD is a practice skill in the GDD hierarchy
