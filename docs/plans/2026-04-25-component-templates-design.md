# Component Templates and `ws component init` — Design Spec

**Date:** 2026-04-25
**Status:** Draft
**Related:** [Realms and Hoards Design](2026-04-24-realms-and-hoards-design.md)

---

## Summary

Introduce **component templates** as the third member of the
template family alongside hoard and (eventual) realm templates. Ship a
flagship `gh-pages` flavor that scaffolds a working GitHub Pages site
suitable for newcomer-friendly tutorial use, and a new `ws component init`
command that mirrors `ws hoard init`. Also clarify the
**template / tutorial / instance** vocabulary in workspace docs now that
all three template kinds (hoard, realm, component) share a directory
shape and an `init` command.

The flagship template is the substrate for a soft-GA newcomer story:
"clone yggdrasil, run two commands, edit a page, open a PR, watch the
bots review you, merge, see it live." A new user can finish the loop
solo by following the template's README — AI assistance is welcomed
but not required.

---

## Vocabulary

After this lands, the workspace has three parallel template kinds and a
clean conceptual split between *template* and *tutorial*:

| Term | Definition |
|------|------------|
| **Template** | A scaffold living at `templates/<kind>/<flavor>/`. Forkable, parameterized minimally, copied by an `init` command. Three kinds today: realm, hoard, component. |
| **Instance** | The on-disk result of running an `init` command — a fresh hoard, realm, or component populated from its template. |
| **Tutorial** | An *instance* deliberately suitable for newcomers. The `gh-pages` component template is designed to produce a tutorial instance: complete walkthrough, low barrier, designed-to-be-edited. Other future flavors may not be tutorial-friendly (they're production scaffolds). |

This vocabulary will land as a short section in `docs/getting-started/`
and a sentence in `docs/ws-cli-guide.md`. No code change.

---

## Directory Structure

```text
yggdrasil/
  templates/
    README.md
    thalamus.md
    commit.md
    change.md
    issue.md
    hoards/
      thalami/                 # existing
    components/                # new top-level under templates/
      gh-pages/                # flagship flavor
      # frontend/, backend/, mcp-server/, ... (sub-project B)
    external/                  # gitignored, future marketplace
  components/                  # gitignored — instances live here
    nordri/                    # community catalog (declared in realm)
    mimir/                     # ditto
    my-blog/                   # NEW: locally-scaffolded instance
    ...
  scripts/
    ws-component.sh            # new
    ws                         # new `component` route
  ecosystem.local.yaml         # NEW: gains `components.<name>` entries
                               # for locally-scaffolded instances
```

`templates/components/` mirrors `templates/hoards/`. Each direct
subdirectory is a flavor; its contents are the literal scaffold copied
into `components/<name>/` at init time.

---

## The `ws component init` Command

### Arg shape

```text
ws component init <flavor> [name] [template-args...]
```

- **`<flavor>`** — required, no default. Must match a directory under
  `templates/components/`. Components are diverse enough that a
  canonical default (like `thalami` for hoards) doesn't fit.
- **`[name]`** — optional. If omitted on a tty, prompt for it (single-
  question wizard seed; future expansion possible). On non-tty + no
  name, error with usage. Becomes the local component directory name
  and the ecosystem entry key.
- **`[template-args...]`** — per-flavor flags. Hardcoded handling per
  flavor in `scripts/ws-component.sh` for v1 (mirrors how
  `ws-hoard.sh` handles `--from-thalamus`). Generalized template
  metadata is a future option once flavor count justifies it.

### Behavior

1. **Validate flavor.** Error if `templates/components/<flavor>/`
   doesn't exist; list available flavors in the error message.
2. **Resolve name.** Use the `name` arg, prompt for one if omitted on
   a tty, or error.
3. **Validate name** against the same safe pattern used by
   `ws_validate_component` in `ws-realm.sh`:
   `^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$`. Allows
   dotted segments (e.g. `some.component`) for parity with names already
   accepted across the workspace. Reject the workspace-root name
   `yggdrasil` (the only reserved name today; `ws_validate_component`
   already special-cases it).
4. **Pre-flight checks (before any filesystem mutation):**
   - `components/<name>/` does not exist (otherwise: error).
   - `<name>` is not already declared in `ecosystem.local.yaml`
     (otherwise: error).
   - If `<name>` is already declared in the realm's `ecosystem.yaml`,
     warn and require explicit confirmation
     (`overwriting community catalog entry locally`) — the local layer
     would shadow the realm's version, which is intentional but
     surprising.
5. **Resolve identity.** Read `identity.human_account` from merged
   ecosystem config. Required (errors with setup guidance if unset).
6. **Copy template.** `cp -R templates/components/<flavor>/ components/<name>/`.
7. **Apply per-template flags.** For `gh-pages`, no flags in v1.
8. **`git init -b main`** in `components/<name>/`, initial commit using
   the user's git config (matching `ws-hoard.sh` portable identity
   handling).
