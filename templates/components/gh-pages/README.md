# Your GitHub Pages site

> **You can ask your AI agent to walk you through any step below, or
> follow this guide directly. Both paths arrive at roughly the same
> place.** The agent is non-deterministic; this guide is the
> deterministic path. They do the same thing in spirit.
>
> **First time through? Turn on mentoring for Chapter 1.** Ask your
> agent: *"let's turn on mentoring while I work through this
> tutorial."* Mentoring explains each command and decision in
> detail rather than just running them — invaluable for the first
> deploy where every `ws` subcommand is new. The orientation skill
> should already offer this when it sees you've started a tutorial;
> if not, just ask. Once you reach Chapter 2, the agent can ease off
> the per-command narration — the basics are familiar by then, and
> the bot-review loop is the focus.

This is a starter site scaffolded from the GDD `gh-pages` component
template. It deploys to GitHub Pages as-is, lets you exercise the
full GDD-and-bot-review workflow with a tiny live target, and is
meant to be edited from day one.

The walkthrough is split into chapters so you can stop after Ch 1
with a working live site, then come back for Ch 2 (bots) and Ch 3+
(theming, custom domain, going further) when you're ready.

---

# Chapter 1: First deploy

Goal: from `ws component init` to a live site you've edited, in
roughly 10–15 minutes. No third-party apps to install yet. Pure GDD
loop on a tiny target.

## 1. Create the GitHub repo

After `ws component init gh-pages <name>` finished, the suggested
next step it printed was something like:

```bash
gh repo create <yourname>/<name> --public \
  --source=components/<name> --remote=<yourname> --push
```

Run that. It creates a public repo on your GitHub account, sets
your username as the remote name (avoids the generic `origin`),
and pushes the initial commit.

> **Why public?** Free GitHub Pages on personal accounts requires a
> public repo. A private Pages site is paid (GitHub Pro / Team /
> Enterprise). If you want it private, swap `--public` for
> `--private` in the suggested command and accept the cost on your
> end.
>
> **Auth wrinkle for agent-account tokens.** If your `.env` holds a
> bot/agent token (e.g. one issued to `agent-refr`) rather than a
> personal PAT, `gh repo create <yourname>/<name>` may fail with
> *"cannot create a repository for `<yourname>`"* — the agent
> identity can't create repos under your username. **Recommended
> fix:** open a fresh shell, `export GH_TOKEN=<your-personal-pat>`,
> and run the create command under your personal token. The
> tutorial repo lives under your account — that's what Chapter 2's
> CodeRabbit/Copilot install assumes (you need admin on the repo's
> account to install GitHub Apps), and what `<yourname>.github.io`
> deploys reflect.
>
> Creating the repo under the agent's namespace
> (`gh repo create <agent-account>/<name>`) is a stopgap **only**
> if you also administer that namespace yourself (rare). Otherwise
> Chapter 2 stalls — you can't install CodeRabbit on an account you
> don't control, so the bot-reviewed half of the tutorial becomes
> impossible to complete.

If you'd rather create the repo by hand:

1. Go to `https://github.com/new` while signed in.
2. Repository name: `<name>` (matching the directory). Public.
3. Skip the README / .gitignore / license options — your scaffold
   already has them.
4. Click **Create repository**.
5. Back in your terminal, set the remote and push (`ws push` wires
   up upstream tracking automatically on the first push, so
   subsequent `ws push <name>` calls work without arguments):

   ```bash
   git -C components/<name> remote add <yourname> https://github.com/<yourname>/<name>.git
   ws push <name> main
   ```

## 2. Enable GitHub Pages

GitHub doesn't auto-enable Pages on new repos. You enable it once.
Two equivalent paths:

**Via the UI** (most common, more discoverable):

