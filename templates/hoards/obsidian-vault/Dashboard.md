---
type: dashboard
tags: [dashboard]
---

# Dashboard

## Due

```dataview
TABLE WITHOUT ID file.link as Project, deadline as Due, (date(today) - deadline) as "Days Overdue"
FROM "10_Projects"
WHERE deadline <= date(today) AND status = "active"
SORT deadline ASC
```

```tasks
not done
(due today) OR (due before today)
hide backlink
sort by due date
hide task count
```

## Priority

```tasks
not done
tag includes #priority
(no due date) OR (due after today)
hide backlink
hide task count
```

## Organize

```tasks
not done
path includes 00_Inbox
tag does not include #priority
(no due date) OR (due after today)
hide backlink
sort by created date desc
hide task count
```

## Projects

```tasks
not done
path includes 10_Projects
tag does not include #priority
(no due date) OR (due after today)
hide backlink
group by function task.file.folder
hide task count
```

---

> [!TIP] Workflow
> 1. **Capture** everything in Daily Notes.
> 2. **Observe** this Dashboard.
> 3. **Organize** items into PARA folders, otherwise → Organize.
> 4. **Date** items that must happen today (`📅 YYYY-MM-DD`) → Due.
> 5. **Tag** important items with `#priority` or `#priority/high` → Priority.
> 6. **Project** items go to `10_Projects/<name>/` → Projects.
>
> *If a Dataview table looks stale (e.g. after midnight), `Ctrl-P → Dataview: Force Refresh Views`. Map to F5 for convenience.*
