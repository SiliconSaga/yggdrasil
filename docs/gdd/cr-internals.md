# CR Internals — Cross-Fork Change Requests

This document covers the internal mechanics of cross-fork CR creation in yggdrasil. It is aimed at realm maintainers and contributors debugging token or MR creation issues — not regular GDD users.

## Overview: The Two-Token Model

When you run `ws cr <component> --upstream`, yggdrasil can operate with two tokens in the split GitLab fork-group case:

| Token | Role | Used for |
|---|---|---|
| Fork write token | Developer (fork group) | Pushing branches, authenticating MR/PR creation from the fork |
| Source reporter token | Reporter (source-project group) | Reading source-project metadata, creating issues, reading MR comments and threads (`ws review`) |

Both roles are needed when no single credential has all required grants. The source reporter token covers read and issue operations against the source project — not just default-branch lookup. Eliminating it from the CR path would still leave source-project read access required for `ws review` and `ws issue`.

These tokens are configured in the ecosystem config's `defaults.gitTokens` map, keyed by URL prefix. The longest matching prefix wins, so a fork-group token (longer path) takes precedence over a parent-group token for the same host.

## GitHub: Cross-Fork PR Flow

```text
ws cr <component> --upstream
  └─ gh pr create
       --repo  source-org/repo           ← source project (target)
       --head  fork-org:branch           ← fork branch reference
       --base  main
```

On **GitHub**, the `gh` CLI creates the PR by calling the target/source project's API. PR creation only requires read access to the source project (GitHub allows PR creation from any repo you can read, including public ones).

**Whether one or two tokens are needed depends on token type:**

- **Classic PAT or account with team membership on both sides**: a single token covers push to fork and PR creation against the source project. No split needed.
- **Fine-grained PAT scoped to fork org only**: works when the source project is public (readable without explicit access). The SiliconSaga/MovingBlocks setup is an example — `GH_TOKEN` is scoped to SiliconSaga, and MovingBlocks repos are public.
- **Fine-grained PAT with explicit source-project access**: also a single token, just scoped to both orgs.

The two-token split is not a GitHub requirement — it's a GitLab necessity that happens to map onto GitHub fine-grained tokens naturally.

## GitLab: Cross-Fork MR Flow

```text
ws cr <component> --upstream
  └─ glab mr create
       --repo   myorg/source-repo              ← source project (target)
       --head   myfork/fork-repo              ← fork project slug
       --source-branch  fix/my-feature
       --target-branch  main
```

On **GitLab**, `glab mr create` uses `--repo` for the target/source project and `--head OWNER/REPO` to identify the fork project that owns the source branch. The MR is created against the target/source project, but the caller must still be allowed to use the fork project and source branch.

This is different from GitHub's `owner:branch` head syntax, but the high-level access split is similar: the target/source project must be readable, and the fork/source-branch side must be writable by the actor creating the request.

**Consequence for token selection in git-cr.sh:**

```text
1. gp_set_token_for_url "$UPSTREAM_URL"   ← reporter token
   gp_default_branch "$UPSTREAM_SLUG"     ← reads source project (needs reporter)

2. gp_set_token_for_url "$FORK_URL"       ← fork write token with source-project read
   gp_create_pr --repo source-project \
                --head fork-slug \         ← glab targets source project with fork head
                ...
```

The token must be switched between the metadata read and MR creation calls in split-token setups. Using only the reporter token for both can fail because the reporter token has no write/source-branch rights on the fork. Using only the fork token can fail when it lacks source-project read; group sharing or a same-hierarchy/public source project can make the fork token sufficient for MR creation.

## Summary: Which Token Goes Where

| Operation | GitHub | GitLab ≥1.65 |
|---|---|---|
| Push branch | Fork write token | Fork write token |
| Read source-project default branch | Any token with source-project read | Source reporter token |
| Create PR/MR API call | Any token with source-project read | Fork write token with source-project read |
| `ws review` (MR comments, threads) | Any token with source-project read | Source reporter token |
| `ws issue` (create issue on source project) | Any token with source-project read | Source reporter token |

