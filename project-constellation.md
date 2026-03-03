# The Project Constellation: Yggdrasil

This document serves as an initial overview of projects, workspaces, and machines. Yggdrasil is a container more than a foundation. Workflow guidance here.

It could be reworked later via the Tech Radar in Backstage? To see when Pulp might be a viable alternative to Nexus/Artifactory, for instance.

If the constellation is set up as a BOM it may make sense to define each section in the abstract, then let users bring their own stack variants.

* Infra
* Data
* Observability
* Dev Tools
* etc

The goal would be to define an API but leave implementation details to the local admins. Vordu could visualize different pieces including bits with overlap. Different communities could show via Vordu how their BOM varies and is progressing.

The groupings could become Backstage Systems while their individual elements become Components. Yggdrasil could define the Domain. If desired the System repos could solely hold the catalog details and overarching docs for that System then Component repos could use nested Git a la Terasology - if they should be split out from the System repo. The whole workspace would effectively represent the Backstage Domain, anchored on Yggdrasil.

## The Root: Yggdrasil (Workspace)

Yggdrasil contains the root workspace config and some documents. Should Parent Driven Development (PDD) live here or be part of Vordu?

*   **Project**: **Yggdrasil**
*   **Location**: `d:/Dev/GitWS/yggdrasil`
*   **Purpose**: The "World Tree". The container for the VS Code Mega-Workspace.
*   **Role**: Holds the workspace configuration, top-level workflows, and this constellation map. Maybe a BOM.

## The Foundation: Norðri (Infrastructure)

Norðri is the bootstrapper dwarf that holds up the sky. This is achieved through the first 4 layers of the overall stack.

*   **Project**: **Norðri**
*   **Location**: `d:/Dev/GitWS/nordri`
*   **Tech Stack**: K3s (Kubernetes), Crossplane (platform), Longhorn (PVs), Garage (object storage), Velero (backups)
        * Later also: Tailscale / Headscale with custom DERPs collocated with similar decentralized elements (RAID nodes, relays, etc)
*   **Purpose**: The "Substrate". A resilient, self-hosted cloud-in-a-box / customized public cloud ready to become more.
*   **Layers 1-4 (Infrastructure)**: Nordri covers the stack from Metal (L1) -> Gitea (L2) -> Argo (L3) -> Fundamentals (L4).
    *   *Note*: This means Nordri installs Crossplane and Traefik, preparing the field for Nidavellir.

## The Rememberer: Mimir (Data Management)

*   **Project**: **Mimir**
*   **Location**: `d:/Dev/GitWS/mimir`
*   **Tech Stack**: Percona (DBs), Kafka (event bus), Valkey (cache)
*   **Purpose**: The "Memory" grouping. Mimir the wise one keeps the Well of Knowledge, built atop Nordri's foundation
        * Mainly Percona with simple Operator installs for Kafka and Valkey (Redis)
*   **Role**: Builds on *Norðri*, supports platform apps. Can offer Kafka topics and Redis support.

## The Watcher: Heimdall (Observability)

*   **Project**: **Heimdall**
*   **Location**: `d:/Dev/GitWS/heimdall`
*   **Tech Stack**: kube-prometheus-stack, Grafana, Loki, Tempo, Thanos (long-term metric storage; not Grafana Mimir)
*   **Purpose**: Keep tabs on things, host alerts, dashboards, etc.
*   **Role**: Builds on *Norðri*, watches everything. No hard dependency on Mimir.

## The Forge: Nidavellir (Developer Tools, Identity & Organizing)

The platform services layer - the foundation other things are built on easily without having to deal with the underlying infrastructure.

Nordri handles the differences between homelab and GKE, which may even become federated to some degree.

