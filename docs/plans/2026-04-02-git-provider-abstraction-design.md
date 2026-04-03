# Git Provider Abstraction — Design Spec

**Date:** 2026-04-02
**Status:** Draft

## Problem

The workspace scripts (`git-push.sh`, `git-pr.sh`, `gh-issue.sh`, `ws-review.sh`)
are tightly coupled to GitHub via the `gh` CLI, hardcoded `github.com` URL parsing,
and a GitHub-specific token URL workaround in push. This blocks use of the GDD
framework with GitLab (or future providers like Gitea/Forgejo).

## Goals

- Add a provider abstraction layer so workspace scripts work with GitHub and GitLab.
- Simplify `git-push.sh` to use plain `git push` (credential helper handles auth).
- Replace hardcoded `SiliconSaga` and `github.com` references with config-driven values.
- Document one-time setup for each provider (CLI install, token creation).
- Keep Gitea/Forgejo as a future extension point without implementing it now.

## Non-Goals (Deferred)

- `ws-review.sh` — GraphQL-heavy review/thread logic. Separate follow-up.
- `setup-branch-protection.sh` / `validate-agent-setup.sh` — admin setup scripts.
- Gitea/Forgejo provider implementation.

## Architecture

### Provider Detection

Detection order (first match wins):

1. **Per-component** `gitProvider` field in ecosystem config.
2. **Domain mapping** via `defaults.gitProviders.<domain>` in ecosystem config
   (for self-hosted instances where the domain doesn't reveal the provider).
3. **Auto-detect from remote URL domain:**
   - `github.com` → `github`
   - `gitlab.com` → `gitlab`
4. **Workspace default** via `defaults.gitProvider` in ecosystem config.
5. **Fail** with a clear error if no match.

### Ecosystem Config Additions

```yaml
# ecosystem.yaml or overlay ecosystem.yaml
defaults:
  gitProvider: github              # workspace-wide default (optional)
  gitProviders:                    # domain → provider mapping (optional)
    git.mycompany.com: gitlab

# Per-component override (optional)
components:
  some-corp-thing:
    gitProvider: gitlab
```

### File Layout

```
scripts/
  git-provider.sh              # Dispatcher: detection + lazy-load + delegation
  providers/
    github.sh                  # GitHub provider (gh CLI)
    gitlab.sh                  # GitLab provider (glab CLI)
```

### Dispatcher (`git-provider.sh`)

A shell library sourced by scripts that need provider-specific operations.

Responsibilities:
- `gp_detect URL` — resolve provider name from a remote URL using the
  detection order above. Returns `github`, `gitlab`, etc.
- Lazy-load `scripts/providers/$provider.sh` on first provider call.
- Delegate `gp_*` function calls to the loaded provider.

The dispatcher reads ecosystem config (via `ws-overlay.sh`) for the
`gitProvider` / `gitProviders` fields. If ecosystem config is unavailable
(e.g., running from a standalone repo), it falls back to URL auto-detection.

### Provider Contract

Each `scripts/providers/<name>.sh` must implement:

| Function | Args | Returns / Side Effects |
|---|---|---|
| `gp_check_cli` | — | Verify CLI is installed and authenticated. Exit with install instructions if missing. |
| `gp_extract_slug` | `URL` | Print `org/repo` (or `group/repo`) slug to stdout. |
| `gp_create_pr` | `--repo SLUG --base BRANCH --head REF --title TEXT --body-file PATH` | Create a PR/MR. Handles provider-specific fork syntax internally. |
| `gp_create_issue` | `--repo SLUG --title TEXT --label LABEL --body-file PATH` | File an issue. |
| `gp_default_branch` | `SLUG` | Print the repo's default branch name to stdout. |

Key differences absorbed by the contract:

- **PR head ref:** GitHub cross-fork uses `Org:branch`. GitLab uses source
  project IDs. The `gp_create_pr` implementation handles this — callers pass
  `--head branch-name` and optionally `--fork-org ORG`.
- **CLI tool:** `gh` vs `glab` — entirely internal to each provider file.
- **Slug format:** GitHub uses `org/repo`. GitLab may use `group/subgroup/repo`.
  The slug format matches what the provider's CLI expects.

### Push (No Provider Needed)

`git-push.sh` is simplified to plain `git push <remote> <branch>`. The existing
token URL workaround (for a GitKraken SSH rewrite issue) is removed. Auth is
handled by the system credential helper (`credential.helper=manager` on Windows,
or `osxkeychain` on macOS, or `gh auth`/`glab auth`).

If a specific system has credential issues (e.g., GitKraken `url.insteadOf`
rewrite), the fix is to correct the system's git config, not to work around it
in the push script.

## Script Changes

### `git-push.sh` — Simplify

- Remove `GH_TOKEN` sourcing and `.env` loading.
- Remove `github.com`-specific HTTPS token URL construction.
- Keep: `--force` flag, main/master safety check, remote detection.
- Push becomes: `git push [--force] <remote> <branch>`.
- Remote detection stays as-is (find remote by name, case-insensitive).

### `git-pr.sh` — Use Provider

- Source `git-provider.sh`.
- Detect provider from the target remote URL.
- Call `gp_check_cli` before doing anything.
- Replace `gh pr create` with `gp_create_pr`.
- Replace `gh api repos/... --jq .default_branch` with `gp_default_branch`.
- Remove hardcoded `SiliconSaga:$BRANCH` — pass `--head $BRANCH` and
  `--fork-org $ORG` to `gp_create_pr`, let the provider format it.
- Remove `GH_TOKEN` sourcing (CLI tools manage their own auth).

### `gh-issue.sh` → `git-issue.sh` — Rename + Use Provider

- Rename file from `gh-issue.sh` to `git-issue.sh`.
- Source `git-provider.sh`.
- Detect provider from the target remote URL.
- Call `gp_check_cli` before doing anything.
- Replace `gh issue create` with `gp_create_issue`.
- Remove `GH_TOKEN` sourcing.
- Keep: AI attribution validation, identity resolution, body file handling.

### `ws` — Wire Up Renames

- Update `ws_issue()` to call `git-issue.sh` instead of `gh-issue.sh`.

### `.env.example` — Expand

```bash
# ── GitHub ───────────────────────────────────────────────────
# Create a classic personal access token at:
#   https://github.com/settings/tokens/new
#
# Required scopes:
#   repo           (full repo access — PRs, issues, code, cross-org forks)
#   workflow        (if you need to touch .github/workflows files)
#
# Note: Fine-grained PATs exist but have known limitations with cross-org
# PRs and workflow files. Classic PATs are recommended for GDD workspaces.
#
# The gh CLI reads GH_TOKEN automatically — no 'gh auth login' needed.
export GH_TOKEN=ghp_xxxxxxxxxxxx
export GH_USER=your-github-username

# ── GitLab ───────────────────────────────────────────────────
# Create a personal access token at:
#   https://gitlab.com/-/user_settings/personal_access_tokens
#   (self-hosted: https://<your-host>/-/user_settings/personal_access_tokens)
#
# Required scopes:
#   api            (full API access — MRs, issues, repo reads)
#
# The glab CLI reads GITLAB_TOKEN automatically — no 'glab auth login' needed.
# export GITLAB_TOKEN=glpat-xxxxxxxxxxxx
# export GITLAB_USER=your-gitlab-username
```

GitLab lines commented out by default so existing users aren't affected.

### `ecosystem.local.yaml.example` — Add Provider Examples

Add commented examples for `gitProvider` and `gitProviders` fields alongside
the existing identity and overlay config.

### `docs/github-cli-setup.md` → `docs/git-provider-setup.md`

Replace the GitHub-only setup guide with a multi-provider guide covering:

- **GitHub section:** Classic PAT creation, `gh` CLI install (OS-specific),
  token storage, verification commands.
- **GitLab section:** Personal access token creation, `glab` CLI install,
  token storage, verification commands.
- **Provider detection:** Brief explanation of how the workspace detects
  which provider to use.
- **Troubleshooting:** Common auth issues per provider (credential helper
  not configured, token expired, wrong scopes, GitKraken SSH rewrite, etc.).
- **Remote naming convention:** Org/group name as remote name (not `origin`).

## Testing

- Test `git push` without token URL on a system with credential helper.
- Test `gp_detect` with GitHub, GitLab, and self-hosted URLs.
- Test `gp_create_pr` and `gp_create_issue` against a test GitLab repo.
- Verify existing GitHub workflows still work after the refactor.
