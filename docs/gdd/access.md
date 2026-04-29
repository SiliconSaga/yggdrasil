# Access — identities, tokens, and remote permissions

The yggdrasil workspace runs with two distinct permission systems
that are easy to confuse but answer different questions:

| Question | Mechanism | Doc |
|----------|-----------|-----|
| *Can the agent run this **shell command** without a confirmation prompt?* | `.claude/settings.json` allowlist + Claude Code matcher | [permissions.md](permissions.md) |
| *Can the agent perform this **remote Git operation** on a repo?* | Token scope + collaborator/fork status + identity selection | this doc |

Both layers must approve an action that crosses both surfaces. A
`git push` is allowed locally (it's in the matcher's auto-allow set
or an explicit pattern), but the remote rejects it if the PAT lacks
push scope or the agent identity isn't a collaborator on the repo.
Layered defense.

This doc covers the remote layer: who the agent is, what tokens it
holds, and how the workspace's fork-and-PR pattern keeps human and
agent contributions cleanly attributed.

---

## 1. Two identities, one workspace

A GDD session typically has **two** Git identities in play:

- **The human contributor** (you). Your GitHub/GitLab username, your
  PAT for any commands you run interactively. Used for committing
  via local git config.
- **The agent identity** (e.g. `agent-refr`). A separate account
  with its own scoped PAT. Used for `ws push`, `ws cr`, `ws review`
  reply/resolve, and `gh api` calls that happen via the agent's
  tooling.

**Why separate identities?** Three reasons:

1. **Reviewable attribution.** Every commit, PR, and review thread
   is clearly authored by a human or an agent. Co-Authored-By
   trailers in commit messages preserve the pairing; the actual
   `Author:` field reflects whoever ran the operation.
2. **Scope minimization.** The agent PAT can hold *just enough*
   scope for routine work (`repo`, plus a couple of read scopes).
   The human PAT might hold more (workflow editing, package
   publishing, etc.). Compromise of the agent token is bounded.
3. **Accountability and revocation.** If something goes wrong, you
   can revoke the agent token immediately without affecting your own
   day-to-day Git access.

Setup mechanics — installing the CLI tools, generating the tokens,
loading them via `.env` — live in
[`docs/git-provider-setup.md`](../git-provider-setup.md). This doc
focuses on the *patterns* that compose those tokens with the
workspace's fork-and-PR model.

---

## 2. The `forkOrg` pattern

For repos owned by an org you're not a maintainer of (typical for
upstream open-source contribution), the workflow is:

1. The agent forks the repo under its own org (`forkOrg`).
2. `ws push <component> <branch>` pushes to that fork.
3. `ws cr <component> "<title>" <bodyfile>` opens a PR from the
   fork to the upstream.

The `forkOrg` is configured per-developer in `ecosystem.local.yaml`
under `identity.forkOrg:`. With a single remote on a component, no
disambiguation is needed; with multiple remotes (e.g. you've added
both upstream and a personal fork manually), `forkOrg` picks which
side to push to.

For repos you DO own (your personal namespace), no fork is needed —
the workspace just pushes to your remote directly.

---

## 3. The collaborator pattern (personal repos)

For personal repos — most commonly hoards (`hoards/thalami-<user>/`)
or personal components — the agent needs write access without forking.
The pattern: **add the agent identity as a collaborator** on the
GitHub repo.

Steps for a thalami hoard:

1. Create the personal repo: `gh repo create <user>/thalami-<user>
   --private --source=hoards/thalami-<user> --remote=<user> --push`.
2. Add the agent as collaborator:

   ```bash
   gh api repos/<user>/thalami-<user>/collaborators/agent-refr \
       -X PUT -f permission=push
   ```

3. The agent's PAT (which has `repo` scope) now inherits write
   access via the collaboration — `ws push thalami-<user>` works
   without needing the agent to fork your personal repo.

This pattern is key for GDD's "personal piles" story. Without it,
multi-machine thalami sync would require manual git operations from
the human's account on every machine.

---

## 4. Token scopes in practice

The agent PAT's scope set determines what it can do remotely. The
common-case minimum:

