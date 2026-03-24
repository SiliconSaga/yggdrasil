# Getting Started

The fastest way to experience GDD is to clone the yggdrasil workspace and start a session in **Mentoring mode** — the AI will explain the workspace, the methodology, and the tools as you go. You don't need to understand everything upfront.

Note that this currently assumes a variety of prerequisites:

- You're using Claude Code as your AI agent
- You're using GitHub for version control
- You're using a Unix-like shell (Linux, macOS, WSL, Git Bash)

This should evolve further soon.

## Setup

1. **Clone the workspace**
   ```bash
   git clone https://github.com/SiliconSaga/yggdrasil.git
   cd yggdrasil
   ```

2. _Optionally_ **Set up auth** — follow the [GitHub CLI Setup](../github-cli-setup.md) guide to configure your `GH_TOKEN` in `.env`. This enables the `ws` CLI to push, file issues, and manage PRs. Without auth you can still do local commits and play with the system, but you won't be able to push changes or create PRs and issues.

3. **Clone a component to work on:**

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

4. **Start Claude Code** from the `yggdrasil/` directory (more validated agents coming soon)

5. **Say hello.** The GDD orientation will kick in automatically — it'll mention SecondBrain, ask about your mode, and ask what you want to work on.

6. **Ask for Mentoring mode.** This is the key for your first session:

   > "Let's use mentoring mode. I'm new to this workspace and want to understand how things work."

   In Mentoring mode, the AI explains its decisions, teaches practices in context, and walks you through the tools. It's like pair programming with someone who knows the codebase.

7. **Pick something small to do.** Some ideas:
   - Explore a component: "What does tafl do? Walk me through the code."
   - Write a BDD scenario: "Help me write a test scenario for [feature]."
   - Fix something: Check the [open issues](https://github.com/SiliconSaga/yggdrasil/issues) for anything labeled `good first issue`.
   - Just explore: "What's in this workspace? Show me around."

   The Mentoring mode will explain the `ws` CLI, the component structure, and GDD itself as you encounter them naturally.

## What Happens Next

As you work, the AI captures observations in the **SecondBrain** — a shared thinking space that persists between sessions. You can write thoughts there too (it's just a markdown file at `SecondBrain.md` in the workspace root).

After a few sessions, try **housekeeping** — review what's accumulated, promote useful observations to issues or skill updates, prune what's resolved. This is how GDD improves itself through use.

When you're comfortable, try other modes:

- **Quick** for 15-minute sessions between other responsibilities
- **Zen** for deep work sessions where you want full ceremony

See the [GDD overview](../gdd/index.md) for the full methodology, or browse the [session transcripts](../gdd/samples/index.md) for examples of real sessions (though honestly, the transcripts can't capture the feel of it — the best way is to try it yourself).

## Bringing GDD to Your Own Projects

<!-- TODO: GDD extraction is not yet automated. The skills reference yggdrasil-specific
paths and conventions. A future effort could create a portable GDD starter kit or
extraction script. For now, the best way to use GDD is within the yggdrasil workspace,
with your project cloned into components/. -->

GDD currently lives in the yggdrasil workspace. The most practical way to use it with your own project is to clone your repo into `components/` as described above — you get the full workspace, CLI, and all the skills.

A standalone GDD starter kit (extract the skills and templates for use in any repo) is a future goal but not yet available.
