# Git Provider Setup

One-time setup for using the workspace CLI (`ws`) with GitHub and/or GitLab.
The workspace auto-detects your provider from remote URLs — no config needed
for `github.com` or `gitlab.com`. Self-hosted instances need a config entry
(see Provider Detection below).

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
After install, open a fresh Git Bash session so the updated `PATH` is picked up.
Alternatively, download the MSI directly from https://cli.github.com.

**Linux:** See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

### Create a classic Personal Access Token

Go to **GitHub → Settings → Developer settings → Personal access tokens →
Tokens (classic) → Generate new token (classic)**.

Settings:
- **Note**: descriptive name, e.g. `yggdrasil-workspace`
- **Expiration**: set a reasonable expiry (90 days, 1 year)
- **Scopes**:

| Scope | Why |
|-------|-----|
| `repo` | Full repo access — PRs, issues, code, cross-org forks |
| `workflow` | Only if you modify `.github/workflows` files |

> **Why classic and not fine-grained?** Fine-grained PATs have known
> limitations with cross-org pull requests and workflow file access.
> Classic PATs are simpler and more reliable for GDD workspaces that span
> multiple orgs or forks.

### Store the token

Create `.env` in the yggdrasil root (gitignored):

```bash
export GH_TOKEN=ghp_xxxxxxxxxxxx
export GH_USER=your-github-username
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

### Create a Token

GitLab offers three token types with increasing scope. Use the narrowest one
that covers your use case:

| Token type | Scope | How to create |
|------------|-------|---------------|
| **Project Access Token** | Single project | Project → Settings → Access Tokens |
| **Group Access Token** | All repos in a group | Group → Settings → Access Tokens |
| **Personal Access Token** | Entire account | User Settings → Access Tokens |

**Recommended:** use a **Project Access Token** for a single test repo, or a
**Group Access Token** if your workspace components all live under one group.
Personal Access Tokens with `api` scope work but give broader access than needed.

> **gitlab.com free tier:** Group and Project Access Tokens require a paid
> subscription (Premium+). Use a **Personal Access Token** with `api` scope
> instead. For the multi-token setup (fork → upstream), you can point multiple
> env vars at the same PAT (see `.env.example` for variable names) — the token
> routing logic still works, you just don't get the access-level separation
> that scoped tokens provide.

Choose the narrowest role that matches the token's job:
- **Developer** for fork/write tokens that must push branches or create MRs.
- **Reporter** for upstream read/review/issue tokens in the split-token setup.

#### Token naming

**GitLab display name** (what appears as the MR/issue author bot):

Pattern: `<scope>-<owner>-<role>` where scope is the group or project slug,
owner is your username, and role is the GitLab role level. For personal
namespaces (no shared scope), omit the scope prefix and use `<owner>-<role>`.

| Token's job | GitLab display name | Why |
|---|---|---|
| Fork group write | `gdd-rpraestholm-developer` | Group slug + owner + GitLab role |
| Upstream group read | `gdd-reporter` | Group slug + role (shared, no owner) |
| Personal namespace write | `rpraestholm-developer` | Namespace + role |
| Single-project write | `aws-ops-wheel-rpraestholm-developer` | Project + owner + role |

With a well-named token, an MR opened by the agent shows as authored by
e.g. `gdd-rpraestholm-developer` — the human connection is clear even though
it's a bot account. Combined with `@HUMAN_ACCOUNT` in the MR body, this is
the primary attribution mechanism on GitLab (see `docs/cr-internals.md`).

**Env var name** (used in `.env` and referenced in `gitTokens`):

Patterns (no redundant `_TOKEN` suffix; all entries are tokens):

- `GITLAB_<SCOPE>_<ROLE>` — shared scope, single owner implied (e.g. `GITLAB_GDD_REPORTER`)
- `GITLAB_<SCOPE>_<OWNER>_<ROLE>` — personal variant within a shared scope (e.g. `GITLAB_GDD_RPRAESTHOLM_DEVELOPER`)
- `GITLAB_<OWNER>_<ROLE>` — personal-namespace token, no group scope (e.g. `GITLAB_RPRAESTHOLM_DEVELOPER`)
- `GITLAB_<OWNER>_PAT` — full-account token; `_PAT` signals broad scope

| Token's job | Env var | Notes |
|---|---|---|
| GDD upstream group read | `GITLAB_GDD_REPORTER` | Group path slug, reporter role |
| GDD fork group write | `GITLAB_GDD_RPRAESTHOLM_DEVELOPER` | Full fork-group path + owner |
| Personal namespace write | `GITLAB_RPRAESTHOLM_DEVELOPER` | Namespace + role |
| Personal access token | `GITLAB_RPRAESTHOLM_PAT` | Full-account token; `_PAT` signals broad scope |

This naming makes `gitTokens` entries readable at a glance:

```yaml
defaults:
  gitTokens:
    gitlab-master.nvidia.com/gni-cis/gdd: GITLAB_GDD_REPORTER
    gitlab-master.nvidia.com/gni-cis/gdd/rpraestholm: GITLAB_GDD_RPRAESTHOLM_DEVELOPER
    gitlab-master.nvidia.com/rpraestholm: GITLAB_RPRAESTHOLM_PAT
