# GitHub CLI Setup

Prerequisites for using `gh` to create and manage GitHub issues across this workspace.

## Install

**macOS:**
```bash
brew install gh
```

**Windows (Git Bash):**
```bash
winget install GitHub.cli
```
After install, open a fresh Git Bash session so the updated `PATH` is picked up.
Alternatively, download the MSI directly from https://cli.github.com and install it.

## Authentication (PAT — no browser required)

Agents cannot drive a browser login. Use a Personal Access Token (PAT) stored in a
gitignored `.env` file; `gh` reads `GH_TOKEN` from the environment automatically.

### 1. Create a fine-grained PAT

Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.

Settings:
- **Token name**: something descriptive, e.g. `yggdrasil-agent-issues`
- **Expiration**: set a reasonable expiry (90 days, 1 year)
- **Resource owner**: `SiliconSaga` (or whichever org the repos live in)
- **Repository access**: "All repositories" or select specific repos then the following access:

  ┌───────────────┬──────────────────────┬────────────────────────────┐
  │  Permission   │    Access needed     │            Why             │
  ├───────────────┼──────────────────────┼────────────────────────────┤
  │ Contents      │ Read and write       │ git push to topic branches │
  ├───────────────┼──────────────────────┼────────────────────────────┤
  │ Issues        │ Read and write       │ Creating issues            │
  ├───────────────┼──────────────────────┼────────────────────────────┤
  │ Pull requests │ Read and write       │ Opening PRs                │
  ├───────────────┼──────────────────────┼────────────────────────────┤
  │ Metadata      │ Read (auto-included) │ Repo info                  │
  └───────────────┴──────────────────────┴────────────────────────────┘

> Classic PATs are an alternative. If you use one, grant only the `repo` scope
> (or `public_repo` if all targeted repos are public). Do not grant `admin`,
> `delete_repo`, or any write-outside-issues scope.

### 2. Store the token

Create `.env` in the `yggdrasil` repo root (this file is gitignored):

```bash
export GH_TOKEN=github_pat_xxxxxxxxxxxx
```

### 3. Load it into your shell

```bash
# From within yggdrasil:
source .env
# From a sibling repo:
source ../yggdrasil/.env
```

> **Note on credential helpers:** `gh auth status` and `validate-agent-setup.sh` may
> warn that the `gh` credential helper is not configured. This is safe to ignore — the
> agent scripts push via an explicit `https://x-access-token:$GH_TOKEN@...` URL, so no
> credential helper is required. Avoiding separate auth may keep the system safer.

### 4. Verify

```bash
gh auth status
```

`gh` reads `GH_TOKEN` automatically — no `gh auth login` step is needed.

### 5. Test

```bash
gh issue list --repo SiliconSaga/mimir --limit 5
```

If this returns a list (or an empty table), auth is working correctly.

## Repos in This Workspace

All current repos are under the `SiliconSaga` GitHub org:

| Repo | CLI reference |
|------|---------------|
| nordri | `SiliconSaga/nordri` |
| nidavellir | `SiliconSaga/nidavellir` |
| mimir | `SiliconSaga/mimir` |
| yggdrasil | `SiliconSaga/yggdrasil` |
| vordu | `SiliconSaga/vordu` |

The `gh` CLI uses `--repo owner/name` directly and does not depend on local remote names.

## Git Remote Naming Convention

Name remotes after the org or service they point to — never use the generic `origin`.
This makes it immediately clear where a push or fetch is going.

| Remote name | Points to |
|-------------|-----------|
| `siliconsaga` | `github.com/SiliconSaga/*` |
| `local-gitea` | Homelab Gitea instance (if added as a permanent remote) |
| `<orgname>` | Any future GitHub org — name the remote after the org |

Examples: a repo mirrored to a `CorpName` org would have a `corpname` remote; a
second homelab Gitea would get a descriptive name like `homelab2-gitea`. The rule is:
the remote name must answer "where does this push go?" without needing to run
`git remote -v`.

Bootstrap scripts add an internal Gitea remote during cluster setup. That remote is
ephemeral and should not be given a permanent name like `origin`.
