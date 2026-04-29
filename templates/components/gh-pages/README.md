# Your GitHub Pages site

> **You can ask your AI agent to walk you through any step below, or
> follow this guide directly. Both paths arrive at roughly the same
> place.** The agent is non-deterministic; this guide is the
> deterministic path. They do the same thing in spirit.

This is a starter site scaffolded from the GDD `gh-pages` component
template. It deploys to GitHub Pages as-is, lets you exercise the full
GDD-and-bot-review workflow with a tiny live target, and is meant to
be edited from day one.

---

## 1. Setup checklist

After `ws component init gh-pages <name>` finished, the suggested next
step it printed was something like:

```bash
gh repo create <yourname>/<name> --public \
  --source=components/<name> --remote=<yourname> --push
```

Run that. It creates a public repo on your GitHub account, sets your
username as the remote name (avoids the generic `origin`), and pushes
the initial commit.

> **Why public?** Free GitHub Pages on personal accounts requires a
> public repo. A private Pages site is paid (GitHub Pro / Team /
> Enterprise). If you want it private, swap `--public` for `--private`
> in the suggested command and accept the cost on your end.

If you'd rather create the repo by hand:

1. Go to `https://github.com/new` while signed in.
2. Repository name: `<name>` (matching the directory). Public.
3. Skip the README / .gitignore / license options — your scaffold
   already has them.
4. Click **Create repository**.
5. Back in your terminal, set the remote and push:

   ```bash
   cd components/<name>
   git remote add <yourname> https://github.com/<yourname>/<name>.git
   git push -u <yourname> main
   ```

### Enable GitHub Pages

GitHub doesn't auto-enable Pages on new repos. You enable it once,
manually:

1. In your new repo on GitHub, click **Settings** (top nav).
2. In the left sidebar, click **Pages** (under "Code and automation").
3. Under **Source**, choose **Deploy from a branch**.
4. Under **Branch**, pick `main` and folder `/ (root)`. Click **Save**.
5. Wait ~1 minute. Refresh the Pages settings page; it'll show a green
   banner with the URL once the first build is done.

Your site lives at `https://<yourname>.github.io/<name>/`. Visit it and
you should see the placeholder page.

---

## 2. Make your first edit

The point of the demo is to feel the full GDD loop — write, propose,
review, merge — on a tiny target. The walkthrough below stays in the
yggdrasil workspace root throughout (no `cd`-juggling), since `ws`
operates on components by name from there.

**1. Create your topic branch:**

```bash
git -C components/<name> checkout -b first-post
```

(Branch creation is git's job; `ws` doesn't wrap it.)

**2. Edit the home page.** Open `components/<name>/index.md` in your
editor and replace the placeholder paragraph with whatever you want.

**3. Write a commit bodyfile.** `ws commit` is bodyfile-driven — every
commit declares the files it stages, so there's no separate `git add`
step. Create `.commits/first-post.md` *in the yggdrasil workspace root*
(the `.commits/` directory is gitignored at the workspace level) with
this content:

```markdown
---
message: "Make the home page mine"
add:
  - index.md
---
First edit on the new GitHub Pages site.
```

The `add:` paths are relative to the component, not the workspace
root — `ws commit` cd's into `components/<name>/` before staging.
The body below the frontmatter becomes the commit message body.

**4. Commit and push:**

```bash
ws commit <name> .commits/first-post.md
ws push <name> first-post
```

`ws commit` stages the listed files, builds the message, and appends a
Co-Authored-By trailer. `ws push` picks the right remote from your
identity config.

---

## 3. Open a PR and watch the bots

Like `ws commit`, `ws cr` is bodyfile-driven. Copy the change template to
`.crs/first-post.md` *in the yggdrasil workspace root* (gitignored) and
fill in the summary:

```bash
cp templates/change.md .crs/first-post.md
$EDITOR .crs/first-post.md
```

