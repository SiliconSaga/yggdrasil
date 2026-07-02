# Skipta Field Amendments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy Skipta — voice-text change orders → Gemini structured extraction → Sheets pricing → dual-signature page → PDF in Drive — live at `https://skipta.cmdbee.org`, per the approved spec `docs/plans/2026-07-01-skipta-field-amendments-design.md`.

**Architecture:** One stateless FastAPI service in the `skipta` namespace; the Google Sheet is the database (pricing tabs + `Amendments` state tab), Drive holds SoW folders and signed PDFs. Vertex AI Gemini structured output does extraction; Workload Identity provides all Google auth (no keys, no OAuth tokens). Kustomize base applied through the armed `ws k8s` guard; images from GitHub Actions → ghcr.

**Tech Stack:** Python 3.11+, FastAPI, Pydantic v2, `google-cloud-aiplatform` (vertexai), `google-api-python-client` (Sheets v4 / Drive v3), Jinja2, WeasyPrint, signature_pad (vendored JS), pytest, ruff, kustomize, Traefik Gateway API.

## Global Constraints

- Python `>=3.11`; images built `FROM python:3.11-slim`.
- GCP project `teralivekubernetes`, region `us-east1`, cluster context `gke_teralivekubernetes_us-east1-d_ttf-cluster`.
- Service account `skipta-gsa@teralivekubernetes.iam.gserviceaccount.com`; KSA `skipta-sa` in namespace `skipta`.
- No secrets anywhere: pod config is identifiers only (ConfigMap); local dev uses ADC impersonation.
- No CDN assets: `signature_pad.umd.min.js` and CSS are vendored under `app/static/`. No Node/Tailwind toolchain.
- Image: `ghcr.io/siliconsaga/skipta` (`:latest` + `type=sha` tags, ting's metadata-action pattern).
- Hostname `skipta.cmdbee.org` via `HTTPRoute` → `traefik-gateway` (`kube-system`), listeners `web` + `websecure`; **no per-host Certificate, no ReferenceGrant** (platform wildcard covers it).
- GDD workspace rules: `ws commit`/`ws push`/`ws cr` (never raw git for those), one shell command per call (no `&&`/`;`/`|`), bodyfiles from `templates/commit.md` at workspace `.commits/`, single-line prose in docs.
- Cluster writes only via `ws k8s … -n skipta` (guard armed to that namespace; pass `-n skipta` explicitly — the guard resolves the target namespace from the command line).
- All local Python runs go through the component venv: `components/skipta/.venv/Scripts/python` on this Windows box (`.venv/bin/python` on POSIX). The Makefile picks the right one, so `ws test skipta` / `ws lint skipta` work everywhere.
- Amendment id format: `amend_<slug>_<YYYYMMDDHHMMSS>` (UTC); PDF name `<Customer_Name>_Amendment_<YYYYMMDDHHMMSS>.pdf`.

## Prerequisites (human-side, in progress)

The user is creating: the `Skipta/` Drive folder (per-customer subfolders, each with a dummy SoW doc), the pricing spreadsheet with tabs `Panels` (`panel_id,max_amperage,description,unit_cost`), `Breakers` (`breaker_id,amps,poles,description,unit_cost`), and `Amendments` with header row exactly: `amendment_id,created_at,customer_name,voice_text,extracted_json,line_items_json,total,status,pdf_drive_url,signed_at`. Both shared as Editor with the GSA email once Task 3 creates it. Task 14 needs the spreadsheet ID and folder ID from the user.

---

### Task 1: Repo bootstrap — SiliconSaga/skipta + workspace registration + scaffold

**Files:**
- Create: `components/skipta/README.md`, `components/skipta/.gitignore`, `components/skipta/requirements.txt`, `components/skipta/requirements-dev.txt`, `components/skipta/pyproject.toml`, `components/skipta/Makefile`, `components/skipta/.env.template`
- Modify: `ecosystem.local.yaml` (workspace root)

**Interfaces:**
- Produces: cloned `components/skipta/` git repo on `main`, `ws` targetability (`ws commit skipta`, `ws test skipta`), pinned dependency set every later task installs against.

- [ ] **Step 1: Create the GitHub repo** (check `ws gh --help` if the arg form differs)

Run: `ws gh repo create SiliconSaga/skipta --public --description "AI-backed field amendment and signing service (GDD showcase)"`
Expected: repo URL printed.

- [ ] **Step 2: Register locally so `ws` can clone it** — add to `ecosystem.local.yaml` `components:` (temporary until the realm entry from Task 2 merges, then delete this block):

```yaml
  skipta:
    tier: supporting
```

- [ ] **Step 3: Clone**

Run: `ws clone skipta`
Expected: empty-repo clone warning is fine; `components/skipta/.git` exists. If the empty clone left no branch, run `git -C components/skipta checkout -b main`.

- [ ] **Step 4: Write the scaffold files**

`components/skipta/.gitignore`:

```gitignore
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
.env
```

`components/skipta/requirements.txt`:

```text
fastapi>=0.115,<1.0
uvicorn[standard]>=0.30,<1.0
google-cloud-aiplatform>=1.60,<2.0
google-api-python-client>=2.100,<3.0
google-auth>=2.30,<3.0
jinja2>=3.1,<4.0
weasyprint>=62,<70
pydantic>=2.7,<3.0
python-dotenv>=1.0,<2.0
slowapi>=0.1.9,<0.2
```

`components/skipta/requirements-dev.txt`:

```text
-r requirements.txt
pytest>=8.0,<9.0
httpx>=0.27,<1.0
ruff>=0.5,<1.0
```

`components/skipta/pyproject.toml`:

```toml
[tool.ruff]
line-length = 110
target-version = "py311"

[tool.pytest.ini_options]
testpaths = ["tests"]
```

`components/skipta/Makefile` (picks the venv python on Windows or POSIX so `ws test`/`ws lint` adapters work on any host):

```make
PY := $(wildcard .venv/Scripts/python.exe)
ifeq ($(PY),)
PY := .venv/bin/python
endif

test:
	$(PY) -m pytest

lint:
	$(PY) -m ruff check .

run:
	$(PY) -m uvicorn app.main:app --reload --port 8000
```

`components/skipta/.env.template`:

```env
GCP_PROJECT_ID=teralivekubernetes
GCP_REGION=us-east1
SKIPTA_SPREADSHEET_ID=
SKIPTA_DRIVE_FOLDER_ID=
SKIPTA_BASE_URL=http://localhost:8000
SKIPTA_MODEL_NAMES=gemini-2.5-flash,gemini-2.5-flash-lite,gemini-2.0-flash-001
MAX_OUTPUT_TOKENS=1024
RATE_LIMIT_PER_MINUTE=10
```

`components/skipta/README.md`:

```markdown
# Skipta

AI-backed field amendment & signing service — a GDD showcase. A field tech dictates a change order; Gemini (Vertex AI structured output) extracts a strict parts payload; Google Sheets prices it; both parties sign on an HTML5 canvas page; the flattened PDF lands in the customer's Google Drive folder.

Design: [yggdrasil docs/plans/2026-07-01-skipta-field-amendments-design.md](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/plans/2026-07-01-skipta-field-amendments-design.md)

## Local dev

1. `python -m venv .venv`
2. `.venv/Scripts/python -m pip install -r requirements-dev.txt` (POSIX: `.venv/bin/python`)
3. Copy `.env.template` to `.env`, fill the spreadsheet/folder IDs.
4. Auth as the service the pod runs as: `gcloud auth application-default login --impersonate-service-account=skipta-gsa@teralivekubernetes.iam.gserviceaccount.com`
5. `make run` → http://localhost:8000

Note: WeasyPrint needs GTK libs; on Windows the PDF test auto-skips — CI and the container cover it.

## Deploy

GitHub Actions builds `ghcr.io/siliconsaga/skipta` on push to main; apply `k8s/base` with kustomize (in the GDD workspace: `ws k8s apply -k components/skipta/k8s/base -n skipta`).
```

- [ ] **Step 5: Create the venv and install deps** (two commands)

Run: `python -m venv components/skipta/.venv`
Run: `components/skipta/.venv/Scripts/python -m pip install -r components/skipta/requirements-dev.txt`
Expected: install succeeds (WeasyPrint wheel installs even without GTK; it fails only at import time, which we handle).

- [ ] **Step 6: Commit + push** — bodyfile `.commits/skipta-scaffold.md`:

```markdown
---
message: "chore: scaffold skipta — deps, Makefile, env template, README"
add:
  - README.md
  - .gitignore
  - requirements.txt
  - requirements-dev.txt
  - pyproject.toml
  - Makefile
  - .env.template
---

Initial scaffold for the Skipta field-amendments service per the approved design (yggdrasil docs/plans/2026-07-01-skipta-field-amendments-design.md). Makefile venv-detection keeps ws test/lint adapters host-portable.
```

Run: `ws commit skipta .commits/skipta-scaffold.md`
Run: `ws push skipta main`
Expected: commit lands with `Co-Authored-By: Claude Fable 5`, push OK (empty repo, no protection yet).

### Task 2: Realm wiring — ecosystem entry + adapter (CR to realm-siliconsaga)

**Files:**
- Modify: `realms/realm-siliconsaga/ecosystem.yaml` (Tier 3 components section)
- Create: `realms/realm-siliconsaga/adapters/skipta.yaml`

**Interfaces:**
- Produces: `ws test skipta` → `make test`, `ws lint skipta` → `make lint`; canonical ecosystem declaration (namespace `skipta`, tier 3).

- [ ] **Step 1: Branch the realm repo**

Run: `git -C realms/realm-siliconsaga checkout -b feat/skipta-component`

- [ ] **Step 2: Add the ecosystem entry** — in `realms/realm-siliconsaga/ecosystem.yaml` under `# -- Tier 3: End-User Platform`, after the `schools:` block:

```yaml
  # skipta — AI-backed field amendment & signing demo (voice → Gemini →
  # Sheets pricing → signed PDF in Drive). Design doc lives in yggdrasil
  # docs/plans/2026-07-01-skipta-field-amendments-design.md.
  skipta:
    tier: 3
    chartVersion: "0.0.0"
    namespace: skipta
```

- [ ] **Step 3: Write the adapter** — `realms/realm-siliconsaga/adapters/skipta.yaml`:

```yaml
# skipta adapter — build/test commands and AI context pointers
commands:
  test: "make test"
  lint: "make lint"

ai_context:
  - path: "README.md"
    description: "Service overview, local dev, deploy"
```

- [ ] **Step 4: Verify wiring**

Run: `ws orient`
Expected: skipta row shows `ws test [runs: make test]` once cloned; at minimum the component resolves.

- [ ] **Step 5: Commit, push, CR** — bodyfile `.commits/realm-skipta.md`:

```markdown
---
message: "feat: declare skipta component (tier 3) + test/lint adapter"
add:
  - ecosystem.yaml
  - adapters/skipta.yaml
---

Registers the new Skipta field-amendments demo service (SiliconSaga/skipta, namespace skipta) in the realm and wires make-based test/lint adapters. See yggdrasil docs/plans/2026-07-01-skipta-field-amendments-design.md.
```

Run: `ws commit realm-siliconsaga .commits/realm-skipta.md`
Run: `ws push realm-siliconsaga`
Then `cp templates/change.md .crs/realm-skipta.md`, fill Summary/Test plan (test plan: `ws orient` shows the adapter row; `ws list` shows skipta), and run: `ws cr realm-siliconsaga "feat: declare skipta component + adapter" .crs/realm-skipta.md`
Expected: CR URL printed. After it merges, delete the temporary `skipta:` block from `ecosystem.local.yaml`.

### Task 3: GCP identity — GSA, IAM, Workload Identity, local impersonation

**Files:** none (cloud state only). One command per call throughout.

**Interfaces:**
- Produces: `skipta-gsa@teralivekubernetes.iam.gserviceaccount.com` usable from the pod (via KSA `skipta-sa`, created in Task 14) and from local dev (impersonated ADC).

- [ ] **Step 1: Enable the Workspace APIs**

Run: `gcloud services enable drive.googleapis.com sheets.googleapis.com --project teralivekubernetes`

- [ ] **Step 2: Create the GSA**

Run: `gcloud iam service-accounts create skipta-gsa --project teralivekubernetes --display-name "Skipta field amendments"`

- [ ] **Step 3: Vertex AI role**

Run: `gcloud projects add-iam-policy-binding teralivekubernetes --member serviceAccount:skipta-gsa@teralivekubernetes.iam.gserviceaccount.com --role roles/aiplatform.user`

- [ ] **Step 4: Workload Identity binding** (KSA needn't exist yet; the member string is declarative)

Run: `gcloud iam service-accounts add-iam-policy-binding skipta-gsa@teralivekubernetes.iam.gserviceaccount.com --role roles/iam.workloadIdentityUser --member "serviceAccount:teralivekubernetes.svc.id.goog[skipta/skipta-sa]"`

- [ ] **Step 5: Let the human impersonate for local dev**

Run: `gcloud iam service-accounts add-iam-policy-binding skipta-gsa@teralivekubernetes.iam.gserviceaccount.com --role roles/iam.serviceAccountTokenCreator --member user:cervator@gmail.com`

- [ ] **Step 6: Hand off to the user (interactive):** ask them to run `! gcloud auth application-default login --impersonate-service-account=skipta-gsa@teralivekubernetes.iam.gserviceaccount.com` and to share the Drive folder + spreadsheet with the GSA email as Editor.

- [ ] **Step 7: Verify Sheets access via impersonated ADC** (after user finishes prep; needs the spreadsheet ID) — write `components/skipta/scripts/verify_access.py`:

```python
"""One-shot access check: prints tab names of the shared spreadsheet via impersonated ADC."""
import os
import sys

import google.auth
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/spreadsheets",
]

creds, _ = google.auth.default(scopes=SCOPES)
sheets = build("sheets", "v4", credentials=creds, cache_discovery=False)
meta = sheets.spreadsheets().get(spreadsheetId=sys.argv[1] if len(sys.argv) > 1 else os.environ["SKIPTA_SPREADSHEET_ID"]).execute()
print([s["properties"]["title"] for s in meta["sheets"]])
```

Run: `components/skipta/.venv/Scripts/python components/skipta/scripts/verify_access.py <SPREADSHEET_ID>`
Expected: `['Panels', 'Breakers', 'Amendments']`. If Sheets rejects the impersonated token's scopes, this is the trigger for the spec's escape hatch (self-impersonated credentials via the IAM Credentials API) — stop and consult the spec's "Google auth" section before proceeding.

- [ ] **Step 8: Commit the verify script** — bodyfile `.commits/skipta-verify-script.md` (message `chore: add one-shot Sheets access verifier`, add: `scripts/verify_access.py`), then `ws commit skipta .commits/skipta-verify-script.md`.

### Task 4: Feature branch + `app/config.py`

**Files:**
- Create: `components/skipta/app/__init__.py` (empty), `components/skipta/app/config.py`
- Test: `components/skipta/tests/__init__.py` (empty), `components/skipta/tests/test_config.py`

**Interfaces:**
- Produces: `Settings` dataclass — fields `project_id, region, spreadsheet_id, drive_folder_id, base_url, model_names: list[str], max_output_tokens: int, rate_limit_per_minute: int`; constructor `Settings.from_env() -> Settings`. All later tasks consume `Settings`.

- [ ] **Step 1: Branch** — run: `git -C components/skipta checkout -b feat/field-amendments-mvp`

- [ ] **Step 2: Write the failing test** — `tests/test_config.py`:

```python
from app.config import Settings


def test_from_env_reads_and_splits(monkeypatch):
    monkeypatch.setenv("GCP_PROJECT_ID", "proj")
    monkeypatch.setenv("GCP_REGION", "us-east1")
    monkeypatch.setenv("SKIPTA_SPREADSHEET_ID", "sheet123")
    monkeypatch.setenv("SKIPTA_DRIVE_FOLDER_ID", "folder123")
    monkeypatch.setenv("SKIPTA_BASE_URL", "https://skipta.cmdbee.org")
    monkeypatch.setenv("SKIPTA_MODEL_NAMES", "gemini-2.5-flash, gemini-2.0-flash-001")
    s = Settings.from_env()
    assert s.project_id == "proj"
    assert s.model_names == ["gemini-2.5-flash", "gemini-2.0-flash-001"]
    assert s.max_output_tokens == 1024
    assert s.rate_limit_per_minute == 10
```

- [ ] **Step 3: Run it, expect failure**

Run: `ws test skipta` (or `components/skipta/.venv/Scripts/python -m pytest tests/test_config.py -v` via `ws exec skipta` if you want just this file)
Expected: FAIL — `ModuleNotFoundError: app.config`.

- [ ] **Step 4: Implement** — `app/config.py`:

```python
"""Environment-driven settings. A .env at the component root is honored for local dev."""
import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()

DEFAULT_MODELS = "gemini-2.5-flash,gemini-2.5-flash-lite,gemini-2.0-flash-001"


@dataclass(frozen=True)
class Settings:
    project_id: str
    region: str
    spreadsheet_id: str
    drive_folder_id: str
    base_url: str
    model_names: list[str] = field(default_factory=list)
    max_output_tokens: int = 1024
    rate_limit_per_minute: int = 10

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            project_id=os.getenv("GCP_PROJECT_ID", ""),
            region=os.getenv("GCP_REGION", "us-east1"),
            spreadsheet_id=os.getenv("SKIPTA_SPREADSHEET_ID", ""),
            drive_folder_id=os.getenv("SKIPTA_DRIVE_FOLDER_ID", ""),
            base_url=os.getenv("SKIPTA_BASE_URL", "http://localhost:8000"),
            model_names=[m.strip() for m in os.getenv("SKIPTA_MODEL_NAMES", DEFAULT_MODELS).split(",") if m.strip()],
            max_output_tokens=int(os.getenv("MAX_OUTPUT_TOKENS", "1024")),
            rate_limit_per_minute=int(os.getenv("RATE_LIMIT_PER_MINUTE", "10")),
        )
```

- [ ] **Step 5: Run tests, expect pass** — `ws test skipta` → PASS.

- [ ] **Step 6: Commit** — bodyfile `.commits/skipta-config.md` (message `feat: env-driven Settings`, add: `app/__init__.py`, `app/config.py`, `tests/__init__.py`, `tests/test_config.py`), run `ws commit skipta .commits/skipta-config.md`.

### Task 5: Extraction — payload models + Gemini structured output

**Files:**
- Create: `components/skipta/app/extraction.py`
- Test: `components/skipta/tests/test_extraction.py`

**Interfaces:**
- Consumes: `Settings.model_names`, `Settings.max_output_tokens`.
- Produces: `AmendmentPayload` (`customer_name: str`, `panel: PanelRequirement | None`, `breakers: list[BreakerRequirement]`), `BreakerRequirement` (`amps: int, poles: int, quantity: int`), `PanelRequirement` (`max_amperage: int`), `ExtractionError`, and `extract_amendment(voice_text: str, *, model_factory, model_names: list[str], max_output_tokens: int) -> AmendmentPayload` where `model_factory(name: str)` returns an object with `.generate_content(prompt, generation_config=...)` returning an object with `.text`.

- [ ] **Step 1: Write the failing tests** — `tests/test_extraction.py`:

```python
import pytest

from app.extraction import AmendmentPayload, ExtractionError, extract_amendment

VALID_JSON = '{"customer_name": "Smith", "panel": {"max_amperage": 200}, "breakers": [{"amps": 20, "poles": 1, "quantity": 3}]}'


class FakeResponse:
    def __init__(self, text):
        self.text = text


class FakeModel:
    def __init__(self, text=None, error=None):
        self.text, self.error = text, error

    def generate_content(self, prompt, generation_config=None):
        if self.error:
            raise self.error
        return FakeResponse(self.text)


def factory_for(models):
    calls = []

    def factory(name):
        calls.append(name)
        return models[len(calls) - 1]

    factory.calls = calls
    return factory


def test_valid_extraction():
    factory = factory_for([FakeModel(text=VALID_JSON)])
    payload = extract_amendment("swap the panel", model_factory=factory, model_names=["m1"], max_output_tokens=512)
    assert payload.customer_name == "Smith"
    assert payload.panel.max_amperage == 200
    assert payload.breakers[0].quantity == 3


def test_falls_back_to_next_model_on_bad_json():
    factory = factory_for([FakeModel(text="not json"), FakeModel(text=VALID_JSON)])
    payload = extract_amendment("x", model_factory=factory, model_names=["m1", "m2"], max_output_tokens=512)
    assert payload.customer_name == "Smith"
    assert factory.calls == ["m1", "m2"]


def test_all_models_fail_raises():
    factory = factory_for([FakeModel(error=RuntimeError("quota")), FakeModel(text="{}")])
    with pytest.raises(ExtractionError):
        extract_amendment("x", model_factory=factory, model_names=["m1", "m2"], max_output_tokens=512)


def test_no_panel_is_fine():
    factory = factory_for([FakeModel(text='{"customer_name": "Jones", "breakers": []}')])
    payload = extract_amendment("x", model_factory=factory, model_names=["m1"], max_output_tokens=512)
    assert payload.panel is None
    assert isinstance(payload, AmendmentPayload)
```

- [ ] **Step 2: Run, expect FAIL** (`ModuleNotFoundError: app.extraction`) — `ws test skipta`.

- [ ] **Step 3: Implement** — `app/extraction.py`:

```python
"""Gemini structured-output extraction of the amendment payload. Anti-hallucination is downstream and deterministic (pricing match) — this layer only shapes the request."""
import logging

from pydantic import BaseModel, Field, ValidationError

logger = logging.getLogger("skipta.extraction")


class BreakerRequirement(BaseModel):
    amps: int = Field(..., description="Amperage of the breaker, e.g. 20, 30, 50")
    poles: int = Field(..., description="Number of poles, usually 1 or 2")
    quantity: int = Field(..., ge=1, description="Quantity requested")


class PanelRequirement(BaseModel):
    max_amperage: int = Field(..., description="Maximum amperage capacity of the panel, e.g. 100, 200")


class AmendmentPayload(BaseModel):
    customer_name: str = Field(..., min_length=1)
    panel: PanelRequirement | None = None
    breakers: list[BreakerRequirement] = Field(default_factory=list)


class ExtractionError(Exception):
    """Every configured model failed to produce a schema-valid payload."""


# Vertex structured-output schema (OpenAPI subset — hand-written; pydantic's json_schema
# emits $defs, which Gemini's response_schema does not accept).
AMENDMENT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "customer_name": {"type": "STRING", "description": "Surname or identifier of the customer"},
        "panel": {
            "type": "OBJECT",
            "nullable": True,
            "properties": {"max_amperage": {"type": "INTEGER"}},
            "required": ["max_amperage"],
        },
        "breakers": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "amps": {"type": "INTEGER"},
                    "poles": {"type": "INTEGER"},
                    "quantity": {"type": "INTEGER"},
                },
                "required": ["amps", "poles", "quantity"],
            },
        },
    },
    "required": ["customer_name"],
}

PROMPT = (
    "You are extracting a field change-order for a residential electrical job from a technician's dictated note. "
    "Extract ONLY parts the note explicitly mentions — never invent parts, quantities, or a customer name.\n\n"
    "Note:\n{voice_text}"
)


def extract_amendment(voice_text, *, model_factory, model_names, max_output_tokens):
    from vertexai.generative_models import GenerationConfig

    config = GenerationConfig(
        response_mime_type="application/json",
        response_schema=AMENDMENT_SCHEMA,
        max_output_tokens=max_output_tokens,
    )
    for name in model_names:
        try:
            response = model_factory(name).generate_content(PROMPT.format(voice_text=voice_text), generation_config=config)
            return AmendmentPayload.model_validate_json(response.text)
        except (ValidationError, ValueError) as exc:
            logger.warning("model %s returned schema-invalid output: %s", name, exc)
        except Exception as exc:  # API errors: quota, permission, model-not-found
            logger.warning("model %s failed: %s", name, exc)
    raise ExtractionError(f"all models failed for extraction: {model_names}")
```

Note: `GenerationConfig` is imported lazily so unit tests exercise it for real (it's a plain data object — no network) while module import stays cheap.

- [ ] **Step 4: Run tests, expect PASS** — `ws test skipta`.

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-extraction.md` (message `feat: Gemini structured-output extraction with model fallback`, add: `app/extraction.py`, `tests/test_extraction.py`), `ws commit skipta .commits/skipta-extraction.md`.

### Task 6: Pricing — Sheets rows → matched, totaled line items

**Files:**
- Create: `components/skipta/app/pricing.py`
- Test: `components/skipta/tests/test_pricing.py`

**Interfaces:**
- Consumes: `AmendmentPayload` from Task 5.
- Produces: `LineItem` dataclass (`kind: str` "panel"|"breaker", `spec: str`, `description: str`, `quantity: int`, `unit_cost: float | None`, `subtotal: float`, `matched: bool`), `PricingResult` (`line_items: list[LineItem]`, `total: float`, `has_unmatched: bool`), `parse_panels(rows) -> list[dict]`, `parse_breakers(rows) -> list[dict]`, `price_amendment(payload, panels, breakers) -> PricingResult`. Rows are `list[list[str]]` as returned by Sheets `values().get`.

- [ ] **Step 1: Write the failing tests** — `tests/test_pricing.py`:

```python
from app.extraction import AmendmentPayload
from app.pricing import parse_breakers, parse_panels, price_amendment

PANEL_ROWS = [["P-200A-01", "200", "200A Main Lug Panel 30-Space", "245.00"]]
BREAKER_ROWS = [
    ["B-20A-1P", "20", "1", "20A Single-Pole Type BR", "7.50"],
    ["B-30A-2P", "30", "2", "30A Double-Pole Type BR", "18.00"],
]


def payload(**kw):
    base = {"customer_name": "Smith", "breakers": [{"amps": 20, "poles": 1, "quantity": 3}], "panel": {"max_amperage": 200}}
    base.update(kw)
    return AmendmentPayload.model_validate(base)


def test_full_match_totals():
    result = price_amendment(payload(), parse_panels(PANEL_ROWS), parse_breakers(BREAKER_ROWS))
    assert result.has_unmatched is False
    assert result.total == 245.00 + 3 * 7.50
    panel_item = next(i for i in result.line_items if i.kind == "panel")
    assert panel_item.matched and panel_item.unit_cost == 245.00


def test_unmatched_breaker_flags_result():
    result = price_amendment(
        payload(breakers=[{"amps": 50, "poles": 2, "quantity": 1}]), parse_panels(PANEL_ROWS), parse_breakers(BREAKER_ROWS)
    )
    assert result.has_unmatched is True
    item = next(i for i in result.line_items if i.kind == "breaker")
    assert item.matched is False and item.unit_cost is None and item.subtotal == 0.0
    assert "50A" in item.spec and "2-pole" in item.spec


def test_no_panel_no_panel_item():
    result = price_amendment(payload(panel=None), parse_panels(PANEL_ROWS), parse_breakers(BREAKER_ROWS))
    assert all(i.kind != "panel" for i in result.line_items)
```

- [ ] **Step 2: Run, expect FAIL** — `ws test skipta`.

- [ ] **Step 3: Implement** — `app/pricing.py`:

```python
"""Deterministic pricing: match extracted requirements against the Panels/Breakers tabs. An unmatched requirement stays visible (UNMATCHED) and blocks signing — this is the guard against LLM-invented parts."""
from dataclasses import asdict, dataclass, field

from app.extraction import AmendmentPayload


@dataclass(frozen=True)
class LineItem:
    kind: str  # "panel" | "breaker"
    spec: str
    description: str
    quantity: int
    unit_cost: float | None
    subtotal: float
    matched: bool


@dataclass(frozen=True)
class PricingResult:
    line_items: list[LineItem] = field(default_factory=list)
    total: float = 0.0
    has_unmatched: bool = False

    def items_as_dicts(self) -> list[dict]:
        return [asdict(i) for i in self.line_items]


def parse_panels(rows):
    return [
        {"panel_id": r[0], "max_amperage": int(r[1]), "description": r[2], "unit_cost": float(r[3])}
        for r in rows
        if len(r) >= 4
    ]


def parse_breakers(rows):
    return [
        {"breaker_id": r[0], "amps": int(r[1]), "poles": int(r[2]), "description": r[3], "unit_cost": float(r[4])}
        for r in rows
        if len(r) >= 5
    ]


def price_amendment(payload: AmendmentPayload, panels: list[dict], breakers: list[dict]) -> PricingResult:
    items: list[LineItem] = []
    if payload.panel is not None:
        match = next((p for p in panels if p["max_amperage"] == payload.panel.max_amperage), None)
        items.append(_line_item("panel", f"{payload.panel.max_amperage}A panel", match, 1))
    for req in payload.breakers:
        match = next((b for b in breakers if b["amps"] == req.amps and b["poles"] == req.poles), None)
        items.append(_line_item("breaker", f"{req.amps}A {req.poles}-pole breaker", match, req.quantity))
    total = round(sum(i.subtotal for i in items), 2)
    return PricingResult(line_items=items, total=total, has_unmatched=any(not i.matched for i in items))


def _line_item(kind, spec, match, quantity) -> LineItem:
    if match is None:
        return LineItem(kind, spec, "UNMATCHED — no pricing row", quantity, None, 0.0, False)
    return LineItem(kind, spec, match["description"], quantity, match["unit_cost"], round(match["unit_cost"] * quantity, 2), True)
```

- [ ] **Step 4: Run tests, expect PASS.** Then run lint: `ws lint skipta` → clean.

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-pricing.md` (message `feat: deterministic pricing with UNMATCHED guard`, add: `app/pricing.py`, `tests/test_pricing.py`), `ws commit skipta .commits/skipta-pricing.md`.

### Task 7: Google clients + Amendments-tab state machine

**Files:**
- Create: `components/skipta/app/google_clients.py`, `components/skipta/app/amendments.py`
- Test: `components/skipta/tests/test_amendments.py`

**Interfaces:**
- Consumes: `Settings` (Task 4).
- Produces: `google_clients.get_credentials()`, `build_sheets(creds)`, `build_drive(creds)`, `make_model_factory(project_id, region)`, `read_values(sheets, spreadsheet_id, a1_range) -> list[list[str]]`. `amendments.AmendmentRecord` dataclass (fields exactly the Amendments header order: `amendment_id, created_at, customer_name, voice_text, extracted_json, line_items_json, total: float, status, pdf_drive_url, signed_at`), `make_amendment_id(customer_name, now) -> str`, `append_amendment(sheets, spreadsheet_id, record)`, `find_amendment(sheets, spreadsheet_id, amendment_id) -> tuple[int, AmendmentRecord] | None` (1-based sheet row), `mark_signed(sheets, spreadsheet_id, row, pdf_url, signed_at)`.

- [ ] **Step 1: Write the failing tests** — `tests/test_amendments.py` (a fake implementing just the Sheets `values()` surface):

```python
from datetime import datetime, timezone

from app.amendments import AmendmentRecord, append_amendment, find_amendment, make_amendment_id, mark_signed


class FakeValues:
    def __init__(self, store):
        self.store = store  # list of rows for the Amendments tab (no header)

    def append(self, spreadsheetId, range, valueInputOption, body):
        self.store.extend(body["values"])
        return self

    def get(self, spreadsheetId, range):
        self._result = {"values": self.store}
        return self

    def update(self, spreadsheetId, range, valueInputOption, body):
        # range like "Amendments!H3:J3" — row 3 is store index 1 (row 1 = header)
        row = int(range.split("!")[1][1:].split(":")[0])
        self.store[row - 2][7:10] = body["values"][0]
        return self

    def execute(self):
        return getattr(self, "_result", {})


class FakeSheets:
    def __init__(self, store):
        self._values = FakeValues(store)

    def spreadsheets(self):
        return self

    def values(self):
        return self._values


def record(aid="amend_smith_20260701120000"):
    return AmendmentRecord(
        amendment_id=aid, created_at="2026-07-01T12:00:00+00:00", customer_name="Smith", voice_text="v",
        extracted_json="{}", line_items_json="[]", total=22.5, status="draft", pdf_drive_url="", signed_at="",
    )


def test_amendment_id_slug():
    aid = make_amendment_id("O'Brien Jr.", datetime(2026, 7, 1, 12, 0, 0, tzinfo=timezone.utc))
    assert aid == "amend_obrien-jr_20260701120000"


def test_append_and_find_roundtrip():
    store = []
    sheets = FakeSheets(store)
    append_amendment(sheets, "sid", record())
    found = find_amendment(sheets, "sid", "amend_smith_20260701120000")
    assert found is not None
    row, rec = found
    assert row == 2 and rec.customer_name == "Smith" and rec.total == 22.5 and rec.status == "draft"


def test_find_missing_returns_none():
    assert find_amendment(FakeSheets([]), "sid", "nope") is None


def test_mark_signed_updates_status_columns():
    store = []
    sheets = FakeSheets(store)
    append_amendment(sheets, "sid", record())
    mark_signed(sheets, "sid", 2, "https://drive/x", "2026-07-01T13:00:00+00:00")
    _, rec = find_amendment(sheets, "sid", "amend_smith_20260701120000")
    assert rec.status == "signed" and rec.pdf_drive_url == "https://drive/x"
```

- [ ] **Step 2: Run, expect FAIL** — `ws test skipta`.

- [ ] **Step 3: Implement** — `app/google_clients.py`:

```python
"""All Google client construction lives here; everything downstream takes injected clients."""
import google.auth
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/spreadsheets",
]


def get_credentials():
    creds, _ = google.auth.default(scopes=SCOPES)
    return creds


def build_sheets(creds):
    return build("sheets", "v4", credentials=creds, cache_discovery=False)


def build_drive(creds):
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def make_model_factory(project_id: str, region: str):
    def factory(model_name: str):
        import vertexai
        from vertexai.generative_models import GenerativeModel

        vertexai.init(project=project_id, location=region)
        return GenerativeModel(model_name)

    return factory


def read_values(sheets, spreadsheet_id: str, a1_range: str):
    result = sheets.spreadsheets().values().get(spreadsheetId=spreadsheet_id, range=a1_range).execute()
    return result.get("values", [])
```

and `app/amendments.py`:

```python
"""The Amendments tab is the state machine: one row per amendment, draft → signed."""
import re
from dataclasses import astuple, dataclass

from app.google_clients import read_values

TAB = "Amendments"
DATA_RANGE = f"{TAB}!A2:J"


@dataclass
class AmendmentRecord:
    amendment_id: str
    created_at: str
    customer_name: str
    voice_text: str
    extracted_json: str
    line_items_json: str
    total: float
    status: str  # "draft" | "signed"
    pdf_drive_url: str
    signed_at: str

    def to_row(self) -> list:
        row = list(astuple(self))
        row[6] = f"{self.total:.2f}"
        return row

    @classmethod
    def from_row(cls, row: list) -> "AmendmentRecord":
        padded = list(row) + [""] * (10 - len(row))
        padded[6] = float(padded[6] or 0)
        return cls(*padded)


def make_amendment_id(customer_name: str, now) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", customer_name.lower()).strip("-")
    return f"amend_{slug}_{now.strftime('%Y%m%d%H%M%S')}"


def append_amendment(sheets, spreadsheet_id: str, record: AmendmentRecord) -> None:
    sheets.spreadsheets().values().append(
        spreadsheetId=spreadsheet_id, range=DATA_RANGE, valueInputOption="RAW", body={"values": [record.to_row()]}
    ).execute()


def find_amendment(sheets, spreadsheet_id: str, amendment_id: str):
    for index, row in enumerate(read_values(sheets, spreadsheet_id, DATA_RANGE)):
        if row and row[0] == amendment_id:
            return index + 2, AmendmentRecord.from_row(row)  # +2: 1-based rows below the header
    return None


def mark_signed(sheets, spreadsheet_id: str, row: int, pdf_url: str, signed_at: str) -> None:
    sheets.spreadsheets().values().update(
        spreadsheetId=spreadsheet_id, range=f"{TAB}!H{row}:J{row}", valueInputOption="RAW",
        body={"values": [["signed", pdf_url, signed_at]]},
    ).execute()
```

- [ ] **Step 4: Run tests, expect PASS** — `ws test skipta`.

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-amendments.md` (message `feat: google clients + Amendments-tab state machine`, add: `app/google_clients.py`, `app/amendments.py`, `tests/test_amendments.py`), `ws commit skipta .commits/skipta-amendments.md`.

### Task 8: Drive — customer folder search + PDF upload

**Files:**
- Create: `components/skipta/app/drive.py`
- Test: `components/skipta/tests/test_drive.py`

**Interfaces:**
- Consumes: a Drive v3 service object (injected).
- Produces: `find_customer_folder(drive, root_folder_id, customer_name) -> str | None`, `upload_pdf(drive, folder_id, filename, pdf_bytes) -> str` (webViewLink).

- [ ] **Step 1: Write the failing tests** — `tests/test_drive.py`:

```python
from app.drive import find_customer_folder, upload_pdf


class FakeFiles:
    def __init__(self, listing):
        self.listing = listing
        self.created = None

    def list(self, q, fields, pageSize):
        self.q = q
        self._result = {"files": self.listing}
        return self

    def create(self, body, media_body, fields):
        self.created = {"body": body, "media": media_body}
        self._result = {"webViewLink": "https://drive.google.com/file/d/abc/view"}
        return self

    def execute(self):
        return self._result


class FakeDrive:
    def __init__(self, listing=()):
        self._files = FakeFiles(list(listing))

    def files(self):
        return self._files


def test_find_folder_builds_query_and_returns_id():
    drive = FakeDrive([{"id": "folder-smith", "name": "Smith"}])
    assert find_customer_folder(drive, "root123", "Smith") == "folder-smith"
    assert "'root123' in parents" in drive.files().q
    assert "mimeType = 'application/vnd.google-apps.folder'" in drive.files().q


def test_find_folder_escapes_quotes():
    drive = FakeDrive([])
    assert find_customer_folder(drive, "root123", "O'Brien") is None
    assert "O\\'Brien" in drive.files().q


def test_upload_pdf_returns_link_and_targets_folder():
    drive = FakeDrive()
    link = upload_pdf(drive, "folder-smith", "Smith_Amendment_20260701120000.pdf", b"%PDF-1.7 fake")
    assert link.startswith("https://drive.google.com/")
    assert drive.files().created["body"]["parents"] == ["folder-smith"]
```

- [ ] **Step 2: Run, expect FAIL** — `ws test skipta`.

- [ ] **Step 3: Implement** — `app/drive.py`:

```python
"""Drive integration: locate the customer's SoW subfolder under the shared Skipta folder, upload signed PDFs."""
import io

from googleapiclient.http import MediaIoBaseUpload

FOLDER_MIME = "application/vnd.google-apps.folder"


def _escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def find_customer_folder(drive, root_folder_id: str, customer_name: str):
    query = (
        f"'{_escape(root_folder_id)}' in parents and mimeType = '{FOLDER_MIME}' "
        f"and name contains '{_escape(customer_name)}' and trashed = false"
    )
    result = drive.files().list(q=query, fields="files(id, name)", pageSize=5).execute()
    files = result.get("files", [])
    return files[0]["id"] if files else None


def upload_pdf(drive, folder_id: str, filename: str, pdf_bytes: bytes) -> str:
    media = MediaIoBaseUpload(io.BytesIO(pdf_bytes), mimetype="application/pdf")
    created = drive.files().create(
        body={"name": filename, "parents": [folder_id]}, media_body=media, fields="webViewLink"
    ).execute()
    return created["webViewLink"]
```

- [ ] **Step 4: Run tests, expect PASS.**

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-drive.md` (message `feat: Drive folder search + PDF upload`, add: `app/drive.py`, `tests/test_drive.py`), `ws commit skipta .commits/skipta-drive.md`.

### Task 9: PDF rendering + amendment document template

**Files:**
- Create: `components/skipta/app/pdf.py`, `components/skipta/app/templates/amendment_pdf.html`
- Test: `components/skipta/tests/test_pdf.py`

**Interfaces:**
- Consumes: nothing app-internal (takes a rendered HTML string).
- Produces: `render_pdf(html: str) -> bytes`; template `amendment_pdf.html` with context `record` (AmendmentRecord), `items` (list of line-item dicts), `crew_signature` / `customer_signature` (data URLs or `None` for preview).

- [ ] **Step 1: Write the test (auto-skips where GTK libs are missing, e.g. this Windows box; CI runs it for real):**

```python
import pytest

from app.amendments import AmendmentRecord

weasyprint = pytest.importorskip("weasyprint")


def test_render_pdf_produces_pdf_bytes():
    from app.pdf import render_amendment_html, render_pdf

    record = AmendmentRecord(
        amendment_id="amend_smith_20260701120000", created_at="2026-07-01T12:00:00+00:00", customer_name="Smith",
        voice_text="Add three 20 amp single pole breakers", extracted_json="{}",
        line_items_json="[]", total=22.5, status="draft", pdf_drive_url="", signed_at="",
    )
    items = [{"kind": "breaker", "spec": "20A 1-pole breaker", "description": "20A Single-Pole Type BR", "quantity": 3, "unit_cost": 7.5, "subtotal": 22.5, "matched": True}]
    html = render_amendment_html(record, items, crew_signature=None, customer_signature=None)
    try:
        pdf = render_pdf(html)
    except OSError as exc:  # missing pango/cairo on the host
        pytest.skip(f"weasyprint system libs unavailable: {exc}")
    assert pdf[:5] == b"%PDF-"
    assert len(pdf) > 1000
```

- [ ] **Step 2: Run, expect FAIL** (import error on `app.pdf`) — or SKIP on this box; in that case rely on CI for the red/green cycle and verify locally only that `render_amendment_html` returns HTML containing "Smith" and "22.50" (add that assertion before the try block so the template logic is still tested when WeasyPrint skips — put the HTML assertions in their own test function `test_render_amendment_html_contents` that never skips).

```python
def test_render_amendment_html_contents():
    from app.pdf import render_amendment_html
    from app.amendments import AmendmentRecord

    record = AmendmentRecord(
        amendment_id="a", created_at="c", customer_name="Smith", voice_text="v", extracted_json="{}",
        line_items_json="[]", total=22.5, status="draft", pdf_drive_url="", signed_at="",
    )
    html = render_amendment_html(record, [], crew_signature=None, customer_signature=None)
    assert "Smith" in html and "22.50" in html
```

- [ ] **Step 3: Implement** — `app/pdf.py`:

```python
"""HTML → flattened PDF. WeasyPrint imports lazily: hosts without GTK libs can still run every non-PDF code path."""
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

_env = Environment(
    loader=FileSystemLoader(Path(__file__).parent / "templates"),
    autoescape=select_autoescape(["html"]),
)


def render_amendment_html(record, items, *, crew_signature, customer_signature) -> str:
    return _env.get_template("amendment_pdf.html").render(
        record=record, items=items, crew_signature=crew_signature, customer_signature=customer_signature
    )


def render_pdf(html: str) -> bytes:
    from weasyprint import HTML

    return HTML(string=html).write_pdf()
```

and `app/templates/amendment_pdf.html`:

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: sans-serif; font-size: 12px; margin: 2em; }
  h1 { font-size: 18px; }
  table { width: 100%; border-collapse: collapse; margin: 1em 0; }
  th, td { border: 1px solid #999; padding: 6px; text-align: left; }
  .total { font-weight: bold; }
  .sigs { display: flex; justify-content: space-between; margin-top: 3em; }
  .sig { width: 45%; border-top: 1px solid #333; padding-top: 4px; }
  .sig img { max-height: 80px; }
  .unmatched { color: #b00; font-weight: bold; }
</style>
</head>
<body>
  <h1>Field Amendment — {{ record.customer_name }}</h1>
  <p>Amendment <strong>{{ record.amendment_id }}</strong>, created {{ record.created_at }}.</p>
  <p>This amendment to the existing statement of work covers the following change requested on site:</p>
  <blockquote>{{ record.voice_text }}</blockquote>
  <table>
    <tr><th>Item</th><th>Description</th><th>Qty</th><th>Unit</th><th>Subtotal</th></tr>
    {% for item in items %}
    <tr {% if not item.matched %}class="unmatched"{% endif %}>
      <td>{{ item.spec }}</td>
      <td>{{ item.description }}</td>
      <td>{{ item.quantity }}</td>
      <td>{{ "%.2f"|format(item.unit_cost) if item.unit_cost is not none else "—" }}</td>
      <td>{{ "%.2f"|format(item.subtotal) }}</td>
    </tr>
    {% endfor %}
    <tr class="total"><td colspan="4">Total</td><td>{{ "%.2f"|format(record.total) }}</td></tr>
  </table>
  <p>By signing below, both parties agree to the described change and pricing as an amendment to the existing agreement.</p>
  <div class="sigs">
    <div class="sig">{% if crew_signature %}<img src="{{ crew_signature }}">{% endif %}<br>Crew — {{ record.signed_at }}</div>
    <div class="sig">{% if customer_signature %}<img src="{{ customer_signature }}">{% endif %}<br>Customer — {{ record.customer_name }}</div>
  </div>
</body>
</html>
```

- [ ] **Step 4: Run tests** — `ws test skipta`: HTML-contents test PASS; PDF test PASS in CI / SKIP locally (expected on Windows).

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-pdf.md` (message `feat: amendment document template + WeasyPrint rendering`, add: `app/pdf.py`, `app/templates/amendment_pdf.html`, `tests/test_pdf.py`), `ws commit skipta .commits/skipta-pdf.md`.

### Task 10: Static assets + intake and signing page templates

**Files:**
- Create: `components/skipta/app/static/skipta.css`, `components/skipta/app/static/signature_pad.umd.min.js` (vendored), `components/skipta/app/templates/index.html`, `components/skipta/app/templates/sign.html`

**Interfaces:**
- Produces: templates consumed by Task 11's routes — `index.html` (no context), `sign.html` (context: `record`, `items`, `has_unmatched: bool`, `already_signed: bool`). JS posts JSON to `/api/v1/amendments` and `/api/v1/amendments/{id}/sign` with the exact field names Tasks 11–12 define.

- [ ] **Step 1: Vendor signature_pad (pin major 5)**

Run: `curl -L -o components/skipta/app/static/signature_pad.umd.min.js https://cdn.jsdelivr.net/npm/signature_pad@5.0.4/dist/signature_pad.umd.min.js`
Expected: file ~10KB, starts with a UMD banner mentioning `signature_pad`.

- [ ] **Step 2: Write `app/static/skipta.css`** (shared, mobile-first):

```css
* { box-sizing: border-box; }
body { font-family: system-ui, sans-serif; margin: 0; padding: 1rem; background: #f5f5f4; color: #1c1917; }
main { max-width: 640px; margin: 0 auto; }
h1 { font-size: 1.3rem; }
textarea, input[type=text] { width: 100%; padding: .6rem; font-size: 1rem; border: 1px solid #a8a29e; border-radius: 6px; }
textarea { min-height: 8rem; }
button { width: 100%; padding: .8rem; margin-top: 1rem; font-size: 1.05rem; border: 0; border-radius: 6px; background: #1d4ed8; color: #fff; }
button:disabled { background: #a8a29e; }
table { width: 100%; border-collapse: collapse; margin: 1rem 0; background: #fff; }
th, td { border: 1px solid #d6d3d1; padding: .5rem; font-size: .9rem; text-align: left; }
.total td { font-weight: 700; }
.unmatched td { color: #b91c1c; font-weight: 600; }
.warn { background: #fef3c7; border: 1px solid #f59e0b; padding: .8rem; border-radius: 6px; }
.ok { background: #dcfce7; border: 1px solid #22c55e; padding: .8rem; border-radius: 6px; }
canvas.sig { width: 100%; height: 160px; background: #fff; border: 1px dashed #78716c; border-radius: 6px; touch-action: none; }
label { display: block; margin-top: 1rem; font-weight: 600; }
a.clear { font-size: .8rem; font-weight: 400; float: right; }
#result a { word-break: break-all; }
```

- [ ] **Step 3: Write `app/templates/index.html`** (intake form; phone dictation supplies the voice text):

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Skipta — new field amendment</title>
<link rel="stylesheet" href="/static/skipta.css">
</head>
<body><main>
  <h1>Skipta — dictate a change order</h1>
  <p>Tap the text box and use your keyboard's mic to dictate the change, e.g. <em>"Smith wants to upgrade to a 200 amp panel and add three 20 amp single pole breakers."</em></p>
  <label>Customer (optional — extracted from the note if blank)<input type="text" id="customer"></label>
  <label>Change order<textarea id="voice" placeholder="Dictate or type the change…"></textarea></label>
  <button id="submit">Create amendment</button>
  <p id="result"></p>
<script>
document.getElementById("submit").addEventListener("click", async () => {
  const result = document.getElementById("result");
  result.textContent = "Working…";
  const body = { voice_text: document.getElementById("voice").value };
  const customer = document.getElementById("customer").value.trim();
  if (customer) body.customer_name = customer;
  const resp = await fetch("/api/v1/amendments", { method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(body) });
  if (!resp.ok) { result.textContent = "Failed: " + (await resp.text()); return; }
  const data = await resp.json();
  result.innerHTML = `Amendment created — <a href="${data.signing_url}">open the signing page</a>`;
});
</script>
</main></body>
</html>
```

- [ ] **Step 4: Write `app/templates/sign.html`**:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Amendment {{ record.amendment_id }}</title>
<link rel="stylesheet" href="/static/skipta.css">
<script src="/static/signature_pad.umd.min.js"></script>
</head>
<body><main>
  <h1>Field amendment — {{ record.customer_name }}</h1>
  <p>Requested change: <em>{{ record.voice_text }}</em></p>
  <table>
    <tr><th>Item</th><th>Description</th><th>Qty</th><th>Unit</th><th>Subtotal</th></tr>
    {% for item in items %}
    <tr {% if not item.matched %}class="unmatched"{% endif %}>
      <td>{{ item.spec }}</td><td>{{ item.description }}</td><td>{{ item.quantity }}</td>
      <td>{{ "%.2f"|format(item.unit_cost) if item.unit_cost is not none else "—" }}</td>
      <td>{{ "%.2f"|format(item.subtotal) }}</td>
    </tr>
    {% endfor %}
    <tr class="total"><td colspan="4">Total</td><td>{{ "%.2f"|format(record.total) }}</td></tr>
  </table>
  {% if already_signed %}
    <p class="ok">Already signed. <a href="{{ record.pdf_drive_url }}">View the PDF in Drive</a>.</p>
  {% elif has_unmatched %}
    <p class="warn">One or more items have no pricing match (UNMATCHED). Fix the pricing sheet or re-submit the request — signing is disabled.</p>
  {% else %}
    <label>Crew signature <a class="clear" href="#" data-clear="crew">clear</a></label>
    <canvas class="sig" id="crew"></canvas>
    <label>Customer signature <a class="clear" href="#" data-clear="customer">clear</a></label>
    <canvas class="sig" id="customer"></canvas>
    <button id="enact">Enact</button>
    <p id="result"></p>
  {% endif %}
<script>
if (!{{ "true" if already_signed or has_unmatched else "false" }}) {
  const pads = {};
  for (const id of ["crew", "customer"]) {
    const canvas = document.getElementById(id);
    canvas.width = canvas.offsetWidth; canvas.height = canvas.offsetHeight;
    pads[id] = new SignaturePad(canvas);
  }
  document.querySelectorAll("a.clear").forEach(a => a.addEventListener("click", e => { e.preventDefault(); pads[a.dataset.clear].clear(); }));
  document.getElementById("enact").addEventListener("click", async () => {
    const result = document.getElementById("result");
    if (pads.crew.isEmpty() || pads.customer.isEmpty()) { result.textContent = "Both signatures are required."; return; }
    result.textContent = "Generating PDF…";
    const resp = await fetch("/api/v1/amendments/{{ record.amendment_id }}/sign", {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({ crew_signature_base64: pads.crew.toDataURL(), customer_signature_base64: pads.customer.toDataURL() }),
    });
    if (!resp.ok) { result.textContent = "Failed: " + (await resp.text()); return; }
    const data = await resp.json();
    result.innerHTML = `Signed! <a href="${data.pdf_drive_url}">PDF in Drive</a>`;
    document.getElementById("enact").disabled = true;
  });
}
</script>
</main></body>
</html>
```

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-frontend.md` (message `feat: intake + signing pages, vendored signature_pad, stylesheet`, add: `app/static/skipta.css`, `app/static/signature_pad.umd.min.js`, `app/templates/index.html`, `app/templates/sign.html`), `ws commit skipta .commits/skipta-frontend.md`. (Templates are exercised by Task 11's route tests — this commit is template-only and safe to land untested.)

### Task 11: Routes — app wiring, intake, signing page

**Files:**
- Create: `components/skipta/app/main.py`
- Test: `components/skipta/tests/test_routes_intake.py`, `components/skipta/tests/conftest.py`

**Interfaces:**
- Consumes: everything from Tasks 4–10.
- Produces: FastAPI `app` with dependency providers `get_settings`, `get_sheets`, `get_drive`, `get_extract` (overridable in tests); routes `GET /`, `GET /healthz`, `POST /api/v1/amendments`, `GET /amendments/{amendment_id}`; Task 12 adds `POST /api/v1/amendments/{amendment_id}/sign` to this same file.

- [ ] **Step 1: Write shared test fixtures** — `tests/conftest.py`:

```python
import pytest
from fastapi.testclient import TestClient

from app.amendments import AmendmentRecord
from app.extraction import AmendmentPayload
from app.main import app, get_drive, get_extract, get_settings, get_sheets
from app.config import Settings
from tests.test_amendments import FakeSheets
from tests.test_drive import FakeDrive

PANEL_ROWS = [["P-200A-01", "200", "200A Main Lug Panel 30-Space", "245.00"]]
BREAKER_ROWS = [["B-20A-1P", "20", "1", "20A Single-Pole Type BR", "7.50"]]


class RoutedFakeSheets(FakeSheets):
    """Serves pricing tabs read-only and the Amendments tab read/write, keyed by A1 range."""

    def __init__(self, store):
        super().__init__(store)
        self._values.get = self._routed_get

    def _routed_get(self, spreadsheetId, range):
        if range.startswith("Panels"):
            self._values._result = {"values": PANEL_ROWS}
        elif range.startswith("Breakers"):
            self._values._result = {"values": BREAKER_ROWS}
        else:
            self._values._result = {"values": self._values.store}
        return self._values


@pytest.fixture
def fakes():
    return {"sheets": RoutedFakeSheets([]), "drive": FakeDrive([{"id": "folder-smith", "name": "Smith"}])}


@pytest.fixture
def client(fakes):
    payload = AmendmentPayload.model_validate(
        {"customer_name": "Smith", "panel": {"max_amperage": 200}, "breakers": [{"amps": 20, "poles": 1, "quantity": 3}]}
    )
    app.dependency_overrides[get_settings] = lambda: Settings(
        project_id="p", region="r", spreadsheet_id="sid", drive_folder_id="root", base_url="http://testserver",
        model_names=["fake"], max_output_tokens=64, rate_limit_per_minute=1000,
    )
    app.dependency_overrides[get_sheets] = lambda: fakes["sheets"]
    app.dependency_overrides[get_drive] = lambda: fakes["drive"]
    app.dependency_overrides[get_extract] = lambda: (lambda voice_text, settings: payload)
    yield TestClient(app)
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Write the failing intake tests** — `tests/test_routes_intake.py`:

```python
def test_healthz(client):
    assert client.get("/healthz").json() == {"status": "healthy"}


def test_index_serves_form(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert "dictate" in resp.text.lower()


def test_create_amendment_returns_signing_url(client, fakes):
    resp = client.post("/api/v1/amendments", json={"voice_text": "Smith wants a 200A panel and three 20A single pole breakers"})
    assert resp.status_code == 201
    data = resp.json()
    assert data["amendment_id"].startswith("amend_smith_")
    assert data["signing_url"] == f"http://testserver/amendments/{data['amendment_id']}"
    assert len(fakes["sheets"]._values.store) == 1  # draft row persisted


def test_signing_page_renders_items(client):
    created = client.post("/api/v1/amendments", json={"voice_text": "x"}).json()
    page = client.get(f"/amendments/{created['amendment_id']}")
    assert page.status_code == 200
    assert "20A Single-Pole Type BR" in page.text
    assert "Enact" in page.text


def test_unknown_amendment_404(client):
    assert client.get("/amendments/amend_nobody_20260101000000").status_code == 404


def test_blank_voice_text_422(client):
    assert client.post("/api/v1/amendments", json={"voice_text": "   "}).status_code == 422
```

- [ ] **Step 3: Run, expect FAIL** (`app.main` missing) — `ws test skipta`.

- [ ] **Step 4: Implement** — `app/main.py`:

```python
"""Skipta — field amendment service. Routes only; logic lives in the sibling modules."""
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field, field_validator
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app import amendments, drive as drive_mod, pricing
from app.amendments import AmendmentRecord
from app.config import Settings
from app.extraction import ExtractionError, extract_amendment
from app.google_clients import build_drive, build_sheets, get_credentials, make_model_factory, read_values

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper(), format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("skipta")

app = FastAPI(title="Skipta")
app.mount("/static", StaticFiles(directory=Path(__file__).parent / "static"), name="static")
templates = Jinja2Templates(directory=Path(__file__).parent / "templates")

limiter = Limiter(key_func=get_remote_address, default_limits=[])
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

_settings: Settings | None = None
_clients: dict = {}


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings.from_env()
    return _settings


def get_sheets():
    if "sheets" not in _clients:
        _clients["sheets"] = build_sheets(get_credentials())
    return _clients["sheets"]


def get_drive():
    if "drive" not in _clients:
        _clients["drive"] = build_drive(get_credentials())
    return _clients["drive"]


def get_extract():
    def _extract(voice_text: str, settings: Settings):
        factory = make_model_factory(settings.project_id, settings.region)
        return extract_amendment(
            voice_text, model_factory=factory, model_names=settings.model_names, max_output_tokens=settings.max_output_tokens
        )

    return _extract


class CreateAmendmentRequest(BaseModel):
    voice_text: str = Field(..., min_length=1, max_length=4000)
    customer_name: str | None = Field(default=None, max_length=200)

    @field_validator("voice_text")
    @classmethod
    def not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("voice_text cannot be blank")
        return v.strip()


@app.get("/healthz")
def healthz():
    return {"status": "healthy"}


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse(request, "index.html")


@app.post("/api/v1/amendments", status_code=201)
@limiter.limit(lambda: f"{get_settings().rate_limit_per_minute}/minute")
def create_amendment(
    request: Request,
    body: CreateAmendmentRequest,
    settings: Settings = Depends(get_settings),
    sheets=Depends(get_sheets),
    extract=Depends(get_extract),
):
    try:
        payload = extract(body.voice_text, settings)
    except ExtractionError as exc:
        raise HTTPException(status_code=422, detail=f"Could not understand the change order: {exc}") from exc
    if body.customer_name:
        payload = payload.model_copy(update={"customer_name": body.customer_name})

    panels = pricing.parse_panels(read_values(sheets, settings.spreadsheet_id, "Panels!A2:D"))
    breakers = pricing.parse_breakers(read_values(sheets, settings.spreadsheet_id, "Breakers!A2:E"))
    result = pricing.price_amendment(payload, panels, breakers)

    now = datetime.now(timezone.utc)
    amendment_id = amendments.make_amendment_id(payload.customer_name, now)
    record = AmendmentRecord(
        amendment_id=amendment_id, created_at=now.isoformat(), customer_name=payload.customer_name,
        voice_text=body.voice_text, extracted_json=payload.model_dump_json(),
        line_items_json=json.dumps(result.items_as_dicts()), total=result.total, status="draft",
        pdf_drive_url="", signed_at="",
    )
    amendments.append_amendment(sheets, settings.spreadsheet_id, record)
    logger.info("amendment %s created (unmatched=%s, total=%.2f)", amendment_id, result.has_unmatched, result.total)
    return {"amendment_id": amendment_id, "signing_url": f"{settings.base_url}/amendments/{amendment_id}"}


@app.get("/amendments/{amendment_id}", response_class=HTMLResponse)
def signing_page(request: Request, amendment_id: str, settings: Settings = Depends(get_settings), sheets=Depends(get_sheets)):
    found = amendments.find_amendment(sheets, settings.spreadsheet_id, amendment_id)
    if found is None:
        raise HTTPException(status_code=404, detail="Unknown amendment")
    _, record = found
    items = json.loads(record.line_items_json)
    return templates.TemplateResponse(
        request, "sign.html",
        {"record": record, "items": items, "has_unmatched": any(not i["matched"] for i in items), "already_signed": record.status == "signed"},
    )
```

Note on the limiter: `slowapi` reads the limit at request time via the callable, so test overrides of `get_settings` don't fight a decorator-time constant. If the installed slowapi version rejects a callable limit, fall back to a module constant read from env at import (`RATE_LIMIT = os.getenv("RATE_LIMIT_PER_MINUTE", "10") + "/minute"`) and note it in the commit body.

- [ ] **Step 5: Run tests, expect PASS** — `ws test skipta`; run `ws lint skipta` → clean.

- [ ] **Step 6: Commit** — bodyfile `.commits/skipta-routes-intake.md` (message `feat: app wiring, intake + signing-page routes`, add: `app/main.py`, `tests/conftest.py`, `tests/test_routes_intake.py`), `ws commit skipta .commits/skipta-routes-intake.md`.

### Task 12: Sign endpoint — signatures → PDF → Drive → signed

**Files:**
- Modify: `components/skipta/app/main.py` (append route + request model)
- Test: `components/skipta/tests/test_routes_sign.py`

**Interfaces:**
- Consumes: `render_amendment_html`/`render_pdf` (Task 9), `find_customer_folder`/`upload_pdf` (Task 8), `find_amendment`/`mark_signed` (Task 7).
- Produces: `POST /api/v1/amendments/{amendment_id}/sign` accepting `{crew_signature_base64, customer_signature_base64}` (PNG data URLs), returning `{pdf_drive_url}`.

- [ ] **Step 1: Write the failing tests** — `tests/test_routes_sign.py`:

```python
import pytest

SIG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=="


@pytest.fixture
def signed_body():
    return {"crew_signature_base64": SIG, "customer_signature_base64": SIG}


@pytest.fixture
def created(client):
    return client.post("/api/v1/amendments", json={"voice_text": "x"}).json()


def test_sign_uploads_pdf_and_marks_signed(client, fakes, created, signed_body, monkeypatch):
    monkeypatch.setattr("app.main.render_pdf", lambda html: b"%PDF-fake")
    resp = client.post(f"/api/v1/amendments/{created['amendment_id']}/sign", json=signed_body)
    assert resp.status_code == 200
    assert resp.json()["pdf_drive_url"].startswith("https://drive.google.com/")
    row = fakes["sheets"]._values.store[0]
    assert row[7] == "signed" and row[8].startswith("https://drive.google.com/")
    assert fakes["drive"].files().created["body"]["parents"] == ["folder-smith"]


def test_double_sign_409(client, fakes, created, signed_body, monkeypatch):
    monkeypatch.setattr("app.main.render_pdf", lambda html: b"%PDF-fake")
    client.post(f"/api/v1/amendments/{created['amendment_id']}/sign", json=signed_body)
    assert client.post(f"/api/v1/amendments/{created['amendment_id']}/sign", json=signed_body).status_code == 409


def test_sign_unknown_404(client, signed_body):
    assert client.post("/api/v1/amendments/amend_no_1/sign", json=signed_body).status_code == 404


def test_sign_rejects_non_png_payload(client, created):
    bad = {"crew_signature_base64": "data:text/html;base64,PGI+", "customer_signature_base64": SIG}
    assert client.post(f"/api/v1/amendments/{created['amendment_id']}/sign", json=bad).status_code == 422


def test_sign_without_customer_folder_uses_root(client, fakes, created, signed_body, monkeypatch):
    monkeypatch.setattr("app.main.render_pdf", lambda html: b"%PDF-fake")
    fakes["drive"].files().listing.clear()
    resp = client.post(f"/api/v1/amendments/{created['amendment_id']}/sign", json=signed_body)
    assert resp.status_code == 200
    assert fakes["drive"].files().created["body"]["parents"] == ["root"]
```

- [ ] **Step 2: Run, expect FAIL** (405/no route) — `ws test skipta`.

- [ ] **Step 3: Implement** — append to `app/main.py` (plus add `from app.pdf import render_amendment_html, render_pdf` to the imports):

```python
class SignRequest(BaseModel):
    crew_signature_base64: str
    customer_signature_base64: str

    @field_validator("crew_signature_base64", "customer_signature_base64")
    @classmethod
    def must_be_png_data_url(cls, v: str) -> str:
        if not v.startswith("data:image/png;base64,"):
            raise ValueError("signature must be a PNG data URL")
        return v


@app.post("/api/v1/amendments/{amendment_id}/sign")
@limiter.limit(lambda: f"{get_settings().rate_limit_per_minute}/minute")
def sign_amendment(
    request: Request,
    amendment_id: str,
    body: SignRequest,
    settings: Settings = Depends(get_settings),
    sheets=Depends(get_sheets),
    drive=Depends(get_drive),
):
    found = amendments.find_amendment(sheets, settings.spreadsheet_id, amendment_id)
    if found is None:
        raise HTTPException(status_code=404, detail="Unknown amendment")
    row, record = found
    if record.status == "signed":
        raise HTTPException(status_code=409, detail="Amendment already signed")

    signed_at = datetime.now(timezone.utc)
    record.signed_at = signed_at.isoformat()
    items = json.loads(record.line_items_json)
    html = render_amendment_html(record, items, crew_signature=body.crew_signature_base64, customer_signature=body.customer_signature_base64)
    try:
        pdf_bytes = render_pdf(html)
    except OSError as exc:
        raise HTTPException(status_code=502, detail=f"PDF rendering unavailable: {exc}") from exc

    folder_id = drive_mod.find_customer_folder(drive, settings.drive_folder_id, record.customer_name) or settings.drive_folder_id
    filename = f"{record.customer_name.replace(' ', '_')}_Amendment_{signed_at.strftime('%Y%m%d%H%M%S')}.pdf"
    try:
        pdf_url = drive_mod.upload_pdf(drive, folder_id, filename, pdf_bytes)
        amendments.mark_signed(sheets, settings.spreadsheet_id, row, pdf_url, record.signed_at)
    except HTTPException:
        raise
    except Exception as exc:  # Drive/Sheets upstream failure — surface honestly
        logger.error("sign flow failed for %s: %s", amendment_id, exc)
        raise HTTPException(status_code=502, detail=f"Google API failure: {exc}") from exc
    logger.info("amendment %s signed → %s", amendment_id, pdf_url)
    return {"pdf_drive_url": pdf_url}
```

- [ ] **Step 4: Run all tests, expect PASS** — `ws test skipta`; `ws lint skipta` clean.

- [ ] **Step 5: Commit** — bodyfile `.commits/skipta-sign.md` (message `feat: sign endpoint — signatures to flattened PDF in Drive`, add: `app/main.py`, `tests/test_routes_sign.py`), `ws commit skipta .commits/skipta-sign.md`.

- [ ] **Step 6: Manual local smoke (optional but recommended):** run `ws exec skipta make run`, open `http://localhost:8000`, create an amendment against the real Sheet (impersonated ADC + real Gemini), check the draft row appears in the spreadsheet. PDF signing locally will 502 without GTK — expected; the container covers it.

### Task 13: Dockerfile + GitHub Actions (ci + image)

**Files:**
- Create: `components/skipta/Dockerfile`, `components/skipta/.dockerignore`, `components/skipta/.github/workflows/ci.yml`, `components/skipta/.github/workflows/image.yml`

**Interfaces:**
- Produces: `ghcr.io/siliconsaga/skipta:latest` on every main push (consumed by Task 14's Deployment).

- [ ] **Step 1: Write `Dockerfile`:**

```dockerfile
FROM python:3.11-slim

# WeasyPrint runtime libs + a real font for PDF output
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpango-1.0-0 libpangoft2-1.0-0 libgdk-pixbuf-2.0-0 fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ app/
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

and `.dockerignore`:

```text
.venv
.git
tests
.pytest_cache
.ruff_cache
__pycache__
```

- [ ] **Step 2: Write `.github/workflows/ci.yml`** (ting's shape, plus WeasyPrint system deps so the PDF test runs for real):

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-python@v5
      with: {python-version: '3.11'}
    - run: sudo apt-get update && sudo apt-get install -y libpango-1.0-0 libpangoft2-1.0-0 libgdk-pixbuf-2.0-0
    - run: pip install -r requirements-dev.txt
    - run: ruff check .
    - run: python -m pytest -v
```

- [ ] **Step 3: Write `.github/workflows/image.yml`** (ting's verbatim pattern, image name swapped):

```yaml
name: image
on:
  push:
    branches: [main]
permissions:
  contents: read
  packages: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: docker/setup-buildx-action@v3
    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - uses: docker/metadata-action@v5
      id: meta
      with:
        images: ghcr.io/siliconsaga/skipta
        tags: |
          type=sha,format=long
          type=raw,value=latest,enable={{is_default_branch}}
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

- [ ] **Step 4: Commit** — bodyfile `.commits/skipta-ci.md` (message `feat: Dockerfile + Actions ci/image workflows (ghcr)`, add: `Dockerfile`, `.dockerignore`, `.github/workflows/ci.yml`, `.github/workflows/image.yml`), `ws commit skipta .commits/skipta-ci.md`.

- [ ] **Step 5: Push the branch and open the component CR** — run `ws push skipta`, then `cp templates/change.md .crs/skipta-mvp.md`, fill it (Summary: the whole MVP; Test plan: CI green — pytest incl. real WeasyPrint render, ruff; k8s apply follows in a later CR-less deploy step), then `ws cr skipta "feat: field amendments MVP — extraction, pricing, signing, PDF to Drive" .crs/skipta-mvp.md`.
Expected: CR opens, `ci` workflow runs green on the PR. Address review (CodeRabbit etc.) via the normal `ws review` triage flow, merge, and confirm the `image` workflow pushes `ghcr.io/siliconsaga/skipta:latest`.

- [ ] **Step 6: Make the ghcr package public** (first push creates it private; the cluster has no pull secret — ting precedent is a public package). Ask the user to flip it in the GitHub UI (org → Packages → skipta → Package settings → Change visibility → Public), or run: `ws gh api --method PATCH /orgs/SiliconSaga/packages/container/skipta --field visibility=public` (if the API rejects the field, the UI path is the fallback).

### Task 14: Kubernetes base + deploy through the guard

**Files:**
- Create: `components/skipta/k8s/base/kustomization.yaml`, `namespace.yaml`, `serviceaccount.yaml`, `configmap.yaml`, `deployment.yaml`, `service.yaml`, `httproute.yaml`

**Interfaces:**
- Consumes: `ghcr.io/siliconsaga/skipta:latest` (Task 13), GSA + WI binding (Task 3), spreadsheet/folder IDs (from the user).
- Produces: live service at `https://skipta.cmdbee.org`.

- [ ] **Step 1: Get the two IDs from the user** (spreadsheet ID from its URL, `Skipta/` folder ID from its URL) and confirm both are shared with the GSA.

- [ ] **Step 2: Write the manifests.**

`k8s/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: skipta
resources:
- namespace.yaml
- serviceaccount.yaml
- configmap.yaml
- deployment.yaml
- service.yaml
- httproute.yaml
```

`k8s/base/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: skipta
```

`k8s/base/serviceaccount.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: skipta-sa
  namespace: skipta
  annotations:
    iam.gke.io/gcp-service-account: skipta-gsa@teralivekubernetes.iam.gserviceaccount.com
```

`k8s/base/configmap.yaml` (fill the two IDs before applying — identifiers, not secrets, so they are committed):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: skipta-config
  namespace: skipta
data:
  gcp_project_id: "teralivekubernetes"
  gcp_region: "us-east1"
  spreadsheet_id: "<SPREADSHEET_ID>"
  drive_folder_id: "<DRIVE_FOLDER_ID>"
  base_url: "https://skipta.cmdbee.org"
```

`k8s/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skipta
  namespace: skipta
spec:
  replicas: 1
  selector:
    matchLabels: {app: skipta}
  template:
    metadata:
      labels: {app: skipta}
    spec:
      serviceAccountName: skipta-sa
      containers:
      - name: skipta
        image: ghcr.io/siliconsaga/skipta:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
        env:
        - name: GCP_PROJECT_ID
          valueFrom: {configMapKeyRef: {name: skipta-config, key: gcp_project_id}}
        - name: GCP_REGION
          valueFrom: {configMapKeyRef: {name: skipta-config, key: gcp_region}}
        - name: SKIPTA_SPREADSHEET_ID
          valueFrom: {configMapKeyRef: {name: skipta-config, key: spreadsheet_id}}
        - name: SKIPTA_DRIVE_FOLDER_ID
          valueFrom: {configMapKeyRef: {name: skipta-config, key: drive_folder_id}}
        - name: SKIPTA_BASE_URL
          valueFrom: {configMapKeyRef: {name: skipta-config, key: base_url}}
        readinessProbe:
          httpGet: {path: /healthz, port: 8000}
          initialDelaySeconds: 3
          periodSeconds: 5
        livenessProbe:
          httpGet: {path: /healthz, port: 8000}
          initialDelaySeconds: 15
          periodSeconds: 10
        resources:
          requests: {cpu: 250m, memory: 512Mi}
          limits: {cpu: 500m, memory: 1Gi}
```

`k8s/base/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: skipta
  namespace: skipta
spec:
  type: ClusterIP
  selector: {app: skipta}
  ports:
  - port: 80
    targetPort: 8000
```

`k8s/base/httproute.yaml` (ting pattern — platform wildcard cert, no Certificate/ReferenceGrant):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: skipta
  namespace: skipta
spec:
  parentRefs:
  - name: traefik-gateway
    namespace: kube-system
    kind: Gateway
    sectionName: web
  - name: traefik-gateway
    namespace: kube-system
    kind: Gateway
    sectionName: websecure
  hostnames:
  - "skipta.cmdbee.org"
  rules:
  - matches:
    - path: {type: PathPrefix, value: "/"}
    backendRefs:
    - name: skipta
      port: 80
```

- [ ] **Step 3: Create the namespace through the guard** (explicitly in-scope):

Run: `ws k8s create namespace skipta`
Expected: created.

- [ ] **Step 4: Apply the base**

Run: `ws k8s apply -k components/skipta/k8s/base -n skipta`
Expected: all resources created/unchanged. If the guard balks at the cluster-scoped Namespace object inside the kustomization, remove `namespace.yaml` from `resources:` (the namespace already exists from Step 3) and re-apply.

- [ ] **Step 5: Watch the rollout (reads are guard-free)**

Run: `ws k8s rollout status deployment/skipta -n skipta`
Expected: `successfully rolled out`. If ImagePullBackOff: the ghcr package is still private (Task 13 Step 6). If CrashLoopBackOff: `ws k8s logs deploy/skipta -n skipta` — most likely a Workload Identity annotation/binding mismatch (compare Task 3 Step 4's member string).

- [ ] **Step 6: Verify Workload Identity from inside the pod**

Run: `ws k8s exec deploy/skipta -n skipta -- python -c "import google.auth; c,_ = google.auth.default(); print(type(c).__name__)"`
Expected: a Compute-engine-style credential class, no exception.

- [ ] **Step 7: Verify the route**

Run: `curl -s https://skipta.cmdbee.org/healthz`
Expected: `{"status":"healthy"}` with a valid `*.cmdbee.org` certificate.

- [ ] **Step 8: Commit + merge via the open CR flow** — bodyfile `.commits/skipta-k8s.md` (message `feat: k8s base — WI service account, deployment, HTTPRoute at skipta.cmdbee.org`, add: `k8s/base/`), `ws commit skipta .commits/skipta-k8s.md`, `ws push skipta` (rides the same CR if still open, else a small follow-up CR).

### Task 15: End-to-end smoke + docs close-out

**Files:**
- Modify: `components/skipta/README.md` (add the live smoke section)

- [ ] **Step 1: Live end-to-end** — from a phone or this machine:

1. Open `https://skipta.cmdbee.org/`, dictate/type: "Smith wants to upgrade to a 200 amp panel and add three 20 amp single pole breakers".
2. Expect the signing link; open it, verify the itemized table matches the Sheet pricing (245.00 + 3×7.50 = 267.50 with the seed data).
3. Sign both canvases, Enact.
4. Verify: PDF appears in the `Skipta/Smith/` Drive folder with both signatures; the `Amendments` row flips to `signed` with the Drive URL; re-signing the same amendment returns 409.
5. Negative check: dictate a part not in the sheet ("add a 70 amp three pole breaker") → signing page shows UNMATCHED and the Enact button is absent.

- [ ] **Step 2: Record results in the README** — append a short "Verified" line with date + the demo transcript used (current-state phrasing only).

- [ ] **Step 3: Commit** — bodyfile `.commits/skipta-smoke.md` (message `docs: record live e2e verification`, add: `README.md`), `ws commit skipta .commits/skipta-smoke.md`, `ws push skipta`.

- [ ] **Step 4: Workspace close-out** — confirm the realm CR (Task 2) merged and remove the temporary `skipta:` block from `ecosystem.local.yaml`; confirm the yggdrasil docs CR (design + this plan) merged; update the Thalamus arc for skipta with the shipped state.

---

## Self-review notes

- Spec coverage: every spec section maps to a task — API surface (11–12), extraction schema + anti-hallucination (5–6), Sheets state machine (7), Drive (8), PDF (9), signing UI (10), auth/WI (3, 14), kustomize/HTTPRoute (14), CI/ghcr (13), realm/adapter (2), error table (11–12 tests: 404/409/422/502), testing strategy (fakes throughout, PDF real in CI), deferred items untouched (YAGNI).
- Known judgment calls encoded above: slowapi callable-limit fallback (Task 11 note), WeasyPrint Windows skip (Task 9), guard-vs-Namespace-object fallback (Task 14 Step 4), ghcr package visibility (Task 13 Step 6), missing-customer-folder → root-folder fallback (Task 12 test).
