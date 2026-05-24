---
name: gdd-hoard-upgrade
description: Use when upgrading a hoard from its template (ws hoard upgrade) — runs the plan, proposes destructive/region changes to the human, then applies with a backup.
---

# Upgrading a hoard

Drives the provenance-tracked `ws hoard upgrade` flow: plan → propose → apply. The script is deterministic; this skill is the judgment + human-approval layer between `--plan` and `--apply`.

1. Run `ws hoard upgrade <hoard> --plan` (add `--template <name>` if the hoard has no `.hoard.yaml` yet — that adopts it at a baseline one version behind so only the latest bump applies). Read the classified plan lines: `uptodate`, `provenance`, `additive`, `region-insert`, `region-edit`, `destructive`.
2. If the only line is `uptodate`: stop, report nothing to do.
3. `additive` lines (enable a new plugin, seed a new config) and `provenance` are safe — note them, no approval needed.
4. For each `region-insert`: open the target file, and propose an exact insertion point to the human (the script's mechanical default is append-to-end; suggest a better spot if the file has obvious structure). For `region-edit`: show the human the diff of the managed block. For `destructive` (remove a file, disable a core plugin): name the file/plugin and why the template changes it, and get explicit approval.
5. Once the human has approved the `region-*` and `destructive` lines, run `ws hoard upgrade <hoard> --apply`. It snapshots the whole hoard to `.upgrade-backup/<ts>/` first, then applies. Report the backup path it prints.
6. Tell the human to open the hoard in Obsidian (plugins activate on launch). If anything looks wrong, `ws hoard upgrade <hoard> --rollback` restores the pre-apply snapshot so they can retry.

**Never** run `--apply` before the human has approved the `destructive` and `region-*` lines from `--plan`. `additive`-only plans may be applied once the human has seen the plan.
