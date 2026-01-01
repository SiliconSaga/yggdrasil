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
    *   Likely "Vegvísir" would be the sub-term for ingress control / gateway / routing. Which is needed in GKE as well as in the homelab (Nordri). Is Traefik in both and if so is Vegvisir just a wrapper / name for it? Maybe Vegvisir is also the operator that configures the Gateway solely on new authorized Routes being added (to avoid a manual step to update the Gateway separately)
    *   **Keycloak**: Identity provider (The "Passport").
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

Agones et al. Basic game hosting.

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