# Unified BOM Architecture: Yggdrasil & Terasology

## Vision
To establish a standardized, "Single Source of Truth" (SSOT) approach for defining system composition across the ecosystem, using **CycloneDX** as the data format and **Backstage** as the visualization engine.

## Core Principles
1. **Universal Format**: CycloneDX (`bom.json`) is the standard for both infrastructure and software modules.
2. **Native Visualization**: Leverage Backstage's built-in "Catalog Graph" instead of external tools like GUAC.
3. **Zero Duplication**: Metadata is defined once (e.g., in `build.gradle`) and artifacts are generated.

---

## Phase 1: Yggdrasil (The "Pull" Model)
*Target: The Mega-Workspace and Infrastructure.*

Since Yggdrasil changes less frequently and lacks a complex build artifact pipeline, it uses the standard Backstage "Pull" model.

* **Source**: Simply the `project-constellation.md` file along with Git repos arranged by hand by a human.
  * *Maintenance*: Manually updated or generated via a simple script scanning the `d:\Dev\GitWS` directory.
* **Ingestion**: Backstage `Catalog` reads catalog files from Git
* **Goal**: Visualize the "Constellation" of workspaces (Norðri, Nidavellir, Vörðu) and their high-level dependencies.

---

## Phase 2: Terasology (The "Push" Model)
*Target: Game Modules and High-Velocity Code.*

Terasology modules require a "Single Source of Truth" to avoid maintaining `module.txt`, `README.md`, and `catalog.yaml` (for adopting Backstage as a more powerful yet existing "module site") separately, while relying on obscure Gradle magic and build harnesses on the backend.

### 1. The Build (Gradle as SSOT)
The `build.gradle` file becomes the master definition.
* **Input**: `build.gradle` (Dependencies, Version, Description).
* **Process**:
  * `gradle cyclonedxBom`: Generates `build/reports/bom.json`.
* **Output**: A standard CycloneDX JSON artifact.

### 2. The Ingestion (Push)
Backstage does not poll Git. It receives the artifact in real-time.
* **CI/CD**: Jenkins builds the project.
* **Push**: Jenkins `POST`s the `bom.json` to Backstage (`http://nidavellir/api/cyclonedx/ingest`).
* **Backstage**: A custom `CycloneDXEntityProvider` receives the JSON, parses it, and applies a **Delta Mutation** to the catalog.
  * Worth highlighting that this needs to be implemented in a new Backstage effort.

### 3. The Game
* **Runtime**: The Terasology engine uses `cyclonedx-core-java` to read `bom.json` directly.
* **Deprecation**: `module.txt` is removed.

---


## Technical Components
1. **Backstage Backend Plugin**:
  * `HttpRouterService`: To expose the `POST` endpoint.
  * `EntityProviderConnection`: To apply mutations to the catalog.
2. **Jenkins Pipeline**:
  * `httpRequest` step to push artifacts.
3. **Gradle Plugin**:
  * `org.cyclonedx.bom` for generation.

---

## Phase 3: The Future (The "Capabilities" Model)
*Target: The Abstract API "Rosetta Stone".*

In the long term, Yggdrasil may evolve from a "Distribution" (listing specific software like Kafka) to a "Specification" (listing required capabilities like `EventBus`).

### 1. The Concept: Bring Your Own Stack (BYOS)
Instead of mandating "You must run Kafka", the platform defines a contract:
* **Requirement**: "I need a PubSub topic named `game-events`."
* **Implementation**: The local admin provides it via whatever they have (Kafka, NATS, Redis Streams, or internal memory).

### 2. The Enabler: Dapr (Distributed Application Runtime)
To avoid writing adapter code for 50 different backends in every app, we use **Dapr** as the universal sidecar.
* **The Code**: `dapr_client.publish_event(pubsub_name='pubsub', topic_name='game-events', data=payload)`
* **The Config**: A simple YAML file maps `pubsub` -> `redis` (Local) or `pubsub` -> `snssqs` (AWS).

### 3. The Value for Bifrost
This creates the "Rosetta Stone" for the Metaverse.
* **Heterogeneity**: A Java Game Service (Terasology) and a Godot client can speak the same language.
* **Flexibility**: A home-lab user runs on lightweight Redis; an enterprise cluster runs on heavy Kafka. Neither changes the code.
