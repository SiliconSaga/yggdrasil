# Skipta — AI-Backed Field Amendment & Signing Service (Design)

**Date:** 2026-07-01 · **Status:** approved design, pre-implementation · **Component:** `skipta` (new, Tier 3) · **Source idea:** `hoards/thalami-Cervator/FieldAmendmentsMVP.md`

Skipta ("shift/exchange" in Old Norse) turns a field technician's spoken change-order into a priced, dual-signed, archived PDF amendment. A tech dictates the change on their phone, Gemini extracts a strict parts payload, Google Sheets prices it, both parties sign on an HTML5 canvas page, and the flattened PDF lands in the customer's Google Drive folder.

This is a **working demo / GDD showcase**: realistic end-to-end on the live GKE cluster, sample data, light auth. It adapts the FieldAmendmentsMVP with two deliberate substitutions: Vertex AI Gemini structured output instead of the OpenAI/Anthropic APIs the MVP suggested (reusing the proven `uplifted-mascot` Vertex + Workload Identity patterns), and the platform's Traefik Gateway API ingress instead of bespoke nginx + certs.

## Goals

- Voice-text → structured amendment → priced line items → signed PDF in Drive, fully working at `https://skipta.cmdbee.org`.
- Zero stored credentials: Workload Identity on GKE, ADC impersonation locally, Drive/Sheets access via asset sharing.
- Stateless service — every durable fact lives in the Google Sheet or Drive.
- Full GDD citizenship: `SiliconSaga/skipta` repo, realm ecosystem entry, adapter wiring, TDD test suite.

## Non-goals (MVP)

- No RAG / vector store — the Drive step is a deterministic folder search, not semantic retrieval. `uplifted-mascot`'s ChromaDB side is intentionally not reused.
- No server-side voice transcription — the intake form relies on the phone keyboard's built-in dictation.
- No user auth on the API — demo-grade exposure with slowapi rate limiting; promoting to real field use is a separate design round.
- No ArgoCD application — direct `kubectl apply` (via the armed `ws k8s` guard) from the workspace.

## Architecture

One FastAPI (Python 3.11+) service, single Deployment in the `skipta` namespace:

```
[Tech phone] --POST /api/v1/amendments (voice text)--> FastAPI (skipta ns)
    ├── extraction.py — Gemini structured output (Vertex AI, Workload Identity)
    ├── pricing.py    — Sheets Panels/Breakers lookup + totals
    ├── amendments.py — append Amendments row (status=draft)
    ├── drive.py      — locate customer SoW subfolder
    └── returns {amendment_id, signing_url}
[Any phone]  --GET /amendments/{id}-->  server-rendered signing page (Jinja2 + signature_pad)
             --POST /api/v1/amendments/{id}/sign--> pdf.py (WeasyPrint) → Drive upload → row status=signed
```

### Modules

| Module | Purpose | Depends on |
|---|---|---|
| `app/main.py` | FastAPI app, routes, slowapi rate limiting | all below |
| `app/config.py` | env settings (`.env` locally, ConfigMap in k8s) | — |
| `app/extraction.py` | Gemini structured output → `AmendmentPayload` | Vertex AI |
| `app/pricing.py` | match payload items against `Panels`/`Breakers` tabs, compute totals | Sheets |
| `app/amendments.py` | amendment state rows in the `Amendments` tab (draft→signed) | Sheets |
| `app/drive.py` | customer SoW folder search, PDF upload | Drive |
| `app/pdf.py` | render amendment HTML (with signatures) → flattened PDF | WeasyPrint |

Google clients are constructed in one place and injected, so tests swap in fakes without patching.

### API surface

