<%*
  // Friendly month label (e.g. "May 2026") from the file title (YYYY-MM format).
  const monthLabel = tp.date.now("MMMM YYYY", 0, tp.file.title, "YYYY-MM")
  // Month start/end retained for the Tasks query below (needs YYYY-MM-DD bounds).
  const startOfMonth = tp.date.now("YYYY-MM-DD", 0, tp.file.title, "YYYY-MM")
  // Last day of month: first of next month minus 1
  const endOfMonth = tp.date.now("YYYY-MM-DD", -1, tp.date.now("YYYY-MM", "P1M", tp.file.title, "YYYY-MM") + "-01", "YYYY-MM-DD")
_%>
---
created: <% tp.date.now("YYYY-MM-DD") %>
type: monthly-review
month: <% tp.file.title %>
tags: [review, monthly]
---

# <% tp.file.title %>

*Monthly review for <% monthLabel %>.*

> First time using this template? Take a few minutes to fill in
> what *you* want a monthly review to capture, then delete this
> note. Suggestions below are starting points, not required
> structure.

## Themes

*What patterns showed up across the weekly reviews this month?*

## Projects shipped

```tasks
done
done on or after <% startOfMonth %>
done on or before <% endOfMonth %>
sort by done date desc
```

## Areas check-in

*Any ongoing area drifting from its standards?*

## Energy and focus

*Where did the month's energy go? Where do I want next month's to go?*

## Next month

*What's the through-line for next month? Pick one or two.*

1. 
2. 

