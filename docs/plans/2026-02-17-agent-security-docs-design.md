# Design: AI Agent Security Patterns Documentation Restructure

**Date:** 2026-02-17
**Status:** Approved

## Problem

`ai-agent-security-patterns.md` has grown into a single large file covering principles,
capability bounding, and six distinct use-case patterns. It's hard to navigate and there
is no place to put OpenClaw-specific guidance or system-specific context.

## Goals

1. Keep `ai-agent-security-patterns.md` at the Yggdrasil root as a focused overview
   (principles + your hardware inventory + capability mode table + links to deep dives)
2. Move each pattern into its own doc in `docs/agent-security/`
3. Add a dedicated OpenClaw security doc
4. Apply Mermaid standards throughout:
   - `<br>` for all newlines in node/edge labels — never `\n`
   - No `fill:#` colors in `style` declarations (transparent backgrounds)
5. Leave room for future `docs/` subdirs for other Yggdrasil topics
   (skills conventions, homelab agent patterns, etc.)

## Final File Structure

```
yggdrasil/
├── ai-agent-security-patterns.md   # Overview: principles + inventory + links
└── docs/
    ├── plans/                       # Design/plan docs (this file lives here)
    └── agent-security/
        ├── pattern-gitops-staging.md
        ├── pattern-calendar.md
        ├── pattern-email.md
        ├── pattern-contact-management.md
        ├── pattern-voice-pipeline.md
        ├── pattern-chat-segmentation.md
        └── openclaw-security.md
```

## Overview Doc (`ai-agent-security-patterns.md`) — Content Outline

- **The Problem** (2–3 sentences, stays brief)
- **Core Principle: The Staging Queue** (with Mermaid flowchart)
- **Core Principle: Capability Bounding**
  - Five capabilities table
  - Risk matrix
  - Why R-local + W-external is critical
- **Your System Inventory** *(new)*
  - Thelio Linux (System76): homelab base — k8s native, NextCloud, Matrix server
  - M1 MacBook Pro: personal/sensitive — OpenClaw (limited), Obsidian personal vault,
    Gmail, contacts; Android voice input via Matrix
  - Intel MacBook Pro: research/community — OpenClaw (moderate), Obsidian staging vault,
    Discord community; less sensitive data
  - Win11: minimal setup, TBD purpose
  - Win10: legacy/messy — sensitive data scattered; migration priority target
  - Android phone: Matrix E2E voice client → processed on M1 Mac
  - Capability mode table updated with these machines
- **Pattern Index** — brief description + link to each `docs/agent-security/` doc
- **Implementation Priority** (updated with homelab column)

## Use-Case Doc Content Outlines

### `pattern-gitops-staging.md`
- Existing GitOps + break-glass content
- Add: how this maps to Thelio homelab (ArgoCD on k3s)
- 2 Mermaid diagrams: GitOps flow + break-glass flow (already exist, fix standards)

### `pattern-calendar.md`
- Existing Calendar Management content
- Add: how M1 Mac / Matrix bot orchestrates this
- 2 Mermaid diagrams: sequence diagram + component overview

### `pattern-email.md`
- Existing Email Drafting content (Options A/B/C)
- Expand: Gmail `gmail.compose` scope as the recommended default
  - Bot creates drafts visible in Gmail UI; human clicks Send
  - Scope grants: compose only, never send
  - Danger zone: never grant this scope in a session that also has R-local
- Expand: Google Sheet fallback (Option A) for maximum safety
- 2 Mermaid diagrams: compose flow + Google Sheet flow

### `pattern-contact-management.md`
- Existing Contact Management content
- Expand: Obsidian as the source of truth for contacts
  - Personal vault (M1 Mac, no internet) — where contacts are written by hand or web clipper
  - Extract to staging vault → sync to Google Contacts
  - Agent 1 (local, no internet): reads personal vault, writes contacts-staging.json
  - Agent 2 (no local files): reads staging only, pushes to Google Contacts API
- 2 Mermaid diagrams: vault segmentation + sync pipeline