9. **Add `ecosystem.local.yaml` entry** under `components.<name>`:

   ```yaml
   components:
     <name>:
       repo: https://github.com/<human_account>/<name>.git   # edit if you push elsewhere
   ```

   The URL is inferred from the printed `gh repo create` suggestion
   (Step 11). Other fields (tier, chartVersion, etc.) are realm-specific
   and absent here — the local layer doesn't need them. If
   `ecosystem.local.yaml` doesn't exist, create it with just this
   `components` block. If it exists, deep-merge.
10. **Print educational output** explaining what just happened and what
    to do next (see "Educational output" below).
11. **Print suggested `gh repo create` command** tailored to the flavor.
    For `gh-pages`:

    ```bash
    gh repo create <human_account>/<name> --public \
      --source=components/<name> --remote=<human_account> --push
    ```

    `--public` is the flavor default for `gh-pages` because free GitHub
    Pages on personal accounts requires public visibility. Explained in
    the README. Other flavors may default differently.

### Educational output

After a successful init, the agent prints a structured "what just
happened" block. Concrete wording:

```text
Component initialized: components/<name>

Registered in ecosystem.local.yaml:
  components:
    <name>:
      repo: https://github.com/<human_account>/<name>.git

This is the local-only layer of the three-layer config merge:
  upstream ecosystem.yaml → realm/ecosystem.yaml → ecosystem.local.yaml

The component is immediately usable from this workspace
(ws status, ws push <name>, etc.) without touching the realm.

When you're ready to share this component with the community:
  1. Push the component to your remote (see suggested gh command below)
  2. Move the entry from ecosystem.local.yaml into the realm's
     ecosystem.yaml, with realm-appropriate fields added (tier, etc.)
  3. Commit and push the realm
```

The template's own README (read after init) walks the user through the
demo flow itself. The educational output covers only the workspace-side
mechanics.

### Mentoring-mode integration

Mentoring-mode behaviors (extra explanation, offering to capture
Thalamus todos for future considerations like theme upgrades) belong
in `gdd-mentoring/SKILL.md` (sub-project C, future). The `ws component
init` script itself outputs the same educational block in all modes;
the agent in mentoring mode adds commentary on top.

The `gh-pages` template's README explicitly invites this — there's a
"Going further" section that says *"if you want to upgrade the theme
later, ask your agent to walk you through GitHub Pages-supported themes
or capture a Thalamus todo for it."*

---

## The `gh-pages` Flagship Template

### File set (MVP)

`templates/components/gh-pages/` ships exactly five files:

