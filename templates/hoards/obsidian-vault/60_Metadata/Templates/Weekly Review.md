<%*
  // Compute week range from the file title (gggg-[W]ww format)
  const startOfWeek = tp.date.now("YYYY-MM-DD", 0, tp.file.title, "gggg-[W]ww")
  const endOfWeek = tp.date.now("YYYY-MM-DD", 6, tp.file.title, "gggg-[W]ww")
_%>
---
created: <% tp.date.now("YYYY-MM-DD") %>
type: weekly-review
week: <% tp.file.title %>
tags: [review, weekly]
---

# Weekly Review: <% tp.file.title %>
*<% startOfWeek %> to <% endOfWeek %>*

## Wins

*What did I ship this week?*

```tasks
done
done on or after <% startOfWeek %>
done on or before <% endOfWeek %>
sort by done date desc
```

## Project Review

- [ ] Active projects: stuck?
- [ ] Backlog: anything ready to move up?
- [ ] Waiting: ping people?

## Themes

*Recurring threads across this week's notes.*

## Connections

*New links between notes / concepts.*

## Next Week

*What are the 3 big rocks?*

1. 
2. 
3. 

