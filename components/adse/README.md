# adse — Agentic Document Synchronization Engine

Reusable pipeline component for GDD project hoards. Provides:

- **Processors** — per-target scripts (Confluence push, PDF export)
- **Scripts** — assembler, section scanner
- **CI templates** — includable job definitions for Confluence publish, Quartz Pages, SADD build

## Using CI templates

In any hoard or component `.gitlab-ci.yml`:

```yaml
include:
  - project: gni-cfr/gdd/adse
    ref: main
    file: ci-templates/pages-quartz.yml   # or confluence-publish.yml / sadd-build.yml
```

## Local usage

```bash
# Section coverage report for a project hoard
python3 scripts/status.py /path/to/hoard

# Assemble SADD from section files
python3 scripts/assemble.py /path/to/hoard --output assembled.md

# Confluence preprocess (run from hoard root)
python3 processors/confluence/preprocess.py --root /path/to/hoard
```

## Design

See `docs/plans/2026-06-09-adse-design.md` in yggdrasil.
