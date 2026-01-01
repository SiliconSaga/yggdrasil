# The Project Constellation: Yggdrasil
*A "Meta-Map" of the User's Ecosystem*

This document serves as the "Manual Backstage" to track the relationships between your distributed projects, workspaces, and machines.

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

A container more than a foundation. Workflow guidance here. Parent Driven Development? Here or as part of Vordu?

*   **Project**: **Yggdrasil**
*   **Location**: `d:/Dev/GitWS/yggdrasil`
*   **Purpose**: The "World Tree". The container for the VS Code Mega-Workspace.
*   **Role**: Holds the workspace configuration, top-level workflows, and this constellation map. Maybe a BOM.

## The Foundation: Norðri (Infrastructure)

TODO: Maybe rename to the southern dwarf as the home-lab only layer (block storage etc that turns basic k8s into basic private cloud - but no more?)

Then stuff that still needs to go in public cloud as well (like new k8s api gateway) can be Nordri - or is all that Nidavellir, which also gets installed into homelab?

*   **Project**: **Norðri** (formerly Fulcrum Infra)
*   **Location**: Macbook (Separate Workspace) / `d:/Dev/GitWS/nordri`
*   **Tech Stack**: K3s (Kubernetes), Crossplane (platform), Longhorn (PVs), Garage (object storage), Velero (backups)
        * Tailscale / Headscale with custom DERPs collocated with similar decentralized elements (RAID nodes, relays, etc)
*   **Purpose**: The "Substrate". A resilient, self-hosted cloud-in-a-box. Nordri is one of the dwarves holding up the sky.
*   **Layer 2 (Infra Services via Crossplane)**: Crossplane runs here to vend "As-a-Service" primitives (Databases, Buckets) to the upper layers.
    *   *Note*: The cluster itself (Layer 0) is bootstrapped manually/scripted, then ArgoCD (Layer 1) installs Crossplane.

## The Rememberer: Mimir (Data Management)

*   **Project**: **Mimir**
*   **Location**: `d:/Dev/GitWS/mimir`
*   **Tech Stack**: Percona (DBs), Kafka (event bus), Valkey (cache)
*   **Purpose**: The "Memory" grouping. Mimir the wise one keeps the Well of Knowledge, built atop Nordri's foundation
        * Mainly Percona with simple Operator installs for Kafka and Valkey (Redis)
*   **Role**: Consumes *Norðri*, supports *Demicracy Apps*. Can offer Kafka topics and Redis support.

## The Watcher: Heimdall (Observability)

*   **Project**: **Heimdall**
*   **Location**: `d:/Dev/GitWS/heimdall`
*   **Tech Stack**: Panoptes (Prometheus, Grafana, Loki, Tempo), Thanos for long term storage (not Grafana Mimir)
*   **Purpose**: Keep tabs on thing, host alerts, dashboards, etc.
*   **Role**: Consumes *Norðri* and Mimir, watches *Demicracy Apps* and everything else

## The Forge: Nidavellir (Developer Tools, Identity & Organizing)

The platform services layer - the foundation other things are built on easily without having to deal with the underlying infrastructure.

Likely same setup in homelab and on GKE, and indeed federated to some degree.

There may be some overlap between extras provided within k3s like Traefik, which would be installed standalone in GKE? Or skip it in k3s and favor Nidavellir's setup?

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
*   **Purpose**: The "Star Forge" to help you build things
*   **Role**: Consumes *Norðri* and Mimir, supports *Demicracy Apps*.

## The Constitution: Demicracy (Governance, Collaboration, & Exploration)

*   **Project**: **Demicracy**
*   **Location**: `d:/Dev/GitWS/demicracy`
*   **Tech Stack**: Backstage, Markdown, Static Site Generator (Hugo/Docusaurus?), GitHub Pages. NextCloud & friends? Later activity federation?
*   **Purpose**: The "Law". Design docs, roadmaps, and philosophy.
*   **Status**: Active Review & Roadmap Phase.
*   **Public Face**: `demicracy.github.io` (Static Site). Demicracy instances.

## The Messengers: Uplifted Mascot & Autoboros

*   Includes basic chat bridging but _not_ activity federation?
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

### Layer 0: The Substrate (Manual/Scripted)

* What: The physical or virtual "Metal."
* Components: Use a script to provision the base GKE cluster or the K3s node. This is the "Bootstrapping" phase. Once the Kubernetes API exists, everything else is automated.

### Layer 1: The Platform Foundation (ArgoCD)

* What: The "Operating System" of the cluster.
* Components: ArgoCD itself, Crossplane (the controller), Traefik (Ingress Controller), Agones (Controller), Cert-Manager.
* Why Argo?: These are complex, in-cluster software deployments with intricate configurations. Argo's visibility and drift management are superior for software lifecycle.

Possibly Argo itself really is layer 1, then the other apps are somewhere around layer 1.5. Another special case would be Gitea in its bootstrapping mode. It can later be upgraded to permanent with persistent DB and file storage.

Layer 0 ready -> Argo installed -> Gitea bootstrapped -> Argo syncs other apps from Gitea -> Proceed to Layer 2 to vend infra -> Potentially upgrade Layer 1 stuff.

A similar approach was used in the Logistics repo where Argo would install then prepare ingress control automatically, but leave other appset inactive until the user takes an action and OKs the ingress setup including cert manager. Then you can refresh Argo from inside Argo, along with everything else. Quite possibly in the new approach you'd just do 

Argo -> Gitea -> Vegvisir -> Argo-in-Argo -> Crossplane -> Argo other apps including Agones etc

### Layer 2: The Infrastructure Services (Crossplane)

* What: "As-a-Service" primitives that applications need to existing.
* Components:
  * Databases: PostgreSQL, MongoDB (via your Mimir compositions).
  * Storage: S3 Buckets (via Garage compositions).
  * Queues: Kafka topics.

Value of Crossplane: Abstraction. An application developer (or Backstage template) requests a PostgresDB claim.

* On GKE: Crossplane provisions a Google Cloud SQL instance (High performance, managed).
* On Local: Crossplane provisions a Helm-based Postgres pod (Free, simple).

The Application doesn't know the difference. It just gets a Secret with a connection string.

### Layer 3: The Platform Capabilities (Nidavellir)

* What: High-level tools built on Layer 1 & 2.
* Components: Jenkins, Artifactory, Keycloak.
* Deployment: These are software applications, so they are deployed via ArgoCD. However, they consume Layer 2 services.
* Example: Keycloak is deployed by Argo, but it requests a PostgresDB claim from Crossplane for its storage.

### Layer 4: User Workloads (Run-Time)

* What: The actual business logic.
* Components:
  * Tafl: Orchestrates games.
  * Demicracy: Runs Backstage.
  * GameServers: Managed by Agones (triggered by Tafl).
