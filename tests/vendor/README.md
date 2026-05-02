# Vendored test dependencies

This directory holds third-party shell-test runtime code as **ordinary
committed files** — not Git submodules. Vendoring trades a tiny amount of
repo size for the property that yggdrasil's test infrastructure works
immediately after a plain `git clone`, without any `--recursive` flag,
`git submodule update`, or extra setup ritual.

If you're updating these vendored copies, do so in a dedicated commit
that touches only this directory so the vendor refresh is easy to spot
in `git log`.

## bats-core

Shell-script test framework used by yggdrasil's `tests/*.bats` files
and exposed via `bash scripts/ws test yggdrasil`.

- **Upstream:** https://github.com/bats-core/bats-core
- **License:** MIT — preserved at `bats-core/LICENSE.md`
- **Vendored version:** v1.11.0
- **Vendored date:** 2026-04-30

Only the runtime parts of the upstream tarball are kept (`bin/`,
`lib/bats-core/`, `libexec/bats-core/`, `LICENSE.md`). Upstream's own
tests, docs, examples, Docker config, and CI scripts are intentionally
discarded — they are not needed to run our tests and would significantly
inflate this directory.

### Refresh procedure

To update bats-core to a new release:

```bash
# From the repo root
VERSION=v1.11.0   # ← set to the desired bats-core release tag
TMP=$(mktemp -d)
curl -sSL "https://github.com/bats-core/bats-core/archive/refs/tags/${VERSION}.tar.gz" \
    | tar -xz -C "$TMP"
SRC="$TMP/bats-core-${VERSION#v}"

rm -rf tests/vendor/bats-core
mkdir -p tests/vendor/bats-core
cp -R "$SRC/bin" "$SRC/lib" "$SRC/libexec" "$SRC/LICENSE.md" tests/vendor/bats-core/

# Sanity check
bash tests/vendor/bats-core/bin/bats --version
bash scripts/ws test yggdrasil
```

After verifying the smoke tests still pass, commit the refresh:

```bash
bash scripts/ws commit yggdrasil .commits/refresh-bats-core.md
```

Do **not** edit any files inside `tests/vendor/bats-core/` directly —
those are upstream code. Local fixes belong in our own glue under
`tests/` (outside `vendor/`).
