# ct-pkg/index

The plain-text package index `ct get --index` reads. One line per released
package:

```
name version git-url tag sha256:<64 lowercase hex>
```

`ct get` resolves a bare name against this list, clones `git-url` at `tag`,
checks the fetched tree against the digest and pins the commit in `ct.lock`.
There is no HTTP service and no database: the file is the index.

## Published

All eight packages are published at `0.1.0` (2026-11-07). The withdrawn
`1.0.0` / `1.0.1` tags are gone from every remote and the version line
restarted at `0.1.0`:

| Package | Repository |
| --- | --- |
| `hal` | https://github.com/ct-pkg/hal |
| `hal-posix` | https://github.com/ct-pkg/hal-posix |
| `std` | https://github.com/ct-pkg/std |
| `zlib` | https://github.com/ct-pkg/zlib |
| `png` | https://github.com/ct-pkg/png |
| `net-posix` | https://github.com/ct-pkg/net-posix |
| `sqlite` | https://github.com/ct-pkg/sqlite |
| `sql` | https://github.com/ct-pkg/sql |

`std` is the CT standard library moved out of ct-lang, and it now owns the C
mappings that used to live in `clib` (which was deleted, not archived). It is
the first package that must also be usable by an *older* compiler, which the
index cannot express: only the highest `v*` tag is listed. See the package
README for the consequence.

## Registered, not yet in the index

Two repositories were registered on 2026-11-08 but have no `v*` tag yet, so they
have **no line in `index` and no digest**. Their `packages.txt` lines stay
commented because `tools/refresh-index.sh` aborts the whole run on a repository
without a release tag; `tools/repos.txt` records the absent tag as `-`.

| Package | Repository | State |
| --- | --- | --- |
| `hashmap` | https://github.com/ct-pkg/hashmap | S0 requirements and skeleton, no tag |
| `dict` | https://github.com/ct-pkg/dict | S0 requirements and skeleton, no tag |

When either pushes its first `v*` tag (planned `v0.1.0`), uncomment its
`packages.txt` line and the next refresh adds the real version and digest. No
version or digest is invented here on purpose.

## Regenerating

`packages.txt` names the repositories. The nightly workflow runs
`tools/refresh-index.sh`, which resolves each repository's highest `v*` tag,
clones it and lets `tools/gen-index.sh` add or replace one line. A release only
needs to push a tag; the next pass picks it up, or dispatch the workflow by hand.

The digest is the one `ct get` computes: the SHA-256 of every regular file's
relative path, a newline and the file's bytes, in sorted order, skipping `.git`,
`vendor` and `.ctcache`. CI workflows and READMEs are therefore part of the
digest: `refresh-index` checks out the tag and digests that tree, so any file
present at tag time is fine, but nothing may be added or edited under an
existing tag — that needs a new version and a new tag.

## Usage

```sh
ct get --index ./index hal-posix
ct update
ct verify
```
