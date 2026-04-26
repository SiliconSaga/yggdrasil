---
# Commit subject — required. Use conventional prefix: feat, fix, docs, chore, test, refactor, style
# Optional scope in parens, e.g. "fix(ws):", "feat(realm):"
message: "type(scope): short imperative description"

# Files to stage before committing. Paths are relative to the component root,
# not the yggdrasil root. Omit if you've already staged manually (not recommended).
add:
  - path/to/file1.md
  - path/to/file2.java

# Optional — deleted files to stage for removal. Omit if no deletions.
# remove:
#   - path/to/old-file.md
---

[Extended commit body — the "why" behind the change.]

[Use paragraphs or bullets. Explain motivation, not mechanics — the diff shows
what changed, this explains why. Reference related issues/PRs as #N.]

[Common patterns:
 - Single-concern commits: one short paragraph is enough
 - Multi-file refactors: group the description by area/file
 - Review-fix commits: note which reviewer and which commit introduced the issue]