| Scope | What it enables |
|-------|-----------------|
| `repo` | Full read/write on accessible repos. PRs, issues, releases, code, branches. |
| `read:org` | Read org membership / discussion (needed for some `gh pr edit` operations on org-owned repos). |

`workflow` scope is needed only if the agent edits files under
`.github/workflows/`. Most GDD work doesn't touch CI definitions.

**Known scope-friction case:** `gh pr edit --title <title>` on an
org-owned repo requires `read:org` and `read:discussion`. If your
agent PAT doesn't have those scopes, the workaround is `gh api PATCH
repos/<owner>/<repo>/pulls/<n> --input <file>` with just `repo`
scope. (On Windows Git Bash, drop the leading `/` from the API path
to avoid MSYS path conversion rewriting it.)

When in doubt about whether a token covers an operation, run
`ws diagnose <component>` — it reports per-component remote
detection, expected token variable, and whether the token is
present and authenticated.

---

## 5. Multi-provider workflows

The workspace is provider-agnostic. A component on GitHub uses
`GH_TOKEN`; a component on GitLab uses `GITLAB_TOKEN`; a self-hosted
Forgejo or Gitea instance uses whatever variable you map under
`defaults.gitTokens` in the realm or local config.

`ws push`, `ws cr`, `ws review`, etc. all auto-detect the provider
from the component's remote URL and pick the right CLI (`gh` vs
`glab`) and the right token. Mixed-provider workspaces (some
components on GitHub, some on GitLab) work without per-command
configuration — the dispatcher handles it.

Tokens for additional providers go in `.env`:

```bash
export GH_TOKEN=ghp_xxx
export GITLAB_TOKEN=glpat_xxx
# Add more as needed for self-hosted instances
```

The mapping from provider → token variable lives in your realm's
`ecosystem.yaml` under `defaults.gitTokens`, or override per-developer
in `ecosystem.local.yaml`.

**Default behavior with no `gitTokens` entry.** For GitHub remotes,
`gh` reads `$GH_TOKEN` automatically — no `gitTokens` entry needed
in the common case. Same for GitLab: `glab` reads `$GITLAB_TOKEN`.
`ws diagnose` reports this as `✓ <VAR> is set (default for
<provider>; no gitTokens entry needed)`. You only need an explicit
`gitTokens` entry when you want **fine-grained per-namespace control**
— e.g., the org repos use the team's `GH_TOKEN` but your personal
forks under `<your-user>` should use a different `GH_TOKEN_PERSONAL`.
In that case, add a longer-prefix `gitTokens` entry that wins the
longest-prefix match for the personal namespace:

```yaml
defaults:
  gitTokens:
    github.com:                          # default for any GitHub remote
      var: GH_TOKEN
    github.com/<your-user>:              # personal forks override
      var: GH_TOKEN_PERSONAL
