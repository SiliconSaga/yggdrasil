# Versioning & Releases

How the GDD reference implementation is versioned, what a release means, and how change notes are produced — including the tooling decisions for the ongoing workflow.

## What is versioned

**The yggdrasil workspace and the `ws` CLI version together under [SemVer](https://semver.org/),** and the methodology docs (`docs/gdd/`) ride along with that version. One number describes the whole reference implementation: a clone of yggdrasil at tag `X.Y.Z` is a complete, coherent snapshot of the CLI, hook, skills, and the docs that describe them.

Everything else versions independently:

- **Realm repos** (e.g. `realm-siliconsaga`) — community config evolves on its own cadence.
- **Component repos** — their own projects, their own versioning.
- **Hoard templates** — already carry their own monotonic `version` in the upgrade manifest (`.upgrade/upgrade.yaml`), consumed by `ws hoard upgrade`; that mechanism is independent of the workspace version.

SemVer interpretation for a workspace + CLI:

| Bump | Meaning here |
|---|---|
| **Major** | Breaking change to the `ws` CLI surface, the ecosystem/realm/hoard config schema, or the hook contract — something a downstream workspace or realm must adapt to |
| **Minor** | New subcommands, new skills, new template flavors, backwards-compatible behavior additions |
| **Patch** | Fixes, docs, de-noising — no new surface |

Pre-1.0 the project deliberately favored clean breaks over compat shims; from 1.0.0 on, breaking changes cost a major bump, which is the point of tagging.

## The changelog

`CHANGELOG.md` at the workspace root follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): an `[Unreleased]` section accumulates entries grouped under Added / Changed / Fixed / Security, and becomes the next version's section at tag time.

**The changelog is curated, not generated.** Generators draft; a human or agent edits for the reader. The raw material is already good, thanks to two existing conventions: `ws commit` bodyfiles carry conventional-commit-shaped subjects (`fix(ws): …`, `docs(gdd): …`, `feat(hook): …`), and PRs land with descriptive titles and bodies. A changelog entry should say what changed *for the user of the workspace*, not restate the commit log.


### Release ceremony

1. Confirm the suite is green (`ws test yggdrasil`) on main.
2. Curate `[Unreleased]` → rename to `## [X.Y.Z] - YYYY-MM-DD`, add a fresh empty `[Unreleased]` above it, update the link references at the bottom.
3. Tag (`git tag -a vX.Y.Z`) and push the tag.
4. Create the GitHub Release from the tag, pasting the changelog section as the body (optionally augmented by GitHub's auto-generated notes — see below).

## Change-note tooling (the ongoing workflow)

Decision record, so the options don't get re-litigated each release:

- **Input convention: conventional commits — already in place.** `ws commit` subjects use `type(scope): summary`. This is the load-bearing choice: every generator below consumes it. A future `ws commit` lint of the subject shape is a cheap polish item if drift appears.
- **Drafting: [git-cliff](https://git-cliff.org/) when wanted.** Single static binary (no Node toolchain — fits the bash/yq/jq stack), config-in-repo (`cliff.toml`), parses conventional commits into grouped sections, supports `--unreleased` drafts. Use it to draft the `[Unreleased]` section before a release; curate the output rather than committing it raw. Not a required dependency — the changelog can always be maintained by hand (or an agent reading `git log`).
- **Per-repo GitHub Releases: auto-generated notes as a complement.** GitHub's built-in release-notes generation (`.github/release.yml` categories driven by PR labels) is zero-tooling and PR-title-based; good as the "what merged" appendix under the curated changelog section in a Release body.
- **Not adopted: semantic-release / release-please.** Full release automation (CI computes the version from commit types and publishes) is more machinery than a workspace repo needs, pulls in a Node/bot dependency, and takes the version decision away from the human. Revisit only if release cadence makes manual tagging a real cost.

## Stack-level aggregation (roadmap, not GA)

The known hard problem — familiar from Terasology, where engine + dozens of module changelogs had to be aggregated into one release announcement — will show up for the **SiliconSaga stack** (yggdrasil + nordri + mimir + other components shipping together) rather than for GDD itself.

GDD has the ingredient Terasology lacked: **the merged ecosystem config is already a machine-readable manifest of the stack.** That makes the future shape a `ws` verb rather than a bespoke pipeline — e.g. `ws changelog <target>|--stack [--since <tag|date>]`, walking the declared components via `ws_resolve_target`, collecting each repo's conventional commits (or CHANGELOG section) since its last tag, and emitting one grouped stack-level draft. Same skill→script extraction principle as every other `ws` verb: the script gathers deterministically; the human/agent curates.

Parked until a stack release needs it; recorded here so the Terasology lesson isn't relearned. Tracked alongside the other deferred CLI ideas in the GA readiness doc (`R6`).
