# Attribution Coverage Across Outbound Writing Surfaces

Status: approved design

## Context

`ws cr` and `ws issue` guarantee two things about a body before it reaches a public tracker: `@HUMAN_ACCOUNT` and `@GDD_HOME` are substituted for real values, and the first line carries the GDD AI-attribution banner naming the human driving the agent. Both guarantees live in `git-cr.sh` and `git-issue.sh`, duplicated between them, and both run **on the creation path only**.

That is the whole bug. Every other way an agent writes to a tracker skips them.

The failure was observed on yggdrasil #158, whose published body read "Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" — *both* placeholders literal. Both being unsubstituted is what proves the body never passed through substitution at all, rather than a substitution having failed. It failed silently, because an unsubstituted placeholder is valid Markdown and nothing looks at a body after it is published. A second workspace reached the same failure by its own route to the raw provider CLI, which makes this the tooling's shape rather than one session's slip.

Three surfaces are affected, and they were found independently:

- **Change-request and issue bodies, after creation.** There is no `ws` verb for editing a description, so an update goes out through raw `gh pr edit --body-file` and none of the guarantees run. This is the yggdrasil #158 case.
- **Review replies and top-level comments.** Closed by #141 (merged), which added `ws review comment`, prepended the banner to `ws review reply`, and introduced `ws_gdd_attribution_line()` as the shared banner generator. Its own comment records that `git-cr.sh` and `git-issue.sh` do not call it because they predate it.
- **Comments, after posting.** #141's own body reports that the missing attribution "required hand-patching both comments afterward" — an edit-a-comment event that lost the guarantees, already observed once. `ws review` prints no comment or note ids today, only thread ids, so there is currently nothing for an edit to address.

Adjacent and folded in here because it is the same validator: `git-cr.sh` requires the first body line to match `^> \*\*AI-assisted change proposal\.\*\*` **exactly**, while the `templates/change.md` installed in `gdd-sandbox` opens `> **AI-assisted change proposal — requested over chat.**`. A sandbox using the template it was given has its change request rejected. The live Kencierge instance carries a host-side patch for this, which dies on a container restart.

## Goals

- One module owns attribution and substitution, called by every path that publishes agent-authored text.
- No body reaches a tracker carrying an unsubstituted `@HUMAN_ACCOUNT` or `@GDD_HOME`, from any path, create or edit.
- Editing a change request, an issue, or a comment is a first-class `ws` verb carrying the same guarantees as creation.
- The banner check accepts wording variants that still carry the attribution, and rejects ones that do not — strictly more rigorous than the exact-match check it replaces.
- Raw `gh pr edit --body` and its siblings redirect at the new verbs, and only once those verbs exist.
- A reply banner costs less vertical space than a body banner, because replies stack in a thread and a body is read once.

## Non-Goals

- **No `comms.identity` config key, and no machine-account suppression of the banner.** Considered and rejected. `docs/gdd/agent-communication.md` argues that identity outranks disclosure, but that is a ranking — it argues for getting the machine account first, not for dropping the banner afterwards. Suppression would trade a marked, translatable sentence for a naming convention legible only to a reader who parses English bot-naming, which is precisely the reader the international-audience argument is about. It would also add a branch to all four posting paths whose misconfiguration produces silently unattributed text, which is the exact class of bug this design exists to close.
- No change to who may post, what token is used, or how remotes are selected. Edit paths reuse the existing `--remote` / `--upstream` / `identity.forkRemote` resolution unchanged.
- No structured or machine-readable `ws review` output. Two `ws review` gaps are deferred by prior decision and stay deferred.
- No validation of body *content* beyond the attribution line and placeholder resolution.

## Design

### The shared module

`scripts/gdd-attribution.sh`, sourced by `git-cr.sh`, `git-issue.sh`, the new edit scripts, and `ws-review.sh`. It owns four operations:

| Function | Responsibility |
|---|---|
| `gdd_attribution_check <bodyfile>` | First line carries a well-formed banner. Fails closed with the template pointer. |
| `gdd_attribution_substitute <bodyfile>` | Emits a resolved temp file; `@HUMAN_ACCOUNT` and `@GDD_HOME` replaced from ecosystem config. |
| `gdd_attribution_assert_resolved <file>` | Refuses a file still containing either placeholder token. Runs immediately before every publish. |
| `ws_gdd_attribution_line <label>` | Generates the banner for text with no template to copy from. Moves here from `ws-realm.sh`. |

`gdd_attribution_assert_resolved` is the guard that would have caught #158 at the moment it happened. It is deliberately separate from `gdd_attribution_substitute` rather than folded into it, because its value is catching bodies that were **never** substituted — including ones authored by tooling this workspace does not own — and a check that only runs inside the substituter cannot see those.

Moving `ws_gdd_attribution_line()` out of `ws-realm.sh` is a relocation with no behavior change. It landed there in #141 for want of a better home, and #141's own comment names the convergence this design performs. `ws-realm.sh` resolves realms and tokens; attribution is not that.

### The banner rule

Replaces the two exact-sentence greps. A body's first line is valid when **both** hold:

1. It matches `^> \*\*AI-assisted [^*]+\*\*` — a blockquote whose bold run opens `AI-assisted ` and closes on the same line.
2. After substitution, it contains `@<human_account>` as resolved from ecosystem config.

Condition 2 is new and is what makes this stricter overall. The current check verifies one fixed sentence and never confirms that the driver reference resolved to anything; a body whose `@HUMAN_ACCOUNT` silently failed to substitute passes it. Under the new rule that body fails, and `> **AI-assisted change proposal — requested over chat.** Filed by agent driven by @cervator via [GDD](…)` passes — which retires the `gdd-sandbox` host-side patch.

