---
created: 2026-05-07
tags: [welcome, setup]
status: unprocessed
---

# Welcome

This is your new Obsidian vault. Process this checklist on first open, then move this note to `04_Archive/` (or just delete it) — it lives in `00_Inbox/` so it'll naturally come up during your first inbox sweep.

> **Mobile (Android)?** Skip ahead to the *Mobile setup* section below — there's a one-time chicken-and-egg dance to install the Obsidian Git plugin before the rest of the vault arrives.

## First-time setup

### 1. Trust the community plugins, then restart Obsidian once

Obsidian prompts on first open. Click trust. The plugins listed in the README activate.

After trusting, **restart Obsidian once**. First-load timing between plugins (Calendar ↔ Periodic Notes especially) can leave plugin settings or ribbon icons in a half-loaded state; a restart cleans this up. You only need to do this once.

### 2. Bind a daily-note hotkey

Settings → Hotkeys → search `daily note` → bind **Periodic Notes: Open daily note** to whatever feels natural (`Ctrl+Shift+D`, `Alt+T`, etc.).

This replaces the old core daily-notes ribbon button. While you're there, also bind "Open weekly note" and "Open monthly note" if you'll use them.

### 3. Find the Calendar view (heads-up: easy to miss)

Calendar plugin adds a ribbon icon at the top of the **right** sidebar.

**Common gotcha:** if your right sidebar is too narrow, the ribbon icons overflow *invisibly*. Widen the right sidebar until you can see all icons, then look for the calendar-shaped one. Click it → Calendar view appears.

If the `Calendar: Open view` hotkey doesn't fire, that's a Calendar plugin quirk in some versions — just use the ribbon icon.

### 4. Layout: Calendar + Dashboard pinned together

Recommended setup is Calendar above `Dashboard.md` in the same pane (both visible always). Direct drag-and-drop within a single Obsidian window can be finicky; the trick that works:

1. Right-click the Calendar tab → **Move to new window**
2. In the new window, drag the Calendar tab back into your main Obsidian window where you want it (top of a column, left of main editor, etc.)
3. Open `Dashboard.md` and right-click its tab → **Pin** so clicking dates in Calendar doesn't replace it
4. Calendar's ribbon icon disappears from the sidebar once moved into the main window — that's expected; collapse the right sidebar to reclaim space

**Don't link tabs** between Calendar and Dashboard. Linking causes one tab's navigation to replace the other's content — opposite of what you want for a stable pinned dashboard.

### 5. Test the magic

Create a note in `01_Projects/` (any name). Templater should auto-apply the Project Note template — frontmatter with today's date, H1 = filename. Same in `02_Areas/`.

If `created:` shows up as something weird like `{"...":null}`, the Templater configuration is wrong — file an issue.

Try wikilinking too: in any note, type `[[` and you'll get an autocomplete picker — for example `[[Dashboard]]` opens this vault's dashboard, `[[Welcome]]` jumps back here.

### 6. (Optional) Web Clipper

The Obsidian Web Clipper is a browser extension (not an Obsidian plugin). Install for your browser:

- [Chrome / Edge](https://chromewebstore.google.com/detail/obsidian-web-clipper/cnjifjpddelmedmihgijeibhnjfabmlf)
- [Firefox](https://addons.mozilla.org/firefox/addon/web-clipper-obsidian/)
- [Safari](https://apps.apple.com/app/obsidian-web-clipper/id6720708363)

Point it at this vault, set the destination folder to `03_Resources/Clippings/`, and configure highlights to *replace* page content rather than append.

## Mobile setup (Android)

The Obsidian Git plugin syncs the vault to/from your git remote. Setting this up has a quirk on first install: **you have to install the plugin twice** — once into a temporary empty vault to get the Clone command, then once again into the cloned vault (which doesn't include the plugin since we gitignore its folder for security — its config holds your auth token).

Step by step:

### 1. Generate a fine-grained Personal Access Token

On GitHub: Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new. Scope to *only* this vault repo, with **Contents: Read and write**. Copy the token (starts with `github_pat_`); store in your password manager. (For Gitea: User Settings → Applications → Generate Token, scope to the repo.)

### 2. Install Obsidian on Android, create an empty throwaway vault

Open the Play Store, install Obsidian. On first launch, "Create new vault" — name it something temporary like `bootstrap`. Obsidian needs a vault open before you can install community plugins.

### 3. Install the Obsidian Git plugin into the throwaway vault

Settings → Community plugins → "Turn on community plugins" → Browse → search "obsidian-git" → Install → Enable.

### 4. Configure the plugin's auth in the throwaway vault

Settings → Obsidian Git:

- **Authentication / Username:** your GitHub or Gitea username
- **Authentication / Password / Personal Access Token:** the PAT from step 1

### 5. Run the clone command

Open the command palette (3-dot menu top-right → Open command palette) → run **"Obsidian Git: Clone an existing remote repo"** → paste the HTTPS URL of this vault's repo. Plugin clones the repo into a new folder.

### 6. Switch Obsidian to the cloned vault

Re-open Obsidian. From the vault picker, choose the newly-cloned vault folder. The throwaway `bootstrap` vault can be deleted later.

### 7. Re-install Obsidian Git in the cloned vault

The cloned vault doesn't have the plugin installed (its folder is gitignored — its `data.json` holds your PAT and we don't want that in git). So:

- Settings → Community plugins → Browse → install "obsidian-git" again → Enable
- Settings → Obsidian Git → re-enter your PAT under Authentication

### 8. Test the round-trip

Edit a note in `00_Inbox/`. Run command palette → "Obsidian Git: Commit all changes" → "Obsidian Git: Push". Pull on a desktop with `cd hoards/<this-vault> && git pull` — your phone's commit should be there.

For ongoing use, bind hotkeys for Pull and Commit-and-push (Settings → Hotkeys), or use the ribbon icons the plugin adds.

### 9. (Optional) Custom commit message format

Default phone commits look like `vault backup: 2026-05-07 15:07:50` — fine but anonymous. Settings → Obsidian Git → "Commit message on auto backup/manual" lets you customize.

Obsidian-Git offers a few useful template variables with `{{date}}` a good automated differentiator between commits. The `{{hostname}}` variable may not work on Android; consider just giving a name for your phone instead. Example:

```text
Updates from Pixel 9 Fold at {{date}}
```

That gives commits like `Updates from Pixel 9 Fold at 2026-05-07 15:07` — clearer attribution when you're scrolling git history later.

### Why installing plugin twice?

`.obsidian/plugins/obsidian-git/` is gitignored in this vault's `.gitignore` because the plugin's config file stores your PAT. Committing it would leak your token. The cost is this one-time setup awkwardness; after that, edits flow normally.

## When you're done

Move to `04_Archive/` or delete. The full reference for what's installed and how to use it lives in [[README]] and the [obsidian-vault hoard docs](https://siliconsaga.github.io/yggdrasil/gdd/obsidian-vault).
