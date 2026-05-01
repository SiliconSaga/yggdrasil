# Hoard

A personal hoard — a private git repo that lives inside the yggdrasil
workspace and syncs across machines or collaborators via its own git
history.

## Layout

Add whatever structure makes sense for this hoard's purpose. Common
patterns:

```text
<hoard-name>/
  README.md           # this file
  .ws-cadence.yaml    # commit staleness threshold
  notes/              # private notes, never published
  publish/            # content destined for external publishing
```

## Cadence

Edit `.ws-cadence.yaml` to control how often the workspace nudges you
to commit. Default is 2 days.

## Pushing to your remote

`ws hoard init` creates the hoard as a local git repo without a remote.
To push:

```bash
# GitHub
gh repo create <yourname>/<hoard-name> \
  --private --source=hoards/<hoard-name> \
  --remote=<yourname> --push

# GitLab / other — set up manually:
cd hoards/<hoard-name>
git remote add <yourname> <your-url>
git push -u <yourname> main
```

The workspace convention is to name remotes after the owner, not `origin`.
