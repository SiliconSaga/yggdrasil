# Getting Started

## For SiliconSaga Contributors

1. **Clone the workspace**
   ```bash
   git clone https://github.com/SiliconSaga/yggdrasil.git
   cd yggdrasil
   ```

2. **Set up auth** — follow the [GitHub CLI Setup](../github-cli-setup.md) guide to configure your `GH_TOKEN` in `.env`.

3. **Clone components** you want to work on:
   ```bash
   bash scripts/ws clone nordri     # or any component
   bash scripts/ws clone --all      # everything
   bash scripts/ws list             # see what's available
   ```

4. **Start a session** — if you're using an AI agent (Claude, Gemini, etc.), the GDD orientation skill will guide you through mode selection and session setup automatically. Just say hello.

5. **Pick a mode:**
   - **Quick** — 15-minute session, minimal ceremony
   - **Zen** — deep work, full ceremony, thorough reviews
   - **Mentoring** — explanations as you go, great for unfamiliar areas

## For GDD in Your Own Projects

GDD is designed to be portable. The core concepts — SecondBrain, orientation, trust verification, housekeeping — can work in any repo with an AI agent.

To adopt GDD:

1. Copy the `.agent/skills/gdd-*` skills and the `secondbrain-template.md` to your project
2. Add a Session Start section to your `AGENTS.md` (or equivalent instruction file) pointing to the orientation skill
3. Add `SecondBrain.md` to your `.gitignore`
4. Start a session — the orientation skill handles the rest

See the [GDD overview](../gdd/index.md) for the full methodology, or browse the [Samples](../samples/index.md) to see it in action.
