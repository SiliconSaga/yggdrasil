# Getting Started

The fastest way to experience GDD is to clone the yggdrasil workspace and start a session in **Mentoring mode** — the AI will explain the workspace, the methodology, and the tools as you go. You don't need to understand everything upfront.

If you'd rather see what's in the box first before diving in, the [GDD Features Tour](../gdd/features.md) is a quick read covering the workspace, realms, hoards, component templates, the bot-driven review loop, modes, and permissions.

Note that this currently assumes a variety of prerequisites:

- You're using Claude Code as your AI agent (more validated agents coming soon)
- You're using GitHub or GitLab for version control (Gitea/Forgejo planned)
- You're using a Unix-like shell (Linux, macOS, WSL, Git Bash)
- **Recommended**: [Obra Superpowers](https://github.com/obra/superpowers) installed in your agent. GDD's implementation plans and several practices (brainstorming, TDD, executing plans, subagent-driven development, code review) reference `superpowers:*` skills. Everything still works without it, but you'll see references to skills the agent can't load. The orientation skill checks for Superpowers at session start and nudges you to install if missing.

## Templates, instances, and tutorials

The yggdrasil workspace ships templates in two shapes: in-repo `templates/<kind>/<flavor>/` directories that an `init` command copies out (hoards, components), and external git repos that an `init` command clones (realms — referenced via `defaults.templateRealm` URL in the ecosystem config).

| Kind | Source | Instance dir | Init command |
|------|--------|--------------|--------------|
| **Realm** | external git repo (URL in `defaults.templateRealm`) | `realms/realm-<community>/` (or `realms/realm-template/` for the upstream tutorial) | `ws realm init` (clones the template URL) |
| **Hoard** | `templates/hoards/<type>/` | `hoards/<type>-<username>/` | `ws hoard init <type>` (copies + git-inits) |
| **Component** | `templates/components/<flavor>/` | `components/<name>/` | `ws component init <flavor> <name>` (copies + git-inits) |

A *template* is a forkable scaffold. An *instance* is the on-disk result of running its `init` command. A *tutorial* is an instance deliberately suitable for newcomers — the `gh-pages` component template produces a tutorial instance with a comprehensive README and a designed-to-be-edited home page. Other flavors may not be tutorial-friendly (they're production scaffolds).

## Setup

### Before you start: bootstrap

Two foundational pieces have to be in place before any of the rest of the walkthrough works. Skim these and skip whichever you already have.

#### Install Git

You need Git to clone the workspace, and on Windows it's also how you get bash (the shell `ws` runs in).

- **macOS:** `xcode-select --install` to get Git via Xcode Command Line Tools, OR `brew install git` if you already use Homebrew. Bash is built-in.
- **Windows:** Download Git for Windows from https://git-scm.com/download/win — this bundles **Git Bash**, the shell you'll use for everything else. Accept the installer's default to add Git to your PATH (the "Git from the command line and also from 3rd-party software" option). After install, **open Git Bash** (Start menu → Git Bash). Run all subsequent commands from Git Bash, not cmd.exe or PowerShell.
- **Linux:** `sudo apt install git` (Debian/Ubuntu) or `sudo dnf install git` (Fedora). Bash is built-in.

You don't need Python for the workspace itself. Python and `uv` are optional, only required for components or MCP servers that explicitly use them.

#### Get a GitHub or GitLab account

GDD assumes you have a hosting account — agents push, open PRs, and file issues on your behalf, and there has to be an account those operations belong to. **If you don't have one yet:**

- **GitHub:** sign up at https://github.com/signup (free). Pick a username — that's your `identity.human_account` in the workspace config below. Verify your email so you can create repos.
- **GitLab:** sign up at https://gitlab.com/users/sign_up (free). Same shape — username becomes your config identity.

That's enough to get through this walkthrough. The token + CLI setup (Step 3 below) needs your account to exist; everything else is stand-alone. If you already have an account, skip ahead.

### Walkthrough

1. **Clone the workspace**

   ```bash
   git clone https://github.com/SiliconSaga/yggdrasil.git
   cd yggdrasil
   ```

   Once cloned, run a prerequisite check before going further:

   ```bash
   bash scripts/ws preflight
   ```

   It verifies bash, git, `yq` (v4+ — Mike Farah's, not the Python yq), `jq`, and a provider CLI (`gh` or `glab`). Anything missing prints a per-OS install hint. Re-run after installing to confirm.

2. **Configure your identity** — copy the example config and fill in your details:

   ```bash
   cp ecosystem.local.yaml.example ecosystem.local.yaml
   ```

   Edit `ecosystem.local.yaml` and set at minimum:
   - `identity.human_account` — your GitHub/GitLab username
   - `identity.forkOrg` — the org/group name for your git remote (e.g., `SiliconSaga`)

3. **Set up auth** — follow the [Git Provider Setup](../git-provider-setup.md) guide to configure your provider token in `.env` and install the CLI tools (`gh` for GitHub, `glab` for GitLab). This enables the `ws` CLI to push, file issues, and manage PRs/MRs.

4. **Add `ws` to your PATH** — all workspace operations go through the `ws` CLI. Adding `scripts/` to your PATH lets you run `ws <command>` directly instead of the longer `bash scripts/ws <command>` form. It also means `ws` always resolves paths relative to the workspace root, so it works correctly no matter which directory you (or an AI agent) run it from:

   ```bash
   echo "export PATH=\"$(pwd)/scripts:\$PATH\"" >> ~/.zshrc   # zsh (macOS default)
   # or:
   echo "export PATH=\"$(pwd)/scripts:\$PATH\"" >> ~/.bashrc  # bash
   ```

   Then reload your shell (`source ~/.zshrc` / `source ~/.bashrc`) or open a new terminal. Run `ws help` to verify.

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

### Recommended first scaffold

If you're new to GDD and want to feel the full workflow on a tiny live target, scaffold the GitHub Pages tutorial:

```bash
ws component init gh-pages my-page
```

Then follow the printed instructions and `components/my-page/README.md`. The tutorial walks you through creating the GitHub repo, enabling Pages, making a first edit on a topic branch, opening a PR, watching CodeRabbit and Copilot review, and seeing it deploy live — the whole GDD loop on something small enough to feel in 15 minutes.

## Your First Session

6. **Start Claude Code** from the `yggdrasil/` directory

7. **Say hello.** The GDD orientation will kick in automatically — it'll mention Thalamus, ask about your mode, and ask what you want to work on.

   **Heads-up about the "scary red" output you might see early on.** In the first few tool calls of a session, you'll often see the agent get a stream of red-looking error messages — things like "Output / input redirection is disallowed" or "File-descriptor merges aren't needed". Those aren't crashes. They're the workspace's PreToolUse hook gently rejecting the agent's generic shell habits and pointing at the local way to do the same thing. The agent reads each message on its next turn and retries; after a handful of denies it has the conventions cached and the noise drops to nearly zero. Nothing was harmed (the rejected commands never ran). See [agent-training.md](../gdd/agent-training.md) for the full explanation if you're curious.

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

2. **Your realm** — a small separate repo (named with a `realm-<community>` convention, e.g. `realm-siliconsaga`) containing your community's configuration: which components to work on, agent identity and attribution, domain settings. When this repo is present in `realms/`, Yggdrasil detects it automatically and merges its config — no config file edits needed. Convention over configuration.

3. **Local overrides** — `ecosystem.local.yaml` (gitignored) for per-developer settings on top of the realm. Same as today.

The bootstrap for a new community member:

```bash
git clone https://github.com/SiliconSaga/yggdrasil.git   # or your fork
cd yggdrasil
bash scripts/ws realm https://github.com/YourOrg/realm-yourorg.git
bash scripts/ws clone --all    # pulls components declared in the realm
```

One person sets up the realm repo for the community. Everyone else runs two commands. The realm declares which components to clone, so `ws clone --all` pulls exactly what the community needs.

`ws clone` accepts arbitrary git URLs for flexibility — any repo gets cloned into `components/`. Realm repos get cloned into `realms/` via `ws realm <url>` and are recognized as configuration when their name matches the `realm-<community>` convention.

When you make it your own, tutorial components are just independent repos in `components/` — don't clone them, or remove them. Nothing in Yggdrasil changes. Your realm declares your components, your agent identity, your domains.

The realm also solves multi-workspace sharing: same realm repo on different machines gives you consistent configuration, while `ecosystem.local.yaml` handles per-machine differences.

The realm architecture is implemented today; multi-realm inheritance (corporate → department → team chains) and a community marketplace for hoard templates remain forward-looking — see the [GDD design docs](../gdd/index.md) for the broader trajectory.
