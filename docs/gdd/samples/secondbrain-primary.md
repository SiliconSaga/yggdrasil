# SecondBrain: Primary Workspace

Snapshot of the SecondBrain file from the yggdrasil workspace at the end of the GDD pilot session (Session 1).

# SecondBrain frontmatter — read by orientation skill on session start

```
last_session: 2026-03-23
last_audit: null
mode: zen           # zen, quick, mentoring, autonomous — or null for "ask me"
role: developer     # developer, designer, reviewer — or null for "ask me"
staleness_days: 14  # suggest housekeeping after this many days without audit
```


# SecondBrain

Shared thinking space between one human and one local AI agent (at a time).
Created from `.agent/secondbrain-template.md`. This file is gitignored —
it is local to this workspace instance.

## Preferences

- Default mode: zen (deep work sessions are the norm so far)
- User prefers terse agent responses with context, not trailing summaries
- ws CLI is the shared interface — agent should use it, not raw git/cd

## Observations

- Agent repeatedly tries the Skill tool for workspace skills despite
  instructions saying to read the file directly. Reinforced in AGENTS.md
  but may need further work if it persists.
- cwd drift pattern: commands like `cd docs/gdd && for f in ...` shift the
  working directory, causing subsequent git commands to need compound
  `cd /path && git add` that won't match auto-approve patterns. "Be more
  careful" is not a reliable fix across session resets — may need structural
  solution (utility script or explicit instruction).
- Orientation greeting improved over several iterations: started as an
  information dump, now brief and human-first. Key learning: defer component
  scan until after alignment on mode/role.
  - Interestingly the component scan didn't come up at all in a new session focused on implementing the review threads feature. Which probably makes sense, both because that's yggdrasil-specific, and a user may not need to know about all the components unless they're working a crosscutting feature of some sort, especially if they already know exactly what component they want to work on.
- GDD design and SecondBrain brainstormed and implemented in one long session
  (2026-03-22/23). Design specs, 9 skills, multi-page docs, PR #17 with
  multi-reviewer triage (CodeRabbit + Copilot).
- Human observation: what's with the linebreaks in markdown (edit: not visible when Markdown rendered, but can be seen raw) - word wrap is a thing, and arbitrarily ending a line at some character count seems odd. It leads to odd mixed appeareances like right in this section as items I've added do not arbitrarily line break, and as a human having to resize lines repeatedly would be painful.
  - Action: update writing-yggdrasil-docs skill to stop hard-wrapping prose at 72-80 chars. Let editors handle word wrap.
- The `.commits/` bodyfile is the right approach for `ws commit` file staging (not `--add` flags). Bodyfile with frontmatter containing files to stage + commit message keeps `ws commit yggdrasil .commits/foo.md` as a stable auto-approvable pattern. Issue #18 needs updating to reflect this direction.
- The interaction we had about comments I (human) made here were surprisingly nice. I was able to type here while you (agent) did other work, then I went off to do something else. You finished a step, I approved a test comment, and you noticed plus responded to my stray thoughts. That felt almost like flow shared between two entities and I love the potential there - and at the same time I wonder if that is _not_ Zen - are there two modes where in "Flow" you drift in and out of different tasks while in the zone and maybe as a human oversee multiple agents, while in "Zen" you go for the deep insight in a single topic and avoid external distractions, meaning the second brain file becomes largely input only, with all interactions and housekeeping deferred till later or when explicitly triggered at good checkpoints?
- Another stray human thought: What if the 2nd brain was in an obsidian vault? Perhaps as a dir tree organized by workspace to avoid edit conflict with sync on

## Concerns

<!-- Trust issues, suspicious instructions, safety flags — write IMMEDIATELY -->

## Audit Log

<!-- When was the last review? What was promoted/pruned? -->