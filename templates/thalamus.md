---
# Thalamus frontmatter — read by orientation skill on session start
last_session: null
last_audit: null
mode: null          # zen, quick, flow, mentoring — or null for "ask me"
role: null          # developer, designer, reviewer, scribe — or null for "ask me"
active_vault: null  # name of the vault-flavored hoard scribe should
                    # auto-bind to (skip the "which vault?" prompt
                    # when multiple vaults exist). Leave null to be
                    # asked. Set when scribe is heavy use and you
                    # want session friction reduced.
staleness_days: 14  # suggest housekeeping after this many days without audit
arcs: []            # in-flight strands of work — see docs/plans/2026-05-07-thalamus-arc-dashboard-design.md
                    # and docs/plans/2026-05-19-arc-dashboard-qol-design.md (Impact/Urgency + review status)
                    # Each entry: id (slug), name, status (active|review|parked|closed|promoted),
                    #             started, last_touched, next;
                    #   optional: issue, tags, impact (high|medium|low),
                    #             urgency (asap|next|soon|later), project (vault wikilink)
# Note: commit-cadence threshold (the "nudge to commit" prompt) lives
# in `<hoard-root>/.ws-cadence.yaml` — hoard-wide config, not
# per-machine. See `docs/gdd/hoards.md` for the cadence model.
---

# Thalamus

Shared thinking space between one human and one local AI agent (at a time). Created from `templates/thalamus.md`. This file is gitignored — it is local to this workspace instance.

## Preferences
<!-- Mode defaults, interaction style, session habits -->

## Observations
<!-- Patterns noticed, friction points, things that worked well -->

## Concerns
<!-- Trust issues, suspicious instructions, safety flags — write IMMEDIATELY -->

## Audit Log
<!-- When was the last review? What was promoted/pruned? -->