*   **Project**: **Nidavellir**
*   **Location**: `d:/Dev/GitWS/nidavellir`
*   **Tech Stack**:
    *   **Vegvísir** (Traefik + Custom Operator): The "Traffic Cop".
        *   Standardizes Ingress/Gateway across GKE and Homelab.
        *   Operator ensures Crossplane-provisioned GameServer routes are safely attached to the shared Gateway.
        *   Note that Traefik may come automatically with k3s (possibly need a gateway config tweak) yet need manual install in GKE. After that then Vegvisir should work the same in both cases.
    *   **Keycloak**: Identity provider (The "Passport"). Deployed by Argo, consumes Crossplane Postgres.
    *   **OpenBAO**: Secrets storage (plus custom Python for local scaffolding)
    *   **Wekan**: Kanban/Project management. Might be an option but doesn't feel super prioritized anymore with all the other solid / core platform bits.
        * Or actually - Vordu? For BDD organizing new projects
    *   Registries (Harbor is solid but no Java, Pulp is interesting but not super ready for Java, Nexus/Artifactory are solid but iffy)
        * It might well be Nexus with a reverse proxy workaround for Keycloak SSO (then reuse that for other tools)
    *   Other development supporting tools
    *   Microservice integrations (like the reverse proxy bit - maybe also simple integrations with Wekan etc)
    *   Jenkins and so on
*   **Purpose**: The "Star Forge" to help you build things
*   **Role**: Consumes *Norðri* and Mimir, hosts platform apps

## The Constitution: Demicracy (Governance, Collaboration, & Exploration)

*   **Project**: **Demicracy**
*   **Location**: `d:/Dev/GitWS/demicracy`
*   **Tech Stack**: Backstage, Markdown, Static Site Generator (Hugo/Docusaurus?), GitHub Pages. NextCloud & friends? Later activity federation?
*   **Purpose**: The "Law". Design docs, roadmaps, and philosophy.
*   **Status**: Active Review & Roadmap Phase.
*   **Public Face**: `demicracy.github.io` (Static Site). Demicracy instances.

## The Messengers: Uplifted Mascot, Autoboros, and Knarr

*   Includes basic chat bridging but _not_ activity federation? That's a more advanced topic on decentralization and so on.
*   **Project**: **Uplifted Mascot (UM)**
    *   **Location**: `d:/Dev/GitWS/uplifted-mascot`
    *   **Sub-projects**: `sample-md` (Test Data).
    *   **Tech**: RAG (ChromaDB), Python, Docker.
    *   **Role**: The "Librarian" (Bill/Gooey). Ingests *Demicracy Docs* to answer user questions.
*   **Project**: **Autoboros**
    *   **Location**: `d:/Dev/GitWS/autoboros`
    *   **Tech**: Python, Django, Discord API, NATS (maybe replace with Kafka)
    *   **Role**: The "Doer". ChatOps bot that creates PRs.
    *   **Synergy**: Autoboros is the "Hands", UM is the "Brain".

