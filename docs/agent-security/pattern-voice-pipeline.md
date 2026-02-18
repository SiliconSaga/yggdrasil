# Pattern: Voice-to-Action Pipeline

> Part of the [AI Agent Security Patterns](../../ai-agent-security-patterns.md) guide.

Speak into the Element app on your Android phone. The message goes E2E-encrypted to your
Matrix server on Thelio. The Matrix bot forwards it to OpenClaw on the M1 Mac. A local
Whisper instance transcribes it. The transcript is classified by intent, and a staging
entry is written to the appropriate queue. You review and approve.

**Key machines:** Android phone → Thelio (Matrix server) → M1 MacBook Pro (transcription + classify)

## End-to-End Flow

```mermaid
sequenceDiagram
    participant Phone as Android (Element)
    participant Thelio as Matrix Server (Thelio)
    participant M1 as M1 Mac (OpenClaw)
    participant Whisper as Local Whisper
    participant Stage as Staging Area

    Phone->>Thelio: Voice message (E2E encrypted)
    Note over Phone,Thelio: Neither Thelio nor anyone else<br>can read message content
    Thelio->>M1: Decrypted on M1 (E2E endpoint)
    M1->>Whisper: Audio → text (local, no internet)
    Whisper->>M1: Transcript
    M1->>M1: Classify intent<br>(calendar / email / contact / task)
    M1->>Stage: Write to appropriate staging queue
    Stage->>M1: Confirmation message back to Matrix
    M1->>Thelio: "Proposed: dentist Thu 3pm. Approve?"
    Thelio->>Phone: Notification
```

## Intent Classification and Staging

```mermaid
flowchart TB
    phone["Phone<br>(Element app)"] -->|"voice message"| matrix["Matrix server<br>(Thelio)"]
    matrix --> transcribe["Transcribe<br>(local Whisper)"]
    transcribe --> classify["Classify intent"]
    classify -->|"calendar"| cal_stage["Proposals<br>calendar"]
    classify -->|"email"| email_stage["Draft queue<br>(Gmail compose)"]
    classify -->|"contact"| contact_stage["contacts-staging.json"]
    classify -->|"task"| task_stage["Obsidian inbox"]
    classify -->|"infra"| git_stage["Git branch + PR"]
    classify -->|"reply"| matrix_reply["Confirmation<br>back to Matrix"]

    cal_stage & email_stage & contact_stage & task_stage & git_stage --> approve["Human reviews<br>+ approves"]
    approve --> executor["Privileged<br>executor"]
```

## Transcription in Your Setup

You have local Whisper available on the M1 Mac (Apple Silicon runs it efficiently).
Use local Whisper for all Matrix voice input — the content is sensitive (personal plans,
health, scheduling) and should not leave your infrastructure.

For the Intel Mac / Discord bot: cloud transcription is acceptable since that channel
carries only community/research content with no sensitive data.

| Method | Privacy | Latency | Use for |
|--------|---------|---------|---------|
| Local Whisper (M1 Mac) | High — audio never leaves device | Slightly higher | Matrix: personal/sensitive voice |
| Cloud API (OpenAI, Google) | Lower — audio sent to internet | Lower | Discord: community/public voice |

## Why Matrix over WhatsApp/Discord for Sensitive Input

- **Self-hosted**: Messages stay on your infrastructure (Thelio)
- **E2E encrypted**: Even the server admin can't read messages
- **Bot-friendly**: Well-documented bot SDK, no Terms of Service risk
- **Bridgeable**: Can bridge to other platforms if needed
- **No vendor lock-in**: Standards-based protocol (unlike proprietary APIs)

Using Discord for sensitive voice input would expose content to Discord's servers and
create a dependency on their platform availability and policies.
