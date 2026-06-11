# <Project Name> — SADD Project Hoard

A GDD project hoard for developing a Software Architecture and Design Document (SADD).

## Layout

```text
<project>/
  .project.yaml          # Section manifest + build config (edit this first)
  index.md               # Quartz site home
  sections/              # Section stubs — one file per SADD section
    purpose-scope.md     # sadd_section: purpose-scope
    architecture.md      # sadd_section: architecture
    ...
    supplemental/        # Example of a nested section subfolder
      other-ha.md        # sadd_section: other-ha  (listed in .project.yaml)
      notes.md           # no sadd_section: — not assembled, just scratch
  working/               # Scratch notes and source material — never compiled
  .gitlab-ci.yml         # Quartz site + SADD build CI
  .publish.yaml          # Confluence config (if using collab path)
```

## Workflow

```bash
# See section coverage
ws project <name> status

# Assemble + validate (fails if mandatory sections missing)
ws project <name> build
```

## Adding sections

Section files can live **anywhere** in the hoard (not under `working/`) as long
as they carry a `sadd_section: <id>` key in their YAML frontmatter.  The
location in the directory tree is irrelevant — the id is what matters.

### Contributing to an existing section

Add a file with the matching id:

```markdown
---
title: My notes on architecture
sadd_section: architecture
---
Content here...
```

### Adding a new custom section

1. Create the file with a new id:

```markdown
---
title: Performance Budget
sadd_section: perf-budget
---
Content here...
```

2. Add the id to `sections:` in `.project.yaml` at the position you want
   it to appear in the assembled document:

```yaml
sections:
  - architecture
  - perf-budget      # ← your new section, placed after architecture
  - security
```

Until you add it to `sections:`, the file is detected but excluded from
the build — it shows as `? extra` in `ws project status`.

3. If the section must be present for the build to succeed, also add it
   to `mandatory:`.

### Promoting an optional section to mandatory

Move the id from `sections:` to `mandatory:` — no other change needed.
The `sections:` list controls order; `mandatory:` controls which are
required.  Every section in `mandatory:` must also appear in `sections:`
so the assembler knows where to place it.

## Design

See `docs/plans/2026-06-09-adse-design.md` in yggdrasil.
