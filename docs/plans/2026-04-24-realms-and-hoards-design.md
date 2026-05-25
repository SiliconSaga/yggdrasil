# Realms and Hoards — Design Spec

**Date:** 2026-04-24
**Status:** Draft
**Extends:** [Overlay Architecture](2026-03-26-overlay-architecture-design.md)

---

## Summary

Three coordinated changes to the Yggdrasil workspace structure:

1. **Rename *overlay* → *realm*.** Better fit with the Norse theme (Yggdrasil
   connects realms). Clean cut; no deprecation aliases.
2. **Introduce *hoards*** — a new top-level directory for personal, per-user
   grab-bag containers. The canonical v1 hoard type is `thalami`, which holds
   per-machine Thalamus files synced across a user's machines. Structure is
   intentionally extensible to future hoard types (Obsidian vaults, zipped
   sample projects, etc).
3. **Promote *templates* to top-level.** Move the scaffolding files out of
   `.agent/` into `templates/`. Templates are workspace scaffolding, not
   agent-specific — this reclassification makes the concept first-class and
   gives hoard templates a natural home.

Design principle carries over from the overlay spec: **always functional,
progressively richer.** A bare workspace with no realm, no hoard, and a
root `Thalamus.md` continues to work. Cloning a realm makes it richer.
Cloning a hoard makes it richer still.

---

## Vocabulary

| Term | Meaning | Scope |
|------|---------|-------|
| **Realm** | A community-owned configuration repo declaring components, identity, adapters, and AI context. One active realm per workspace. | Shared / community |
| **Hoard** | A personal container repo. Named `<type>-<username>`. Multiple hoards can coexist in a workspace. Orientation cares about specific hoard types (e.g. `thalami`); others are the user's own business. | Personal / per-user |
| **Thalami** (plural of Thalamus) | The canonical v1 hoard type. Holds per-machine Thalamus files so a user's preferences, observations, and concerns sync across machines. | Per-user |

A realm has **special meaning** — it's tied to a specific set of components
and community context. A hoard is a **grab-bag "other" container** — a named,
typed directory that happens to live in `hoards/`.

Inheritance between realms (e.g. corp → department → team) is a plausible
future direction but out of scope for v1. A one-line comment in code + a
Future Directions note is enough reservation.

---

## Directory Structure

```
yggdrasil/
  ecosystem.yaml                 # Upstream defaults
  ecosystem.local.yaml           # Per-developer overrides (gitignored)
  components/                    # Component repos (gitignored)
    terasology/
    ...
  realms/                        # Community configuration repos (gitignored)
    realm-siliconsaga/           # Active realm for this user
    realm-template/              # Starter template (shipped upstream)
  hoards/                        # Personal containers (gitignored)
    thalami-cervator/            # Canonical v1 hoard type
    obsidian-cervator/           # (future) personal notes vault
    ...
  templates/                     # Workspace scaffolding (new top-level)
    README.md
    thalamus.md
    commit.md
    change.md
    issue.md
    hoards/
      thalami/                   # v1-shipped hoard template
    external/                    # gitignored; future fetched templates
  scripts/
    ws
    ws-realm.sh                  # renamed from ws-overlay.sh
    ws-hoard.sh                  # new
    ...
  .agent/
    skills/                      # agent skills (unchanged)
  docs/
```

Both `realms/` and `hoards/` are gitignored with tracked `.gitkeep` files.
`templates/external/` is gitignored.

---

## Realms (the overlay rename)

### Clean-cut rename

| Old | New |
|-----|-----|
| `overlays/` | `realms/` |
| `overlay-yggdrasil-live` | `realm-<community>` (e.g. `realm-siliconsaga`) |
| `overlay-yggdrasil-template` | `realm-template` |
| `ws overlay …` | `ws realm …` |
| `overlay:` key in `ecosystem.local.yaml` | `realm:` |
| `OVERLAYS_DIR`, `ws_detect_overlay`, `scripts/ws-overlay.sh` | `REALMS_DIR`, `ws_detect_realm`, `scripts/ws-realm.sh` |

