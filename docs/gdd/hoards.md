# Hoards

A **hoard** is a personal git repo that lives inside the workspace at
`hoards/<type>-<user>/`, alongside the components and realms. The
yggdrasil workspace is the only "shared" part of the tree — components
and realms come from elsewhere; hoards come from *you*. They're a
catch-all for content that isn't a component (a project) and isn't a
realm (community config), but still wants to live next to your work
and ride the same `ws` CLI for sync.

The canonical hoard type is **thalami** — the per-developer container
for the [Thalamus](thalamus.md). Other hoard types are likely to
emerge as the framework gets used (knowledgebase vaults, scratch
spaces, personal experiments); the architecture is intentionally
generic so they slot in without redesign.

---

## Why hoards live where they do

A hoard is "personal" but not necessarily "private." A thalami hoard
typically pushes to a private GitHub repo on your namespace, but
nothing stops you from keeping it local-only or making it public.

The placement at `hoards/<type>-<user>/` matters for two reasons:

1. **`ws` operations work transparently.** `ws status`, `ws commit`,
   `ws push`, `ws log` all walk hoards the same way they walk
   components — no `cd hoards/...` needed.
2. **Multi-machine sync via git.** Edit on one machine, commit, push,
   pull on another. The thalami type uses per-machine files
   (`<machine>-thalamus.md`) so two machines don't collide on the
   same lines, but they share the hoard's audit log and any
   committed history.

Hoards are gitignored from the workspace itself — they're independent
git repos, just like components. The workspace's `.gitignore` lists
`hoards/`; the workspace's history doesn't track them.

---

## Setting up a thalami hoard

```bash
ws hoard init                  # creates hoards/thalami-<your-user>/
# OR, to migrate an existing root Thalamus.md into the new hoard:
ws hoard init --from-thalamus
```

The output prints a `gh repo create` next-step. For a private personal
hoard, run something like:

```bash
gh repo create <user>/thalami-<user> --private \
  --source=hoards/thalami-<user> --remote=<user> --push
```

If you want the agent's PAT to be able to push to your hoard (so
`ws push thalami-<user>` works without a personal interactive
auth step), add `agent-refr` (or whatever your agent identity is)
as a GitHub collaborator on the hoard repo. The PAT inherits write
access via that collaboration.

After `init`, `ws status` will show the new hoard in its listing,
and the next session's orientation will resolve it as the active
thalami hoard.

---

## Per-machine files

The thalami hoard contains one `<machine>-thalamus.md` file per
workstation you use. The machine name comes from the bash builtin
`$HOSTNAME` with any domain suffix stripped (so `dionysus.local`
becomes `dionysus`); set `machine: <name>` in
`ecosystem.local.yaml` to override if your hostname is unstable.

Each per-machine file carries:

- **Frontmatter** for per-machine state: `last_session`, `last_audit`,
  default `mode`, default `role`, audit `staleness_days`.
- **Body sections**: Preferences, Observations, Concerns, Audit Log
  (per the Thalamus model — see [thalamus.md](thalamus.md)).

Why per-machine? Two reasons:

1. **Avoids merge conflicts.** Two machines editing the same file
   between syncs would collide on every other line. Per-machine files
   eliminate that class of conflict.
2. **Reflects reality.** Each machine has its own context (different
   keyboard, different network, different screen). Preferences that
   make sense at the desk don't always make sense on the laptop.
   Per-machine files keep that fidelity.

Cross-machine concerns (preferences that genuinely apply everywhere,
duplicate observations on multiple machines) get reconciled during
**multi-thalami housekeeping** — see the `gdd-housekeeping` skill's
"Multi-Thalami Review" section.

---

## Cadence config — `.ws-cadence.yaml`

A small file at the hoard root controls when the orientation skill
nudges you to commit accumulated changes. Default contents (shipped
in the `templates/hoards/thalami/` template):

```yaml
staleness_days: 2
```

