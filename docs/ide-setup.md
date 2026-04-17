# IDE Setup

IDE workspace files are NOT tracked in Git — they vary per developer and
per set of cloned components.

## VS Code

Run `bash scripts/ws vscode` to generate `yggdrasil.code-workspace` from your
currently cloned components. Re-run after cloning more components.

## JetBrains

Open the `yggdrasil/` directory, then attatch component directories as modules
via File > Project Structure.

## Terminal / Neovim / other editors

`cd` into `yggdrasil/` or any component under `components/`. The scripts work
from anywhere.
