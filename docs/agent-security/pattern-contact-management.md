# Pattern: Contact Management via Obsidian

> Part of the [AI Agent Security Patterns](../../ai-agent-security-patterns.md) guide.

Obsidian is the source of truth for personal contacts. The agent that reads your vault
has no internet access. The agent that syncs to Google Contacts has no access to your vault.
A structured staging file (`contacts-staging.json`) is the only crossing point.

**Key machines:** M1 MacBook Pro (personal vault, Agent 1), Intel MacBook Pro (sync, Agent 2)

## Your Obsidian Vault Setup

| Vault | Location | Contains | Agent Access | Network |
|-------|----------|---------|-------------|---------|
| **Personal** | M1 Mac `~/obsidian/personal/` | Contacts, finances, health, journals | Agent 1: R-local only | Never |
| **Staging** | Intel Mac `~/obsidian/staging/` | Structured JSON extracts, contact data, task exports | Agent 2: R-local (staging only) | Yes (for sync) |

The Personal vault is never accessible from the Intel Mac. The Staging vault contains
only structured data that has been explicitly extracted — no raw notes, no free-text.

Agent 1 (M1 Mac, no internet) extracts structured contact fields from Personal vault notes
and writes `contacts-staging.json` to the Staging vault location. Agent 2 (Intel Mac,
no access to Personal vault) reads only that JSON file and pushes to Google Contacts.

## The Two-Agent Pipeline

```mermaid
flowchart LR
    subgraph "M1 Mac — Personal Zone"
        vault["Personal vault<br>(Obsidian)"]
        agent1["Agent 1<br>R-local + W-local<br>no internet"]
        vault --> agent1
    end
    staging["contacts-staging.json<br>(shared location)"]
    agent1 -->|"structured extract"| staging
    subgraph "Intel Mac — Research Zone"
        agent2["Agent 2<br>R-external + W-external<br>no R-local to personal vault"]
        contacts["Google Contacts"]
        staging --> agent2
        agent2 -->|"Google Contacts API"| contacts
    end
    human["Human review<br>(optional gate)"]
    staging -.->|"optional"| human
    human -.->|"approve"| agent2
```

**Agent 1** (has: `R-local` + `W-local`, lacks: `R-external`, `W-external`):
- Reads Obsidian vault for new/updated contact notes
- Extracts structured data (name, email, phone, company)
- Writes to `contacts-staging.json`
- Cannot exfiltrate because it has no internet access

**Agent 2** (has: `R-external` + `W-external`, lacks: `R-local` to sensitive files):
- Reads ONLY `contacts-staging.json` (not the full Obsidian vault)
- Pushes contacts to Google Contacts API
- Cannot steal sensitive data because it never sees it

## Cross-Machine Flow

```mermaid
flowchart LR
    web["Web clipper"] -->|"saves contact"| personal["Personal vault<br>(M1 Mac)"]
    personal -->|"local agent extracts"| staging["Staging vault<br>(structured data only)"]
    staging -->|"sync agent pushes"| google["Google Contacts<br>Google Calendar"]
    personal -.->|"human reviews"| staging
```

## Why the Boundary Holds

The staging area contains only structured, extracted fields — name, email, phone, company —
never the raw Obsidian note that might include personal context ("met at funeral", "owes me
money", "avoid on Tuesdays"). Even if Agent 2 were compromised, the attacker gets contact
metadata, not your personal notes.

The Personal vault agent (Agent 1) has no path to send data anywhere. It can only write to
`contacts-staging.json`. An attacker who injects into Agent 1 via a malicious contact note
can write arbitrary JSON to the staging file — but cannot reach any external system.