On GitHub, "any token with source-project read" may be a single token that also covers the fork — especially with classic PATs or public source projects. On GitLab with private source and fork groups, separate tokens are often useful because the fork group and source-project group each need explicit access grants; a PAT or a fork-group token that has been granted source-project read can cover both roles, but with less isolation.

The practical difference for yggdrasil is token routing: source-project metadata, review, and issue operations use a source-readable token, while MR creation uses an actor that can write to the fork/source branch and read the target/source project.

## Token Types, Machine Users, and Managed GitLab

### GitHub: two approaches to scoping

On GitHub you have two legitimate options for limiting the blast radius of an automation token:

1. **Fine-grained PAT on your own account** — GitHub lets you scope these below your actual access level. You can be an org owner and issue a PAT that only has write on your fork org and read on the source project. The PR is posted as *you*, with your full username and avatar visible in the GitHub UI. The scoping is enforced at the token level, not the account level.

2. **Dedicated machine user** (separate GitHub account) — an older pattern that predates fine-grained PATs. A separate account with a classic token is granted only the team memberships it needs. The PR appears as the machine user, not you personally. Still common and valid, but no longer strictly necessary on GitHub.

The key point: on GitHub, option 1 lets you post as your own human account while still running with restricted permissions.

### GitLab: scoped actors, PAT fallback

A GitLab Personal Access Token runs as the creating user and inherits their full access level. If your account is Owner of `group/project`, your PAT is effectively Owner too — there is no way to issue a PAT that has only Reporter access to a group where you have Owner access.

The GitLab-native solutions are **Group Access Tokens**, **Project Access Tokens**, and **Service Accounts**. Group/project access tokens carry an explicit role independent of any human user; they are available on self-managed/Dedicated GitLab and on GitLab.com paid tiers. Group service accounts are a useful GitLab.com Free-compatible path when the GitLab instance exposes them to group Owners, but they are not general cross-group machine users: they can only be added to their creation group or descendants, so sibling/external source-project access must come from public visibility, same-hierarchy membership, or GitLab project/group sharing to the fork-home group.

Group sharing has one non-obvious consequence for fork creation: a fork-group access-token bot cannot be directly invited to a sibling/external source project, but if the source project or parent group invites the fork-home group, the bot can gain source-project read through that group membership. Then the same fork-group token may satisfy GitLab's fork API requirement: one caller identity with source-project read and destination-namespace create rights.

**Machine users on managed GitLab** are often not an option either — user accounts may be managed by SSO or central administration, so you can't create a dedicated bot account as easily as you could on public GitHub. Instance service accounts are the closest GitLab analogue, but they require administrator involvement and are usually too heavyweight for per-developer GDD setup.

When no scoped actor is available, use a Personal Access Token and point both env vars at the same PAT to maintain the two-token routing pattern. This preserves the mechanics but loses permission isolation.

The result: on GitLab, CRs submitted by the agent usually appear as opened by a bot or service-account user (`project_NNN_bot_...`, `group_NNN_bot_...`, or a named service account), not your personal account.

### Human attribution on GitLab

Since the GitLab UI shows the bot as the MR author, yggdrasil uses two layers of attribution to tie the CR back to the human who initiated it:

1. **Fork namespace path** — the MR source is `youruser/project`, making the human's name visible in the MR header even if the opener is a bot.

2. **`@HUMAN_ACCOUNT` in the MR body** — the CR template substitutes the `identity.human_account` value (e.g. `@youruser`) into the body at creation time, so the human is explicitly named in the description.

This is an accepted trade-off for now. It provides adequate attribution for most team workflows, but may not satisfy formal audit requirements that expect the GitLab *author* field to match a human identity. If that becomes a requirement, the only human-author path is a per-developer PAT, and because GitLab PATs cannot be downscoped that carries a wider blast radius than the scoped-actor approach.

## See Also

- `docs/git-provider-setup.md` — token setup and ecosystem config
- `scripts/git-cr.sh` — cross-fork path implementation
- `scripts/providers/gitlab.sh` — `gp_create_pr`
- `scripts/git-provider.sh` — `gp_set_token_for_url`
