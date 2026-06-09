# <Project Name> — SADD Project Hoard

A GDD project hoard for developing a Software Architecture and Design Document (SADD).

## Layout

```text
<project>/
  .project.yaml          # Section manifest + build config (edit this first)
  index.md               # Quartz site home
  philosophy.md          # sadd_section: purpose-scope
  architecture.md        # sadd_section: architecture (mandatory)
  design/
    alternatives.md      # sadd_section: design-alternatives
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

# Build with PDF artifact
ws project <name> build --pdf
```

Add more section files anywhere in the hoard (not under `working/`) by setting
`sadd_section: <id>` in their YAML frontmatter, where `<id>` matches a section
listed in `.project.yaml`.

## Design

See `docs/plans/2026-06-09-adse-design.md` in yggdrasil.
