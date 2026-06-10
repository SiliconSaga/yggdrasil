---
title: "<Project Name>"
---

# <Project Name>

> Project hoard — SADD in progress. Run `ws project <name> status` to check section coverage.

## Sections

All section files live under `sections/` and carry a `sadd_section:` frontmatter key that
determines their place in the assembled document. Files without that key (e.g.
`sections/supplemental/notes.md`) are ignored by the assembler.

Run `ws project <name> build` to assemble `working/sadd.md`.

## Working notes

Scratch material in `working/` — excluded from assembly entirely.