```

Without that entry, both namespaces flow through the same default
`GH_TOKEN` — fine for most setups; only worth splitting when the
isolation is intentional.

### GitLab specifics (gitlab.com or self-hosted)

GitLab's API model differs from GitHub's enough that the same
abstract pattern (fork → push → MR) plays out differently in
practice. Notes from real workflows on self-hosted GitLab:

**The biggest model flip:** on GitHub, `gh pr create` POSTs to the
**upstream's** API. On GitLab, `glab mr create` POSTs to the
**fork's** API — the `--repo` flag looks like a target but the
actual POST goes through the fork project. Consequence: the **fork
write token**, not the upstream reporter token, is the one needed
for MR creation, even though the MR targets upstream. This catches
people the first time.

**Two-token model.** Every fork-based GitLab operation needs two
distinct tokens, configured in `defaults.gitTokens` (longest URL
prefix wins, so a fork-group entry shadows the upstream group entry
for repos in the fork namespace):

| Token | Role | Used for |
|-------|------|----------|
| **Fork write** | Developer on fork group | Push branches, create MRs |
| **Upstream reporter** | Reporter on upstream group | Read default branch, read MR threads (`ws review`), file issues |

**GitLab PATs cannot be downscoped.** A Personal Access Token runs
*as you* and inherits your full account access — there's no way to
issue a "read-only on group X" PAT when you're an Owner there. The
GitLab-native workaround is **Group Access Tokens** or **Project
Access Tokens**, which carry an explicit role independent of any
user. On paid tiers and self-hosted instances, create one at
`Settings → Access Tokens` for the group/project. On gitlab.com
free tier these aren't available — point both token vars at the
same PAT and accept the over-scope.

**Bot attribution trade-off.** MRs opened via a Group Access Token
appear as authored by `project_NNN_bot_...`, not your personal
account. The workspace mitigates this with two layers:
(1) the fork namespace path makes your username visible in the MR
source header, (2) `@HUMAN_ACCOUNT` substitution puts your handle
in the MR body. Adequate for team workflows; not sufficient for
formal audit trails that require the GitLab `author` field to be a
human identity.

**glab gotchas worth knowing up front:**

- `glab issue list` and several other subcommands require
  `GITLAB_HOST` in the environment for self-hosted instances. There's
  no `--hostname` flag on subcommands. Set it in `.env`.
- `glab auth login` configures SSH for API calls but does **not**
  store HTTPS git credentials. `git clone`/`push` over HTTPS will
  hang waiting for a password. Either use SSH URLs, or run
  `git credential approve` to cache the token in your keychain. The
  `ws gitlab-auth` subcommand registers the token with glab and
  caches HTTPS credentials in one step.
- `GITLAB_TOKEN` must be set for `glab` to authenticate (parallel to
  `GH_TOKEN` for `gh`).
- `glab mr create --head <ref>` expects the **full fork project
  slug** (e.g. `<your-user>/<repo>`), not just a branch name.

**`identity.forkOrg` must match the GitLab namespace exactly.** If
your forks live at `gitlab.com/<your-user>/...`, set `forkOrg:
<your-user>` in `ecosystem.local.yaml`. Easy to get wrong if your
fork namespace differs from your login handle.

**The verified workflow on GitLab** (in practice on self-hosted,
mirrors the GitHub flow but with provider-specific details
substituted):

```text
ws diagnose <comp>                          # check token coverage first
git checkout -b type/description            # topic branch
# edit
ws commit <comp> <bodyfile>
ws push <comp>
ws cr <comp> --upstream "title" <crfile>    # opens MR fork → upstream
ws review <comp> <mr#>                      # fetch CR threads
# fix → ws push → repeat until approved
# merge via GitLab UI
git checkout main
git pull <upstream-remote> main
```

Running `ws diagnose <comp>` before the first push to a new
component reveals missing token vars before you hit a 403 mid-CR.

---

## 6. Diagnostics: `ws diagnose`

When an operation fails for what looks like an access reason, run:

```bash
ws diagnose <component>
```

It reports:

- The detected remote URL and provider.
- The expected token variable for that provider.
- Whether the token is set in the environment (✓ / ✗).
- Whether `gh auth status` (or equivalent) succeeds.
- Whether the agent identity has access to the remote (read at
  minimum; push requires further verification by attempting one).

If `ws diagnose` shows ✗ for token coverage, the operation will
fail with an opaque auth error at runtime; fix the missing token
or scope first. The orientation skill runs `ws diagnose` proactively
on components likely to be pushed during the session — see
[`gdd-orientation` Step 6b](../../.agent/skills/gdd-orientation/SKILL.md).

---

## 7. Future direction: scope-templated PATs

Today's pattern asks the human to manually create a PAT with the
right scopes. A future improvement is workflow-aware scope templates
— "workflow A needs scopes X+Y; workflow B needs X+Z" — surfaced
as `ws diagnose` recommendations or `ws auth setup` interactive
flows. Not implemented in v1; tracked under the broader
"onboarding and identity" design doc (see Thalamus / project-level
backlog).

---

## See also

- [Permissions](permissions.md) — the *local* permission system
  (shell command allowlisting). Pairs with this doc; together they
  cover "what the agent can do."
- [`docs/git-provider-setup.md`](../git-provider-setup.md) —
  setup mechanics: installing CLIs, generating tokens, loading
  via `.env`.
- [Trust and Safety](trust-and-safety.md) — the broader trust
  hierarchy that places agent vs human identity in context.
- [Hoards](hoards.md) — the canonical case for the collaborator
  pattern (personal multi-machine sync).
- [Features Tour](features.md) — where access control fits in the
  larger feature set.
