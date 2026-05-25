<!-- Template-managed (ws hoard upgrade). Edits inside the markers are overwritten on upgrade; edit around them freely. The meta-bind-button command-action block targets Meta Bind 1.4.10 (pinned in upgrade.yaml); confirm it renders as a button on first open in Obsidian. -->
> [!tip]- Dashboard controls
> ```meta-bind-button
> label: "🔄 Refresh"
> style: default
> action:
>   type: command
>   command: dataview:dataview-force-refresh-views
> ```
> Hit Refresh if the **Days** column reads negative — Dataview caches `date(today)` until the view re-renders, so a pane left open across days drifts. See `docs/gdd/thalamus.md` if this recurs.
