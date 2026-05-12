<%*
  // Prompt-all-first, rename-last pattern (same as Project Note): if
  // the file is "Untitled" because user used "New note" without typing
  // a name first, prompt for it. Rename happens after all prompts to
  // close the FHS-debounce race that would otherwise duplicate the H1.
  let title = tp.file.title
  const needsRename = title.startsWith("Untitled")
  if (needsRename) {
    title = await tp.system.prompt("Area Name")
  }
  // Trim the prompt result so whitespace-only input is treated as
  // "no parent" (top-level area), matching the prompt's stated
  // semantics. Without this, a blank parent emits an empty wikilink
  // `[[]]` into the frontmatter — broken metadata.
  const parent = ((await tp.system.prompt("Parent Area (leave blank for top-level area)")) || "").trim()
  if (needsRename) {
    await tp.file.rename(title)
  }
_%>
---
created: <% tp.date.now("YYYY-MM-DD") %>
type: area
area: "<% parent ? `[[${parent}]]` : '' %>"
tags:
  - area/<% title.toLowerCase().replace(/ /g, "-") %>
status: active
description: ""
---

# <% title %>

> [!INFO] Context
> **Parent Area:** <% parent || "*(top-level)*" %>
> **Role:** *Owner / Maintainer / Observer*

## Purpose

What ongoing responsibility does this area cover?

## Standards

What does "good" look like here? Cadence, quality bar, definition of done for routine work.

## Active Projects

```dataview
TABLE status, deadline, area
FROM "10_Projects"
WHERE area = this.file.link OR area.area = this.file.link
SORT status ASC, deadline ASC
```

## Recurring Responsibilities

*Tasks without specific due dates (maintenance).*

```tasks
not done
(path includes <% tp.file.path(true) %>) OR (tag includes #area/<% tp.file.title.toLowerCase().replace(/ /g, "-") %>)
hide backlink
```

## Resources

Reference material specific to this area.

## Links