Replies and comments are not validated by this rule. Their banner is *generated* by `ws_gdd_attribution_line()`, never supplied by a caller, so there is nothing to check.

### Banner forms

Bodies keep today's sentence, unchanged, because it is what `templates/change.md` and `templates/issue.md` already ship and it is read once at the top of a review:

```
> **AI-assisted change proposal.** Filed by agent driven by @cervator via [GDD](https://siliconsaga.github.io/yggdrasil/gdd/).
```

Replies and comments get a compact italic form, roughly half the chrome, still a marked and translatable sentence, and visually distinct from a body banner so a dozen of them down a thread do not read as shouting:

```
> _Agent-authored reply — @cervator via [GDD](https://siliconsaga.github.io/yggdrasil/gdd/)._
```

The label word is retained so `ws_gdd_attribution_line <label>` keeps the signature #141 shipped.

### The edit verbs

```
ws cr     <comp> edit <cr#>    [--title <title>] <bodyfile>
ws issue  <comp> edit <issue#> [--title <title>] <bodyfile>
ws review <comp> edit <cr#> <comment-id> <bodyfile>
```

The subcommand follows the component, matching `ws review <comp> threads <cr#>` rather than introducing a reserved word ahead of component resolution. `ws cr` create takes exactly two positionals after the component, so `edit` is unambiguous against it.

`ws cr edit` and `ws issue edit` are `scripts/git-cr-edit.sh` and `scripts/git-issue-edit.sh`. They deliberately do **not** reuse `git-cr.sh`'s creation preflights — the stale-base check, the source-branch verification, and the changelog reminder are all statements about a branch being proposed, and none of them are meaningful when only a description is changing. What they do reuse is its repository resolution: `--remote`, `--upstream`, `identity.forkRemote`, unchanged. A change request living on a remote other than the one it would have been created from needs an explicit `--remote` or `--upstream`, the same as creation does.

`ws review edit` has a prerequisite: `ws review` prints ids for *threads* but not for notes or inline comments, so today there is no way to name the comment to edit. Comment ids are added to both output paths. That is the discovery half and is independently useful — reading a review and being unable to address any single comment in it is a gap regardless of editing.

Provider contract gains three functions, implemented in both `providers/github.sh` and `providers/gitlab.sh`:

| Function | GitHub | GitLab |
|---|---|---|
| `gp_update_pr` | `PATCH repos/{slug}/pulls/{n}` | `PUT projects/{id}/merge_requests/{n}` |
| `gp_update_issue` | `PATCH repos/{slug}/issues/{n}` | `PUT projects/{id}/issues/{n}` |
| `gp_update_comment` | `PATCH repos/{slug}/issues/comments/{id}` and `.../pulls/comments/{id}` | `PUT projects/{id}/merge_requests/{n}/notes/{id}` |

GitHub splits comment editing across two endpoints because a top-level note and an inline review comment are different resources. The id surfaced by `ws review` records which kind it is, so the caller does not have to guess or probe both. GitLab needs no such split, but its note endpoint is nested under the merge request, so `gp_update_comment` takes the CR number on both providers even though GitHub ignores it for the issue-comment case.

`ws review edit` is change-request scoped, matching the rest of `ws review`. Editing a comment on a plain issue has no verb here and is out of scope.

### The hook redirect

A Tier 2 `[redirect-commands]` entry per raw form, denying with a pointer at the corresponding verb:

| Denied | Pointer |
|---|---|
| `gh pr edit … --body` / `--body-file` / `--title` | `ws cr <comp> edit <cr#> …` |
| `gh issue edit … --body` / `--body-file` / `--title` | `ws issue <comp> edit <issue#> …` |
| `glab mr update … --description` / `--title` | `ws cr <comp> edit <cr#> …` |
| `glab issue update … --description` / `--title` | `ws issue <comp> edit <issue#> …` |

Scoped to the body- and title-writing flags only. `gh pr edit --add-label`, `--add-reviewer`, and the rest stay reachable, because denying a capability with no replacement manufactures bypass requests — the failure `hook-rules` warns about in its own review-reading section. This entry lands in the same change as the verbs it points at, never before them.

## Testing

- `tests/ws-cr/attribution.bats` — the banner rule: the current sentence passes, the `gdd-sandbox` variant passes, a bold run that does not close on the line fails, a banner with no resolved driver fails, a body with no blockquote fails.
- `tests/ws-cr/placeholder-leak.bats` — `gdd_attribution_assert_resolved` refuses a body carrying either placeholder, on both create and edit paths, for both `cr` and `issue`. This is the #158 regression test.
- `tests/ws-cr/edit.bats` — argument parsing, `--title`, numeric validation, remote resolution, and that creation preflights do **not** run.
- `tests/ws-review/comment-edit.bats` — comment ids appear in notes and inline output; edit dispatches to the correct endpoint for each id kind.
- `tests/hook/` — each redirect fires on its body/title form and stays silent on `--add-label`.

Verification runs `ws test yggdrasil`. Note that this box has fourteen pre-existing environment-shaped failures unrelated to this work (absent symlink support, absent parallel backends, a kubectl path containing a space); the CI Ubuntu job is the authoritative gate.

## Consequences

- `git-cr.sh` and `git-issue.sh` each shed their duplicated attribution block. Behavior changes in exactly one direction: bodies that would have passed the exact-match check and carried an unresolved driver now fail.
- `gdd-sandbox` can drop the `templates/change.md` host-side patch on its next rebuild.
- The `docs/gdd/agent-communication.md` line stating that the disclaimer "covers bodies, not replies" becomes stale once #141 and this change are both in. **That file is not touched here** — it arrives with #161, which is still open, so there is nothing in this repository to edit. Recorded as a follow-up owed by whichever of the two lands second, and named in this change's review notes so it is not lost.
