# Access — identities, tokens, and remote permissions

The yggdrasil workspace runs with two distinct permission systems that are easy to confuse but answer different questions:

| Question | Mechanism | Doc |
|----------|-----------|-----|
| *Can the agent run this **shell command** without a confirmation prompt?* | `.claude/settings.json` allowlist + Claude Code matcher | [permissions.md](permissions.md) |
| *Can the agent perform this **remote Git operation** on a repo?* | Token scope + collaborator/fork status + identity selection | this doc |

Both layers must approve an action that crosses both surfaces. A `git push` is allowed locally (it's in the matcher's auto-allow set or an explicit pattern), but the remote rejects it if the PAT lacks push scope or the agent identity isn't a collaborator on the repo. Layered defense.

This doc covers the remote layer: who the agent is, what tokens it holds, and how the workspace's fork-and-PR pattern keeps human and agent contributions cleanly attributed.

---

## 1. Two identities, one workspace

A GDD session can have **two** Git identities in play:

- **The human contributor** (you). Your GitHub/GitLab username, your PAT for any commands you run interactively. Used for committing via local git config.
- **The agent identity** (e.g. [agent-refr](https://github.com/agent-refr)). A separate account with its own scoped PAT. Used for `ws push`, `ws cr`, `ws review` reply/resolve, and `gh api` calls that happen via the agent's tooling.

**Why separate identities?** Three reasons:

1. **Reviewable attribution.** Every commit, PR, and review thread is clearly authored by a human or an agent. Co-Authored-By trailers in commit messages preserve the pairing; the actual `Author:` field reflects whoever ran the operation.
2. **Scope minimization.** The agent PAT can hold *just enough* scope for routine work (`repo`, plus a couple of read scopes). The human PAT might hold more (workflow editing, package publishing, etc.). Compromise of the agent token is bounded.
3. **Accountability and revocation.** If something goes wrong, you can revoke the agent token immediately without affecting your own day-to-day Git access.

Setup mechanics — installing the CLI tools, generating the tokens, loading them via `.env` — live in [`docs/git-provider-setup.md`](../git-provider-setup.md). This doc focuses on the *patterns* that compose those tokens with the workspace's fork-and-PR model.

---

## 2. The fork-home pattern

For repos owned by an org you're not a maintainer of (typical for external open-source contribution), the workflow is:

1. The agent forks the source project into its fork home (a group or organization).
2. `ws push <component> <branch>` pushes to that fork.
3. `ws cr <component> "<title>" <bodyfile>` opens a PR/MR from the fork to the source project.

The fork home is configured per-developer in `ecosystem.local.yaml`. For GitLab fork groups, set `identity.homes.fork.namespace` to the absolute fork-home namespace, such as `gitlab.example.com/my-team/gdd/alice-fork-group`. `ws clone-fork` uses that namespace to create or find `<namespace>/<repo>`. Set `identity.forkRemote` to the local git remote name used by `ws push` and `ws cr`. With a single remote on a component, no disambiguation is needed; with multiple remotes, `forkRemote` picks which side to push to.

For repos you DO own (your personal namespace), no fork is needed — the workspace just pushes to your remote directly.

### Remote selection in multi-home repos

A complex local checkout may have several remotes: an external source project, an internal mirror or company home, a fork-group home, and an arbitrary extra remote. The workspace treats the fork remote as first-class, treats one non-fork remote as the source-project CR target, and leaves extra remotes as explicit operator choices.

| Use case | Remote selected | Current selector | Command shape |
|---|---|---|---|
| Declare the source project for a component | External or internal source project | `components.<name>.repo` | `ws clone <name>` or `ws clone-fork <name>` |
| Create or find the fork-home copy | Fork group home | `identity.homes.fork.namespace`; `components.<name>.forkRepo` for one-off exact URLs | `ws clone-fork <name>` |
| Name the fork remote used for normal branch pushes | Fork group home remote | `identity.forkRemote` matching the local remote name | `ws push <name> [branch]` |
| Open a CR/MR against the fork project itself | Fork group home remote | `identity.forkRemote`; no `--upstream` | `ws cr <name> "<title>" <bodyfile>` |
| Open a CR/MR against a rare alternate fork/project remote | Operator-selected fork/head remote | `--remote <remote>` or `GIT_CR_REMOTE=<remote>` for this invocation only | `ws cr <name> --remote siliconsaga "<title>" <bodyfile>` |
| Open a CR/MR from the fork to a source project | The non-fork source-project remote | `--upstream`; `defaults.upstreamRemote` breaks ties when more than one non-fork remote exists | `ws cr <name> --upstream "<title>" <bodyfile>` |
| Inspect token coverage and remote detection | All configured remotes | No remote selector; diagnostic output lists remotes and token matches | `ws diagnose <name>` |
| Push or fetch an arbitrary fourth remote | Operator-selected remote | `GIT_PUSH_REMOTE=<remote>` for `ws push`, or explicit Git through `ws exec` for unsupported flows | `GIT_PUSH_REMOTE=scratch ws push <name> [branch]`; `ws exec <name> git fetch scratch` |

The implemented homes model currently makes the fork home first-class through `identity.homes.fork.namespace`. The `homes.internal` and `homes.external` routing distinction remains future design work; until then, use `defaults.upstreamRemote` for the one non-fork source-project remote that `ws cr --upstream` should target, use `ws cr --remote` for rare alternate fork/head remotes, and treat any fourth remote as an explicit escape hatch rather than workspace policy.

---

## 3. The collaborator pattern (personal repos)

For personal repos — most commonly hoards (`hoards/thalami-<user>/`) or personal components — the agent needs write access without forking. The pattern: **add the agent identity as a collaborator** on the GitHub repo.

Steps for a thalami hoard:

1. Create the personal repo: `gh repo create <user>/thalami-<user> --private --source=hoards/thalami-<user> --remote=<user> --push`.
2. Add the agent as collaborator:

   ```bash
   gh api repos/<user>/thalami-<user>/collaborators/agent-refr \
       -X PUT -f permission=push
   ```

3. The agent's PAT (which has `repo` scope) now inherits write access via the collaboration — `ws push thalami-<user>` works without needing the agent to fork your personal repo.

This pattern is key for GDD's "personal piles" story. Without it, multi-machine thalami sync would require manual git operations from the human's account on every machine.

---

## 4. Token scopes in practice

The agent PAT's scope set determines what it can do remotely. The recommended baseline is one write scope plus three read scopes — all the read scopes are low-risk additions that just remove recurring papercuts in routine PR/review operations:

| Scope | What it enables |
|-------|-----------------|
| `repo` | Full read/write on accessible repos. PRs, issues, releases, code, branches. The one *write* scope. |
| `read:org` | Read org membership. `gh pr edit` and several other org-aware operations need this. |
| `read:discussion` | Read discussion threads. `gh pr edit` checks this. |
| `read:project` | Read GitHub Projects (boards, items). `gh pr edit --body-file` checks this. |

`workflow` scope is needed only if the agent edits files under `.github/workflows/`. Most GDD work doesn't touch CI definitions.

The three `read:*` scopes don't grant any mutation power and don't unlock any code the agent can't already reach via `repo` — they're metadata reads that gate routine `gh pr edit`-shaped operations. Compromise of the agent token isn't meaningfully expanded by adding them; declining them just means hitting the `gh api PATCH` fallback below for every PR-edit-shaped call.

**Strict-minimum** (when org policy or paranoia gates the read scopes): `repo` alone, with the `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> --input <file>` workaround for PR-edit operations. `gh api` expects the HTTP method via `-X`/`--method`, not as a positional argument. On Windows Git Bash, drop the leading `/` from the API path to avoid MSYS path conversion rewriting it as a Windows filesystem path.

When in doubt about whether a token covers an operation, run `ws diagnose <component>` — it reports per-component remote detection, expected token variable, and whether the token is present and authenticated.

---

## 5. Multi-provider workflows

The workspace is provider-agnostic. A component on GitHub uses `GH_TOKEN`; a component on GitLab uses `GITLAB_TOKEN`; a self-hosted Forgejo or Gitea instance uses whatever variable you map under `defaults.gitTokens` in the realm or local config.

`ws push`, `ws cr`, `ws review`, etc. all auto-detect the provider from the component's remote URL and pick the right CLI (`gh` vs `glab`) and the right token. Mixed-provider workspaces (some components on GitHub, some on GitLab) work without per-command configuration — the dispatcher handles it.

Tokens for additional providers go in `.env`:

```bash
export GH_TOKEN=ghp_xxx
export GITLAB_TOKEN=glpat_xxx
# Add more as needed for self-hosted instances
```

The mapping from provider → token variable lives in your realm's `ecosystem.yaml` under `defaults.gitTokens`, or override per-developer in `ecosystem.local.yaml`.

**Default behavior with no `gitTokens` entry.** For GitHub remotes, `gh` reads `$GH_TOKEN` automatically — no `gitTokens` entry needed in the common case. Same for GitLab: `glab` reads `$GITLAB_TOKEN`. `ws diagnose` reports this as `✓ <VAR> is set (default for <provider>; no gitTokens entry needed)`. You only need an explicit `gitTokens` entry when you want **fine-grained per-namespace control** — e.g., the org repos use the team's `GH_TOKEN` but your personal forks under `<your-user>` should use a different `GH_TOKEN_PERSONAL`. In that case, add a longer-prefix `gitTokens` entry that wins the longest-prefix match for the personal namespace:

```yaml
defaults:
  gitTokens:
    github.com:                          # default for any GitHub remote
      var: GH_TOKEN
    github.com/<your-user>:              # personal forks override
      var: GH_TOKEN_PERSONAL
```

Without that entry, both namespaces flow through the same default `GH_TOKEN` — fine for most setups; only worth splitting when the isolation is intentional.

### GitLab specifics (gitlab.com or self-hosted)

GitLab's API model differs from GitHub's enough that the same abstract pattern (fork → push → MR) plays out differently in practice. Notes from real workflows on self-hosted GitLab:

**The biggest model flip:** on GitHub, `gh pr create` POSTs to the target/source project's API. On GitLab, `glab mr create` POSTs to the **fork's** API — the `--repo` flag looks like a target but the actual POST goes through the fork project. Consequence: the **fork write token**, not the source-project reporter token, is the one needed for MR creation, even though the MR targets the source project. This may catch people the first time.

For fork creation, use more precise terms: the **source project** is the project being forked, and the **destination namespace** is the fork-home group where GitLab creates the fork. After the fork exists, the same source project is usually the MR target.

**Two-token model.** Every fork-based GitLab operation needs two distinct tokens, configured in `defaults.gitTokens` (longest URL prefix wins, so a fork-group entry shadows the source-project group entry for repos in the fork namespace):

| Token | Role | Used for |
|-------|------|----------|
| **Fork write** | Developer on fork group | Push branches, create MRs |
| **Source reporter** | Reporter on source-project group | Read default branch, read MR threads (`ws review`), file issues |

**GitLab PATs cannot be downscoped.** A Personal Access Token runs *as you* and inherits your full account access — there's no way to issue a "read-only on group X" PAT when you're an Owner there. Prefer a narrower GitLab-native actor when your instance supports one.

**GitLab actor ladder.** Use the narrowest actor that can perform the operation:

| Actor | Best fit | Notes |
|-------|----------|-------|
| **Group / Project Access Token** | Self-managed/Dedicated GitLab, or GitLab.com Premium/Ultimate | Explicit role independent of your human account. Good for fork-group write and source-project read tokens. Access-token bot users are scoped to the project/group that created them and cannot be invited directly to unrelated groups. If the source project/group invites the fork-home group, a fork-group access-token bot can gain source-project read through that group membership and satisfy GitLab's fork API. |
| **Group Service Account** | GitLab.com Free/Premium/Ultimate, or self-managed instances that expose group service accounts to top-level group Owners | Good fork-home actor when it can read the source project and create the fork in a non-personal namespace. It can only be added to its creation group or descendants, so sibling/external source projects must be public, same-hierarchy readable, or available through GitLab project/group sharing to the fork-home group. Service-account forks must target a group/project namespace, not a personal namespace. |
| **Instance Service Account** | Admin-managed self-hosted/Dedicated instances | Closest to a general robot user because it can be invited across groups. Too heavyweight for normal per-user GDD setup. |
| **Personal Access Token** | Universal fallback | Works when no narrower actor exists, but carries your full GitLab account permissions. For split-token config, point both env vars at the same PAT to preserve routing even though isolation is lost. |
| **Manual UI fork** | Human-only authority boundary | `ws clone-fork` emits a prefilled fork URL when the configured fork actor cannot read the source project. The human completes the fork, then reruns the command. |

**Bot attribution trade-off.** MRs opened via a Group Access Token, Project Access Token, or service-account token appear as authored by the bot/service-account user, not your personal account. The workspace mitigates this with two layers: (1) the fork namespace path makes your username visible in the MR source header, (2) `@HUMAN_ACCOUNT` substitution puts your handle in the MR body. Adequate for team workflows; not sufficient for formal audit trails that require the GitLab `author` field to be a human identity.

**Cross-group fork creation.** GitLab's fork API requires the caller to read the source project and create in the destination namespace. `ws clone-fork` handles this automatically when the fork token has both rights. If a group service account or access-token bot can create in the fork group but cannot read the source project, the API cannot create the fork; use GitLab's project/group "Invite a group" sharing mechanism, a different actor, or the manual UI helper. This is group-to-group or project-to-group sharing, not a token-specific share.

For a step-by-step setup walkthrough, see [`docs/git-provider-setup.md`](../git-provider-setup.md) § Set Up a GitLab Fork Group for GDD.

**glab gotchas worth knowing up front:**

- `glab issue list` and several other subcommands require `GITLAB_HOST` in the environment for self-hosted instances. There's no `--hostname` flag on subcommands. Set it in `.env`.
- `glab auth login` configures API calls but does **not** automatically make raw HTTPS Git operations non-interactive. `ws push` uses the matching `.env` / `defaults.gitTokens` token for its own HTTPS push process and disables credential-helper prompts, so it does not need a keychain entry. Raw `git clone` / `git push` still need SSH URLs or a credential helper if you run them outside `ws`.
- `ws clone-fork` also injects the matching token for its own HTTPS clone/fetch/push operations, but the resulting checkout stores normal HTTPS remotes. IDE background fetches or raw `git` commands against that checkout can still hit the OS credential helper and show Keychain/Git Credential Manager prompts. Use `ws` commands, configure a credential helper, or set `defaults.forkTransport: ssh` if you want non-`ws` Git clients to avoid HTTPS credential prompts.
- `GITLAB_TOKEN` must be set for `glab` to authenticate (parallel to `GH_TOKEN` for `gh`).
- `glab mr create --head <ref>` expects the **full fork project slug** (e.g. `<your-user>/<repo>`), not just a branch name.

**GitLab fork-group config.** Set `identity.homes.fork.namespace` to the full fork-home namespace, including host. This is the source of truth for where `ws clone-fork` creates or finds fork-home projects. Keep `identity.forkRemote` as the Git remote name, normally the final namespace segment such as `<your-user>` or `<user>-fork-group`.

**The verified workflow on GitLab** (in practice on self-hosted, mirrors the GitHub flow but with provider-specific details substituted):

```text
ws diagnose <comp>                          # check token coverage first
git checkout -b type/description            # topic branch
# edit
ws commit <comp> <bodyfile>
ws push <comp>
ws cr <comp> --upstream "title" <crfile>    # opens MR fork → source project
ws review <comp> <mr#>                      # fetch CR threads
# fix → ws push → repeat until approved
# merge via GitLab UI
git checkout main
git pull <source-remote> main
```

Running `ws diagnose <comp>` before the first push to a new component reveals missing token vars before you hit a 403 mid-CR.

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
- Whether the agent identity has access to the remote (read at minimum; push requires further verification by attempting one).

If `ws diagnose` shows ✗ for token coverage, the operation will fail with an opaque auth error at runtime; fix the missing token or scope first. Running `ws diagnose <comp>` before the first push to a new component is the cheap way to catch a missing token before it becomes a 403 mid-CR.

---

## 7. Future direction: scope-templated PATs

Today's pattern asks the human to manually create a PAT with the right scopes. A future improvement is workflow-aware scope templates — "workflow A needs scopes X+Y; workflow B needs X+Z" — surfaced as `ws diagnose` recommendations or `ws auth setup` interactive flows. Not implemented in v1; tracked under the broader "onboarding and identity" design doc (see Thalamus / project-level backlog).

---

## See also

- [Permissions](permissions.md) — the *local* permission system (shell command allowlisting). Pairs with this doc; together they cover "what the agent can do."
- [`docs/git-provider-setup.md`](../git-provider-setup.md) — setup mechanics: installing CLIs, generating tokens, loading via `.env`.
- [Trust and Safety](trust-and-safety.md) — the broader trust hierarchy that places agent vs human identity in context.
- [Hoards](hoards.md) — the canonical case for the collaborator pattern (personal multi-machine sync).
- [Features Tour](features.md) — where access control fits in the larger feature set.
