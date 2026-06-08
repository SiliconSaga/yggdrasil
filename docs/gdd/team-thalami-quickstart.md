# Team Thalami — Quickstart (dogfooding `ws thalami publish`)

A minimal loop for promoting a personal arc to a shared team-thalami hoard.

## One-time setup

1. **Team hoard:** `ws hoard init team-thalami --name team-thalami-cfr`
   (push it to a shared remote when you want teammates to clone it).
2. **Notes vault:** `ws hoard init obsidian-vault --name obsidian-<you>` — where meeting notes / tab dumps live.
3. **Point your thalamus at the vault:** in your active `hoards/thalami/<host>-thalamus.md` frontmatter, set `vault: hoards/obsidian-<you>` — an absolute path, or a path relative to the workspace root (resolved against it, so it works from any directory).
   Your team identity defaults to your `identity.human_account` from ecosystem config — set a top-level `user:` in your thalamus only if you need to override it.
4. **Create the arc:** add an arc to that frontmatter, e.g.
   ```yaml
   - id: observability-improvements
     name: Observability improvements
     status: active
     started: 2026-06-04
     last_touched: 2026-06-04
     next: "summarize last meeting"
     published: true
   ```

## The loop

1. Tag a note for the arc — either in **frontmatter** (the Obsidian-idiomatic form, no `#`: a `tags:` list item `- team/observability-improvements`, or inline `tags: [team/observability-improvements]`) or as an **inline** `#team/observability-improvements` tag in the body. To keep a note out even if it carries the team tag, add a `private` or `noteam` tag (frontmatter `- private`, or inline `#private`) — built-in exclusion tags the sweep always skips (a bare mention of the word "private" in prose does not exclude).
2. Preview: `ws thalami publish --dry-run`.
3. Publish: `ws thalami publish` (review the file list, confirm), or `--yes` to skip the prompt.
4. Look: open the team hoard's `TeamArcDashboard.md` in Obsidian; browse `team-thalami-cfr/<you>/observability-improvements/` for the mirrored notes.
5. Edit notes or the arc's `next:`, re-publish, repeat. Re-publishing is idempotent (un-tagged notes drop off).
6. Share: `ws commit team-thalami-cfr <bodyfile>` and push when you want teammates to see the update. (Publish itself never commits or pushes.)

## Not yet (later plans)

- Auto-cloning the team hoard from a realm declaration.
- Orientation/housekeeping surfacing the team hoard or prompting to publish.
- GitLab Pages rendering of the dashboard.
