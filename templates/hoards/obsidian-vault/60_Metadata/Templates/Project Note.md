<%*
  // Collect all prompts FIRST, then rename at the end. This closes the
  // FHS-debounce race: with rename last, FHS's 1000ms debounce fires
  // after Templater has fully written the body (which already contains
  // an H1 matching the new filename), so no duplicate H1 gets inserted.
  let title = tp.file.title
  const needsRename = title.startsWith("Untitled")
  if (needsRename) {
    // Guard canceled / empty prompt: keep the original "Untitled-N"
    // title rather than crashing tp.file.rename(undefined). User can
    // rename manually later.
    const promptedTitle = await tp.system.prompt("Project Name")
    if (promptedTitle && promptedTitle.trim()) {
      title = promptedTitle.trim()
    }
  }
  // Guard the parent-area prompt similarly. If the user dismisses the
  // prompt or leaves it blank, emit no area wikilink at all rather
  // than `[[]]` (broken metadata) or a literal "undefined".
  const promptedArea = await tp.system.prompt("Parent Area (e.g. Obsidian)")
  const area = (promptedArea && promptedArea.trim()) ? promptedArea.trim() : ""
  if (needsRename) {
    await tp.file.rename(title)
  }
_%>
---
created: <% tp.date.now("YYYY-MM-DD") %>
status: active
area: "<% area ? `[[${area}]]` : '' %>"
deadline:
tags:
  - "#project/<% title.toLowerCase().replace(/ /g, '-') %>"
priority: Medium
repo:
doc_hub:
---

# <% title %>

*Definition of done:* 

---

# Task Board

*Auto-generated from Daily Notes. DO NOT EDIT MANUALLY.*

## Tasks From Elsewhere

```tasks
not done
(tag includes #project/<% title.toLowerCase().replace(/ /g, "-") %>) OR (description includes [[<% title %>]])
path does not include <% tp.file.path(true) %>
sort by due date
hide backlink
```

## Completed

```tasks
done
(tag includes #project/<% title.toLowerCase().replace(/ /g, "-") %>) OR (description includes [[<% title %>]])
path does not include <% tp.file.path(true) %>
sort by done date desc
limit 5
```

---

# Timeline

*Past and upcoming events, decisions, milestones.*

- 