"Knarr" is a late addition and the primary viking merchant ship for open ocean trade _and_ coincidentally a [board/card game](https://boardgamegeek.com/boardgame/379629/knarr) with a perfect mechanics mix - you recruit vikings (agents) and send them off to explore and trade (integrations). Works to really organize the overall message connections, and this area needed a good viking term, UM doesn't really fit and Autoboros is made up and more latin. Design plan in progress via Claude on the new Mac. Would be about adding something like OpenClaw for bridging agentic work in various ways, safely.

## The Map: Vörðu (Roadmap Visualization)

*   **Project**: **Vörðu**
    *   **Location**: `d:/Dev/GitWS/vordu`
    *   **Tech**: Node.js (Web App).
    *   **Purpose**: A "Cairn" or Landmark.
    *   **Role**: Visualizes the *Matrixed Roadmap* dynamically.

## The Public Faces (Static Sites)

*   **Front State**: `frontstate.github.io` - The Philosophy (Civics).
*   **Demicracy**: `demicracy.github.io` - The Platform (Tech).
*   **Cervator**: `Cervator.github.io` - The Personal Blog.

## Tafl: Game Hosting

*   **Project**: **Tafl**
    *   **Location**: `d:/Dev/GitWS/tafl`
    *   **Tech**: Agones (K8s), Django (Orchestrator).
    *   **Role**: The "Game Board". Manages the lifecycle of game servers.
    *   **Architecture**:
        *   **ArgoCD**: Deploys the Agones Controller (Platform Layer).
        *   **Tafl API**: Instructs Agones to spawn servers (Application Layer).
        *   **Vegvísir**: Routes traffic to the game servers.
        *   **Crossplane**: Connects the servers to S3 buckets for world data.

## The Metaverse: Bifrost (Game Bridging)

Advanced API for bridging games together.

*   **Project**: **Bifrost**
    *   **Location**: `d:/Dev/GitWS/bifrost`
    *   **Tech**: Java (Terasology), Agones, WebSocket.
    *   **Purpose**: A federated game metaverse connecting engines.
    *   **Role**: A primary "Use Case" for the Demicracy platform.
    *   **Mascot**: Gooey (The face of the RAG system here).

---

## Issue Tracking Strategy (TODO)

As the project moves toward community collaboration, informal TODOs in code and docs
need a home that's discoverable and shareable.

### Chosen direction: Gitea Issues → GitHub Issues → GitHub Projects

These should also result in some AI skills - going from usual Markdown write-ups to instead using the CLIs to submit well-structured issues.

**Gitea Issues** (in-platform, internal staging)
- Platform users who don't want GitHub dependency can file and track issues entirely
  within the embedded Gitea instance.
- `tea` CLI (Gitea's official CLI, parallel to `gh`) makes this scriptable and AI-usable.
- Issues start here and get promoted to GitHub when ready to be community-facing.

**Sync mechanism: Gitea Actions → GitHub API**
- Gitea 1.19+ ships GitHub Actions-compatible workflow syntax.
- A Gitea Action fires on issue creation / label trigger (e.g. label: `public`) and
  calls the GitHub API to mirror the issue there. No external tool needed.
- Autoboros or Knarr could own this sync logic as a natural extension of their
  ChatOps/integration role.

**GitHub Issues + Projects v2** (community-facing, visualization)
- Community interaction happens on GitHub where contributors already are.
- GitHub Projects v2 is the visualization/prioritization layer — genuinely good now.
- `gh` CLI for scripting and AI-assisted issue management on the GitHub side.
- A GitHub Action scanning `# TODO:` comments in code to auto-file issues bridges
  the code→tracker gap.

**Not pursuing:**
- Linear: commercial, vendor lock-in, contradicts self-hosted ethos.
- Plane.so: open-core with proprietary cloud tier (rug-pull risk), adds a new component
  for a problem already solvable with what's in the stack.
- Wekan: kanban-only, no GitHub sync, stagnant relative to alternatives.

---

## The "Grand Unification" Workflow

1.  **Design Phase** (Demicracy): You write a "Feature" in Gherkin/Markdown.
    *   *Example*: `Feature: Fence Permit`
2.  **Intelligence Phase** (UM): **Uplifted Mascot** ingests this doc.
3.  **Execution Phase** (Autoboros): You tell **Autoboros** (via Discord/Matrix): "I need a fence permit."
    *   Autoboros queries UM: "What are the rules?"
    *   Autoboros checks **Nidavellir**: "Is this user verified in Keycloak?"
    *   Autoboros creates a PR in the **Governance Repo**.

## Another Layer Perspective

An overview of what goes where to do what for who.

### Layer 1: The Substrate (Metal / Kubernetes)
*   **What**: The physical or virtual "Metal" + Raw K8s API.
*   **Components**: GKE Cluster or K3s Server.
*   **Action**: Provisioned via script (bootstrap.sh).

### Layer 2: The Seed (Gitea)
*   **What**: The local "Brain" of the cluster.
*   **Components**: Gitea (Helm).
*   **Action**: Hydrated with configuration by `bootstrap.sh`. Solves the Chicken/Egg problem for Argo.

### Layer 3: The Engine (ArgoCD)
*   **What**: The "Operating System" / Controller.
*   **Components**: ArgoCD.
*   **Action**: Installs itself, reads from Layer 2 (Seed), and deploys the rest.

### Layer 4: The Fundamentals (Cluster Plumbing)
*   **What**: Essential services required for any higher-level platform.
*   **Components**:
    *   **Traefik**: Ingress/Gateway.
    *   **Cert-Manager**: Identity/Sec.
    *   **Crossplane**: Infrastructure Vending.
    *   **Longhorn**: Storage (Homelab).

### Layer 5: The Platform Services (Nidavellir)
*   **What**: The capabilities provided to developers.
*   **Components**:
    *   **Mimir**: Data Services (DB flavors, Kafka, Valkey) - *Vended via Crossplane*.
    *   **Heimdall**: Observability.
    *   **Keycloak**: Identity.
    *   **Vegvísir**: Routing Operator.
    *   **Jenkins**: CI/CD.

### Layer 6: User Workloads (The Apps)
*   **What**: The business logic.
*   **Components**:
    *   **Tafl** + **Agones**: Game Hosting.
    *   **Demicracy** (Backstage): Interface.
    *   **User Apps**: Whatever else you build.
