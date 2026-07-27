---
# Commit subject — required. Use conventional prefix: feat, fix, docs, chore, test, refactor, style
# Optional scope in parens, e.g. "fix(ws):", "feat(realm):"
message: "type(scope): short imperative description"

# Files / directories to stage. Each entry is passed verbatim to `git add`.
# Paths are relative to the component root (not yggdrasil root).
#
# What works:
#   - new or modified files                → regular path
#   - already-deleted-from-disk-but-tracked file → regular path
#                                            (git add detects the deletion)
#   - directories                          → stages new + modified files
#                                            recursively (NOT deletions)
#
# What does NOT work:
#   - a directory you've fully `rm -rf`'d  → git add errors on missing path.
#     Pre-stage with `git add -A <dir>` before the ws commit, then list
#     surviving (new / modified) files individually in add: below.
#
# add: is fail-fast: if any listed path doesn't exist on disk AND isn't a
# tracked deletion, the commit aborts before staging anything.
add:
  - path/to/file1.md
  - path/to/file2.java
  - path/to/dir/

# Paths to delete via `git rm` (touches index AND working tree). Use only
# for files still on disk that this commit should remove. For files
# already removed from disk, list them in add: instead — git add stages
# the deletion of tracked files transparently.
# remove:
#   - path/to/still-on-disk-but-should-be-deleted.md
---

[Extended commit body — the "why" behind the change. Explain motivation, not
mechanics: the diff shows what changed. Reference related issues/PRs as #N.]

[Budget: ~4-8 lines for a typical single-concern commit; a bare subject is
fine when the diff speaks for itself. Every line must earn its place —
evidence (what proved the bug), traps (what a future reader would miss), and
significance (why it matters) stay; a per-file tour of what the diff already
shows never does.]

[style.changeNotes in ecosystem config tunes the budget (`ws orient` shows
the active value): terse = subject only, plus ≤3 body lines when something
non-obvious needs recording; standard = the budget above; detailed = fuller
narrative, reserved for teaching contexts or genuinely intricate changes.]

[Common patterns:
 - Single-concern commits: subject alone, or one short paragraph
 - Multi-file refactors: group the description by area/file
 - Review-fix commits: note which reviewer and which commit introduced the issue]
