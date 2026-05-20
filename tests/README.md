# Running the workspace tests

`ws test yggdrasil` runs every `*.bats` file under this directory using the vendored bats-core at `tests/vendor/bats-core/`. No system bats install needed.

## Prerequisite: GNU `timeout`

The bats helpers wrap each hook / `ws` invocation in `timeout 10 …` so a regression that hangs the upward-walk loop (or any other infinite loop) fails loudly instead of stalling the suite. That command is GNU coreutils.

- **Linux / Git Bash on Windows:** ships with coreutils already — no action.
- **macOS:** install via Homebrew. The helpers pick up the `g`-prefixed binary automatically:

  ```bash
  brew install coreutils
  ```

  After install, `gtimeout` is on PATH wherever your Homebrew prefix puts shims (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel; `brew --prefix` confirms). The test helpers detect either `timeout` or `gtimeout`; you do not need to add the `gnubin` directory to PATH.

If neither binary is present, every test fails immediately with a clear "install coreutils" message — no silent hangs.

## Running

```bash
ws test yggdrasil                # whole suite
bash tests/vendor/bats-core/bin/bats tests/hook/   # one directory
```

## Interactive acceptance

`tests/hook/interactive-acceptance.md` is the human-in-the-loop companion to the hook bats suite. The bats tests verify the hook's JSON output; the acceptance script verifies the human-facing permission prompt actually appears. Ask the agent to "run the hook acceptance script."