| File | Purpose |
|------|---------|
| `index.md` | Home page. Obvious "edit me" placeholder + a friendly explanation of what the user is looking at. |
| `_config.yml` | Minimal Jekyll config: `theme: jekyll-theme-cayman` (clean, supported by GitHub's built-in renderer). |
| `README.md` | Comprehensive tutorial-style walkthrough — see below. |
| `.gitignore` | Standard Jekyll ignores: `_site/`, `.jekyll-cache/`, `.bundle/`, `vendor/`, `Gemfile.lock`. |
| `LICENSE` | MIT placeholder. The user replaces or keeps as-is. |

Deliberately omitted from the MVP:
- `about.md` or other pages — keep it to one page; users add more once
  they understand the flow.
- GitHub Actions workflow for Pages — the default
  Pages-from-branch-root deploy is enough for a bare markdown site; no
  custom workflow needed.
- Per-component adapter file — `gh-pages` has no build step beyond what
  GitHub does automatically.
- Sample CR/issue templates — those live at the realm level (the realm
  already provides them via the workspace's existing
  `templates/change.md` / `templates/issue.md`).

### `index.md` content

Front-matter + a single editable section:

```markdown
---
layout: default
title: <your name>'s page
---

# Hello — this is your new GitHub Pages site

You're looking at the placeholder home page. **Edit this file
(`index.md`) to make it yours**, then commit, open a PR, and watch the
bots review your changes before you merge.

Replace this paragraph with whatever you want — a short bio, project
log, recipe collection, anything. The `_config.yml` next to this file
controls the theme and site title; tweak that whenever you're ready.

For the full tutorial walkthrough, see [`README.md`](README.md).
```

### `_config.yml` content

```yaml
title: <your name>'s page
description: Built with the GDD GitHub Pages template
theme: jekyll-theme-cayman

# A few other GitHub-supported themes you can swap to later by
# editing the `theme:` line above:
#   jekyll-theme-minimal, jekyll-theme-slate, jekyll-theme-architect,
#   jekyll-theme-merlot, jekyll-theme-modernist, jekyll-theme-leap-day
# For richer theming, ask your agent to walk you through forking a
# theme repo or moving to a different SSG.
```

### `README.md` structure

The README is the user-facing tutorial. Comprehensive enough that a
solo user (no AI assistant) can finish the demo loop end-to-end.

Header note (right under the title):

> **You can ask your AI agent to walk you through any step below, or
> follow this guide directly. Both paths arrive at roughly the same
> place.** (The agent is non-deterministic; this guide is the
> deterministic path. They do the same thing in spirit.)

Sections:

1. **What this is** — 2-3 sentences. "This is a starter site scaffolded
   from the GDD `gh-pages` component template. It deploys to GitHub
   Pages as-is, lets you exercise the full GDD-and-bot-review workflow
   with a tiny live target, and is meant to be edited from day one."
2. **Setup checklist** — explicit steps:
   - Create your remote: `gh repo create ...` (the exact command the
     init script printed) OR via GitHub UI.
   - Push the initial commit if you didn't pass `--push` above.
   - Enable GitHub Pages in the new repo: Settings → Pages → Source:
     "Deploy from a branch" → Branch: `main` → Folder: `/ (root)` →
     Save. (Screenshots / direct UI link if useful.)
   - Wait ~1 minute. Visit
     `https://<your-username>.github.io/<your-repo>/` to confirm.
3. **Make your first edit** — guided exercise editing `index.md`. Use
   a topic branch (`git -C components/<name> checkout -b first-post`).
   Write a `.commits/first-post.md` bodyfile listing `index.md` under
   `add:` (paths relative to the component), then commit:
   `ws commit <name> .commits/first-post.md`.
4. **Open a PR and watch the bots** — `ws push <name> first-post`,
   then `gh pr create --fill` (or use GitHub UI). What to expect:
   - **CodeRabbit** posts a review usually within a couple of minutes.
     If you don't see one, check that the [CodeRabbit GitHub App](https://github.com/marketplace/coderabbit)
     is installed on your account.
   - **GitHub Copilot review** can be requested from the PR's
     reviewers panel ("Request review from Copilot"). Free for personal
     accounts with a Copilot subscription.
5. **Merge and see it live** — once you've responded to or accepted any
   review feedback, merge the PR. GitHub Pages rebuilds the site
   automatically (~1 minute). Refresh your URL to see the change.
6. **Going further** — pointers, no instructions:
   - Want a different theme? Edit `_config.yml` (commented options
     listed). For richer theming, ask your agent to walk you through
     forking a theme repo or moving to a different static-site
     generator. *Or capture a Thalamus todo about the theme work and
     come back to it later.*
   - Want a custom domain? Ask your agent for the `CNAME` file +
     DNS setup pattern.
   - Want more pages? Add `<name>.md` files alongside `index.md`. Link
     from `index.md`.
   - Want analytics, comments, search? Each is a separate add-on; the
     template stays minimal so you can take it where you want.

---

## Per-Template Flag Handling (v1)

Hardcoded per-flavor in `scripts/ws-component.sh`, mirroring how
`ws-hoard.sh` handles `--from-thalamus`. For `gh-pages` v1, no flags
are accepted (the template needs no parameters beyond the component
name).

When a future flavor needs flags, extend the per-flavor `case` block in
`ws_component_init`. If/when the flavor count exceeds ~3-4, switch to a
`templates/components/<flavor>/template.yaml` metadata file declaring
accepted flags + defaults. Same pattern would generalize to hoards.

---

## Collision and Error Handling

| Condition | Behavior |
|-----------|----------|
| Unknown flavor (`templates/components/<flavor>/` missing) | Error with list of available flavors. |
| `components/<name>/` already exists | Error: "component '<name>' already exists at components/<name>". No partial scaffold. |
| `<name>` already in `ecosystem.local.yaml` | Error: "component '<name>' is already declared locally. Edit ecosystem.local.yaml or pick a different name." |
| `<name>` already in realm `ecosystem.yaml` | Warn and require y/N confirmation: "'<name>' is in the community catalog; the local entry will shadow it. Continue?" |
| `identity.human_account` unset | Error with setup guidance (matches `ws hoard init`). |
| `<name>` is `yggdrasil` (workspace root) | Error: "yggdrasil is the workspace root name; pick a different component name." |
| `<name>` violates regex | Error with the safe-pattern explanation. |
| Non-tty + no name passed | Error with usage. |
| `git init` fails | Roll back: remove `components/<name>/`. Error to stderr. Don't touch `ecosystem.local.yaml`. |
| `ecosystem.local.yaml` write fails | Roll back: remove `components/<name>/` (the dir is the rollback point — git init having succeeded is fine, it's local-only). Error to stderr. |

The pre-flight checks ensure no half-state when a likely-failure
condition is detectable upfront. Mid-operation failures roll back the
component dir.

---

## Schema: `ecosystem.local.yaml` entry

Minimal — just enough to make the component visible to the merged
config and clonable later if needed:

```yaml
components:
  <name>:
    repo: https://github.com/<human_account>/<name>.git   # edit if you push elsewhere
```

Realm-specific fields (`tier`, `chartVersion`, `chartName`, `path`,
`namespace`, etc.) are absent. Those are added when the user upstreams
the entry to the realm's `ecosystem.yaml`. The local layer is the
"works right now on this machine" minimum.

If `ecosystem.local.yaml` doesn't exist, the init command creates it
with just:

```yaml
components:
  <name>:
    repo: https://github.com/<human_account>/<name>.git
```

If it does exist, init runs `yq -i '.components["<name>"] = { ... }'`
which sets the new key without touching surrounding content. (mikefarah
yq v4 preserves YAML structure for in-place edits to specific paths
better than templating the file in shell — but it does not perfectly
preserve every comment in every position. Acceptable trade-off for
v1.)

Other code reading the merged config (e.g. `ws-resolve.sh`,
`ws-list.sh`) sees a minimal entry with only `repo` and must handle the
absence of realm-specific fields (`tier`, `chartVersion`, etc.)
gracefully. This is already an existing concern — those fields are
optional even in the community catalog — but worth a verification step
during implementation.

---

## Interaction with Existing Code

### `ws_validate_component`

After PR #44 (`enhance/ws-validate-hoards`), `ws_validate_component`
accepts: workspace root, realm dirs, hoard dirs, and ecosystem-declared
components that are cloned locally. Components scaffolded by
`ws component init` automatically pass the existing ecosystem-config
check (since the local layer of the merge declares them) — **no change
needed to `ws_validate_component`**.

### `ws clone <name>`

Reads merged ecosystem config to find a URL. After init writes the
local entry with `repo:`, `ws clone <name>` would find a URL but the
local component dir already exists, so clone would skip with the
existing "already cloned" guard. No new behavior needed.

### `ws status`

Walks declared components. After init, `<name>` appears in `ws status`
output automatically because the local layer adds it to the merged
config. No script change.

### `ws push <name>`

Validates, cd's to component dir, pushes via `git-push.sh` rules:
single remote (your push URL) → use it. Works as-is with the standard
flow.

### `ws-realm.sh`

Exports `HOARDS_DIR` for hoard recognition (per PR #44). Add
`COMPONENT_TEMPLATES_DIR` (or similar) — but realistically, the only
script that needs to know about templates is `ws-component.sh` itself,
which can compute `$ROOT_DIR/templates/components` directly. No changes
to `ws-realm.sh`.

### `scripts/ws` router

Add a `component)` case routing to `ws-component.sh`. Add help-block
entries for `component init [flavor] [name]`. Mirrors the existing
`hoard)` and `realm)` routing.

### `.claude/settings.json`

Add explicit allowlist entries for safe `ws component` invocations
(mirrors the post-CodeRabbit-review tightening for `ws hoard`):

```json
"Bash(ws component)",
"Bash(ws component --help)",
"Bash(ws component -h)",
"Bash(ws component init *)",
"Bash(ws component init * *)",
"Bash(ws component init * * *)"
```

URL-fetch forms (none planned for `ws component` v1) would stay out of
Safe per the same rationale as `ws hoard <url>`.

---

## Documentation Updates

- **`AGENTS.md`** — add `ws component` to the workspace-CLI list. Brief
  "Component templates" subsection mirroring the Hoards section.
- **`CLAUDE.md`** — `ws component` added to the available commands
  inventory.
- **`docs/ws-cli-guide.md`** — `component init` added to the Safe-tier
  table (mirroring `realm init` and `hoard init`). New section under
  the `ws hoard init` description for `ws component init` semantics.
- **`docs/getting-started/index.md`** — add the
  Template/Instance/Tutorial vocabulary section. Update the newcomer
  flow to point at `ws component init gh-pages` as the recommended
  starting point.
- **`templates/README.md`** — extend the table to list `components/`
  subdirectory; mention that the leaf-to-directory promotion pattern
  applies.

---

## Migration / Impact

Pure additive — no existing scripts, configs, or files change behavior.
Realms without component templates (e.g. third-party realms not yet
updated) keep working unchanged. The new `ws component` command
appears in `ws help` automatically once the route lands.

No `.gitignore` change needed. Components scaffolded into
`components/<name>/` are gitignored by the existing `/components/*`
rule.

---

## Future Directions

- **Additional template flavors** (sub-project B). Frontend, backend,
  full-stack mini, MCP server. Each is small once the plumbing is
  shipped — landing them as separate small PRs preserves review
  granularity.
- **Mentoring-mode integration** (sub-project C). Update
  `gdd-mentoring/SKILL.md` so the new tutorial path is its natural
  entry point. Includes the "spot a future-work item, offer to capture
  a Thalamus todo" pattern that came up in this brainstorm — broader
  than just templates.
- **Mermaid diagrams** (sub-project E). Architecture diagram with
  realms / hoards / components / templates as labeled boxes; flow
  diagram for the `init`-and-merge process. Belongs in
  `docs/ecosystem-architecture.md` and the getting-started arc.
- **Single-question wizard expansion.** When `name` is omitted on a
  tty, today's design prompts. Future flavors might want more wizard
  questions (e.g. "include a license? [MIT/Apache-2.0/none]"). The
  wizard machinery generalizes naturally — start with one prompt,
  graduate to a per-flavor question list when needed.
- **Template-metadata files.** When per-template flag handling
  graduates beyond hardcoded `case` blocks, introduce
  `templates/components/<flavor>/template.yaml` declaring accepted
  flags, defaults, and prompts. Same pattern works for hoards.
- **External / fetched templates.** `templates/external/` is reserved
  by the realms-and-hoards work. A future `ws template fetch <url>`
  could place templates there for trial use. Not in v1.
- **Backstage / CookieCutter integration.** Both ecosystems already
  solve parameterized scaffolding at a level richer than our `cp -R`.
  A long-term direction: depend on one of them so the same template
  artifacts work in `ws component init` AND in Backstage's catalog
  scaffolder, getting visualization for free. Ties into the broader
  Backstage thread already noted in Thalamus observations alongside
  Heimdall observability and Vordu's BDD roadmap visualization.
- **Auto-detect adapter co-shipping.** A future flavor may want to ship
  a sample adapter file (`templates/components/<flavor>/adapter.yaml`)
  that init copies into the realm's `adapters/` directory. v1 doesn't
  need this — `gh-pages` has no build commands worth wiring.
- **Full multi-realm inheritance** (already noted in realms-and-hoards
  Future Directions). Component template handling would generalize
  identically across multi-realm chains since the merge is the same.

---

## User Experience

### New user, first GDD session, soft-GA flow

```bash
git clone https://github.com/SiliconSaga/yggdrasil.git
cd yggdrasil
ws realm init                    # (or skip — realm-template ships)
ws component init gh-pages my-page

# Suggested commands printed by init:
gh repo create cervator/my-page --public \
  --source=components/my-page --remote=cervator --push

# Open in browser, click through Settings → Pages → enable, wait 1 min.
# Visit cervator.github.io/my-page

# First edit (from yggdrasil root):
git -C components/my-page checkout -b first-post
# ... edit components/my-page/index.md ...
# ... write .commits/first-post.md bodyfile (message + add: index.md) ...
ws commit my-page .commits/first-post.md
ws push my-page first-post
gh pr create --fill

# Watch CodeRabbit review the PR. Address feedback. Merge. Refresh page.
```

Three commands plus a couple of git operations. The README walks each
step in detail for solo users.

### Existing community member adds a personal sandbox component

```bash
cd yggdrasil
ws component init gh-pages sandbox
# Component is local-only (in ecosystem.local.yaml), invisible to
# other workspace clones. Push and open a PR as above.
```

### Upstreaming a local-only component into the realm

Manual step (deliberate). User opens the realm repo, copies the entry
from `ecosystem.local.yaml` into `realms/<realm>/ecosystem.yaml` with
realm-appropriate fields filled in (tier, chartVersion, etc.), then
commits the realm. The local entry can be deleted at that point or
left in place (the merge prefers the local layer; harmless duplication).

A future `ws component upstream <name>` could automate this step. Not
in v1.
