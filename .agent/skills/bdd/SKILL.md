---
name: bdd
description: >
  Behavior Driven Development practice skill. Guides writing Gherkin scenarios,
  placing .feature files, and integrating with test runners (godog, pytest-bdd,
  kuttl). Use when writing scenarios, implementing step definitions, or setting
  up BDD infrastructure in any component.
---

# BDD (Behavior Driven Development)

BDD scenarios are the universal unit of work in GDD. Every role can
participate at some stage of the pipeline: writing scenarios, filing issues,
implementing step definitions, or reviewing results.

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
contribution even if nobody implements it for weeks.

## Writing Good Scenarios

### File Placement

`.feature` files live in the component they describe:

- Go components: `features/` or `test/features/` directory
- Python components: `features/` or `tests/features/` directory
- Infrastructure (kuttl): `tests/e2e/` per existing @kuttl-testing conventions

### Gherkin Format

```gherkin
Feature: Brief description of the capability

  Scenario: Specific behavior being verified
    Given some precondition
    And another precondition
    When an action is performed
    Then an expected outcome occurs
    And another expected outcome
```

### Scenario Guidelines

- **One behavior per scenario** — test one thing, not a workflow
- **Declarative, not imperative** — describe *what*, not *how*
- **Business language** — scenarios should be readable by non-developers
- **Concrete examples** — use specific values, not abstractions

```gherkin
# Good — declarative, specific
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

## Runner Integration

### Go: godog

```bash
# Run all scenarios
godog ./features/

# Run a specific feature
godog ./features/auth.feature

# Run scenarios with a tag
godog --tags="@smoke" ./features/
```

Step definitions go in `*_test.go` files alongside the feature files or
in a dedicated `steps/` directory.

### Python: pytest-bdd

```bash
# Run all BDD tests
pytest tests/features/ -v

# Run a specific feature
pytest tests/features/test_auth.py -v
```

Step definitions use `@given`, `@when`, `@then` decorators in test files
that import `from pytest_bdd import given, when, then, scenarios`.

### Infrastructure: kuttl

For Kubernetes infrastructure testing, see @kuttl-testing for full
conventions. KUTTL tests use a directory-based structure rather than
`.feature` files, but the principle is the same: declarative, behavior-focused.

## Session Sizing

What's achievable in a given time window:

| Time | Suggested Activity |
|------|--------------------|
| 15 min | Write 1-2 scenarios for an existing feature |
| 30 min | Write scenarios + implement step definitions for one feature |
| 45 min | End-to-end: scenarios → issue → implementation → PR |
| 2+ hours | Multiple features, runner setup, CI integration |

## Relationship to Other Skills

- **@creating-github-issues** — convert a scenario into a GitHub issue with
  proper labels (e.g., "good first issue" for straightforward implementations)
- **@kuttl-testing** — infrastructure BDD uses kuttl conventions
- **@gdd** — BDD is a practice skill in the GDD hierarchy, invoked by the
  orchestrator based on task context