Replace the bracketed placeholder under **Summary** with one bullet
describing the edit, and either keep the **Test plan** as-is (loading
the deployed site is the test) or trim it. The `@HUMAN_ACCOUNT` /
`@GDD_HOME` markers in the body are substituted at CR-creation time
from your identity config.

Open the PR:

```bash
ws cr <name> "Make the home page mine" .crs/first-post.md
```

`ws cr` picks the right remote from your identity, runs the underlying
`gh pr create`, and prints the PR URL.

Now wait for the reviewers:

- **CodeRabbit** posts a review usually within a couple of minutes.
  If you don't see one, install the [CodeRabbit GitHub App](https://github.com/marketplace/coderabbit)
  on your account first; it's free for public repos.
- **GitHub Copilot review**, if you have a Copilot subscription, can
  be requested from the PR's **Reviewers** panel — click the gear icon
  next to "Reviewers" and choose "GitHub Copilot". Copilot doesn't
  re-review automatically on every push; if you want a second pass
  after addressing feedback, click "Re-request review" in the same
  panel.

You'll see review threads appear inline in the diff. CodeRabbit's
review tends to be detailed; for a one-paragraph change it might just
suggest a wording tweak or note that everything looks fine.

---

## 4. Merge and see it live

Once you're happy with the review thread responses (or there's nothing
to address):

1. Click **Merge pull request** on the PR, then **Create a merge
   commit**. The GDD convention is to keep the original commit (with
   its body and Co-Authored-By trailer) in `main` history rather than
   collapse it via *Squash and merge* — the trail is more useful when
   you're scanning history later, and AI-pair-programming attribution
   stays intact.
2. GitHub Pages rebuilds the site within a minute or so. There's no
   click required — the rebuild fires on every push to `main`.
3. Refresh `https://<yourname>.github.io/<name>/`. Your edit is live.

That's the whole loop.

---

## 5. Going further

The template stays minimal so you can take it where you want. A few
common next steps:

- **Fill in the placeholders.** A few files ship with literal
  `<your name>` / `<year>` / `<name>` placeholders meant for you to
  edit: the `title:` line in `_config.yml`, the front-matter `title:`
  in `index.md`, and the `Copyright (c) <year> <name>` line in
  `LICENSE`. Replace them whenever you're ready (or ask your agent to
  fill them in based on your `identity.human_account`).
- **Different theme.** Edit the `theme:` line in `_config.yml`. The
  comments next to that line list other GitHub-supported themes you
  can pick from. For richer theming (custom CSS, layouts), you'd
  either fork a Jekyll theme repo or move to a different static-site
  generator (Astro, VitePress, 11ty, Hugo). Ask your agent to walk
  you through whichever path interests you — *or capture a Thalamus
  todo about the theme work and come back to it later when you have
  ideas*.
- **Custom domain.** Drop a `CNAME` file at the repo root containing
  your domain. Configure DNS to point at GitHub Pages' servers
  (instructions in your domain registrar's docs + GitHub's [custom
  domain guide](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site)).
- **More pages.** Add `<page-name>.md` files alongside `index.md`,
  link from `index.md` (Markdown links: `[About](about.md)`).
- **Comments / analytics / search.** Each is a separate add-on with
  its own setup. Ask your agent for the typical patterns — Disqus or
  utterances for comments, GoatCounter or Plausible for cookieless
  analytics, lunr or Algolia for search.

---

## What's in this directory

- `index.md` — the home page you're editing
- `_config.yml` — Jekyll config (title, theme)
- `README.md` — this file
- `.gitignore` — keeps Jekyll's local build output out of git
- `LICENSE` — MIT placeholder; replace or leave as-is once your repo
  is the source of truth

The component is registered in your workspace's `ecosystem.local.yaml`
under `components.<name>` so `ws status`, `ws push <name>`, `ws log
<name>`, etc. all work from the yggdrasil root. To share this
component with your community, move that `ecosystem.local.yaml` entry
into your realm's `ecosystem.yaml` with realm-appropriate fields
(tier, etc.) and push the realm.
