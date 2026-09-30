# Third-party notices

Yggdrasil is licensed under the [Apache License, Version 2.0](LICENSE). The
third-party code below is redistributed inside this repository under its own
license, which is compatible with Apache-2.0 and travels with the code.

Components, realms, and hoards are separate repositories cloned into gitignored
directories; they are not part of this repository and carry their own licenses.
Build-time tools that are downloaded rather than committed (the docs
toolchain pinned in `requirements-docs.txt`, the Obsidian plugins a hoard lock
names) are not redistributed here and are likewise not listed.

## bats-core

| | |
|---|---|
| Upstream | <https://github.com/bats-core/bats-core> |
| Version | v1.11.0 (tag commit `5da66876b8b619235aee1eb3e54954eaca88059b`) |
| License | MIT (SPDX: `MIT`) |
| Copyright | (c) 2017 bats-core contributors; portions (c) 2014 Sam Stephenson, from the original [bats](https://github.com/sstephenson/bats) |
| Location | `tests/vendor/bats-core/` |
| Modified | No — byte-identical to the upstream release for every retained file |

Only the runtime (`bin/`, `lib/`, `libexec/`) plus `LICENSE.md` are retained;
upstream's tests, docs, and container files are not. The full license text and
both copyright notices are in
[`tests/vendor/bats-core/LICENSE.md`](tests/vendor/bats-core/LICENSE.md).
Upstream's contributor roll is its
[`AUTHORS`](https://github.com/bats-core/bats-core/blob/v1.11.0/AUTHORS) file,
referenced rather than copied because it carries personal email addresses this
repository does not need to republish.
Provenance, the source-archive checksum, and the refresh procedure are in
[`tests/vendor/README.md`](tests/vendor/README.md).