```

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

### Load and verify

For self-hosted instances, register the hostname with `glab` once after
setting `GITLAB_HOST`:

```bash
source .env
# Uses the multi-token write var if set (see .env.example), else GITLAB_TOKEN
glab auth login --hostname "$GITLAB_HOST" --token "${GITLAB_GDD_GROUP_WRITE_TOKEN:-$GITLAB_TOKEN}"
```

For `gitlab.com`, `glab` reads `GITLAB_TOKEN` automatically and no `auth login`
step is needed. For self-hosted, the one-time login registers the host;
subsequent calls use the stored credentials.

Verify with:

```bash
glab auth status
```

> **Note:** `glab auth status` exits non-zero if *any* configured GitLab host
> fails authentication — including `gitlab.com` if you have no token for it.
> Check that your self-hosted instance shows `✓ Logged in to <your-host>`.
> The `gitlab.com` failure is harmless if you only use the self-hosted instance.

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

`ws diagnose` is the fastest way to confirm auth is wired up correctly for a
new component — it shows the ecosystem entry, clone status, remotes, provider
detection, and whether the covering token env var is set or missing.

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

See `ecosystem.local.yaml.example` for more options (workspace-wide defaults,
per-component overrides).

---

## Shared Prerequisites

### yq (YAML processor)

The workspace scripts require [yq](https://github.com/mikefarah/yq) v4+
to parse `ecosystem.yaml`.

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

The GitLab provider uses [jq](https://jqlang.github.io/jq/) to parse API
responses. GitHub uses `gh --jq` natively, so jq is only required for GitLab.

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

After installing via chocolatey on Windows, jq may not be on PATH in Git Bash.
Add it to `~/.bashrc`:
```bash
export PATH="/c/ProgramData/chocolatey/bin:$PATH"
```

Verify: `jq --version` should report 1.6+.

### Running Shell Scripts on Windows

All workspace scripts are Bash scripts. Windows needs Git Bash (installed
with Git for Windows).

| From | How to run |
|------|------------|
| Git Bash | `bash scripts/ws help` |
| cmd / PowerShell | `bash scripts/ws help` (Git Bash must be on PATH) |
| VS Code terminal | Set default shell to Git Bash, or prefix with `bash` |

A `.gitattributes` in the repo root forces LF line endings on `.sh` files,
preventing `\r: command not found` errors. If you hit this on existing checkouts:
`git checkout -- scripts/*.sh`

---

## Git Remote Naming Convention

Name remotes after the org or service — never use the generic `origin`.

| Remote name | Points to |
|-------------|-----------|
| `siliconsaga` | `github.com/SiliconSaga/*` |
| `mygroup` | `gitlab.com/mygroup/*` |
| `local-gitea` | Homelab Gitea instance |
| `<orgname>` | Any org — name the remote after it |

The rule: the remote name should answer "where does this push go?" without
running `git remote -v`.

Bootstrap scripts may add an internal Gitea remote during cluster setup. That
remote is ephemeral and should not be given a permanent name like `origin`.

---

## Troubleshooting

### `gh`/`glab` not found after install

Open a fresh terminal session. The installer updates PATH, but existing
sessions don't pick it up.

### "Bad credentials" or 401 errors (GitHub)

- Token may be expired — check at GitHub → Settings → Developer settings →
  Personal access tokens.
- Classic PAT: ensure the `repo` scope is selected.
- Org-scoped fine-grained PAT: the org owner may need to approve it first.

### "401 Unauthorized" (GitLab)

- Token may be expired or revoked.
- Ensure the `api` scope is selected.
- For self-hosted: set `GITLAB_HOST` in `.env`.

### Push fails with "remote: Permission denied" or "Write access not granted"

- Credential helper may not have your token stored. Run
  `gh auth status` (GitHub) or `glab auth status` (GitLab) to check.
- **Stale cached credential (Windows):** Git Credential Manager caches tokens
  and won't pick up a new `GH_TOKEN` from `.env` automatically. If you rotated
  your PAT, erase the stale entry and let the next push re-cache:

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

- GitKraken users: check `~/.gitconfig` for `url.insteadOf` entries that
  redirect HTTPS to SSH. Remove or scope them if they interfere with CLI auth.
  GitKraken manages its own credentials separately from the system credential
  helper, so it is unaffected by the erase/store steps above.

### "Cannot detect git provider for URL"

Self-hosted domain not recognized. Add it to `defaults.gitProviders` in
`ecosystem.local.yaml`:

```yaml
defaults:
  gitProviders:
    git.mycompany.com: gitlab
```

See Provider Detection above.