`ws_resolve_ecosystem()` keeps its name — no "overlay" in it, still accurate.

### Naming pattern correction

The old `overlay-yggdrasil-live` naming was goofy in hindsight — "yggdrasil"
is the workspace, not a community. The new pattern:

- **Community realm:** `realm-<community>`. Example: `realm-siliconsaga`.
- **Upstream template:** `realm-template`.
- **No `-live` suffix.** "Active" is determined by selector or by being the
  only non-template realm — not by dir name.

### Discovery

1. If `ecosystem.local.yaml` has a `realm:` selector, use that.
2. Else: scan `realms/` for any `realm-*` that is not `realm-template`.
   - Exactly one: use it.
   - Multiple: error with guidance to set `realm:`.
   - Zero: fall back to `realm-template` if present.
   - None at all: no realm active (upstream `ecosystem.yaml` only).

### Inheritance reservation

Multi-level realm inheritance (corp → dept → team) is a future direction.
The three-layer merge (`upstream → realm → local`) already templates the
pattern — dropping additional parents in is a small generalization when
needed. For v1:

- Future Directions section in this spec.
- One-line comment in `ws_resolve_ecosystem()` noting the N-layer future.
- One-line mention in `docs/ecosystem-architecture.md`.

No schema reservation (no `extends:` key parsed today).

---

## Hoards (new)

### What is a hoard?

A personal git repo living in `hoards/`, named `<type>-<username>`. Examples:

- `hoards/thalami-cervator` — per-machine Thalamus files (v1 shipped type)
- `hoards/obsidian-cervator` — personal Obsidian vault (future)
- `hoards/claudesidian-cervator` — Claudesidian-style notes (future)
- `hoards/samples-cervator` — zipped sample projects (future)

Hoards are typed. Orientation cares about specific types (today: `thalami`);
other hoards are the user's own business.

### Thalami hoard layout

Flat, at repo root:

```
hoards/thalami-<username>/
  README.md
  win10-desktop-thalamus.md     # this machine
  macbook-thalamus.md           # another machine
  ...
  (.gitignore if needed)
  (AGENTS.md if the user wants notes for future sessions)
```

No nested `thalami/` subdirectory — the repo's name already says `thalami`.
If internal structure becomes useful later, it can be retrofitted by making
the path template configurable (see below). 3–5 machine files at a flat root
is expected to be the steady state for a long time.

### Machine name

- Default: short hostname via the bash builtin `$HOSTNAME` with any
  domain suffix stripped (`${HOSTNAME%%.*}`). Portable across Linux,
  macOS, and Windows Git Bash; `hostname -s` is avoided because Windows
  Git Bash doesn't accept the `-s` flag.
- Override: `machine: <name>` in `ecosystem.local.yaml` for machines with
  awkward or unstable hostnames.

The resolved machine name determines `<machine>-thalamus.md`.

### Internal path configurability

The thalamus file path within a hoard is not hardcoded in the resolver
(future-proofing for subdirectory layouts). The path template defaults to
`{machine}-thalamus.md`. A config-level override is reserved for future
use if/when the flat layout outgrows itself — exact schema to be settled
at retrofit time, not now.

### Discovery

Config key (when override is needed) is nested under `hoards:`, keyed by
hoard type — extensible to future types:

```yaml
# ecosystem.local.yaml
hoards:
  thalami: thalami-cervator   # explicit active thalami hoard
```

Resolution:

1. If `hoards.thalami` is set in `ecosystem.local.yaml`, use it.
2. Else: scan `hoards/` for `thalami-*`.
   - Exactly one: use it.
   - Multiple: error with guidance to set `hoards.thalami`.
   - Zero: no thalami hoard active.

Mirrors realm discovery. Other hoard types are discovered similarly when
something is looking for them; v1 only ships thalami-aware orientation.

---

## Orientation Integration

### Dual-file awareness

On session start, orientation resolves Thalamus content from up to two
sources:

| Source | When used | Role |
|--------|-----------|------|
| `hoards/thalami-<user>/<machine>-thalamus.md` | Active thalami hoard exists | Primary — reads and writes default here |
| Root `Thalamus.md` | Present (with or without hoard) | Scratch — also read; writes only on explicit request |

