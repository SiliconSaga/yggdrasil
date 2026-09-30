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
- **License:** MIT — preserved at `bats-core/LICENSE.md` (two notices:
  bats-core contributors 2017, and Sam Stephenson 2014 for the original
  bats it continues); contributors are listed in upstream's
  [`AUTHORS`](https://github.com/bats-core/bats-core/blob/v1.11.0/AUTHORS),
  linked rather than copied because it carries personal email addresses
- **Vendored version:** v1.11.0, tag commit
  `5da66876b8b619235aee1eb3e54954eaca88059b`
- **Source archive:** `https://github.com/bats-core/bats-core/archive/refs/tags/v1.11.0.tar.gz`,
  SHA-256 `aeff09fdc8b0c88b3087c99de00cf549356d7a2f6a69e3fcec5e0e861d2f9063`
- **Vendored:** 2026-05-02 (commit d8bfe8e)
- **Local modifications:** none — every retained file is byte-identical to
  the archive (re-verified 2026-09-30 by diffing against a fresh download)

Only the runtime parts of the upstream tarball are kept (`bin/`,
`lib/bats-core/`, `libexec/bats-core/`, `LICENSE.md`). Upstream's
own tests, docs, examples, Docker config, and CI scripts are intentionally
discarded — they are not needed to run our tests and would significantly
inflate this directory. The repository-level inventory of redistributed
third-party code is [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md);
update its entry alongside any refresh here.

### Refresh procedure

To update bats-core to a new release:

```bash
# From the repo root
VERSION=v1.11.0   # ← set to the desired bats-core release tag
TMP=$(mktemp -d)
curl -sSL -o "$TMP/bats.tar.gz" \
    "https://github.com/bats-core/bats-core/archive/refs/tags/${VERSION}.tar.gz"
sha256sum "$TMP/bats.tar.gz"      # record this above, with the tag's commit
tar -xz -C "$TMP" -f "$TMP/bats.tar.gz"
SRC="$TMP/bats-core-${VERSION#v}"

rm -rf tests/vendor/bats-core
mkdir -p tests/vendor/bats-core
cp -R "$SRC/bin" "$SRC/lib" "$SRC/libexec" "$SRC/LICENSE.md" tests/vendor/bats-core/

# Sanity check
bash tests/vendor/bats-core/bin/bats --version
bash scripts/ws test yggdrasil
```

After verifying the smoke tests still pass, update the version, tag commit,
checksum and date above and the matching entry in `THIRD_PARTY_NOTICES.md`,
then commit the refresh:

```bash
bash scripts/ws commit yggdrasil .commits/refresh-bats-core.md
```

Do **not** edit any files inside `tests/vendor/bats-core/` directly —
those are upstream code. Local fixes belong in our own glue under
`tests/` (outside `vendor/`).
