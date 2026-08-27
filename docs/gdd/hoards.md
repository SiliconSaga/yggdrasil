# Hoards

A **hoard** is a personal git repo that lives inside the workspace at `hoards/<type>-<user>/`, alongside the components and realms. The yggdrasil workspace is the only "shared" part of the tree — components and realms come from elsewhere; hoards come from *you*. They're a catch-all for content that isn't a component (a project) and isn't a realm (community config), but still wants to live next to your work and ride the `ws` CLI for sync.

The canonical hoard type is **thalami** — the per-developer container for the [Thalamus](thalamus.md). The other shipped type is the [**obsidian-vault**](obsidian-vault.md) — a PARA-laid-out Obsidian vault for personal knowledge management, paired with the scribe role. The architecture is intentionally generic, so further types (scratch spaces, personal experiments) slot in without redesign.

---

## Why hoards live where they do

A hoard is "personal" but not necessarily "private." A thalami hoard typically pushes to a private GitHub repo on your namespace, but nothing stops you from keeping it local-only or making it public.

The placement at `hoards/<type>-<user>/` matters for two reasons:

1. **`ws` operations work transparently.** `ws status`, `ws commit`, `ws push`, `ws log` all walk hoards the same way they walk components — no `cd hoards/...` needed.
2. **Multi-machine sync via git.** Edit on one machine, commit, push, pull on another. The thalami type uses per-machine files (`<machine>-thalamus.md`) so two machines don't collide on the same lines, but they share the hoard's audit log and any committed history.

Hoards are gitignored from the workspace itself — they're independent git repos, just like components. The workspace's `.gitignore` lists `hoards/`; the workspace's history doesn't track them.

---

## Setting up a thalami hoard

```bash
ws hoard init                  # creates hoards/thalami-<your-user>/
# OR, to migrate an existing root Thalamus.md into the new hoard:
ws hoard init --from-thalamus
```

The output prints a `gh repo create` next-step. For a private personal hoard, run something like:

```bash
gh repo create <user>/thalami-<user> --private \
  --source=hoards/thalami-<user> --remote=<user> --push
```

For the agent's PAT to push to your hoard (so `ws push thalami-<user>` works without a personal interactive auth step), add `agent-refr` (or whatever your agent identity is) as a GitHub collaborator on the hoard repo — the PAT inherits write access via that collaboration.

After `init`, `ws status` will show the new hoard in its listing, and the next session's orientation will resolve it as the active thalami hoard.

---

## Per-machine files

The thalami hoard contains one `<machine>-thalamus.md` file per workstation you use. The machine name comes from the environment variable `$HOSTNAME` with any domain suffix stripped (so `dionysus.local` becomes `dionysus`); set `machine: <name>` in `ecosystem.local.yaml` to override if your hostname is unstable.

Each per-machine file carries:

- **Frontmatter** for per-machine state: `last_session`, `last_audit`, and the audit `staleness_days` (housekeeping cadence — distinct from the hoard-wide commit cadence covered below, which lives in `.ws-cadence.yaml` at the hoard root). Role, stance, and mentoring are not stored here; they're established per session via `ws session`.
- **Body sections**: Preferences, Observations, Concerns, Audit Log (per the Thalamus model — see [thalamus.md](thalamus.md)).

Per-machine files also carry an `arcs:` list — short entries (slug, status, next step) that surface as a live cross-host table when the hoard is opened as an Obsidian vault with the Dataview plugin installed. See [the arc dashboard design](../plans/2026-05-07-thalamus-arc-dashboard-design.md) for the schema, lifecycle, and skill integration; see the hoard's own `ArcDashboard.md` for the rendered view.

Why per-machine? Two reasons:

1. **Avoids merge conflicts.** Two machines editing the same file between syncs would collide on every other line. Per-machine files eliminate that class of conflict.
2. **Reflects reality.** Each machine has its own context (different keyboard, different network, different screen). Preferences that make sense at the desk don't always make sense on the laptop. Per-machine files keep that fidelity.

Cross-machine concerns (preferences that apply everywhere, duplicate observations on multiple machines) get reconciled during **multi-thalami housekeeping** — see the `gdd-housekeeping` skill's "Multi-Thalami Review" section.

---

## Cadence config — `.ws-cadence.yaml`

A small file at the hoard root controls when the orientation skill nudges you to commit accumulated changes. Default contents (shipped in the `templates/hoards/thalami/` template):

```yaml
staleness_days: 2
```

That's the threshold the orientation skill uses: if your per-machine thalamus has been dirty for longer than this, surface a "commit your thalamus before we start?" nudge at session start.

