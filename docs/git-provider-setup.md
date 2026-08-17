# Git Provider Setup

One-time setup for using the workspace CLI (`ws`) with GitHub and/or GitLab. The workspace auto-detects your provider from remote URLs — no config needed for `github.com` or `gitlab.com`. Self-hosted instances need a config entry (see Provider Detection below).

---

## Env var quick reference

All workspace credentials live in `.env` at the yggdrasil root (gitignored). The shell scripts source it automatically — there's no manual `source .env` step required during normal `ws` use.

| Variable | Purpose | Required when |
|---|---|---|
| `GH_TOKEN` | GitHub PAT (`gh` reads it directly) | Using GitHub remotes |
| `GITLAB_TOKEN` | Default GitLab PAT (`glab` fallback) | Using GitLab remotes |
| `GITLAB_USER` | GitLab username — referenced in setup docs and example `.env`. | Optional |
| `GITLAB_HOST` | Self-hosted GitLab hostname | Self-hosted GitLab only |
| `GITLAB_<scope>_<owner>_<role>` | Per-fork / per-group GitLab tokens | Multi-token GitLab setups (see GitLab section) |

For GitLab multi-token setups, individual env vars are mapped to URL prefixes via `defaults.gitTokens` in `ecosystem.yaml` (longest-prefix match). The script `gp_set_token_for_url` exports the right `GITLAB_TOKEN` for each operation. The full naming pattern and examples live in the [GitLab](#gitlab) section below.

Verify what's currently set without changing anything:

```bash
ws gitlab-auth --status   # which token slots are set/unset
ws diagnose <comp>        # which token covers each remote for a component
```

---

## GitHub

### Install the GitHub CLI

**macOS:**
```bash
brew install gh
```

**Windows (Git Bash):**
```bash
winget install GitHub.cli
```
After install, open a fresh Git Bash session so the updated `PATH` is picked up. Alternatively, download the MSI directly from https://cli.github.com.

**Linux:** See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

### Create a classic Personal Access Token

Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token (classic)**.

Settings:
- **Note**: descriptive name, e.g. `yggdrasil-workspace`
- **Expiration**: set a reasonable expiry (90 days, 1 year)
- **Scopes**:

| Scope | Why |
|-------|-----|
| `repo` | Full repo access — PRs, issues, code, cross-org forks |
| `read:org` | Read org membership — needed by `gh pr edit` and other org-aware ops |
| `read:discussion` | Read discussion threads — also checked by `gh pr edit` |
| `read:project` | Read GitHub Projects — checked by `gh pr edit --body-file` |
| `workflow` | Only if you modify `.github/workflows` files |

The three `read:*` scopes are the recommended baseline alongside `repo`. They don't grant any mutation power — they just remove recurring papercuts where `gh pr edit`-shaped operations would otherwise fail with a scopes error and need the `gh api PATCH` workaround documented in [`docs/gdd/access.md`](gdd/access.md) § 4. If org policy or token-issuance rules block adding them, the strict-minimum (`repo` alone) still works — you'll just hit the fallback path more often.

> **Why classic and not fine-grained?** Fine-grained PATs have known limitations with cross-org pull requests and workflow file access. Classic PATs are simpler and more reliable for GDD workspaces that span multiple orgs or forks.

#### Classic PAT vs fine-grained vs a machine account

The base setup above (a classic PAT on your own account) is the right default for a single user willing to manage one token. The trade-offs, if you outgrow it:

| Option | Pros | Cons |
|---|---|---|
| **Classic PAT** (default) | One token; works across every org/fork you can access; no per-repo wiring | Account-wide — it can reach everything your account can; you renew it by hand at expiry |
| **Fine-grained PAT** | Least privilege — scope to specific repos + specific permissions | More maintenance: shorter max lifetimes, per-repo/per-org selection to keep current, org-owner approval for org-owned repos; still hits the cross-org/workflow limits above |
| **Separate machine (bot) account** | Access managed through normal team/collaborator membership instead of token juggling; not tied to your personal identity; durable | One more account to create and hold a seat for |

A machine account is often the nicest long-term answer for shared or automated work: you add the bot as a collaborator (or to a team) on the specific repos, and access is maintained via team management rather than by rotating a personal token. Reach for fine-grained tokens or a machine account when least-privilege or shared ownership actually matters; until then, a classic PAT keeps setup a single step.

### Store the token

Create `.env` in the yggdrasil root (gitignored):

```bash
export GH_TOKEN=ghp_xxxxxxxxxxxx
```

### Load and verify

```bash
source .env
gh auth status
```

`gh` reads `GH_TOKEN` automatically — no `gh auth login` step is needed.

### Test

```bash
gh issue list --repo <your-org>/<your-repo> --limit 5
```

If this returns a list (or an empty table), auth is working correctly.

---

## GitLab

### Install the GitLab CLI

**macOS:**
```bash
brew install glab
```

**Windows (Git Bash):**
```bash
winget install GLab.GLab
```
After install, open a fresh Git Bash session so the updated `PATH` is picked up.

**Linux:** See https://gitlab.com/gitlab-org/cli#installation

### Create a Token or Service Account

GitLab offers several token-bearing actors. Use the narrowest one that covers your use case:

| Actor | Scope | How to create |
|------------|-------|---------------|
| **Project Access Token** | Single project | Project → Settings → Access Tokens |
| **Group Access Token** | All repos in a group | Group → Settings → Access Tokens |
| **Group Service Account** | A named service-account user under a top-level group | Group → Settings → Service Accounts, then create a token for the service account |
| **Instance Service Account** | A named service-account user that admins can invite across groups | Admin-created; too broad/heavy for normal per-user setup |
| **Personal Access Token** | Entire account | User Settings → Access Tokens |

**Recommended:** use a **Project Access Token** for a single test repo, a **Group Access Token** when your workspace components all live under one group, or a **Group Service Account** when your GitLab instance exposes it and you want a named fork-home actor on a Free-compatible GitLab setup. Personal Access Tokens with `api` scope work but give broader access than needed.

> **GitLab.com Free and older self-managed instances:** Group and Project Access Tokens require a paid GitLab.com subscription, while group service accounts may be available when the instance exposes `Settings → Service Accounts` to top-level group Owners. If that section is absent on a self-managed or Dedicated instance, first check whether an administrator has enabled top-level group owners to create service accounts and whether you are an Owner of the top-level group; absence of the UI alone does not prove the feature is unavailable. If the instance version, feature flags, permissions, or admin settings still do not expose the flow, use a **Personal Access Token** with `api` scope as the fallback. For the multi-token setup (fork → source project), you can point multiple env vars at the same PAT (see `.env.example` for variable names) — the token routing logic still works, you just don't get the access-level separation that scoped actors provide.

Choose the narrowest role that matches the token's job:
- **Developer** for fork/write tokens that must push branches or create MRs.
- **Reporter** for source-project read/review/issue tokens in the split-token setup.
- **Maintainer** may be required on a destination group for API-created forks, depending on instance settings around project creation/import. If a Developer token fails with "not allowed to import projects," raise only the fork-home token's role.

For cross-group fork creation, the fork token must be able to read the source project and create in the destination namespace. A fork-group access-token bot cannot be invited directly to a sibling/external source group, but GitLab's project/group "Invite a group" sharing can grant source-project read by inviting the fork-home group. This is a group-sharing grant, not a token-specific grant.

### Set Up a GitLab Fork Group for GDD

Use a fork group when you want GDD agents to push branches and open MRs from a controlled namespace instead of pushing directly to source projects. The fork group is the **destination namespace** for forks; the project being forked is the **source project**.

1. Choose a fork-home namespace. Good generic shapes are `gitlab.example.com/<team>/gdd/<user>-fork-group`, `gitlab.example.com/<team>/<user>-forks`, or `gitlab.example.com/<user>-forks`. Pick a path you can administer and that makes the human owner obvious in MR source paths.
2. Create the group in GitLab. Go to **Groups → New group**, create the chosen fork-home group, and keep it empty at first. You need enough access on this group to create projects/forks and create tokens.
3. Create the fork-write actor. Preferred: create a **Group Access Token** on the fork-home group with `api` scope and the Maintainer role to allow fork creation.
4. Add the token to `.env` with a descriptive variable name:

   ```bash
   export GITLAB_FORKGROUP_ALICE_WRITE=glpat-or-token-value
   ```

5. Map the fork group in `ecosystem.local.yaml`. Use the full fork-home group path as the `gitTokens` key so longest-prefix matching sends fork operations to the fork-write token:

   ```yaml
   defaults:
     gitProviders:
       gitlab.example.com: gitlab        # self-hosted instances only; gitlab.com is auto-detected
     gitTokens:
       gitlab.example.com/my-team/gdd/alice-fork-group: GITLAB_FORKGROUP_ALICE_WRITE

   identity:
     human_account: alice
     forkRemote: alice-fork-group        # git remote name used by ws push/ws cr
     homes:
       fork:
         namespace: gitlab.example.com/my-team/gdd/alice-fork-group
   ```

6. Make source projects readable to the fork actor. For source projects under the same GitLab group tree, the fork token may already read them. For private sibling/external source projects, either add a separate Reporter token mapping for the source project/group, or ask the source project/group owner to use GitLab's **Invite a group** sharing to grant Reporter access to the fork-home group. The sharing option can let the fork-group token satisfy GitLab's fork API because the same caller can read the source project and create in the destination namespace.

   For a private cross-group source, open the source project (or source group) Members page and choose **Invite a group**. Share the fork-home group with the **Reporter** role. Do not try to invite the access token itself: GitLab represents group/project access tokens as bot users that generally cannot be invited directly across unrelated group boundaries. Sharing the bot's owning group grants inherited source read access to that same fork-token identity, which can then call the fork API because it also has project-create rights in the destination namespace.

7. Declare or override the component. With `identity.homes.fork.namespace` set, `ws clone-fork` creates or uses `gitlab.example.com/my-team/gdd/alice-fork-group/<repo>` automatically. Use an explicit `forkRepo` only for one-off exceptions:

   ```yaml
   components:
     example-service:
       tier: supporting
       repo: https://gitlab.example.com/source-team/example-service.git
       # forkRepo: https://gitlab.example.com/my-team/special-forks/example-service.git
   ```

8. Verify and clone:

   ```bash
   ws gitlab-auth --status
   ws clone-fork example-service
   ```

`ws clone-fork` creates the fork if the configured fork token can read the source project and create in the destination namespace. If not, it prints a prefilled GitLab UI fork URL; complete the fork as a human, then rerun the command.

#### Token naming

**GitLab display name** (what appears as the MR/issue author bot or service-account user):

Pattern: `<scope>-<owner>-<role>` where scope is the group or project slug, owner is your username, and role is the GitLab role level. For personal namespaces (no shared scope), omit the scope prefix and use `<owner>-<role>`.

| Token's job | GitLab display name | Why |
|---|---|---|
| Fork group write | `gdd-rpraestholm-developer` | Group slug + owner + GitLab role |
| Upstream group read | `gdd-reporter` | Group slug + role (shared, no owner) |
| Personal namespace write | `rpraestholm-developer` | Namespace + role |
| Single-project write | `aws-ops-wheel-rpraestholm-developer` | Project + owner + role |

With a well-named token or service account, an MR opened by the agent shows as authored by e.g. `gdd-rpraestholm-developer` — the human connection is clear even though it is not the human GitLab account. Combined with `@HUMAN_ACCOUNT` in the MR body, this is the primary attribution mechanism on GitLab (see `docs/gdd/cr-internals.md`).

**Env var name** (used in `.env` and referenced in `gitTokens`):

Patterns (no redundant `_TOKEN` suffix; all entries are tokens):

- `GITLAB_<SCOPE>_<ROLE>` — shared scope, single owner implied (e.g. `GITLAB_GDD_REPORTER`)
- `GITLAB_<SCOPE>_<OWNER>_<ROLE>` — personal variant within a shared scope (e.g. `GITLAB_GDD_RPRAESTHOLM_DEVELOPER`)
- `GITLAB_<OWNER>_<ROLE>` — personal-namespace token, no group scope (e.g. `GITLAB_RPRAESTHOLM_DEVELOPER`)
- `GITLAB_<OWNER>_PAT` — full-account token; `_PAT` signals broad scope

| Token's job | Env var | Notes |
|---|---|---|
| GDD source group read | `GITLAB_GDD_REPORTER` | Group path slug, reporter role |
| GDD fork group write | `GITLAB_GDD_RPRAESTHOLM_DEVELOPER` | Full fork-group path + owner |
| Personal namespace write | `GITLAB_RPRAESTHOLM_DEVELOPER` | Namespace + role |
| Personal access token | `GITLAB_RPRAESTHOLM_PAT` | Full-account token; `_PAT` signals broad scope |

This naming makes `gitTokens` entries readable at a glance:

```yaml
defaults:
  gitTokens:
    gitlab.example.com/gdd: GITLAB_GDD_REPORTER
    gitlab.example.com/gdd/rpraestholm-fork-group: GITLAB_GDD_RPRAESTHOLM_DEVELOPER
    gitlab.example.com/rpraestholm: GITLAB_RPRAESTHOLM_PAT
```

`gitTokens` values are environment-variable names, not arbitrary environment lookups. Use `GITLAB_*` names for GitLab tokens; `GH_TOKEN` and `GITHUB_TOKEN` are also accepted for GitHub. Other names are rejected before shell indirection so a realm or local mapping cannot redirect credential reads to unrelated variables such as cloud credentials.

For self-hosted instances, token URLs follow the pattern:
`https://<your-host>/<group>/<project>/-/settings/access_tokens`.

Regardless of token type, set the scope to:

| Scope | Why |
|-------|-----|
| `api` | Required for MRs, issues, and repo writes via `glab` |

### Store the token

Add to `.env` in the yggdrasil root:

```bash
export GITLAB_TOKEN=glpat-xxxxxxxxxxxx
export GITLAB_USER=your-gitlab-username

# Self-hosted instances only:
export GITLAB_HOST=git.mycompany.com
```

`ws` parses `.env` as literal `KEY=value` or `export KEY=value` assignments. It does not execute command substitutions, pipelines, or other shell syntax from the file. Single- and double-quoted values are accepted as literal text. Variables that alter command lookup or shell/runtime startup, such as `PATH`, `BASH_ENV`, and dynamic-loader variables, are rejected; configure those in your shell profile instead.

### Load and verify

For self-hosted instances, register the hostname with `glab` once after setting `GITLAB_HOST`:

```bash
ws gitlab-auth
```

For `gitlab.com`, `glab` reads `GITLAB_TOKEN` automatically and no `auth login` step is needed. For self-hosted, the one-time login registers the host for API calls. `ws push` does not require the OS credential helper for HTTPS remotes when a matching `.env` / `defaults.gitTokens` token is present; it injects that token into the single push process and disables credential-helper prompts.

Verify with:

```bash
glab auth status
```

> **Note:** `glab auth status` exits non-zero if *any* configured GitLab host fails authentication — including `gitlab.com` if you have no token for it. Check that your self-hosted instance shows `✓ Logged in to <your-host>`. The `gitlab.com` failure is harmless if you only use the self-hosted instance.

### Test

```bash
# gitlab.com
glab issue list --repo <your-group>/<your-repo>

# Self-hosted (GITLAB_HOST must be set in environment)
source .env
glab issue list --repo <your-group>/<your-repo>
```

#### Verifying token coverage

Before pushing or opening a CR, confirm token routing is wired up correctly:

```bash
ws gitlab-auth --status   # shows all configured token slots and set/unset status
ws diagnose <comp>        # shows which token covers each remote for a specific component
```

`ws diagnose` is the fastest way to confirm auth is wired up correctly for a new component — it shows the ecosystem entry, clone status, remotes, provider detection, and whether the covering token env var is set or missing.

---

## Provider Detection

The workspace auto-detects which provider to use from the remote URL:
- `github.com` → GitHub (`gh` CLI)
- `gitlab.com` → GitLab (`glab` CLI)

For self-hosted instances, add a mapping in `ecosystem.local.yaml`:

```yaml
defaults:
  gitProviders:
    git.mycompany.com: gitlab
```

See `ecosystem.local.yaml.example` for more options (workspace-wide defaults, per-component overrides).

---

## Shared Prerequisites

### yq (YAML processor)

The workspace scripts require [yq](https://github.com/mikefarah/yq) v4+ to parse `ecosystem.yaml`.

**macOS:**
```bash
brew install yq
```

**Windows:**
```bash
# Option 1: winget
winget install MikeFarah.yq

# Option 2: manual download (no admin needed)
mkdir -p "$HOME/bin"
curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_windows_amd64.exe \
  -o "$HOME/bin/yq.exe"
```

If you use the manual download, add `~/bin` to your PATH in `~/.bashrc`:
```bash
export PATH="$HOME/bin:$PATH"
```

Verify: `yq --version` should report v4.x.

### jq (JSON processor)

The GitLab provider uses [jq](https://jqlang.github.io/jq/) to parse API responses. GitHub uses `gh --jq` natively, so jq is only required for GitLab.

**macOS:**
```bash
brew install jq
```

**Windows:**
```bash
# Option 1: winget
winget install jqlang.jq

# Option 2: chocolatey
choco install jq
```

After installing via chocolatey on Windows, jq may not be on PATH in Git Bash. Add it to `~/.bashrc`:
```bash
export PATH="/c/ProgramData/chocolatey/bin:$PATH"
```

Verify: `jq --version` should report 1.6+.

### Running Shell Scripts on Windows

All workspace scripts are Bash scripts. Windows needs Git Bash (installed with Git for Windows).

| From | How to run |
|------|------------|
| Git Bash | `bash scripts/ws help` |
| cmd / PowerShell | `bash scripts/ws help` (Git Bash must be on PATH) |
| VS Code terminal | Set default shell to Git Bash, or prefix with `bash` |

A `.gitattributes` in the repo root forces LF line endings on `.sh` files, preventing `\r: command not found` errors. If you hit this on existing checkouts: `git checkout -- scripts/*.sh`

---

## Git Remote Naming Convention

Name remotes after the org or service — never use the generic `origin`.

| Remote name | Points to |
|-------------|-----------|
| `siliconsaga` | `github.com/SiliconSaga/*` |
| `mygroup` | `gitlab.com/mygroup/*` |
| `local-gitea` | Homelab Gitea instance |
| `<orgname>` | Any org — name the remote after it |

The rule: the remote name should answer "where does this push go?" without running `git remote -v`.

Bootstrap scripts may add an internal Gitea remote during cluster setup. That remote is ephemeral and should not be given a permanent name like `origin`.

---

## Troubleshooting

### `gh`/`glab` not found after install

Open a fresh terminal session. The installer updates PATH, but existing sessions don't pick it up.

### "Bad credentials" or 401 errors (GitHub)

- Token may be expired — check at GitHub → Settings → Developer settings → Personal access tokens.
- Classic PAT: ensure the `repo` scope is selected.
- Org-scoped fine-grained PAT: the org owner may need to approve it first.

### "401 Unauthorized" (GitLab)

- Token may be expired or revoked.
- Ensure the `api` scope is selected.
- For self-hosted: set `GITLAB_HOST` in `.env`.

### Authentication succeeds but repository operations fail

`ws diagnose` validates token routing and provider authentication; it does not prove repository-specific push, fork, or MR authorization.

| Symptom | Meaning | Next check |
|---|---|---|
| 401 / rejected token | Authentication is expired, revoked, or malformed. | Replace the mapped `.env` token and rerun `ws diagnose`. |
| 403 on direct push | Authentication succeeded, but the identity cannot write that project or the wrong remote was selected. | For upstream work, confirm the fork remote marker and push to the fork rather than the source. |
| 403/404 while creating a cross-group fork | The fork identity usually cannot read the private source project. | Share the fork-home group into the source project/group as Reporter, then rerun `ws clone-fork`. |
| Green token row in `ws diagnose` | Token routing and provider authentication succeeded. | Do not infer push/fork/MR rights; inspect remote topology and the identity's project/group role. |

### Push fails with "remote: Permission denied" or "Write access not granted"

- Credential helper may not have your token stored. Run `gh auth status` (GitHub) or `glab auth status` (GitLab) to check.
- **Stale cached credential (Windows):** Git Credential Manager caches tokens and won't pick up a new `GH_TOKEN` from `.env` automatically. If you rotated your PAT, erase the stale entry and let the next push re-cache:

  ```bash
  # Erase the cached credential for github.com
  printf 'protocol=https\nhost=github.com\n' | git credential-manager erase

  # Verify the new token works
  source .env
  gh api user --jq .login    # should print your bot account name
  ```

  The next `git push` will prompt GCM to store the current credential.
  If using a bot PAT via `.env`, you can pre-store it:

  ```bash
  source .env
  printf 'protocol=https\nhost=github.com\nusername=agent-refr\npassword=%s\n' \
    "$GH_TOKEN" | git credential-manager store
  ```

- GitKraken users: check `~/.gitconfig` for `url.insteadOf` entries that redirect HTTPS to SSH. Remove or scope them if they interfere with CLI auth. GitKraken manages its own credentials separately from the system credential helper, so it is unaffected by the erase/store steps above.

### "Cannot detect git provider for URL"

Self-hosted domain not recognized. Add it to `defaults.gitProviders` in `ecosystem.local.yaml`:

```yaml
defaults:
  gitProviders:
    git.mycompany.com: gitlab
```

See Provider Detection above.
