<%*
  // Collect all prompts FIRST, then rename at the end. This closes the
  // FHS-debounce race: with rename last, FHS's 1000ms debounce fires
  // after Templater has fully written the body (which already contains
  // an H1 matching the new filename), so no duplicate H1 gets inserted.
  let title = tp.file.title
  const needsRename = title.startsWith("Untitled")
  if (needsRename) {
    title = await tp.system.prompt("Project Name")
  }
  const area = await tp.system.prompt("Parent Area (e.g. Obsidian)")
  if (needsRename) {
    await tp.file.rename(title)
  }
_%>
---
created: <% tp.date.now("YYYY-MM-DD") %>
status: active
area: "[[<% area %>]]"
deadline:
tags:
  - "#project/<% title.toLowerCase().replace(/ /g, "-") %>"
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
