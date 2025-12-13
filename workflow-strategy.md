# Yggdrasil Workflow Strategy
*How we build the world together.*

## The "Artifact Cycle"
We use AI Artifacts as **temporary, interactive workspaces** for high-velocity collaboration, which then "crystallize" into permanent files.

1.  **Spawn (Artifact)**: When brainstorming or drafting (e.g., a new Roadmap or Architecture Doc), I will create an **Artifact**.
    *   *Benefit*: It appears in a dedicated UI panel, I can update it instantly, and we can iterate fast without cluttering your Git history with 50 typos.
2.  **Refine (Chat)**: We discuss, you give feedback, and I update the Artifact in real-time.
3.  **Crystallize (File)**: Once we agree "This is good," I write the Artifact to a permanent file in the appropriate repo (e.g., `demicracy/docs/roadmap.md`).
    *   *Benefit*: It becomes part of the "Source of Truth" for other tools (Vörðu, Uplifted Mascot).
4.  **Revive (Optional)**: If we need to do a major overhaul later, I can read the file back into an Artifact, we iterate, and then overwrite the file.

---

## Naming & Identity Standards
Every project in the Yggdrasil ecosystem follows this `README.md` header format to bridge the gap between "Mythological Name" and "Practical Utility".

### Template
```markdown
# [Project Name] (e.g., Norðri)
*[Mythological Role] - [Practical Description]*

> "[Brief Mythological Context]"

**[Project Name]** is the [Functional Component] of the Yggdrasil ecosystem. It [Primary Action/Purpose].
```

### Examples

#### Norðri
```markdown
# Norðri
*The Foundation - Self-Hosted Infrastructure*

> "One of the four dwarves who hold up the sky, guarding the North."

**Norðri** is the **Infrastructure Layer** of the ecosystem. It provides the resilient Kubernetes substrate (K3s/Longhorn) that holds up the rest of the digital world.
```

#### Nidavellir
```markdown
# Nidavellir
*The Forge - Platform & Tooling*

> "The dark fields where the dwarves forge the most powerful treasures of the gods."

**Nidavellir** is the **Platform Layer**. It is the workspace where we forge applications, hosting the CI/CD pipelines (Jenkins), Dashboards (Backstage), and Identity Systems (Keycloak) needed to build everything else.
```

#### Demicracy
```markdown
# Demicracy
*The Constitution - Design & Philosophy*

> "The rule of the people."

**Demicracy** is the **Design Repository**. It holds the "Source Code" for our governance models, containing the philosophy (Front State), the specifications, and the matrixed roadmap that guides the project.
```
