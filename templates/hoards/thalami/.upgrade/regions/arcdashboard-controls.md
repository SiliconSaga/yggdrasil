<!-- Template-managed (ws hoard upgrade). Edits inside the markers are overwritten on upgrade; edit around them freely. VERIFY the meta-bind-button syntax against the pinned Meta Bind release before first --apply. -->
> [!tip]- Dashboard controls
> ```meta-bind-button
> label: "🔄 Refresh"
> style: default
> actions:
>   - type: command
>     command: dataview:dataview-force-refresh-views
> ```
> Hit Refresh if the **Days** column reads negative — Dataview caches `date(today)` until the view re-renders, so a pane left open across days drifts. See `docs/gdd/thalamus.md` if this recurs.
