# `ws hoard upgrade` v2 — provenance-tracked, plan/apply, agent-mediated

**Status:** design (brainstormed 2026-05-23). Implementation plan: [`2026-05-23-hoard-upgrade-v2-plan.md`](2026-05-23-hoard-upgrade-v2-plan.md).

## Problem

`ws hoard upgrade` is currently disabled behind a `WS_HOARD_UPGRADE_ENABLED=1` gate. The reasons it was disabled (see `scripts/ws-hoard-upgrade.sh` header + the 2026-05-22 Thalamus observation):

- **No provenance.** The command auto-discovers "the one template that ships an `.upgrade/upgrade.yaml`" (today only `obsidian-vault`) and applies it to *any* hoard named — so running it against a `thalami` hoard pushed the full PARA-vault plugin suite (Templater, Periodic Notes, Calendar, **Linter**, **Filename Heading Sync**, …) onto a vault that only wants Dataview. Linter (auto-format on save) and Filename Heading Sync (renames H1/filename) would then edit the thalamus files on next Obsidian open.
- **Blind apply.** Even with the right template, the run overwrites `data.json` files, rewrites `community-plugins.json`, disables core plugins, and `rm`s declared files with no preview and no consent. There is no diff, no backup, no human gate.

The goal is to re-enable the command by replacing blind apply with a provenance-tracked, plan-first, agent-mediated, human-approved flow — and to prove it on a real change (`thalami` gaining the Meta Bind plugin plus interactive controls on `ArcDashboard.md`).

## Goals

- **Provenance:** every hoard records which template it came from and which version it has been upgraded to, so the tool never guesses.
- **Declarative desired-state + reconcile:** the template declares the desired end state (plugins, disabled core plugins, removed files, template-managed file regions) plus a `version`; the tool diffs that against the live hoard and decides what to change.
- **Plan / apply split:** `--plan` computes and prints the change set, touching nothing; `--apply` executes an approved plan after taking a backup.
- **Agent-mediated approval:** a `gdd-hoard-upgrade` skill runs `--plan`, lets the agent interpret it and propose the risky changes (destructive ops, edits to user-customized files) to the human, and only then runs `--apply`.
- **Backup + rollback:** `--apply` snapshots the whole hoard before changing it; `--rollback` restores the latest snapshot, so an upgrade can be applied, inspected, and retried until clean.
- **`thalami` gets its own recipe:** a minimal `.upgrade/upgrade.yaml` so it is no longer mismatched against `obsidian-vault`'s.
- **Re-enable:** drop the `WS_HOARD_UPGRADE_ENABLED` gate once provenance resolves the template.

## Non-goals (explicit future seams, not built here)

- **Software-component upgrades (Dependabot-style).** The provenance + version concept is meant to generalize to `components/` later, but nothing component-facing is built now. The design only avoids decisions that would foreclose it.
- **Three-way JSON merge for `data.json`.** The current overwrite-on-apply behavior for plugin `data.json` is kept. `thalami`'s recipe is tiny, so the risk is low; the three-way merge cited in the yggdrasil#54 follow-up is deferred.
- **A general filter/sort UX for `ArcDashboard`.** The Meta Bind controls region added here is the first concrete managed-region, not a full dashboard redesign.

## Architecture

### Provenance — `.hoard.yaml`

Each hoard carries a git-committed `.hoard.yaml` at its root:

```yaml
template: thalami
applied_version: 1
```

- `template` names the template directory under `templates/hoards/<template>/` the hoard was scaffolded from.
- `applied_version` is the integer `version` of that template's `.upgrade/upgrade.yaml` last successfully applied.
- Git-committed (not under gitignored `.obsidian/`) because it is the durable hoard→template link, shared across the hoard's machines.

