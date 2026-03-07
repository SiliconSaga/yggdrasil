# AI Agent Guidelines for This Workspace

Yggdrasil is the workspace root for the SiliconSaga ecosystem: not a deployable, but the
home of architecture docs, agent skills, utility scripts, and workflow conventions shared
across all repos.

Full ecosystem map: [`docs/ecosystem-architecture.md`](docs/ecosystem-architecture.md)

---

## Repo Roles (quick reference)

| Repo | Tier | Role |
|------|------|------|
| `yggdrasil` | — | Docs, skills, scripts, workspace root |
| `nordri` | 1 | Cluster substrate (Traefik, Crossplane, Velero, ArgoCD) |
| `nidavellir` | 2 | Platform app-of-apps (Vegvísir, Mimir, Keycloak, …) |
| `mimir` | 2 component | Data services via Crossplane + operators |
| `vordu` | 2 component | BDD roadmap visualization |
| `demicracy` | 3 | End-user platform app-of-apps (Backstage, Tafl, …) |

GitHub org: Avoid using a generic `origin` and use explicit remote names like `siliconsaga`

---

## Skills

Skills live in `.agent/skills/<name>/SKILL.md`.

| Skill Name | Description | Source / Reference |
| :--- | :--- | :--- |
| **ArgoCD Bootstrap on K3d** | Bootstrapping ArgoCD app-of-apps on k3d, CRD chicken-and-egg fixes, portable shell scripts | [SKILL.md](./.agent/skills/argocd-bootstrap-on-k3d/SKILL.md) |
| **Crossplane on K3d** | Guide for configuring Crossplane in local K3d clusters | [SKILL.md](./.agent/skills/crossplane-on-k3d/SKILL.md) |
| **Creating GitHub Issues** | Pre-flight checks, issue templates, and filing process for deferring work to GitHub issues | [SKILL.md](./.agent/skills/creating-github-issues/SKILL.md) |
| **KUTTL Testing** | Guidelines for writing and running KUTTL tests | [SKILL.md](./.agent/skills/kuttl-testing/SKILL.md) |
| **Multi-Repo Orchestration** | Session start/end discipline when a session touches more than one repo, TODO triage | [SKILL.md](./.agent/skills/multi-repo-orchestration/SKILL.md) |
| **Nordri Bootstrap Guide** | Bootstrapping Nordri (refr-k8s) on k3d, Mimir integration, ArgoCD sync troubleshooting | [SKILL.md](./.agent/skills/nordri-bootstrap-guide/SKILL.md) |
| **Topic Branch Workflow** | Branch naming, commit/push workflow, utility scripts, and when direct push to main is acceptable | [SKILL.md](./.agent/skills/topic-branch-workflow/SKILL.md) |
| **Writing Yggdrasil Docs** | Conventions for documentation, Mermaid diagram rules, terminology, and cluster layer naming | [SKILL.md](./.agent/skills/writing-yggdrasil-docs/SKILL.md) |

---

## Utility Scripts

All scripts live in `scripts/` and auto-source `.env` for `GH_TOKEN`.
Run from any workspace repo directory using the full path.

| Script | Usage |
|--------|-------|
| `git-push.sh [branch]` | Push current (or named) branch to `siliconsaga` via HTTPS token URL (bypasses GitKraken SSH rewrite) |
| `git-pr.sh TITLE BODYFILE` | Open PR from current branch to main |
| `gh-issue.sh REPO TITLE LABEL BODYFILE` | File a GitHub issue with attribution check |
| `setup-branch-protection.sh` | One-time admin op — requires admin-scoped `GH_TOKEN` |
| `validate-agent-setup.sh` | Verify GH_TOKEN, auth, repo access, branch protection |

---

## Git Workflow

Always use a topic branch. Main is protected.

```bash
# 1. Start from up-to-date main
git checkout main && git pull siliconsaga main   # pull may need HTTPS workaround — see below

# 2. Create topic branch
git checkout -b <type>/<description>             # feat, fix, docs, chore, test, refactor

# 3. Commit (include Co-Authored-By trailer identifying the AI agent)
git commit -m "type: description

Co-Authored-By: <agent-name> <agent-email>"

# 4. Push (MUST use script — plain git push fails due to GitKraken SSH rewrite)
/path/to/yggdrasil/scripts/git-push.sh

# 5. Draft PR body → .prs/<description>.md (gitignored)
cp .agent/pr-template.md .prs/<description>.md

# 6. Open PR
/path/to/yggdrasil/scripts/git-pr.sh "type: description" .prs/<description>.md
```

**Why `git-push.sh` and not plain `git push`:** GitKraken adds a global
`url."git@github.com:".insteadOf=https://github.com/` rule to `~/.gitconfig`,
silently rewriting all HTTPS remotes to SSH. The terminal shell doesn't have
GitKraken's SSH key loaded, so plain `git push siliconsaga` fails with
"Permission denied (publickey)". The script pushes to an explicit
`https://x-access-token:$GH_TOKEN@…` URL that doesn't match the insteadOf
prefix and bypasses the rewrite. GitKraken continues to push via SSH unaffected.

---

## Auth Setup

- `GH_TOKEN` in `.env` (gitignored). See `.env.example`.
- Source it: `source .env` (add to shell profile for convenience).
- `gh` CLI uses `GH_TOKEN` automatically — no browser login needed.
- Day-to-day agent PAT scopes: Contents write, Issues write, Pull requests write.
  Administration scope is NOT included; use a separate admin token for `setup-branch-protection.sh`.

Full setup guide: [`docs/github-cli-setup.md`](docs/github-cli-setup.md)

---

## Issue / PR Drafts

| Path | Purpose |
|------|---------|
| `.agent/issue-template.md` | Committed template for GitHub issues |
| `.agent/pr-template.md` | Committed template for PR bodies |
| `.issues/<repo>-<name>.md` | Gitignored draft clearinghouse for issues |
| `.prs/<description>.md` | Gitignored draft clearinghouse for PRs |

All agent-filed issues must start with the AI attribution blockquote from the template.

---

## Operational Rules

1. **Check `AGENTS.md` first**: Always verify if a relevant skill exists here before starting a complex task.
2. **Read Referenced Skills**: If a task matches a skill above, read the content of the referenced file to get the latest instructions.
