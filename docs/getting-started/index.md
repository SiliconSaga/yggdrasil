# Getting Started

The fastest way to experience GDD is to clone the yggdrasil workspace and start a session in **Mentoring mode** — the AI will explain the workspace, the methodology, and the tools as you go. You don't need to understand everything upfront.

Note that this currently assumes a variety of prerequisites:

- You're using Claude Code as your AI agent (more validated agents coming soon)
- You're using GitHub or GitLab for version control (Gitea/Forgejo planned)
- You're using a Unix-like shell (Linux, macOS, WSL, Git Bash)

## Setup

1. **Clone the workspace**
   ```bash
   git clone https://github.com/SiliconSaga/yggdrasil.git
   cd yggdrasil
   ```

2. **Configure your identity** — copy the example config and fill in your details:
   ```bash
   cp ecosystem.local.yaml.example ecosystem.local.yaml
   ```
   Edit `ecosystem.local.yaml` and set at minimum:
   - `identity.human_account` — your GitHub/GitLab username
   - `identity.forkOrg` — the org/group name for your git remote (e.g., `SiliconSaga`)

3. **Set up auth** — follow the [Git Provider Setup](../git-provider-setup.md) guide to configure your provider token in `.env` and install the CLI tools (`gh` for GitHub, `glab` for GitLab). This enables the `ws` CLI to push, file issues, and manage PRs/MRs.

4. **Add `ws` to your PATH** _(recommended)_ — so you can run `ws` from anywhere:
   ```bash
   # Add to your ~/.bashrc or shell profile:
   export PATH="<path-to-yggdrasil>/scripts:$PATH"
   ```

5. **Clone a component to work on:**

   Note that these components are fairly centric to nerdy homelab or indie game dev projects.

   ```bash
   bash scripts/ws list             # see what's available
   bash scripts/ws clone terasology # or any component that interests you
   ```

   Not sure what to clone? Some suggestions:

   - **vordu** — BDD roadmap visualization. Has a React UI and a Python API.
   - **terasology** — a voxel game (Java). Make a quick content change and see it in-game.
   - **destinationsol** — a space shooter (Java). Same idea — tweak something visible and run it.

   Or bring your own project — clone any repo into `components/` and the `ws` CLI will pick it up:

   ```bash
   cd components
   git clone https://github.com/your-org/your-project.git
   cd ..
   ```

## Your First Session

6. **Start Claude Code** from the `yggdrasil/` directory

7. **Say hello.** The GDD orientation will kick in automatically — it'll mention Thalamus, ask about your mode, and ask what you want to work on.

8. **Ask for Mentoring mode.** This is the key for your first session:

   > "Let's use mentoring mode. I'm new to this workspace and want to understand how things work."

   In Mentoring mode, the AI explains its decisions, teaches practices in context, and walks you through the tools. It's like pair programming with someone who knows the codebase.

9. **Pick something small to do.** Some ideas:
   - Explore a component: "What does tafl do? Walk me through the code."
   - Write a BDD scenario: "Help me write a test scenario for [feature]."
   - Fix something: Check the [open issues](https://github.com/SiliconSaga/yggdrasil/issues) for anything labeled `good first issue`.
   - Just explore: "What's in this workspace? Show me around."

   The Mentoring mode will explain the `ws` CLI, the component structure, and GDD itself as you encounter them naturally.

## What Happens Next

As you work, the AI captures observations in the **Thalamus** — a shared thinking space that persists between sessions. You can write thoughts there too (it's just a markdown file at `Thalamus.md` in the workspace root).

After a few sessions, try **housekeeping** — review what's accumulated, promote useful observations to issues or skill updates, prune what's resolved. This is how GDD improves itself through use.

When you're comfortable, try other modes:

- **Quick** for 15-minute sessions between other responsibilities
- **Zen** for deep work sessions where you want full ceremony

See the [GDD overview](../gdd/index.md) for the full methodology, or browse the [session transcripts](../gdd/samples/index.md) for examples of real sessions (though honestly, the transcripts can't capture the feel of it — the best way is to try it yourself).

## Bringing GDD to Your Own Community

Yggdrasil is designed as scaffolding around your projects, not something embedded in them. Your target projects don't need to adopt any agentic conventions — no AGENTS.md, no `.claude/` directory, no AI config files. The workspace provides the skills, tooling, and methodology; your projects stay clean.

This means you can use GDD to contribute to any project, even one that hasn't adopted AI tooling. The human is always the one submitting work — the agent is your collaborator, clearly labeled.

### How adoption works

<!-- Backlink anchor from https://siliconsaga.net/guardian-driven-development/ -->

Initial design — details will evolve!

The idea is a three-layer configuration:

1. **Yggdrasil upstream** — fork or clone the generic workspace. Ships with tutorial components and sample configuration. Works out of the box for exploring GDD.

2. **Your overlay** — a small separate repo (named with a `ygg-overlay` convention, e.g. `siliconsaga-ygg-overlay`) containing your community's configuration: which components to work on, agent identity and attribution, domain settings. When this repo is present in `components/`, Yggdrasil detects it automatically and merges its config — no config file edits needed. Convention over configuration.

3. **Local overrides** — `ecosystem.local.yaml` (gitignored) for per-developer settings on top of the overlay. Same as today.

The bootstrap for a new community member:

```bash
git clone https://github.com/SiliconSaga/yggdrasil.git   # or your fork
cd yggdrasil
bash scripts/ws clone https://github.com/YourOrg/your-ygg-overlay.git
bash scripts/ws clone --all    # pulls components declared in the overlay
```

One person sets up the overlay repo for the community. Everyone else runs two commands. The overlay declares which components to clone, so `ws clone --all` pulls exactly what the community needs.

`ws clone` would accept arbitrary git URLs for flexibility — any repo gets cloned into `components/`. But only a repo matching the `ygg-overlay` naming convention gets picked up as configuration automatically.

When you make it your own, tutorial components are just independent repos in `components/` — don't clone them, or remove them. Nothing in Yggdrasil changes. Your overlay declares your components, your agent identity, your domains.

The overlay also solves multi-workspace sharing: same overlay repo on different machines gives you consistent configuration, while `ecosystem.local.yaml` handles per-machine differences.

**This is an initial design concept, not yet implemented.** The current practical path is still: clone Yggdrasil, clone your project into `components/`, and use the workspace as-is. The overlay architecture is the next evolution — see the [GDD design docs](../gdd/index.md) for where things are headed.
