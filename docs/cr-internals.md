# CR Internals — Cross-Fork Change Requests

This document covers the internal mechanics of cross-fork CR creation in yggdrasil.
It is aimed at overlay maintainers and contributors debugging token or MR creation
issues — not regular GDD users.

## Overview: The Two-Token Model

When you run `ws cr <component> --upstream`, yggdrasil operates with two tokens
in the cross-fork case:

| Token | Role | Used for |
|---|---|---|
| Fork write token | Developer (fork group) | Pushing branches, creating MRs/PRs |
| Upstream reporter token | Reporter (upstream group) | Reading upstream metadata, creating issues, reading MR comments and threads (`ws review`) |

Both tokens are needed. The upstream reporter token covers all read and issue operations
against the upstream project — not just default-branch lookup. Eliminating it from
the CR path would still leave it required for `ws review` and `ws issue`.

These tokens are configured in the ecosystem config's `defaults.gitTokens` map,
keyed by URL prefix. The longest matching prefix wins, so a fork-group token
(longer path) takes precedence over a parent-group token for the same host.

## GitHub: Cross-Fork PR Flow

```text
ws cr <component> --upstream
  └─ gh pr create
       --repo  upstream-org/repo         ← upstream (target)
       --head  fork-org:branch           ← fork branch reference
       --base  main
```

On **GitHub**, the `gh` CLI creates the PR by calling the **upstream project's API**.
PR creation only requires read access to the upstream (GitHub allows PR creation
from any repo you can read, including public ones).

**Whether one or two tokens are needed depends on token type:**

- **Classic PAT or account with team membership on both sides**: a single token
  covers push to fork and PR creation against upstream. No split needed.
- **Fine-grained PAT scoped to fork org only**: works when the upstream is public
  (readable without explicit access). The SiliconSaga/MovingBlocks setup is an
  example — `GH_TOKEN` is scoped to SiliconSaga, and MovingBlocks repos are public.
- **Fine-grained PAT with explicit upstream access**: also a single token, just
  scoped to both orgs.

The two-token split is not a GitHub requirement — it's a GitLab necessity that
happens to map onto GitHub fine-grained tokens naturally.

## GitLab: Cross-Fork MR Flow

```text
ws cr <component> --upstream
  └─ glab mr create
       --repo   myorg/upstream-repo            ← upstream (target)
       --head   myfork/fork-repo              ← fork project slug
       --source-branch  fix/my-feature
       --target-branch  main
```

On **GitLab**, the behavior depends on the glab version:

### glab < 1.65 (--source-project, now removed)

Older glab used `--source-project SLUG` to identify the fork. In this mode,
glab called the **upstream project's API** — mirroring the GitHub behaviour.
The upstream reporter token was sufficient.

### glab ≥ 1.65 (--head, current)

`--source-project` was removed and replaced with `--head OWNER/REPO`.
With this flag, glab calls the **fork project's API** to create the MR —
not the upstream's API. GitLab's MR creation endpoint lives on the source
(fork) project.

This is the opposite of how GitHub works, and opposite of what the `--repo`
argument implies at first glance.

**Consequence for token selection in git-cr.sh:**

```text
1. gp_set_token_for_url "$UPSTREAM_URL"   ← reporter token
   gp_default_branch "$UPSTREAM_SLUG"     ← reads upstream (needs reporter)

2. gp_set_token_for_url "$FORK_URL"       ← fork write token
   gp_create_pr --repo upstream \
                --head fork-slug \         ← glab POSTs to fork project
                ...
```

The token must be switched between the two calls. Using only the reporter
token for both will produce a `403 Forbidden` from the fork project, since
the reporter token has no write access there.

## Summary: Which Token Goes Where

| Operation | GitHub | GitLab ≥1.65 |
|---|---|---|
| Push branch | Fork write token | Fork write token |
| Read upstream default branch | Any token with upstream read | Upstream reporter token |
| Create PR/MR API call | Any token with upstream read | **Fork write token** |
| `ws review` (MR comments, threads) | Any token with upstream read | Upstream reporter token |
| `ws issue` (create issue on upstream) | Any token with upstream read | Upstream reporter token |

On GitHub, "any token with upstream read" may be a single token that also covers
the fork — especially with classic PATs or public upstreams. On GitLab with private
groups, separate tokens are required because the fork group and upstream group each
need explicit access grants.

The fundamental difference: GitHub owns the PR on the upstream side; GitLab owns
the MR on the source (fork) side. This is reflected in which project's API
endpoint is called during creation.

## Token Types, Machine Users, and Corporate GitLab

### GitHub: two approaches to scoping

On GitHub you have two legitimate options for limiting the blast radius of an
automation token:

1. **Fine-grained PAT on your own account** — GitHub lets you scope these below
   your actual access level. You can be an org owner and issue a PAT that only
   has write on your fork org and read on the upstream. The PR is posted as *you*,
   with your full username and avatar visible in the GitHub UI. The scoping is
   enforced at the token level, not the account level.

2. **Dedicated machine user** (separate GitHub account) — an older pattern that
   predates fine-grained PATs. A separate account with a classic token is granted 
   only the team memberships it needs. The PR appears as the machine user, not you 
   personally. Still common and valid, but no longer strictly necessary on GitHub.

The key point: on GitHub, option 1 lets you post as your own human account while
still running with restricted permissions.

### GitLab: PATs cannot be downscoped

A GitLab Personal Access Token runs as the creating user and inherits their full
access level. If your account is Owner of `group/project`, your PAT is effectively
Owner too — there is no way to issue a PAT that has only Reporter access to a
group where you have Owner access.

The GitLab-native solution is **Group Access Tokens** and **Project Access Tokens**,
which are created with an explicit role independent of any user. This is what
yggdrasil uses (e.g. `GITLAB_UPSTREAM_REPORTER_TOKEN`, `GITLAB_FORK_WRITE_TOKEN`).

**Machine users on corporate GitLab** are often not an option either — user
accounts may be managed by IT/SSO, so you can't create a dedicated bot account
as easily as you could on the public cloud GitLab or GitHub.

The result: on GitLab, CRs submitted by the agent appear as opened by a bot user
(`project_NNN_bot_...`), not your personal account.

### Human attribution on GitLab

Since the GitLab UI shows the bot as the MR author, yggdrasil uses two layers of
attribution to tie the CR back to the human who initiated it:

1. **Fork namespace path** — the MR source is `youruser/project`, making the
   human's name visible in the MR header even if the opener is a bot.

2. **`@HUMAN_ACCOUNT` in the MR body** — the CR template substitutes the
   `identity.human_account` value (e.g. `@youruser`) into the body at creation
   time, so the human is explicitly named in the description.

This is an accepted trade-off for now. It provides adequate attribution for
most team workflows, but may not satisfy formal audit requirements that expect
the GitLab *author* field to match a human identity. If that becomes a
requirement, the path forward would be a per-developer PAT with exactly Reporter
access to the upstream — but since GitLab PATs can't be downscoped, that token
would carry your full account permissions on that group, which is a wider blast
radius than the Group Access Token approach.

## See Also

- `docs/git-provider-setup.md` — token setup and ecosystem config
- `scripts/git-cr.sh` — cross-fork path implementation
- `scripts/providers/gitlab.sh` — `gp_create_pr`
- `scripts/git-provider.sh` — `gp_set_token_for_url`