The file is committable, hoard-wide, and shared across machines — it's a workflow preference, not a per-machine value. Edit `staleness_days` to tune; commit and push so other machines pick it up. If the file is missing or the field is unset, the cadence script defaults to 2 days.

The check itself runs as `ws hoard cadence` and reports a status line (`clean`, `dirty-fresh`, `dirty-stale`, `never-committed`, `no-active-hoard`, `no-thalamus-file`) plus elapsed-time fields the nudge text substitutes in. The orientation skill calls it automatically; you can also run it manually any time.

**Migrating an existing thalami hoard** without `.ws-cadence.yaml`: copy `templates/hoards/thalami/.ws-cadence.yaml` into your hoard root, commit, and push. A per-machine `commit_staleness_days` frontmatter field is ignored; without the new file, the cadence script falls back to its 2-day default.

**Future direction: scope filters.** A `watch:` glob list could let other hoard types scope dirty-detection (e.g., a vault hoard counting `*.md` but ignoring `_attachments/`). Not implemented in v1 — thalami's per-machine-file watching is hardcoded — but the extension point is reserved for when a second hoard type needs it.

---

## Frontmatter lint — `ws hoard lint`

```bash
ws hoard lint            # the active thalami hoard
ws hoard lint thalami    # a named one
```

Checks every `*-thalamus.md` in the hoard — all hosts, not just this machine's — for the things the [arc schema](../plans/2026-05-07-thalamus-arc-dashboard-design.md) requires and nothing else enforces:

- the frontmatter block parses as YAML at all
- each arc carries `id`, `name`, `status`, `started`, `last_touched`, `next`
- `status` is one of `active`, `review`, `parked`, `closed`, `promoted`
- `next` is a single line under `WS_ARC_NEXT_MAX` characters (default 200)

Output is `key: value` lines plus one line per finding, the same greppable shape as `ws hoard cadence`. It exits **0** when clean, **1** when it has findings, and **2** on a tooling failure — so a caller that only wants a warning should read the `status:` line rather than the exit code.

**Why it exists.** The arc schema had three enforcement layers — the schema block in `ArcDashboard.md`, the rules in `gdd-housekeeping`, the narration step in `gdd-orientation` — and all three were prose. Nothing parsed the YAML, which made one failure mode completely silent: the dashboard selects files with `WHERE arcs`, and a file whose frontmatter fails to parse simply stops matching. Every arc on that host vanishes from the cross-host view while the file still reads perfectly to a human or an agent, and it stays that way until somebody notices the row count looks low. The usual cause is an unescaped `"` inside a quoted `next:` value, which closes the scalar early and takes the whole document with it.

`gdd-orientation` runs it at session start as a warning; `gdd-housekeeping` runs it at the top of the arc walk. Both are advisory — the lint never edits anything.

Since `ws lint` accepts hoard names too, a realm that wants the reflex verb to work on a thalami hoard can point its adapter at this command:

```yaml
# realms/<realm>/adapters/<hoard-name>.yaml
commands:
  lint: "ws hoard lint <hoard-name>"
```

That is optional sugar — `ws hoard lint` works with no adapter at all.

**On `last_touched`.** The lint checks the field is present, but only you can tell whether it is *true*. It is the input to the dashboard's decay icons and to housekeeping's stale-arc check, and nothing computes it — so the convention is that whoever edits an arc stamps it in the same edit. An unstamped edit leaves a moving arc looking abandoned, which is worse than no signal because the dashboard is trusted.

---

## Multi-machine workflows

The standard pattern with a thalami hoard across machines:

1. **Start a session.** Orientation reads `<machine>-thalamus.md`, may nudge if cadence threshold passed.
2. **Work.** Agent writes observations / preferences / concerns into the per-machine file as they accumulate.
3. **Commit when prompted** (or at natural endpoints — end of session, before stance switch, during housekeeping).
4. **`ws push thalami-<user>`** to sync to the personal remote.
5. **On the next machine**: `ws pull thalami-<user>` brings down the committed state. Orientation sees the updated audit log, other machines' files (read-only signals about what's happening elsewhere), and any cross-machine preferences from the housekeeping skill's multi-thalami review.

Two coexisting modes that work well:

- **Each machine commits its own per-machine file.** The hoard's history shows alternating commits per machine.
- **One machine does cross-machine housekeeping** (typically the most-used desktop): it walks all `<machine>-thalamus.md` files, promotes universal preferences, and dedups observations. Edits to another machine's file happen only in this coordinated mode, while that machine's sessions are idle — the everyday per-machine write rule exists to prevent concurrent-edit conflicts, and idle-time housekeeping is the one sanctioned exception. The other machines pick up the consolidated state on next pull.