| Route | Behavior |
|---|---|
| `GET /` | Mobile intake form: customer name + voice-text area (phone dictation), posts to the API |
| `POST /api/v1/amendments` | Extract → price → persist draft row → return `{amendment_id, signing_url}` |
| `GET /amendments/{id}` | Server-rendered signing page: itemized parts, totals, two signature_pad canvases |
| `POST /api/v1/amendments/{id}/sign` | Accept both Base64 signatures, render PDF, upload to Drive, flip row to `signed` |
| `GET /healthz` | Probe target (ting convention) |

`amendment_id` is `amend_<slugified-customer>_<YYYYMMDDHHMMSS>` per the MVP naming convention. A small hand-rolled mobile-first stylesheet and `signature_pad.umd.js` are vendored under `app/static/` — no CDN dependency on a job site with weak signal, and no Node/Tailwind toolchain in the build (a deliberate simplification of the MVP's TailwindCSS suggestion).

## LLM extraction

The MVP's Pydantic schema is kept verbatim (`AmendmentPayload` with optional `PanelRequirement` and a list of `BreakerRequirement`). Vertex AI's structured output (`response_schema` + `response_mime_type="application/json"` on `GenerativeModel.generate_content`) enforces it at the API layer — no prompt-format parsing. Model selection reuses `uplifted-mascot`'s fallback chain starting at `gemini-2.5-flash`, with `MAX_OUTPUT_TOKENS`/`MAX_INPUT_TOKENS` cost caps from env.

Anti-hallucination is deterministic, not prompt-based: extraction only names amps/poles/quantities; `pricing.py` matches those against actual Sheet rows. A requirement with no matching row becomes an `UNMATCHED` line item — the draft persists, the signing page shows the gap, and the sign button stays disabled until a human fixes the sheet or the request.

## Data schema (the Google Sheet is the database)

One spreadsheet, three tabs. `Panels` and `Breakers` follow the MVP schema exactly:

- `Panels`: `panel_id`, `max_amperage`, `description`, `unit_cost`
- `Breakers`: `breaker_id`, `amps`, `poles`, `description`, `unit_cost`
- `Amendments` (state machine, one row per amendment): `amendment_id`, `created_at`, `customer_name`, `voice_text`, `extracted_json`, `line_items_json`, `total`, `status` (`draft` | `signed`), `pdf_drive_url`, `signed_at`

The signing page re-reads its row on every GET, so replicas and pod restarts are invisible. Drive layout: a `Skipta/` folder shared with the service account, one subfolder per customer holding their SoW doc; signed PDFs upload into that subfolder as `[Customer_Name]_Amendment_[Timestamp].pdf`.

## Google auth — no tokens, no keys

One service account, `skipta-gsa@teralivekubernetes.iam.gserviceaccount.com`:

- **Vertex AI:** `roles/aiplatform.user` on project `teralivekubernetes` (mirror of `um-vertex-ai-gsa`).
- **Drive/Sheets:** no IAM role — the human shares the `Skipta/` folder and the spreadsheet with the GSA email as Editor. `drive.googleapis.com` and `sheets.googleapis.com` get enabled on the project.
- **On GKE:** KSA `skipta-sa` in the `skipta` namespace, annotated `iam.gke.io/gcp-service-account=skipta-gsa@…`, with the `roles/iam.workloadIdentityUser` binding for `teralivekubernetes.svc.id.goog[skipta/skipta-sa]`. The workload pool is already enabled on `ttf-cluster`.
- **Locally:** `gcloud auth application-default login --impersonate-service-account=skipta-gsa@…` (requires `roles/iam.serviceAccountTokenCreator` on the GSA for the human) — dev runs as the same identity the pod uses.
- **In code:** `google.auth.default(scopes=[drive, spreadsheets, cloud-platform])`; the GKE Workload Identity metadata server honors requested scopes. Escape hatch if scope-narrowing misbehaves: self-impersonated credentials via the IAM Credentials API (`impersonated_credentials` targeting the same GSA with explicit Drive/Sheets scopes).

Config that reaches the pod is identifiers only (spreadsheet ID, Drive folder ID, project, region, model list) — a ConfigMap, no Secret.

**Documented caveat:** PDFs uploaded by the GSA are owned by it and count against the service account's own ~15 GB Drive quota. Acceptable for a demo; the promote-to-real path is a Workspace Shared Drive.

## Kubernetes deployment

ting-shaped kustomize base at `k8s/base/`: `namespace.yaml`, `serviceaccount.yaml` (the annotated KSA), `deployment.yaml` (1 replica, `serviceAccountName: skipta-sa`, `/healthz` readiness/liveness probes, requests 250m/512Mi limits 500m/1Gi — WeasyPrint is heavier than ting), `service.yaml` (ClusterIP 80→8000), `configmap.yaml`, `httproute.yaml`, `kustomization.yaml`.

Ingress is one `HTTPRoute` for `skipta.cmdbee.org` attached to `traefik-gateway` (`kube-system`) on `web` + `websecure`, exactly like ting. TLS is the platform wildcard `*.cmdbee.org` cert — per Vegvísir's rules, **no per-host Certificate and no ReferenceGrant**. Wildcard DNS already points at the Gateway LB, so no DNS work.

Deploys are `ws k8s apply -k k8s/base` from the workspace; the session k8s guard is armed to `context=gke_teralivekubernetes_us-east1-d_ttf-cluster, namespaces=skipta`, which allows creating and writing the `skipta` namespace and blocks anything else.

## Image build & CI

GitHub Actions on push to `main`: build the Dockerfile, push `ghcr.io/siliconsaga/skipta:latest` + `:<short-sha>`, using the default `GITHUB_TOKEN` with `packages: write` (ting's registry pattern). The Dockerfile is a plain `python:3.11-slim` base plus WeasyPrint's system libraries (pango, cairo, gdk-pixbuf) — not UM's Jenkins-oriented base image. CI also runs `pytest` and `ruff` before the build. Rollout after a push is manual for the MVP: `ws k8s rollout restart deployment/skipta`.

## Workspace integration

- **Repo:** new `SiliconSaga/skipta` on GitHub, cloned at `components/skipta`.
- **Ecosystem:** Tier 3 entry in `realms/realm-siliconsaga/ecosystem.yaml` (`namespace: skipta`), landed via a realm branch + `ws cr`.
- **Adapter:** `realms/realm-siliconsaga/adapters/skipta.yaml` wiring `ws test` → `python -m pytest` and `ws lint` → `ruff check .`.

## Error handling

| Failure | Response |
|---|---|
| Gemini extraction fails or returns schema-invalid output after fallback chain | `422` with a human-readable "couldn't parse the request" message |
| Extracted part has no pricing row | Draft saved with `UNMATCHED` line item; signing page renders the gap and disables signing |
| Sheets/Drive API error | `502` surfacing the upstream error honestly; no fake success |
| Sign posted on an already-`signed` amendment | `409` (state check on the Amendments row before rendering) |
| Unknown amendment id | `404` |
| Abuse | slowapi per-IP rate limits on the POST endpoints (UM pattern) |

## Testing

TDD (superpowers flow) with pytest. `pricing.py` matching/totaling and `amendments.py` row serialization are pure-unit. Routes run under FastAPI's `TestClient` with faked Sheets/Drive/Gemini clients injected — no network, no live LLM in CI. Extraction is tested against canned Gemini structured-output responses (valid, schema-violating, empty). PDF generation gets a smoke test: renders without error and the extracted text contains customer name and total. A thin manual smoke script (curl sequence from the MVP flow) documents the live-cluster check.

## Deferred / promote-to-real seams

- Auth on the intake + signing endpoints (signed URLs or OIDC) when real customers sign.
- Workspace Shared Drive for human-owned PDFs.
- Server-side transcription (upload audio → Speech-to-Text) if phone dictation proves insufficient.
- ArgoCD application + realm chart once the demo stabilizes.
