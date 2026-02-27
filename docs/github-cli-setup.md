# GitHub CLI Setup

Prerequisites for using `gh` to create and manage GitHub issues across this workspace.

## Install

```bash
brew install gh
```

## Authenticate

```bash
gh auth login
```

Recommended: choose the **browser** flow when prompted. It handles scopes automatically.

If using a Personal Access Token (PAT) instead, the token needs the `repo` scope. Do not grant `admin`, `delete_repo`, or any other elevated scopes — `repo` alone is sufficient for issue creation on private repos. If all repos are public, `public_repo` is enough.

## Verify

```bash
gh auth status
```

## Test

```bash
gh issue list --repo SiliconSaga/mimir --limit 5
```

If this returns a list (or an empty table), auth is working correctly.

## Repos in This Workspace

All repos are under the `SiliconSaga` GitHub org:

| Repo | CLI reference |
|------|---------------|
| nordri | `SiliconSaga/nordri` |
| nidavellir | `SiliconSaga/nidavellir` |
| mimir | `SiliconSaga/mimir` |
| yggdrasil | `SiliconSaga/yggdrasil` |
| vordu | `SiliconSaga/vordu` |

The `gh` CLI uses `--repo owner/name` directly and does not depend on local remote names.

## Git Remote Naming Convention

Remotes are named after what they represent, not generic defaults:

| Remote name | Points to |
|-------------|-----------|
| `siliconsaga` | `github.com/SiliconSaga/*` — the canonical GitHub org |
| `local-gitea` | Homelab Gitea instance (if added as a permanent remote) |

Avoid `origin` — it conveys no information about where the remote lives. All repos in this workspace should use `siliconsaga` as the GitHub remote name. The bootstrap scripts add an internal Gitea remote during cluster setup; that remote is ephemeral and should not be committed as `origin`.
