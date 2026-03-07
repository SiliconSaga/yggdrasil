# The Project Constellation: Yggdrasil

This document is the narrative companion to
[`docs/ecosystem-architecture.md`](docs/ecosystem-architecture.md). It describes **what
each project is and why it exists**. For deployment tiers, bootstrap layers, and how
things wire together, see the ecosystem architecture doc.

Long-term these groupings may become Backstage Systems (with individual elements as
Components and Yggdrasil defining the Domain), and could be visualized via a Tech Radar
or Vordu BOM view.

---

## The Root: Yggdrasil (Workspace)

*   **Project**: **Yggdrasil**
*   **Location**: `d:/Dev/GitWS/yggdrasil`
*   **Purpose**: The "World Tree". Container for the VS Code Mega-Workspace.
*   **Role**: Holds workspace configuration, agent skills, top-level workflows, and this
    constellation map.

## The Foundation: Nordri (Infrastructure)

Nordri is the bootstrapper dwarf that holds up the sky.

*   **Project**: **Nordri**
*   **Location**: `d:/Dev/GitWS/nordri`
*   **Tech Stack**: K3s (Kubernetes), Crossplane, Longhorn (PVs), Garage (object storage),
    Velero (backups), Traefik (gateway).
    *   Future: Tailscale / Headscale with custom DERPs.
*   **Purpose**: The "Substrate". A resilient, self-hosted cloud-in-a-box / customized
    public cloud.
*   **Role**: Tier 1. Installs Crossplane, Traefik, and object storage, preparing the
    field for Nidavellir.

## The Rememberer: Mimir (Data Management)

*   **Project**: **Mimir**
*   **Location**: `d:/Dev/GitWS/mimir`
*   **Tech Stack**: Percona (PostgreSQL, MySQL, MongoDB), Strimzi (Kafka), OT-Container-Kit
    (Valkey). All vended via Crossplane Compositions.
*   **Purpose**: The "Memory". Mimir the wise one keeps the Well of Knowledge, built atop
    Nordri's foundation.
*   **Role**: Tier 2 component. Supports platform and application teams with self-service
    databases, event streaming, and caching.

## The Watcher: Heimdall (Observability)

*   **Project**: **Heimdall**
*   **Location**: `d:/Dev/GitWS/heimdall`
*   **Tech Stack**: kube-prometheus-stack, Grafana, Loki, Tempo, Thanos (long-term metric
    storage; not Grafana Mimir).
*   **Purpose**: The "Vigilant Guardian". Metrics, logs, traces, alerts, dashboards.
*   **Role**: Tier 2 component. Builds on Nordri (Crossplane + Garage/GCS). No hard
    dependency on Mimir.

## The Forge: Nidavellir (Platform Layer)

Nidavellir is the app-of-apps that ties platform components together.

*   **Project**: **Nidavellir**
*   **Location**: `d:/Dev/GitWS/nidavellir`
*   **Components**:
    *   **Vegvisir** (Traefik + Custom Operator): The "Traffic Cop". Standardizes
        Gateway routing across GKE and Homelab.
    *   **Keycloak**: Identity provider (The "Passport"). Consumes Crossplane Postgres
        via Mimir.
    *   **OpenBAO**: Secrets management.
*   **Purpose**: The "Star Forge" — the developer platform foundation.
*   **Role**: Tier 2 orchestrator. Deploys Mimir, Heimdall, Keycloak, and other platform
    components via ArgoCD sync waves. Also bootstraps Tier 3 (Demicracy).

## The Constitution: Demicracy (Governance, Collaboration & Exploration)

*   **Project**: **Demicracy**
*   **Location**: `d:/Dev/GitWS/demicracy`
*   **Tech Stack**: Backstage (developer portal), static site generator, GitHub Pages.
*   **Purpose**: The "Law". Design docs, roadmaps, philosophy, and community tooling.
*   **Status**: Active Review & Roadmap Phase.
*   **Public Face**: `demicracy.github.io` (Static Site).

## The Messengers: Uplifted Mascot, Autoboros, and Knarr

*   **Project**: **Uplifted Mascot (UM)**
    *   **Location**: `d:/Dev/GitWS/uplifted-mascot`
    *   **Tech**: RAG (ChromaDB), Python, Docker.
    *   **Role**: The "Librarian" (Bill/Gooey). Ingests Demicracy docs to answer user
        questions.