1. In your new repo on GitHub, click **Settings** (top nav).
2. In the left sidebar, click **Pages** (under "Code and
   automation").
3. Under **Source**, choose **Deploy from a branch**.
4. Under **Branch**, pick `main` and folder `/ (root)`.
   Click **Save**.

**Via `gh api`** (one-liner, useful for scripted setups). Note
the path has no leading `/` — Windows Git Bash's MSYS layer
otherwise rewrites `/repos/...` as a Windows filesystem path:

```bash
gh api -X POST repos/<yourname>/<name>/pages \
  --raw-field 'source[branch]=main' \
  --raw-field 'source[path]=/'
```

Either way, wait ~1 minute. Refresh the Pages settings page; it'll
show a green banner with the URL once the first build is done.

Your site lives at `https://<yourname>.github.io/<name>/`. Visit it
and you should see the placeholder page.

## 3. Make your first edit (and clean up placeholders)

The point of the demo is to feel the full GDD loop — write,
propose, merge — on a tiny target. The walkthrough below stays in
the yggdrasil workspace root throughout (no `cd`-juggling), since
`ws` operates on components by name from there.

The scaffold ships with a few literal placeholders that are
**visible on the live site immediately** — clean these up in your
first edit so the deployed page doesn't render something like
`<your name> — GDD tutorial test | 's page` in the browser tab.

**1. Create your topic branch:**

```bash
git -C components/<name> checkout -b first-post
```

(Branch creation is git's job; `ws` doesn't wrap it.)

**2. Edit the home page and replace placeholders.** Open the
following files in your editor and replace the `<...>` placeholders
with real values:

| File | Placeholder | Replace with |
|------|-------------|--------------|
| `components/<name>/_config.yml` | `title: <your name>'s page` | Your real title (e.g. `title: Cervator's page`) |
| `components/<name>/index.md` | front-matter `title: <your name>'s page` | Same — usually matches `_config.yml` |
| `components/<name>/index.md` | the placeholder paragraph in the body | Whatever you want the home page to say |
| `components/<name>/LICENSE` | `Copyright (c) <year> <name>` | The current year and your name |

The agent can fill these in based on your `identity.human_account`
if you'd rather not edit by hand — just ask.

**3. Write a commit bodyfile.** `ws commit` is bodyfile-driven —
every commit declares the files it stages, so there's no separate
`git add` step. Create `.commits/first-post.md` *in the yggdrasil
workspace root* (the `.commits/` directory is gitignored at the
workspace level) with this content:

```markdown
---
message: "First post + placeholder cleanup"
add:
  - _config.yml
  - index.md
  - LICENSE
---
First edit on the new GitHub Pages site. Replaced placeholder
title, copyright, and home-page body.
```

The `add:` paths are relative to the component, not the workspace
root — `ws commit` cd's into `components/<name>/` before staging.
The body below the frontmatter becomes the commit message body.

**4. Commit and push:**

```bash
ws commit <name> .commits/first-post.md
ws push <name> first-post
```

`ws commit` stages the listed files, builds the message, and
appends a Co-Authored-By trailer. `ws push` picks the right remote
from your identity config.

## 4. Open a (simple) PR

Chapter 1 keeps the PR step simple — open it, merge it, see it
live. Bot review comes in Chapter 2.

Like `ws commit`, `ws cr` is bodyfile-driven. Copy the change
template to `.crs/first-post.md` *in the yggdrasil workspace root*
(gitignored) and fill in the summary:

```bash
cp templates/change.md .crs/first-post.md
$EDITOR .crs/first-post.md
```

Replace the bracketed placeholder under **Summary** with one bullet
describing the edit, and either keep the **Test plan** as-is
(loading the deployed site is the test) or trim it. The
`@HUMAN_ACCOUNT` / `@GDD_HOME` markers in the body are substituted
at CR-creation time from your identity config.

Open the PR:

```bash
ws cr <name> "First post + placeholder cleanup" .crs/first-post.md
```

`ws cr` picks the right remote from your identity, runs the
underlying `gh pr create`, and prints the PR URL.

## 5. Merge and see it live

1. Click **Merge pull request** on the PR, then **Create a merge
   commit**. The GDD convention is to keep the original commit
   (with its body and Co-Authored-By trailer) in `main` history
   rather than collapse it via *Squash and merge* — the trail is
   more useful when you're scanning history later, and AI-pair-
   programming attribution stays intact.
2. GitHub Pages rebuilds the site within a minute or so. There's
   no click required — the rebuild fires on every push to `main`.
3. Refresh `https://<yourname>.github.io/<name>/`. Your edit is
   live, the placeholders are gone, and the browser tab shows your
   real title.

**That's Chapter 1.** You've cloned, scaffolded, deployed, edited,
opened a PR, and merged — the whole no-bots GDD loop. Stop here
for now if you like. Come back to Chapter 2 when you want to add
the bot-review layer.

---

# Chapter 2: Bot-reviewed PRs

Goal: install CodeRabbit (and optionally Copilot review), push a
follow-up edit, and watch the bots leave inline review threads.
This is where GDD's review loop really earns its keep.

> By Chapter 2 the basic `ws` commands (`commit`, `push`, `cr`,
> `review`) are familiar from Chapter 1. Mentoring can ease
> off — the agent doesn't need to re-narrate them in the same
> detail. The new material is the bot side: installation, what they
> look for, how to read and resolve review threads.

## 1. Install CodeRabbit

CodeRabbit is a GitHub App. Free for public repos.

1. Visit https://github.com/marketplace/coderabbit
2. Click **Set up a plan** → pick the free tier for public repos.
3. Choose the repos you want it to review. Either install on your
   personal account (covers all your public repos) or scope it to
   the tutorial repo specifically.
4. Authorize the app's permissions.

> **Why this is its own chapter:** if your tutorial repo is on a
> bot/agent account (not your personal namespace), the App install
> needs to happen on whichever account hosts the repo. A fresh user
> shouldn't have to authorise a third-party app just to ship a
> first deploy — that's why Chapter 1 skipped it.
>
> **If your Ch 1 repo ended up under an agent namespace** you don't
> administer, Chapter 2 is blocked here — you can't install
> CodeRabbit on someone else's account. Re-create the tutorial repo
> under your personal account first (per the Ch 1 §1 auth wrinkle):
> `export GH_TOKEN=<your-personal-pat>` in a fresh shell, then
> `gh repo create <yourname>/<name> --public --source=components/<name> --remote=<yourname> --push`,
> then come back here.

## 2. Optional: enable Copilot review

If you have a GitHub Copilot subscription, you can also request
Copilot's review on PRs:

- On the PR page, click the gear icon next to **Reviewers**.
- Choose **GitHub Copilot**.
- Copilot doesn't re-review automatically on every push — click
  **Re-request review** in the same panel after addressing
  feedback.

Copilot's findings often complement CodeRabbit's; they catch
different things. Worth running both if you have access.

## 3. Push a second edit

Make a fresh topic branch and edit something visible — adding a
new page or a paragraph works well:

```bash
git -C components/<name> checkout main
git -C components/<name> pull <yourname> main
git -C components/<name> checkout -b second-post
$EDITOR components/<name>/index.md
```

Then the now-familiar Chapter 1 cycle:

```bash
# Write .commits/second-post.md (frontmatter + body — see Ch 1 §3.3)
ws commit <name> .commits/second-post.md
ws push <name> second-post

# Write .crs/second-post.md (cp templates/change.md, fill in)
ws cr <name> "Second post" .crs/second-post.md
```

## 4. Read and address review threads

Within a couple of minutes, CodeRabbit will post inline comments
on the PR. Fetch them in one shell view:

```bash
ws review <name> <pr#>
```

The output groups inline diff comments by file, plus a summary at
the bottom. For each finding, decide:

- **Address it.** Edit the file, write a fixup bodyfile, `ws
  commit` and `ws push` — CodeRabbit auto-resolves the thread when
  the next commit lands.
- **Reply with reasoning.** `ws review <name> reply <pr#> <thread-id>
  "<message>" --resolve` lets you respond and close the thread in
  one go.
- **Decline.** Sometimes the bot's suggestion isn't right.
  Reply explaining why, mark resolved, move on.

Repeat the push/review cycle until the bots are quiet.

## 5. Merge

Same as Chapter 1 — **Merge pull request** → **Create a merge
commit**. Your second edit deploys within a minute.

**That's Chapter 2.** From here on you've got the review loop in
muscle memory: edit → commit → push → cr → review → fix → merge.
The same flow scales to real components.

---

# Chapter 3+: Going further

The template stays minimal so you can take it where you want. A
few common next steps, in roughly increasing complexity:

- **Different theme.** Edit the `theme:` line in `_config.yml`. The
  comments next to that line list other GitHub-supported themes
  you can pick from. For richer theming (custom CSS, layouts),
  you'd either fork a Jekyll theme repo or move to a different
  static-site generator (Astro, VitePress, 11ty, Hugo). Ask your
  agent to walk you through whichever path interests you — *or
  capture a Thalamus todo about the theme work and come back to it
  later when you have ideas*.
- **More pages.** Add `<page-name>.md` files alongside `index.md`,
  link from `index.md` (Markdown links: `[About](about.md)`).
- **Custom domain.** Drop a `CNAME` file at the repo root
  containing your domain. Configure DNS to point at GitHub Pages'
  servers (instructions in your domain registrar's docs + GitHub's
  [custom domain guide](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site)).
- **Comments / analytics / search.** Each is a separate add-on
  with its own setup. Ask your agent for the typical patterns —
  Disqus or utterances for comments, GoatCounter or Plausible for
  cookieless analytics, lunr or Algolia for search.

Each of these is more involved than the Chapter 1+2 loop and
benefits from breaking into its own PR with its own review cycle.
The basic shape doesn't change — you've already practiced it.

---

## What's in this directory

- `index.md` — the home page you edited in Ch 1
- `_config.yml` — Jekyll config (title, theme)
- `README.md` — this file
- `.gitignore` — keeps Jekyll's local build output out of git
- `LICENSE` — MIT, with placeholders you replaced in Ch 1

The component is registered in your workspace's
`ecosystem.local.yaml` under `components.<name>` so `ws status`,
`ws push <name>`, `ws log <name>`, etc. all work from the
yggdrasil root. To share this component with your community, move
that `ecosystem.local.yaml` entry into your realm's
`ecosystem.yaml` with realm-appropriate fields (tier, etc.) and
push the realm.
