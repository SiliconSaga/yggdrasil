<!-- Template-managed (ws hoard upgrade); edit the region source in the template, not here. -->
```meta-bind-button
label: "🔄 Refresh"
style: default
id: arc-refresh
hidden: true
action:
  type: command
  command: dataview:dataview-force-refresh-views
```
**Filter** `INPUT[text:filter]` · **Sort by** `INPUT[inlineSelect(option(Status), option(Touched, Last touched), option(Arc), option(Host), option(Age), option(Impact), option(Urgency)):sortby]` · **Desc** `INPUT[toggle:descending]` · `BUTTON[arc-refresh]`
