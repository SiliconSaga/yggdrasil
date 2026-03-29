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
