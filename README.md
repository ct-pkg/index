# ct-pkg/index

The plain-text package index `ct get --index` reads. One line per released
package:

```
name version git-url tag sha256:<64 lowercase hex>
```

`ct get` resolves a bare name against this list, clones `git-url` at `tag`,
checks the fetched tree against the digest and pins the commit in `ct.lock`.
There is no HTTP service and no database: the file is the index.

## Wave 1

| Package | Repository |
| --- | --- |
| `hal` | https://github.com/ct-pkg/hal |
| `hal-posix` | https://github.com/ct-pkg/hal-posix |
| `clib` | https://github.com/ct-pkg/clib |

## Regenerating

`packages.txt` names the repositories. The nightly workflow runs
`tools/refresh-index.sh`, which resolves each repository's highest `v*` tag,
clones it and lets `tools/gen-index.sh` add or replace one line. A release only
needs to push a tag; the next pass picks it up, or dispatch the workflow by hand.

The digest is the one `ct get` computes: the SHA-256 of every regular file's
relative path, a newline and the file's bytes, in sorted order, skipping `.git`,
`vendor` and `.ctcache`. A package repository therefore must not carry CI
workflows or other files that change after the tag — the tag and the digest
would stop agreeing.

## Usage

```sh
ct get --index ./index hal-posix
ct update
ct verify
```
