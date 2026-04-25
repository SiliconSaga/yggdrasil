# Templates

Workspace scaffolding used by `ws` commands and (future) `ws hoard init`.

## Top-level templates

| File | Used by | Purpose |
|------|---------|---------|
| `thalamus.md` | `gdd-orientation` skill | Seed for a new `Thalamus.md` |
| `commit.md` | `ws commit` | Commit bodyfile frontmatter + body |
| `change.md` | `ws cr` | CR (PR/MR) body |
| `issue.md` | `ws issue` | Issue body |

## Subdirectories

- `hoards/` — templates for `ws hoard init <type>` (e.g. `thalami/`).
- `external/` — gitignored landing area for fetched / externally-sourced
  templates (future "marketplace" use). Tracked only by `.gitkeep`.

## Leaf-to-directory promotion

A template starts as a single file (e.g. `thalamus.md`). If it grows
multi-file, it becomes a directory (`thalamus/`) containing an entry file
(by convention `default.md`). Consumers should resolve in that order.
