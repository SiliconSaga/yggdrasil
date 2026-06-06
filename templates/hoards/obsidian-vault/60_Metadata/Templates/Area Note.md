<%*
  // Prompt-all-first, rename-last pattern (same as Project Note): if
  // the file is "Untitled" because user used "New note" without typing
  // a name first, prompt for it. Rename happens after all prompts to
  // close the FHS-debounce race that would otherwise duplicate the H1.
  let title = tp.file.title
  const needsRename = title.startsWith("Untitled")
  if (needsRename) {
    // Guard canceled / empty prompt: keep the original "Untitled-N"
    // title rather than crashing tp.file.rename(undefined). User can
    // rename manually later.
    const promptedTitle = await tp.system.prompt("Area Name")
    if (promptedTitle && promptedTitle.trim()) {
      title = promptedTitle.trim()
    }
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

## Links

## Active Projects

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  status AS "Status",
  deadline AS "Due"
FROM "10_Projects"
WHERE area = this.file.link OR area.area = this.file.link
SORT
  choice(status = "active", 0,
  choice(status = "next", 1,
  choice(status = "soon", 2,
  choice(status = "waiting", 3, 4)))) ASC,
  deadline ASC
```

## Backlog Micro-items

*Small scraps that don't deserve their own file yet. Promote a row to a `someday` project note in `40_Archive/Backlog/` when it accumulates real context.*

| Item | Notes | Added |
|---|---|---|
|  |  |  |

## Recurring Responsibilities

*Tasks without specific due dates (maintenance).*

```tasks
not done
tag includes #area/<% tp.file.title.toLowerCase().replace(/ /g, "-") %>
path does not include <% tp.file.path(true) %>
hide backlink
```

## Resources

Reference material specific to this area.

## Someday

*Open-ended someday backlog for this area — both `someday`-status project notes and individual `#someday` tasks tagged this area's `#area/...` tag. Lives at the bottom by design; nothing here is committed, and it stays off the global Dashboard.*

**Projects**

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  (date(today) - file.mtime).days AS "Days idle"
FROM "40_Archive/Backlog"
WHERE area = this.file.link OR area.area = this.file.link
SORT file.mtime DESC
```

**Tasks**

```tasks
not done
tag includes #someday
tag includes #area/<% tp.file.title.toLowerCase().replace(/ /g, "-") %>
hide task count
```

