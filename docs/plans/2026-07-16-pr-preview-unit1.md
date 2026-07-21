# PR Preview Publisher (Unit 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every same-repository pull request to `ken-site` gets a live preview of its build at a URL, posted as a sticky comment, and removed when the PR closes. (Fork PRs are unsupported by design — see Scope.)

**Architecture:** GitHub Pages serves one site per repo, so previews live *inside* the production site's tree on a `gh-pages` branch: production at `/`, previews at `/pr-preview/pr-<N>/`. `main` becomes source-only; workflows build it. All publishing is plain `git` on the runner — no third-party *publishing* actions or services, no PAT, no secrets beyond the built-in `GITHUB_TOKEN`. (Toolchain setup uses the GitHub-maintained `actions/*` and `ruby/setup-ruby` actions; the restriction is about who holds publish credentials, not about setup helpers.)

**Tech Stack:** GitHub Actions, Ruby 3.3 + Jekyll (`github-pages` gem), `gh` CLI (preinstalled on runners), plain `git`.

## Global Constraints

- **All-GitHub.** No Netlify/Vercel/Cloudflare, no SaaS, no third-party signup.
- **No secrets beyond `GITHUB_TOKEN`.** No PAT. Same-repo writes only.
- **No LLM/API key.** This pipeline is vanilla CI.
- **Production should not break, but this is not yet the official campaign site.** `gibbonsforwestorange.com` still points at the original build; the Pages site is a review copy. Verify production anyway (a broken `baseurl` is the likeliest failure and would go unnoticed otherwise) — but no change freeze is warranted, and the rollback is one API call.
- Repo: `SiliconSaga/ken-site`. Production URL: `https://siliconsaga.github.io/ken-site/`.
- Production `baseurl` stays `/ken-site` (already in `_config.yml`) — unchanged by this work.
- Preview `baseurl` is `/ken-site/pr-preview/pr-<N>`.
- Component path in the workspace: `components/ken-site/` (its own git repo).
- Commit via `ws commit ken-site <bodyfile>`; push via `ws push ken-site <branch>`; PRs via `ws cr ken-site "<title>" <bodyfile>`.
- `<N>` in verification commands means the real PR number — substitute it.
- Raw `git -C components/ken-site …` appears only where `ws` deliberately has no wrapper (branch creation, fetch/ls-tree inspection); commits, pushes, and CRs go through `ws` per the workspace convention.

## Scope

**In:** production build→`gh-pages` migration, PR preview publish, sticky comment, cleanup on close.

**Out (deliberately):**
- **Unit 2** (screenshots + visual diff) — separate plan.
- **`prefers-reduced-motion`** support in the site — a Unit 2 precondition; valuable on its own, not needed for previews.
- **Graduation into `templates/components/gh-pages/`** — deferred until Unit 2 lands so the template is ported **once**, not twice. Tracked as the design's success criterion 7.
- **Fork PRs** — a fork's token cannot write `gh-pages`. Unsupported by design.

## A note on testing

This is CI plumbing. There is no meaningful unit test for a workflow file: the thing under test *is* the interaction between GitHub's event model, a runner, and a branch. Each task is therefore verified by an **integration check against real GitHub**, with exact commands and expected output.

Do not fake a unit-test cycle here. Verify by observing the real system.

**Every verification includes a CSS check.** A broken `baseurl` still returns `200` on the page itself — it just renders unstyled. Only the stylesheet request proves the path resolved. Never skip it.

## File Structure

| File | Responsibility |
|---|---|
| `components/ken-site/.github/workflows/deploy.yml` | On push to `main`: build, publish to `gh-pages:/`, preserving `pr-preview/`. Creates `gh-pages` on first run. |
| `components/ken-site/.github/workflows/pr-preview.yml` | On PR open/sync: build with preview `baseurl`, publish to `gh-pages:/pr-preview/pr-<N>/`, upsert a sticky comment. On close: remove it. |
| `components/ken-site/Gemfile.lock` | Committed (newly) so CI builds are pinned and cacheable. |
| `components/ken-site/.gitignore` | Modify: stop ignoring `Gemfile.lock`. |

Both workflows write the same branch, so they share one concurrency group (`gh-pages-write`, `cancel-in-progress: false`) to serialize pushes.

---

### Task 1: Migrate production to `gh-pages`