**Push directly to `main` — no PR ceremony.** Thalami (and other personal hoards) are stream-of-consciousness notes; bot review adds nothing useful and a PR/review cycle just slows down sync. The convention: `ws commit` → `ws pull` (fetch+rebase) → `ws push`, straight to `main`. PRs are a component-and-realm pattern.

---

## Upgrading a hoard

A hoard tracks where it came from in a git-committed `.hoard.yaml` at its root — the source `template` and the `applied_version` of that template's recipe last applied. `ws hoard init` writes it; existing hoards adopt it on first upgrade (see below).

Templates evolve — a new plugin, a new managed block on a dashboard — and `ws hoard upgrade <hoard>` is how a hoard catches up. It's provenance-tracked and plan-first: it never guesses which template applies and never changes anything without showing you first.

- `ws hoard upgrade <hoard> --plan` reads the template from `.hoard.yaml`, diffs the template's desired state against your live hoard, and prints a classified change set — additive (enable a new plugin), region edits (a template-managed block inside a file, delimited by `<!-- BEGIN upgrade-<id> -->` sentinels), and destructive (remove a file, disable a core plugin) — touching nothing.
- `ws hoard upgrade <hoard> --apply` snapshots the whole hoard to `.upgrade-backup/<timestamp>/` first, then applies the plan and bumps `applied_version`. If the backup can't be taken, it aborts before changing anything.
- `ws hoard upgrade <hoard> --rollback` restores the most recent snapshot, so you can apply, inspect in Obsidian, and retry until it's clean.

Templates that install Obsidian plugins carry an `assets:` lock beside each release pin. Init and upgrade download every declared `main.js`, `manifest.json`, and optional `styles.css` into temporary staging, verify their committed SHA-256 values, and leave the installed plugin set untouched if any download or digest fails. Maintainers bump a plugin by editing its `pin:`, running `ws hoard lock <template> --plugin <id>`, reviewing the resulting lock-only diff, incrementing the template's top-level `version:`, then running `ws hoard upgrade <hoard> --plan` and approving `--apply`; omitting `--plugin` refreshes the complete template lock atomically. The lock command deliberately changes only `assets:` values and never advances the upgrade version itself.

The `gdd-hoard-upgrade` skill drives the loop: it runs `--plan`, proposes the destructive and region changes to you for approval (additive changes are safe), and only then runs `--apply`. A hoard without `.hoard.yaml` is adopted with `--template <name>`, which records provenance one version behind the template so only the newest change applies rather than re-applying the whole recipe.

(Plugin `data.json` is currently overwritten on apply rather than merged, so per-hoard plugin-setting tweaks don't yet survive an upgrade — tracked as future work.)

---

## Hoard types

Two types ship today:

- **thalami** — the per-machine Thalamus container this page mostly describes. The default for `ws hoard init`.
- **obsidian-vault** — a PARA-laid-out Obsidian vault with a curated plugin set, seeded on init. Lands your knowledge graph as a hoard, with `ws push/pull` ergonomics and cadence config for keeping it synced. Full reference: [obsidian-vault.md](obsidian-vault.md).

Plausible future types:

- **Scratch / experiment** spaces — short-lived hoards for spike work that shouldn't pollute components but you want the workspace's CLI ergonomics for.
- **Cross-tool transcripts** — agent session transcripts, voice memos, anything that's "yours" but not a project.

Each new type ships as a `templates/hoards/<type>/` directory with its own scaffold. The `ws hoard init <type>` command picks it up automatically. If the type wants its own cadence behavior, it ships a `.ws-cadence.yaml` (or omits it for the default).

---

## See also

- [GDD Features Tour](features.md) — where hoards fit in the larger feature set.
- [Thalamus](thalamus.md) — the thinking-space concept the thalami type is built around.
- [Trust and Safety](trust-and-safety.md) — hoards' trust level (your own content, equivalent to your other instructions).
- [Roles and Stances](roles-and-stances.md) — the role and stance concepts that sessions are configured with.
- [`gdd-orientation` skill](../../.agent/skills/gdd-orientation/SKILL.md) — how the startup sequence resolves the thalamus and reacts to `ws hoard cadence` and `ws hoard lint`.
- [`gdd-housekeeping` skill](../../.agent/skills/gdd-housekeeping/SKILL.md) — multi-thalami review process, including the arc walk that `ws hoard lint` feeds.
- [Arc Dashboard design doc](../plans/2026-05-07-thalamus-arc-dashboard-design.md) — the arc lifecycle and schema the lint enforces.