### `pattern-voice-pipeline.md`
- Existing Voice-to-Action content
- Expand: Android → Matrix (E2E) → M1 Mac → local Whisper → classify → stage
- Add: latency vs. privacy trade-off table (local Whisper vs cloud API)
- 2 Mermaid diagrams: full pipeline + per-intent staging paths

### `pattern-chat-segmentation.md`
- Existing Matrix vs Discord content
- Expand: Matrix on homelab (Thelio) with E2E → sensitive personal use
- Expand: Discord on Intel Mac → community/research, less sensitive
- Add: Skill token optimization section (already exists, keep)
- 2 Mermaid diagrams: Matrix private flow + Discord community flow

## New Doc: `openclaw-security.md`

### Sections
- **What OpenClaw Is**
  - Open-source personal AI agent (formerly Clawdbot/Moltbot)
  - Runs locally, uses messaging platforms as UI
  - 50+ integrations, 145K+ GitHub stars (Feb 2026)
  - Extremely new — not in model training data at cutoff

- **Why It's a High Risk Platform**
  - Skill/plugin supply chain: Snyk found 13% of ClawHub skills have critical flaws;
    28 malicious skills appeared in a 3-day window (Jan 27–29 2026)
  - Prompt injection: incoming messages can hijack tool use; if agent has R-local,
    a malicious chat message can exfiltrate credentials
  - 512 vulnerabilities found in Jan 2026 audit, 8 critical
  - **Default rule: Do NOT install skills unless you have read the source and trust the author**

- **Safe Configuration: M1 Mac (Personal/Sensitive Instance)**
  - Capabilities: R-local (Obsidian personal vault only) + W-local (staging area)
  - Lacks: R-external, W-external, Secrets
  - Integrations: local Obsidian, local Whisper (if used), Gmail compose-only
  - No skills installed from ClawHub
  - Network: ideally no outbound except to LLM API endpoint (allowlist)
  - Use for: personal planning, Obsidian notes, email drafting, contact extraction

- **Safe Configuration: Intel Mac (Research/Community Instance)**
  - Capabilities: R-external + W-local + W-external (public only)
  - Lacks: R-local (no sensitive files accessible to this instance)
  - Integrations: web search, Discord, public GitHub
  - Skills: only from personally vetted, source-reviewed list
  - Use for: research, community support, OSS project work

- **Obsidian Staging Area Pattern (cross-machine)**
  - Personal vault on M1: write-only for the Intel Mac instance (no R-local)
  - Staging vault: structured extracts only, safe to share across instances
  - Intel Mac instance reads staging, never personal vault

- **What to Never Do**
  - Never grant both R-local and W-external to the same instance
  - Never install skills from ClawHub without source review
  - Never store secrets/API keys where the agent has R-local access
  - Never run OpenClaw on Win10 (messy, sensitive data everywhere)

- **Win10 Migration Priority**
  - Until Win10 is cleaned up, treat it as air-gapped for agent access
  - No OpenClaw installation on Win10
  - Data migration plan: move sensitive data to encrypted homelab (NextCloud on Thelio)

- Mermaid: M1 vs Intel Mac capability comparison diagram
- Mermaid: OpenClaw instance trust boundary diagram

## Mermaid Standards (to enforce across all docs)

```markdown
# CORRECT — transparent, <br> newlines
flowchart LR
    A["Agent reads<br>real state"] -->|read-only| B["Staging area"]
    style A color:#000

# WRONG — background color, \n newlines
flowchart LR
    A["Agent reads\nreal state"] -->|read-only| B["Staging area"]
    style A fill:#f9d0d0
```

- `<br>` inside quoted node labels for line breaks
- No `fill:` property in any `style` declaration
- Prefer quoted labels (`["text"]`) over unquoted for safety with special chars
- Direction: `LR` for pipelines, `TB` for hierarchies, `sequenceDiagram` for step-by-step

## Implementation Notes

- Existing content in `ai-agent-security-patterns.md` is the source; extract and expand,
  do not start from scratch
- Each use-case doc should stand alone (brief intro + context, not "see overview")
- Cross-link: overview links to each doc, each doc links back to overview
- Git: one commit per doc (or batch by section) on `claudefix` branch