**Precedence:** if a hoard thalamus exists, it is primary. Writes go there
unless the user explicitly asks for the scratch file. If both exist,
orientation reads both during content scan and briefly acknowledges the
split ("hoard thalamus (5 observations) + scratch (1 item)").

### "Scratch for free" emergence

A user's first session has no hoard. Orientation, finding no `Thalamus.md`,
offers to create one from the template → root `Thalamus.md` exists.
Later, the user runs `ws hoard init --from-thalamus`, which **moves**
`Thalamus.md` into the hoard as `<machine>-thalamus.md`. No scratch file
yet; the user's workflow is clean.

Sometime later, the user runs `hello` again on a fresh workspace without
first creating the hoard. Orientation again creates `Thalamus.md` at root.
If a hoard is then cloned (`ws hoard <git-url>`), the root file is
*already there* — and it naturally becomes the scratch, with no ceremony.
The two-tier pattern emerges without any scaffolding code.

### Fresh-workspace behavior

- No hoard, no root: orientation offers to create `Thalamus.md` (today's behavior).
- Hoard present, no root: orientation uses hoard thalamus, does not create root.
- Both present: hoard primary, root scratch. No prompt to reconcile.
- Root present, no hoard: today's behavior — orientation uses root.

### Multi-machine notes

The template for `<machine>-thalamus.md` is the same as today's
`Thalamus.md` template (now at `templates/thalamus.md`). Each machine's
file is its own full Thalamus with frontmatter, Preferences, Observations,
Concerns, etc. This is intentional: machine-specific context (friction,
observations) is allowed to be different per machine.

---

## Housekeeping Integration

### Multi-thalami review

`gdd-housekeeping` gains an opt-in mode that audits across every
`<machine>-thalamus.md` in the active thalami hoard:

1. Walk all files in the hoard root matching `*-thalamus.md`.
2. Identify Preferences / Observations that appear in one file but not others
   — candidates for cross-machine promotion (agent asks; user decides
   where to add them).
3. Identify apparent duplicates across files — candidates for dedup.
4. Update `last_audit` frontmatter on each reviewed file.

**Compare-only, v1.** No introduction of a shared/common file. If the pressure
for a shared file emerges over time (the same preference keeps getting
promoted everywhere), a `common-thalamus.md` can be added in v2 with a clear
precedence rule (common read first, per-machine overrides).

### CLI entry

Invoked via the existing housekeeping skill with a flag or mode selection
— specifics left to the housekeeping skill's own update. Not a new
top-level `ws` command.

---

## ws CLI Changes

### Realm (rename)

Subcommands are unchanged from the overlay spec, just renamed:

```
ws realm init               # Clone realm-template
ws realm <git-url>          # Clone a community realm
ws realm use <name>         # Set active realm
ws realm list               # Show realms, mark active
```

### Hoard (new)

```
ws hoard init [template] [template-args...]
ws hoard <git-url>
ws hoard list
```

**`ws hoard init [template]`** scaffolds a local hoard in
`hoards/<type>-<username>/` from an in-tree template:

- Template defaults to `thalami` if omitted.
- `<username>` is read from `identity.human_account` in the merged
  ecosystem config (typically set in `ecosystem.local.yaml`). If unset,
  `ws hoard init` errors with guidance pointing to the identity setup.
- Copies the template directory from `templates/hoards/<template>/` into
  the new hoard location, `git init`s it, and creates the first commit.
- User pushes to their own remote manually (e.g.
  `gh repo create cervator/thalami-cervator --private --source=.`). Not
  automated — it's a personal-repo decision.

**Template-specific args** are handled per-template. v1 supports:

- `ws hoard init thalami --from-thalamus` — moves root `Thalamus.md` into
  the new hoard as `<machine>-thalamus.md`. Prompts `y/N` before the move.
  Clear logging: "Moving `Thalamus.md` → `hoards/thalami-<user>/<machine>-thalamus.md`."

Wiring is hardcoded per-template in `ws-hoard.sh` for v1. If future templates
proliferate, a `template.yaml` manifest per template can generalize argument
declaration.

**`ws hoard <git-url>`** clones an existing hoard (e.g. from another
machine where the user already set it up). Local directory name is derived
from the repo name.

**`ws hoard list`** shows hoards in `hoards/`, with active thalami hoard
marked.

### Other commands (unaffected)

`ws commit`, `ws cr`, `ws issue`, `ws push`, `ws pull`, etc. are only
affected by path updates (templates moved out of `.agent/`) — see
Templates Relocation below.

---

## Templates Relocation

### Move from `.agent/` to top-level `templates/`

Templates are workspace scaffolding, not agent-specific. Four existing
files move out of `.agent/`:

| Old path | New path |
|----------|----------|
| `.agent/thalamus-template.md` | `templates/thalamus.md` |
| `.agent/commit-template.md` | `templates/commit.md` |
| `.agent/change-template.md` | `templates/change.md` |
| `.agent/issue-template.md` | `templates/issue.md` |

Name cleanup: drop the `-template` suffix. The context (`templates/`)
already says they are templates.

### Subdirectory for hoards

Hoard templates live under `templates/hoards/<type>/`:

```
templates/hoards/
  thalami/
    README.md
    (other template files if needed)
```

The four top-level templates (thalamus/commit/change/issue) stay at
`templates/` root. They are a small group; a git/forge subdirectory was
considered but rejected (naming clashes with other projects; three files
don't justify a group).

### Leaf-to-directory promotion pattern

A template starts as a single file (`templates/thalamus.md`). If it later
grows multi-file, it becomes `templates/thalamus/` with a default entry
file inside. Code that reads the template uses a resolver that handles
both:

```bash
resolve_template() {
    local name="$1"
    if [[ -f "$TEMPLATES_DIR/$name.md" ]]; then
        echo "$TEMPLATES_DIR/$name.md"
    elif [[ -d "$TEMPLATES_DIR/$name" ]]; then
        echo "$TEMPLATES_DIR/$name/default.md"   # or the conventional entry
    fi
}
```

Not implemented in v1 (all templates are currently leaf files); pattern
documented for future evolution.

### External templates (future)

`templates/external/` is reserved for fetched / externally-sourced
templates (a potential "marketplace" future direction). Gitignored with
a `.gitkeep` for now. No fetch command in v1.

### Script path updates

- `gdd-orientation` skill: read `templates/thalamus.md` (was `.agent/thalamus-template.md`)
- `ws commit`: read `templates/commit.md`
- `ws cr`: read `templates/change.md`
- `ws issue`: read `templates/issue.md`
- `ws hoard init`: copy from `templates/hoards/<template>/`

### AGENTS.md updates

The "Issue / CR / Commit Drafts" table in `AGENTS.md` updates paths from
`.agent/*-template.md` to `templates/*.md`.

---

## Migration

### Realm rename (for existing users — today, just you)

Manual, documented. Three local steps plus a GitHub rename:

```bash
# In yggdrasil root
mv overlays realms
mv realms/overlay-yggdrasil-live realms/realm-siliconsaga
# If you had an 'overlay:' selector in ecosystem.local.yaml, rename it to 'realm:'
```

Then on GitHub, rename the `SiliconSaga/overlay-yggdrasil-live` repo to
`SiliconSaga/realm-siliconsaga`. GitHub auto-redirects legacy URLs; existing
local clones' `origin` (or equivalent) URL keeps working.

If you also use `overlay-yggdrasil-template`, rename its clone too:
`mv realms/overlay-yggdrasil-template realms/realm-template` plus the
GitHub repo rename.

**No `ws realm migrate` command.** One user, one-shot migration — not worth
maintaining code for.

### Thalamus migration (opt-in, any time)

```bash
ws hoard init thalami --from-thalamus
```

Prompts `y/N`, moves root `Thalamus.md` → `hoards/thalami-<user>/<machine>-thalamus.md`,
creates an initial commit in the new hoard, prints the result and the
suggested remote-push command.

If the user wants a scratch file after migrating, they can create one
manually later (`cp templates/thalamus.md Thalamus.md`). v1 does not
auto-create a scratch.

### Template relocation (one-shot, with this change)

`git mv` the four files out of `.agent/` to `templates/`, drop the
`-template` suffix, update every script/skill/doc path reference. Commit
as part of this change.

---

## Documentation Updates

Touched files:

- **`AGENTS.md`** — realm vocabulary, hoard concept, new `ws hoard` commands, updated template paths.
- **`CLAUDE.md`** — workspace structure section, realm/hoard terminology.
- **`.agent/skills/gdd-orientation/SKILL.md`** — hoard discovery, thalami file resolution, dual-file awareness, machine-name handling, template path update.
- **`.agent/skills/gdd-housekeeping/SKILL.md`** — multi-thalami review mode.
- **`docs/ecosystem-architecture.md`** — realm vocabulary, hoard section, one-line inheritance-future comment, Mermaid diagram updates (realms + hoards).
- **`docs/getting-started/index.md`** — realm/hoard vocabulary in the new-user flow.
- **`docs/ws-cli-guide.md`** — new `ws hoard` subcommands, renamed `ws realm`.
- **`docs/plans/2026-03-26-overlay-architecture-design.md`** — kept as historical predecessor. This spec supersedes and references it.

---

## User Experience

### New user, first session

```bash
git clone <yggdrasil>
cd yggdrasil
ws realm init                   # gets the template (tutorial realm)
ws clone --all                  # clones tutorial components
# Start Claude Code; orientation creates Thalamus.md at root as today
```

No hoard at this stage — personal sync across machines isn't a concern yet.

### Existing community member

```bash
git clone <yggdrasil>
cd yggdrasil
ws realm https://github.com/SiliconSaga/realm-siliconsaga.git
ws clone --all
# Optional: pull in personal hoard from another machine
ws hoard https://github.com/cervator/thalami-cervator.git
```

Orientation finds both the realm and the hoard. Thalamus reads come from
`hoards/thalami-cervator/<machine>-thalamus.md`.

### Moving to a new machine

```bash
git clone <yggdrasil>
cd yggdrasil
ws realm <community-realm-url>
ws hoard https://github.com/cervator/thalami-cervator.git
# A new <new-machine>-thalamus.md is created on first session from template
```

Preferences and observations from other machines are immediately visible
during orientation. Machine-specific items stay on their own machine's file.

### Creating a thalami hoard from an existing root Thalamus.md

```bash
ws hoard init thalami --from-thalamus
# Prompts y/N, moves the file, creates the hoard
# User pushes to their own remote:
gh repo create cervator/thalami-cervator --private --source=hoards/thalami-cervator
```

---

## Future Directions

- **Realm inheritance (multi-layer realms).** Corp → department → team
  chains. The existing three-layer merge (upstream → realm → local)
  generalizes to N layers with a child-wins rule. Useful for organizations
  where different teams share a common base but diverge in details (e.g.
  corporate-style department / team layering). Not needed yet.
- **Additional hoard templates.** `obsidian` (personal Obsidian vault),
  `claudesidian` (Claudesidian-style notes), `samples` (zipped sample
  projects). Each lives in `templates/hoards/<type>/` and ships in the
  upstream yggdrasil repo.
- **Shared/common thalamus file.** A `common-thalamus.md` in the thalami
  hoard, read by every machine's orientation on top of the per-machine
  file. Only worth adding if multi-thalami review consistently surfaces
  the same preferences getting promoted to every machine.
- **Realm templates in-tree.** If realm scaffolding ever gains a
  "copy-don't-fork" path, `templates/realms/<flavor>/` is the natural home
  (parallel to `templates/hoards/`). Today realms remain external repos
  expected to grow through fork history.
- **External / fetched templates.** `templates/external/` exists (gitignored)
  for a future `ws template fetch <url>` or template marketplace. Not built
  in v1.
- **`ws realm migrate` command.** If the workspace ever grows beyond a
  single-user migration window, an automated realm-rename command could
  move the directory, rename the subdirectory, and update the local config
  key.