*   **Project**: **Autoboros**
    *   **Location**: `d:/Dev/GitWS/autoboros`
    *   **Tech**: Python, Django, Discord API, NATS (may migrate to Kafka).
    *   **Role**: The "Doer". ChatOps bot that creates PRs. Autoboros is the "Hands",
        UM is the "Brain".

Knarr is the primary viking merchant ship for open ocean trade — and coincidentally a
[board/card game](https://boardgamegeek.com/boardgame/379629/knarr) with a perfect
mechanics mix (recruit agents, send them off to explore and trade). Planned as the
integration/bridging layer, potentially incorporating OpenClaw for agentic work.

## The Map: Vordu (Roadmap Visualization)

*   **Project**: **Vordu**
    *   **Location**: `d:/Dev/GitWS/vordu`
    *   **Tech**: Node.js (Web App).
    *   **Purpose**: A "Cairn" or Landmark.
    *   **Role**: Visualizes the Matrixed Roadmap dynamically.

## The Public Faces (Static Sites)

*   **Front State**: `frontstate.github.io` — The Philosophy (Civics).
*   **Demicracy**: `demicracy.github.io` — The Platform (Tech).
*   **Cervator**: `Cervator.github.io` — The Personal Blog.

## Tafl: Game Hosting

*   **Project**: **Tafl**
    *   **Location**: `d:/Dev/GitWS/tafl`
    *   **Tech**: Agones (K8s), Django (Orchestrator).
    *   **Role**: The "Game Board". Manages the lifecycle of game servers.
    *   **Architecture**:
        *   **ArgoCD**: Deploys the Agones Controller (Platform Layer).
        *   **Tafl API**: Instructs Agones to spawn servers (Application Layer).
        *   **Vegvisir**: Routes traffic to the game servers.
        *   **Crossplane**: Connects the servers to S3 buckets for world data.

## The Metaverse: Bifrost (Game Bridging)

*   **Project**: **Bifrost**
    *   **Location**: `d:/Dev/GitWS/bifrost`
    *   **Tech**: Java (Terasology), Agones, WebSocket.
    *   **Purpose**: A federated game metaverse connecting engines.
    *   **Role**: A primary "Use Case" for the Demicracy platform.

---

## Issue Tracking Strategy

As the project moves toward community collaboration, informal TODOs in code and docs
need a home that's discoverable and shareable.

### Chosen direction: Gitea Issues -> GitHub Issues -> GitHub Projects

**Gitea Issues** (in-platform, internal staging)
- Platform users who don't want GitHub dependency can file and track issues entirely
  within the embedded Gitea instance.
- `tea` CLI (Gitea's official CLI, parallel to `gh`) makes this scriptable and AI-usable.
- Issues start here and get promoted to GitHub when ready to be community-facing.

**Sync mechanism: Gitea Actions -> GitHub API**
- Gitea 1.19+ ships GitHub Actions-compatible workflow syntax.
- A Gitea Action fires on issue creation / label trigger (e.g. label: `public`) and
  calls the GitHub API to mirror the issue there. No external tool needed.
- Autoboros or Knarr could own this sync logic as a natural extension of their
  ChatOps/integration role.

**GitHub Issues + Projects v2** (community-facing, visualization)
- Community interaction happens on GitHub where contributors already are.
- GitHub Projects v2 is the visualization/prioritization layer.
- `gh` CLI for scripting and AI-assisted issue management on the GitHub side.
- A GitHub Action scanning `# TODO:` comments in code to auto-file issues bridges
  the code-to-tracker gap.

**Not pursuing:**
- Linear: commercial, vendor lock-in, contradicts self-hosted ethos.
- Plane.so: open-core with proprietary cloud tier, adds a new component for a problem
  already solvable with what's in the stack.

---

## The "Grand Unification" Workflow

1.  **Design Phase** (Demicracy): You write a "Feature" in Gherkin/Markdown.
    *   *Example*: `Feature: Fence Permit`
2.  **Intelligence Phase** (UM): **Uplifted Mascot** ingests this doc.
3.  **Execution Phase** (Autoboros): You tell **Autoboros** (via Discord/Matrix): "I need a fence permit."
    *   Autoboros queries UM: "What are the rules?"
    *   Autoboros checks **Nidavellir**: "Is this user verified in Keycloak?"
    *   Autoboros creates a PR in the **Governance Repo**.