That's the threshold the orientation skill uses: if your per-machine
thalamus has been dirty for longer than this, surface a "commit your
thalamus before we start?" nudge at session start.

The file is committable, hoard-wide, and shared across machines —
it's a workflow preference, not a per-machine value. Edit
`staleness_days` to tune; commit and push so other machines pick it
up. If the file is missing or the field is unset, the cadence script
defaults to 2 days.

The check itself runs as `ws hoard cadence` and reports a status
line (`clean`, `dirty-fresh`, `dirty-stale`, `never-committed`,
`no-active-hoard`, `no-thalamus-file`) plus elapsed-time fields the
nudge text substitutes in. The orientation skill calls it
automatically; you can also run it manually any time.

**Future direction: scope filters.** A `watch:` glob list at the
hoard root would let other hoard types scope dirty-detection to
specific files (e.g., a vault-style hoard might want all `*.md`
files to count, but ignore `_attachments/`). Not implemented in v1
because thalami's "watch the per-machine file specifically" is
hardcoded and that's the only shipping hoard type. Add `watch:` to
`.ws-cadence.yaml` when a second hoard type with different scoping
needs lands.

---

## Multi-machine workflows

The standard pattern with a thalami hoard across machines:

1. **Start a session.** Orientation reads `<machine>-thalamus.md`,
   may nudge if cadence threshold passed.
2. **Work.** Agent writes observations / preferences / concerns into
   the per-machine file as they accumulate.
3. **Commit when prompted** (or at natural endpoints — end of
   session, before mode switch, during housekeeping).
4. **`ws push thalami-<user>`** to sync to the personal remote.
5. **On the next machine**: `ws pull thalami-<user>` brings down the
   committed state. Orientation sees the updated audit log, other
   machines' files (read-only signals about what's happening
   elsewhere), and any cross-machine preferences from the housekeeping
   skill's multi-thalami review.

Two coexisting modes that work well:

- **Each machine commits its own per-machine file.** The hoard's
  history shows alternating commits per machine.
- **One machine does cross-machine housekeeping** (typically the
  most-used desktop). It walks all `<machine>-thalamus.md` files,
  promotes universal preferences, dedups observations, updates each
  machine's audit log. The other machines pick up the consolidated
  state on next pull.

---

## Future hoard types

Hoards are intentionally generic; thalami is just the first type
shipped. Plausible future types:

- **Vault-style knowledgebase** (Obsidian-flavored or similar). Users
  who already maintain a personal knowledge graph could land it as a
  hoard, get the `ws push/pull` ergonomics, and the cadence-config
  shape for keeping it synced. The
  [Claudesidian](https://github.com/heyitsnoah/claudesidian) project
  is the prototypical example.
- **Scratch / experiment** spaces — short-lived hoards for spike work
  that shouldn't pollute components but you want the workspace's
  CLI ergonomics for.
- **Cross-tool transcripts** — agent session transcripts, voice
  memos, anything that's "yours" but not a project.

Each new type ships as a `templates/hoards/<type>/` directory with
its own scaffold. The `ws hoard init <type>` command picks it up
automatically. If the type wants its own cadence behavior, it ships
a `.ws-cadence.yaml` (or omits it for the default).

---

## See also

- [GDD Features Tour](features.md) — where hoards fit in the
  larger feature set.
- [Thalamus](thalamus.md) — the thinking-space concept the thalami
  type is built around.
- [Trust and Safety](trust-and-safety.md) — hoards' trust level
  (your own content, equivalent to your other instructions).
- [Roles and Modes](roles-and-modes.md) — the per-machine `mode:`
  and `role:` defaults that live in thalamus frontmatter.
- [`gdd-orientation` skill](../../.agent/skills/gdd-orientation/SKILL.md)
  — how Step 0a uses `ws hoard cadence`.
- [`gdd-housekeeping` skill](../../.agent/skills/gdd-housekeeping/SKILL.md)
  — multi-thalami review process.