The step with the most moving parts. It ships alone and is verified before anything else exists — not because the site is load-bearing yet (it isn't; the real domain still points elsewhere), but because a `baseurl` or `.nojekyll` mistake here is invisible until it breaks Task 2 in a confusing way.

**Files:**
- Create: `components/ken-site/.github/workflows/deploy.yml`
- Create: `components/ken-site/Gemfile.lock` (commit the generated one)
- Modify: `components/ken-site/.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a `gh-pages` branch whose root is the built site and which contains `.nojekyll`; Pages serving `gh-pages`/root. Task 2 relies on `gh-pages` existing and on `pr-preview/` being preserved by this workflow.

- [ ] **Step 1: Generate and un-ignore the lockfile**

```bash
ws exec ken-site bundle install
```

Edit `components/ken-site/.gitignore` — delete the `Gemfile.lock` line so the Bundler block reads exactly:

```gitignore
# Bundler artifacts (only present if you decide to run Jekyll locally)
.bundle/
vendor/
```

- [ ] **Step 2: Write the production deploy workflow**

Create `components/ken-site/.github/workflows/deploy.yml`:

```yaml
name: Deploy site

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: gh-pages-write
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Build
        run: bundle exec jekyll build
        env:
          JEKYLL_ENV: production

      - name: Publish to gh-pages (preserving PR previews)
        run: |
          set -euo pipefail
          git config --global user.name  "github-actions[bot]"
          git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

          # Attach a worktree to gh-pages, creating the branch on first run.
          if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
            git fetch origin gh-pages:refs/remotes/origin/gh-pages
            git worktree add -B gh-pages ../ghp origin/gh-pages
          else
            echo "gh-pages does not exist yet — creating it."
            git worktree add --detach ../ghp
            git -C ../ghp checkout --orphan gh-pages
            git -C ../ghp rm -rf --cached . >/dev/null 2>&1 || true
            find ../ghp -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
          fi

          # Replace the production tree, but never touch previews.
          find ../ghp -mindepth 1 -maxdepth 1 \
            ! -name .git ! -name pr-preview -exec rm -rf {} +
          cp -r _site/. ../ghp/
          touch ../ghp/.nojekyll

          cd ../ghp
          git add -A
          git commit -m "deploy: ${GITHUB_SHA::7}" || { echo "No changes to publish."; exit 0; }
          for i in 1 2 3; do
            git push origin gh-pages && exit 0
            git pull --rebase origin gh-pages
          done
          echo "Failed to push after 3 attempts." >&2
          exit 1
```

> **`.nojekyll` is load-bearing.** Without it GitHub runs Jekyll *again* over our already-built output, and Jekyll **ignores any path beginning with `_`** — which would silently 404 Unit 2's `_diff/` directory later. Do not omit it.

- [ ] **Step 3: Write the commit bodyfile**

Create `.commits/ken-deploy.md` in the **workspace root**:

```markdown
---
message: "ci: build and publish the site to gh-pages"
add:
  - .github/workflows/deploy.yml
  - .gitignore
  - Gemfile.lock
---
Moves the site to a built-output deploy so PR previews can coexist with
production on the one Pages site (Pages serves one site per repo).

main becomes source-only; this workflow builds it and publishes to
gh-pages, preserving any pr-preview/ directories. .nojekyll stops GitHub
re-running Jekyll over already-built output, which would drop
underscore-prefixed paths. Gemfile.lock is now committed so CI builds are
pinned rather than resolved fresh on every run.
```

- [ ] **Step 4: Write the CR bodyfile**

```bash
cp templates/change.md .crs/ken-deploy.md
```

Replace the bracketed **Summary** placeholder with:

```markdown
- Build the site in CI and publish to `gh-pages`; `main` becomes source-only.
- Preserve `pr-preview/` on deploy so PR previews (next PR) can coexist with production.
- Add `.nojekyll` so GitHub serves built output as-is.
- Commit `Gemfile.lock` for reproducible CI builds.
```

For the **Test plan**, use:

```markdown
- Merge, confirm the `Deploy site` run succeeds and `gh-pages` holds built output.
- Flip the Pages source to `gh-pages`/root.
- Confirm `https://siliconsaga.github.io/ken-site/` and its `assets/css/site.css` both return 200.
```

- [ ] **Step 5: Branch, commit, push, open the PR**

```bash
git -C components/ken-site checkout -b ci/deploy-to-gh-pages
ws commit ken-site .commits/ken-deploy.md
ws push ken-site ci/deploy-to-gh-pages
ws cr ken-site "ci: build and publish the site to gh-pages" .crs/ken-deploy.md
```

- [ ] **Step 6: Merge, then confirm the workflow published `gh-pages`**

After merging the PR:

```bash
ws gh api "repos/SiliconSaga/ken-site/actions/runs?branch=main" --jq '[.workflow_runs[] | select(.name == "Deploy site")][0] | .name + " " + .status + " " + .conclusion'
```

(The name+branch filter matters — bare `workflow_runs[0]` is the newest run repository-wide and can belong to a different workflow or event.)

Expected: `Deploy site completed success`

```bash
git -C components/ken-site fetch SiliconSaga gh-pages
git -C components/ken-site ls-tree --name-only SiliconSaga/gh-pages
```

Expected: `.nojekyll`, `index.html`, `assets`, `about`, `news`, … — built output. **Not** `_config.yml`, `Gemfile`, or `*.md` sources. If you see sources, the build or the copy is wrong; stop and fix before Step 7.

- [ ] **Step 7: Flip the Pages source to `gh-pages`/root**

```bash
ws gh api -X PUT repos/SiliconSaga/ken-site/pages \
  --raw-field 'source[branch]=gh-pages' \
  --raw-field 'source[path]=/'
```

- [ ] **Step 8: Verify production is intact — the gate for this task**

```bash
ws gh api repos/SiliconSaga/ken-site/pages/builds/latest --jq '.status'
```

Expected: `built`

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/assets/css/site.css
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/news/campaign-launch/
```

Expected: `200`, `200`, `200`.

> **Rollback:** if production is wrong, restore the old source immediately:
> ```bash
> ws gh api -X PUT repos/SiliconSaga/ken-site/pages \
>   --raw-field 'source[branch]=main' --raw-field 'source[path]=/'
> ```
> The `gh-pages` branch is inert once unreferenced; nothing else needs undoing.

---

### Task 2: Publish a preview on PR open/sync

**Files:**
- Create: `components/ken-site/.github/workflows/pr-preview.yml`

**Interfaces:**
- Consumes: the `gh-pages` branch and the preserved-`pr-preview/` guarantee from Task 1.
- Produces: a preview at `https://siliconsaga.github.io/ken-site/pr-preview/pr-<N>/`, and a sticky comment whose body's **first line** is the literal marker `<!-- pr-preview -->`. Task 3 finds and rewrites that comment by that exact marker.

- [ ] **Step 1: Write the preview workflow**

Create `components/ken-site/.github/workflows/pr-preview.yml`:

```yaml
name: PR preview

on:
  pull_request:
    types: [opened, synchronize, reopened]

# Build and publish are separate jobs BY DESIGN: `jekyll build` executes
# PR-controlled code (Gemfile, plugins), so the build job runs with a
# read-only token and no persisted git credentials. Only the publish job
# — which executes nothing from the PR, it just moves the built artifact
# — holds write permissions. A malicious build step therefore has no
# credential capable of touching gh-pages.
permissions:
  contents: read

concurrency:
  group: gh-pages-write
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      PR: ${{ github.event.number }}
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Build with the preview baseurl
        run: bundle exec jekyll build --baseurl "/ken-site/pr-preview/pr-${PR}"

      - uses: actions/upload-artifact@v4
        with:
          name: preview-site
          path: _site/

  publish:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    env:
      PR: ${{ github.event.number }}
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: gh-pages

      - uses: actions/download-artifact@v4
        with:
          name: preview-site
          path: _site

      - name: Publish the preview
        run: |
          set -euo pipefail
          git config --global user.name  "github-actions[bot]"
          git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
          rm -rf "pr-preview/pr-${PR}"
          mkdir -p "pr-preview/pr-${PR}"
          cp -r _site/. "pr-preview/pr-${PR}/"
          rm -rf _site
          git add -A -- "pr-preview/pr-${PR}"
          git commit -m "preview: PR #${PR} (${GITHUB_SHA::7})" || { echo "No preview changes."; exit 0; }
          for i in 1 2 3; do
            git push origin gh-pages && exit 0
            git pull --rebase origin gh-pages
          done
          echo "Failed to push after 3 attempts." >&2
          exit 1

      - name: Upsert the sticky comment
        run: |
          set -euo pipefail
          URL="https://siliconsaga.github.io/ken-site/pr-preview/pr-${PR}/"
          BODY="<!-- pr-preview -->
### 🔎 Preview this change

**[Open the preview site](${URL})**

Built from \`${GITHUB_SHA::7}\`. Updates on every push. Removed when this PR closes."
          ID=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" \
                --jq 'map(select(.body | startswith("<!-- pr-preview -->"))) | .[0].id // empty')
          if [ -n "$ID" ]; then
            gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${ID}" -f body="$BODY" >/dev/null
          else
            gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" -f body="$BODY" >/dev/null
          fi
```

> Pages takes ~1 minute to publish after the push, so the comment can appear slightly before the URL is live. That is expected; blocking the job on a deployment poll buys nothing.

- [ ] **Step 2: Write the bodyfiles**

Create `.commits/ken-preview.md` in the workspace root:

```markdown
---
message: "ci: publish a preview site for every pull request"
add:
  - .github/workflows/pr-preview.yml
---
Builds each PR with a preview baseurl and publishes it under
pr-preview/pr-<N>/ on gh-pages, then upserts a sticky comment linking to
it. Uses the built-in GITHUB_TOKEN only — no PAT, no third-party
publishing action — and the PR-controlled build runs in a separate
read-only job from the write-capable publish job.
```

```bash
cp templates/change.md .crs/ken-preview.md
```

Replace the **Summary** placeholder with:

```markdown
- Publish a live preview of every PR under `pr-preview/pr-<N>/` on `gh-pages`.
- Post a sticky comment linking to it, updated in place on each push.
```

And the **Test plan** with:

```markdown
- Open this PR; confirm the preview URL and its CSS both return 200.
- Push again; confirm exactly one preview comment exists (updated, not duplicated).
- Confirm production still returns 200.
```

- [ ] **Step 3: Branch and open a smoke PR**

```bash
git -C components/ken-site checkout main
git -C components/ken-site pull SiliconSaga main
git -C components/ken-site checkout -b test/preview-smoke
ws commit ken-site .commits/ken-preview.md
ws push ken-site test/preview-smoke
ws cr ken-site "ci: publish a preview site for every pull request" .crs/ken-preview.md
```

- [ ] **Step 4: Verify the run succeeded**

```bash
ws gh api "repos/SiliconSaga/ken-site/actions/runs?branch=test/preview-smoke&event=pull_request" --jq '[.workflow_runs[] | select(.name == "PR preview")][0] | .name + " " + .status + " " + .conclusion'
```

Expected: `PR preview completed success`

- [ ] **Step 5: Verify the preview is live and styled**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/pr-preview/pr-<N>/
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/pr-preview/pr-<N>/assets/css/site.css
```

Expected: `200`, `200`. The CSS proves the injected `baseurl` resolved.

- [ ] **Step 6: Verify production did not regress**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/assets/css/site.css
```

Expected: `200`, `200`. This proves publishing a preview did not disturb the production tree.

- [ ] **Step 7: Verify the comment is sticky, not duplicated**

```bash
ws gh api repos/SiliconSaga/ken-site/issues/<N>/comments --jq '[.[] | select(.body | startswith("<!-- pr-preview -->"))] | length'
```

Expected: `1`

Push an empty commit and re-check:

```bash
git -C components/ken-site commit --allow-empty -m "chore: trigger a preview rebuild"
ws push ken-site test/preview-smoke
```

Re-run the count. Expected: still `1`.

---

### Task 3: Remove the preview when the PR closes

**Files:**
- Modify: `components/ken-site/.github/workflows/pr-preview.yml`

**Interfaces:**
- Consumes: the `pr-preview/pr-<N>/` layout and the `<!-- pr-preview -->` marker from Task 2.
- Produces: nothing downstream.

- [ ] **Step 1: Add `closed` to the trigger**

In `pr-preview.yml`, change:

```yaml
  pull_request:
    types: [opened, synchronize, reopened]
```

to:

```yaml
  pull_request:
    types: [opened, synchronize, reopened, closed]
```

- [ ] **Step 2: Guard the build job so it skips on close**

Add an `if` to the `build` job, directly above `runs-on` (the `publish` job follows automatically — its `needs: build` skips it when `build` skips):

```yaml
jobs:
  build:
    if: github.event.action != 'closed'
    runs-on: ubuntu-latest
```

- [ ] **Step 3: Add the cleanup job**

Append to `pr-preview.yml`:

```yaml
  cleanup:
    if: github.event.action == 'closed'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    env:
      PR: ${{ github.event.number }}
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      # Check out gh-pages directly. A closed PR's merge ref may no longer
      # exist, so a default checkout can fail — and this job needs no PR code.
      - uses: actions/checkout@v4
        with:
          ref: gh-pages

      - name: Remove the preview
        run: |
          set -euo pipefail
          git config --global user.name  "github-actions[bot]"
          git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
          # No early exit when the directory is absent — the sticky-comment
          # update below must ALWAYS run, or a manually-removed preview
          # leaves the comment pointing at a dead link forever.
          if [ -d "pr-preview/pr-${PR}" ]; then
            rm -rf "pr-preview/pr-${PR}"
            git add -A -- "pr-preview/pr-${PR}"
            git commit -m "preview: remove PR #${PR}"
            for i in 1 2 3; do
              git push origin gh-pages && break
              if [ "$i" = 3 ]; then
                echo "Failed to push after 3 attempts." >&2
                exit 1
              fi
              git pull --rebase origin gh-pages
            done
          else
            echo "No preview directory to remove; continuing to the comment update."
          fi

      - name: Update the sticky comment
        run: |
          set -euo pipefail
          BODY="<!-- pr-preview -->
### 🔎 Preview

Removed — this PR is closed."
          ID=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" \
                --jq 'map(select(.body | startswith("<!-- pr-preview -->"))) | .[0].id // empty')
          if [ -n "$ID" ]; then
            gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${ID}" -f body="$BODY" >/dev/null
          fi
```

The cleanup job inherits the workflow-level `gh-pages-write` concurrency group, so it can never race a publish.

- [ ] **Step 4: Write the bodyfile and push to the same smoke PR**

Create `.commits/ken-preview-cleanup.md`:

```markdown
---
message: "ci: remove a PR's preview when it closes"
add:
  - .github/workflows/pr-preview.yml
---
Adds a cleanup job on pull_request: closed that deletes pr-preview/pr-<N>/
from gh-pages and rewrites the sticky comment, so previews don't
accumulate on the branch forever. Checks out gh-pages directly because a
closed PR's merge ref may be gone and the job needs no PR source.
```

```bash
ws commit ken-site .commits/ken-preview-cleanup.md
ws push ken-site test/preview-smoke
```

- [ ] **Step 5: Verify the guard didn't break the happy path**

```bash
ws gh api "repos/SiliconSaga/ken-site/actions/runs?branch=test/preview-smoke&event=pull_request" --jq '[.workflow_runs[] | select(.name == "PR preview")][0] | .name + " " + .conclusion'
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/pr-preview/pr-<N>/
```

Expected: `PR preview success`, then `200`.

- [ ] **Step 6: Merge the smoke PR, then verify cleanup ran**

After merging:

```bash
ws gh api "repos/SiliconSaga/ken-site/actions/runs?branch=test/preview-smoke&event=pull_request" --jq '[.workflow_runs[] | select(.name == "PR preview")][0] | .name + " " + .conclusion'
```

Expected: `PR preview success` (the closed-event cleanup run is the newest match on this branch).

```bash
git -C components/ken-site fetch SiliconSaga gh-pages
git -C components/ken-site ls-tree --name-only SiliconSaga/gh-pages pr-preview/
```

Expected: no `pr-<N>` entry (empty output if it was the only preview).

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/pr-preview/pr-<N>/
```

Expected: `404`.

- [ ] **Step 7: Verify production survived the whole exercise**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/
curl -s -o /dev/null -w "%{http_code}\n" https://siliconsaga.github.io/ken-site/assets/css/site.css
```

Expected: `200`, `200`.

- [ ] **Step 8: Sweep the drafts**

```bash
ws clean --force
```

---

## Done means

1. Opening a PR produces a working, **styled** preview URL within ~2 minutes.
2. Pushing to that PR updates the preview and does **not** add a second comment.
3. Closing the PR removes the directory from `gh-pages` and the preview 404s.
4. `https://siliconsaga.github.io/ken-site/` and its CSS return `200` throughout.
5. No secret beyond `GITHUB_TOKEN` exists anywhere in the repo.