`ws hoard init` writes `.hoard.yaml` for new hoards (with `applied_version` set to the template's current `version`). Existing hoards are retrofitted (see "Adopting existing hoards").

### Manifest — versioned `.upgrade/upgrade.yaml`

The existing declarative manifest gains a top-level `version` (monotonic integer) and a `managed_regions` block. Existing keys (`plugins`, `core_plugins_disable`, `files_remove`) keep their meaning. Example (`thalami`, see worked example below):

```yaml
version: 2
description: |
  Thalami hoard — Dataview for the ArcDashboard, plus Meta Bind for
  the dashboard's interactive controls.
plugins:
  - id: dataview
    name: Dataview
    description: Query engine powering ArcDashboard.md.
    repo: blacksmithgu/obsidian-dataview
    pin: "0.5.68"
  - id: obsidian-meta-bind-plugin
    name: Meta Bind
    description: Inline inputs/buttons bound to frontmatter; powers the ArcDashboard controls.
    repo: mProjectsCode/obsidian-meta-bind-plugin
    pin: "1.4.1"        # pin verified at implementation time
managed_regions:
  - file: ArcDashboard.md
    id: controls
    source: regions/arcdashboard-controls.md   # relative to .upgrade/
```

- `version` is what `applied_version` is compared against. The tool applies the manifest when `applied_version < version`.
- `managed_regions` declares parts of a content file the template owns. `file` is hoard-relative; `id` is the sentinel slug; `source` is a file under `.upgrade/` whose contents fill the region. The managed text lives between `<!-- BEGIN upgrade-<id> -->` and `<!-- END upgrade-<id> -->` markers — the same mechanism the README "Installed plugins" block already uses (`_ws_hoard_upgrade_from_template` in the current script).

The manifest describes a **desired end state**, not per-version migration scripts. The `version` is a coarse "has this hoard seen the current recipe?" marker, not a sequence of ordered steps. (If per-version ordering is ever needed — e.g. a change that must run before another — that is a future extension; YAGNI now with two templates.)

### Flow — `--plan` → propose → `--apply`

```
ws hoard upgrade <hoard> --plan
  1. Read <hoard>/.hoard.yaml → template + applied_version.
     (If absent: emit a "establish provenance" step — see Adopting existing hoards.)
  2. Read templates/hoards/<template>/.upgrade/upgrade.yaml → version + desired state.
  3. If applied_version >= version: report "up to date", empty plan.
  4. Else diff desired-state vs the live hoard and classify each change:
       additive    — enable a not-yet-present plugin, seed a new data.json,
                     insert a managed region whose markers are absent
       region-edit — replace the content inside an existing managed region
       destructive — disable a core plugin, remove a declared file, or
                     overwrite an existing data.json
  5. Print the plan (human-readable + a machine-readable form), change NOTHING.

[gdd-hoard-upgrade skill]
  - Runs --plan, reads the classified plan.
  - Auto-OK for additive ops.
  - For each region-edit and destructive op: show the human exactly what
    changes (the region diff, the file to be removed), get approval.
  - On approval, runs --apply.

ws hoard upgrade <hoard> --apply
  1. Recompute the plan (same logic as --plan).
  2. Backup: copy the whole hoard to <hoard>/.upgrade-backup/<timestamp>/
     (excluding .git/ and .upgrade-backup/ itself). Abort the apply if the
     backup fails — never change the hoard without a restore point.
  3. Execute the plan: download plugins, seed data.json, write
     community-plugins.json, disable core plugins, remove files, splice
     managed regions.
  4. Write <hoard>/.hoard.yaml with applied_version = version.
  5. Report what changed and where the backup lives.

ws hoard upgrade <hoard> --rollback
  - Restore the most recent <hoard>/.upgrade-backup/<timestamp>/ over the
    hoard (the inverse copy), so a botched upgrade can be undone and retried.
```

The script stays deterministic: it classifies and applies, but it does not decide whether a destructive op is acceptable — that judgment is the skill+human's. The plan is the contract between them.

### Managed regions

A managed region is delimited by `<!-- BEGIN upgrade-<id> -->` / `<!-- END upgrade-<id> -->` sentinels inside a content file. On apply:

- **Markers present:** replace everything between them with the region `source` content (idempotent; user content outside the markers is untouched). This is a region-edit.
- **Markers absent:** the region has never been inserted. The plan classifies this as additive-insert, but *where* to put it in a user-customized file is a judgment call — so the plan flags it for the agent, which proposes an insertion point (e.g. "after the H1, before the first `dataview` block in `ArcDashboard.md`") for the human to approve. Once inserted with markers, all future upgrades are clean marker-replacements.

This keeps the template's ownership scoped to the marked block and never clobbers the surrounding note.

### Adopting existing hoards

The four live `thalami` hoards predate `.hoard.yaml`. On the first `--plan` against a hoard with no `.hoard.yaml`:

- The tool infers the template. For a single-machine run this is unambiguous only if told; to stay safe it does **not** guess across templates. Resolution order: (a) explicit `--template <name>` flag, else (b) if the hoard name or contents match exactly one template's signature (e.g. an `ArcDashboard.md` + `Intake.md` ⇒ `thalami`), use it, else (c) error asking for `--template`.
- The plan's first step is **establish-provenance**: write `.hoard.yaml` with `applied_version` set to a **baseline** — the version representing the hoard's current shipped state (for the live thalami hoards: the pre-Meta-Bind baseline, `version: 1`). This ensures the very next change (`version: 2`, Meta Bind + controls) is what applies, rather than re-applying the whole recipe from zero.

### Re-enable

Once `.hoard.yaml` provenance exists and `thalami` ships its own `.upgrade/upgrade.yaml`, the `WS_HOARD_UPGRADE_ENABLED` gate and the "multiple upgradeable templates" error are removed: the template is read from `.hoard.yaml`, so there is no cross-template misapplication to guard against. `ws hoard init`'s existing call into the internal apply path is unaffected (it already passes an explicit template).

## Worked example — `thalami` v1 → v2 (the test vehicle)

1. **`thalami` template gains `.upgrade/upgrade.yaml`** at `version: 1` describing the current baseline: Dataview only, no managed regions. This is what the live hoards get retrofitted to.
2. **Bump to `version: 2`:** add the `obsidian-meta-bind-plugin` to `plugins`, and a `managed_regions` entry for `ArcDashboard.md` region `controls`, whose `source` (`regions/arcdashboard-controls.md`) contains the Meta Bind widget block (a refresh button + a filter/sort input bound to dashboard frontmatter — exact widget syntax verified against the pinned Meta Bind version during implementation).
3. **Upgrade a live hoard:** `ws hoard upgrade thalami-Cervator --plan` ⇒ establish-provenance @ v1 (first run), then v1→v2: additive (enable Meta Bind, download its release) + additive-insert (`ArcDashboard.md` `controls` region, markers absent ⇒ agent proposes placement). No destructive ops in this bump. The skill proposes the ArcDashboard insertion, human approves, `--apply` backs up the hoard, installs Meta Bind, splices the region, writes `.hoard.yaml` @ v2.
4. **Re-runnable:** a second `--plan` reports up-to-date (`applied_version 2 >= version 2`).

This exercises every new mechanism (provenance write + retrofit, plan classification, additive plugin install, region insert, backup, version bump) on a real, useful change, and is the basis for "test locally then on the three other workspaces."

## Error handling

- **No `.hoard.yaml` and template not resolvable:** error, ask for `--template`.
- **Template has no `.upgrade/upgrade.yaml`:** error (nothing to upgrade).
- **`gh` / `jq` / `yq` missing:** error with install hint (as today).
- **Backup fails (disk, permissions):** abort `--apply` before any change.
- **`--rollback` with no backup present:** error, no-op.
- **Plugin download fails mid-apply:** report which plugin/tag failed; the backup is the recovery path (advise `--rollback`).
- **Managed-region markers malformed (e.g. BEGIN without END):** treat as a conflict, surface to the agent rather than blindly rewriting.

## Testing strategy

bats coverage under `tests/ws-hoard-upgrade/`, isolated via `ROOT_DIR` / `HOARDS_DIR` overrides (the pattern `tests/ws-smoke` and `tests/ws-clean` use), with plugin downloads stubbed (no real `gh` calls in tests — inject a fake downloader or assert on the plan rather than network effects):

- `--plan` classification: additive vs region-edit vs destructive, and "up to date" when `applied_version >= version`.
- Provenance: `--plan`/`--apply` writes `.hoard.yaml`; retrofit writes the baseline; `--template` override; refusal when template unresolvable.
- Region splice: insert when markers absent (with an explicit anchor in the test), replace when present, idempotent re-run, malformed-marker conflict.
- `--apply`: backup directory created before changes; `applied_version` bumped; `files_remove` / `core_plugins_disable` honored.
- `--rollback`: restores the latest snapshot; errors with no snapshot.
- Re-enable: command runs without `WS_HOARD_UPGRADE_ENABLED`.

## Deferred / open items

- `data.json` three-way merge (kept as overwrite for now).
- Per-version ordered migrations (current model is desired-state + a coarse version marker).
- Component-level upgrades (future seam only).
- Exact Meta Bind pin + widget syntax — verified during implementation against the live plugin release.
