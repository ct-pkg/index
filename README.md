# ct-pkg/index

This is the maintenance repository for the ct-pkg organization. It holds the
published package index, the cross-package decision documents, and the scripts
that refresh the index, publish packages and enforce the workspace-wide gates.

**It is not a ct package.** There is no `ct.pkg` here, it is not listed in
`packages.txt`, and `ct get` never resolves the name `index`. `ct get` reads the
`index` *file* through `--index` / `CT_INDEX`; the repository that ships it is
an ordinary maintenance repo. Keeping it out of `packages.txt` is deliberate:
the index cannot contain itself.

## Layout

```
index                          the generated package index (one line per release)
packages.txt                   the repositories the index is built from
tools/refresh-index.sh         rebuild `index` from packages.txt
tools/gen-index.sh             write or replace one index line
tools/publish-package.sh       create/push package repositories via the GitHub API
tools/release-package.sh       push a tag, refresh the index, commit and push it
tools/sync-repos-tags.sh       derive the `tag` column of tools/repos.txt
tools/check-layout.sh          gate: unit directory == namespace
tools/check-char-host.sh       gate: method-name uniqueness per mapping host
tools/repos.txt                release manifest (name|tag|content|description)
docs/                          cross-package decision records
.github/workflows/index.yml    nightly index refresh
```

## The index file

`index` is the plain-text package index `ct get --index` reads. One line per
released package:

```
name version git-url tag sha256:<64 lowercase hex>
```

`ct get` resolves a bare name against this list, clones `git-url` at `tag`,
checks the fetched tree against the digest and pins the commit in `ct.lock`.
There is no HTTP service and no database: the file is the index.

The digest is the one `ct get` computes: the SHA-256 of every regular file's
relative path, a newline and the file's bytes, in sorted order, skipping `.git`,
`vendor` and `.ctcache`. CI workflows and READMEs are therefore part of the
digest: `refresh-index` checks out the tag and digests that tree, so any file
present at tag time is fine, but nothing may be added or edited under an
existing tag — that needs a new version and a new tag.

## Published

Twelve packages are registered as of 2026-11-08. Versions differ because the
index always names each remote's highest `v*` tag: `std`, `sql`, `png` and
`net-posix` are at `0.2.0`; `hal`, `hal-posix`, `zlib`, `sqlite`, `json`,
`curl`, `hashmap` and `dict` are at `0.1.0`. The withdrawn `1.0.0` / `1.0.1` tags are gone from every remote and the
version line restarted at `0.1.0`:

| Package | Repository | Version |
| --- | --- | --- |
| `hal` | https://github.com/ct-pkg/hal | `0.1.0` |
| `hal-posix` | https://github.com/ct-pkg/hal-posix | `0.1.0` |
| `std` | https://github.com/ct-pkg/std | `0.2.0` |
| `zlib` | https://github.com/ct-pkg/zlib | `0.1.0` |
| `png` | https://github.com/ct-pkg/png | `0.2.0` |
| `net-posix` | https://github.com/ct-pkg/net-posix | `0.2.0` |
| `sqlite` | https://github.com/ct-pkg/sqlite | `0.1.0` |
| `sql` | https://github.com/ct-pkg/sql | `0.2.0` |
| `json` | https://github.com/ct-pkg/json | `0.1.0` |
| `curl` | https://github.com/ct-pkg/curl | `0.1.0` |
| `hashmap` | https://github.com/ct-pkg/hashmap | `0.1.0` |
| `dict` | https://github.com/ct-pkg/dict | `0.1.0` |

`std` is the CT standard library moved out of ct-lang, and it now owns the C
mappings that used to live in `clib` (which was deleted, not archived). It is
the first package that must also be usable by an *older* compiler, which the
index cannot express: only the highest `v*` tag is listed. See the package
README for the consequence.

## Regenerating the index

`packages.txt` names the repositories. The nightly workflow runs
`tools/refresh-index.sh`, which resolves each repository's highest `v*` tag,
clones it and lets `tools/gen-index.sh` add or replace one line. A release only
needs to push a tag; the next pass picks it up, or dispatch the workflow by hand.

The same script carries the manual workflow; no flags means "refresh only":

```sh
sh tools/refresh-index.sh            # rewrite index, leave it uncommitted
sh tools/refresh-index.sh --dry-run  # per-package old -> new + unified diff
sh tools/refresh-index.sh --commit   # rewrite and commit index only
sh tools/refresh-index.sh --push     # commit, then push HEAD:main over SSH
```

`--push` uses `git@github.com:ct-pkg/index.git` and passes it to `git push` as a
one-shot URL: the `origin` remote stays on HTTPS. It never passes `--force`.
Before pushing it fetches `main` and refuses unless the remote tip is an ancestor
of `HEAD`; after pushing it runs `git ls-remote` and fails if the remote `main`
does not equal the local `HEAD`.

A refresh commit carries only the `index` file. The preflight therefore refuses
to run on any other work-tree change, including edits under `docs/` and
`tools/`: commit those first, then refresh. This keeps a refresh reviewable as a
one-file diff and prevents an unrelated doc edit from riding along.

For tests against a local bare repository, override both URLs:

```sh
INDEX_PUSH_URL=/tmp/remote.git INDEX_READ_URL=/tmp/remote.git \
    sh tools/refresh-index.sh --push
```

A repository without a `v*` tag is reported by name and URL; the run exits 1
and leaves `index` untouched, so a missing tag can never silently drop a line.

## Release and publish scripts

| Script | What it does |
| --- | --- |
| `tools/publish-package.sh [name]` | Creates a missing repository under the `ct-pkg` org through the GitHub REST API (RESTie), pushes `main`, pushes the tag from `tools/repos.txt`, then reads `content` back through the API to prove the push landed. Idempotent; never force-pushes. Needs `GITHUB_TOKEN` (or `GH_TOKEN`) with repo/workflow scope. `ORG` and `STAGING` are env overrides. |
| `tools/release-package.sh <name> <tag>` | For an already-committed tag: checks that `$STAGING/<name>` is clean, the tag exists and `ct.pkg`'s `version` matches the tag; pushes `main` and the tag; runs `tools/refresh-index.sh`; commits and pushes `index`; then points the `tag` column of `tools/repos.txt` at `<tag>`. |
| `tools/sync-repos-tags.sh [--check] [<index-file> <manifest>]` | Derives the `tag` column of `tools/repos.txt` from `index`: the file is the authority, the manifest is human-maintained prose. `--check` reports drift and exits 1 without writing. Rows the index does not contain (hashmap, dict, index itself) keep their current value and are reported if they carry a tag the index cannot confirm. |

The index holds one line per package and `ct get` picks the *lowest* version
satisfying a range (MVS), so a stale lower line would keep winning. That is why
`release-package.sh` rebuilds the whole index rather than appending to it.

## Gate scripts

| Script | What it checks |
| --- | --- |
| `tools/check-layout.sh [package ...]` | Every unit that declares `namespace A::B;` sits in `<package-root>/A/B/`. With no arguments it walks every `*/ct.pkg` in the workspace. Units without a namespace (C bindings and their `.m.ct` shims) are exempt. |
| `tools/check-char-host.sh` | The compiler keys a mapped method by `(host, method)` and ignores the signature, so two packages may each add `len()` on `char *` and only clash at a call site that sees both. The script groups every `map trait ... for type\|namespace ...` block by host and fails on a duplicate name, and on a host declared `const` / `volatile` (the type key drops those qualifiers). |

Both gates walk two levels up from `tools/`, i.e. the ct-pkg workspace root,
because the packages are separate repositories. They are useful in a working
checkout of the workspace, not in a bare clone of this repository alone.

## Cross-package decision documents

`docs/` holds decisions that span packages and therefore have no single package
home. They are records, not per-package manuals:

| File | Subject |
| --- | --- |
| `docs/char-host-methods.md` | Every method mapped onto `char *` and the other shared hosts; the admission ledger for new method names. |
| `docs/std-oo-coverage.md` | OO coverage of the `std` package: capability counts per module. |
| `docs/std-absorption-survey.md` | What `std` absorbed from ct-lang and what stayed behind. |
| `docs/std-clib-overlap.md` | The overlap between `std` and the deleted `clib`, module by module. |
| `docs/std-gap-analysis.md` | What the language still lacks for each `std` module. |
| `docs/std-to-package-evaluation.md` | Why and how `std` became a package. |
| `docs/phase2.md` | The Wave 2 plan for real C mapping packages (SQLite first). |
| `docs/ct-v0.19.1-reevaluation.md` | Re-evaluation of the mapping rules against ct v0.19.1. |

## Usage

```sh
ct get --index ./index hal-posix
ct update
ct verify
```

## 术语表（Glossary）

| 术语 | 含义 | 本包中的所指 |
| --- | --- | --- |
| `ct-pkg/index`（维护仓库） | 发布索引、跨包决策文档与发布/门禁脚本所在的仓库，本身不是 ct 包、不发版。 | 本仓库；没有 `ct.pkg`，不在 `packages.txt` 中，`ct get` 永远不会把它当作包解析。 |
| 包仓库（package repository） | 每个包各自独立的仓库，根目录放 `ct.pkg` 与源码，发版时打 tag。 | 上文 `Published` 一节列出的 `github.com/ct-pkg/<name>`。 |
| `packages.txt` | 刷新索引的输入清单，一行一个仓库。 | 仓库根目录的 `packages.txt`，字段顺序是 `name url`，空格分隔，行序即刷新顺序；刻意不含 `index` 自身。 |
| `#`（注释行） | 以 `#` 开头的行与空行都不参与解析。 | `packages.txt` 顶部的说明段；`refresh-index.sh` 的 `'' \| '#'*` 分支直接跳过。需要临时停用某个仓库时把它注释掉即可。 |
| `name` | 包名，同时是仓库名与 `ct.pkg` 的 `name` 键。 | `packages.txt` 第一列即仓库名；`gen-index.sh` 写入 `index` 的名字取自包内 `ct.pkg`，两者与 `github.com/ct-pkg/<name>` 必须一致。 |
| `version` | 包的语义化版本 `x.y.z`，只比较前三位数字。 | `index` 第二列，取自 `ct.pkg` 的 `version =`；当前 `std` / `sql` / `png` / `net-posix` 是 `0.2.0`，其余八个是 `0.1.0`。`ct get name@range` 按这一列筛选并取满足范围的最低版本。 |
| `git-url` | 克隆源码用的仓库地址。 | `index` 第三列（`packages.txt` 第二列），如 `https://github.com/ct-pkg/hal`。 |
| `tag` / `v*` | 指向一次发布的 git 标签，约定为 `v<version>`。 | `index` 第四列记录实际 tag；`refresh-index.sh` 用 awk 按三段数字比较取远端最高的 `v*` tag（BSD `sort` 没有 `-V`），因此每个包在索引里只有一行，只能表达一条版本线。 |
| `sha256`（digest / 摘要） | 按路径排序后，把每个文件的相对路径、换行与内容依次汇入同一个 SHA-256 流得到的摘要。 | `index` 第五列 `sha256:<64 hex>`；`gen-index.sh` 生成，`ct get` 取回后比对，不一致报 `does not match the index`。 |
| 摘要排除名单 | 不属于包内容、不计入摘要的目录名。 | `.git`、`vendor`、`.ctcache` 之外的所有普通文件都会进摘要；`gen-index.sh` 的 `find` 与 `ct` 的 `sha_collect` 跳过同一组名字。 |
| `ct get` | 把一个 spec 解析成具体版本、克隆进 `vendor/` 并写锁的取包命令。 | 三种来源：以 `.`、`/` 开头或带 `file://` 的 spec 走本地目录；裸名先查 `--index`（或 `CT_INDEX`）指定的索引，命中则按该行的 `git-url` / `tag` / `sha256` 取；未命中或无索引时按 `CT_REGISTRY`（默认 `https://github.com/ct-pkg`）当 git 源取满足范围的 tag。 |
| `ct.lock` | 记录每个已取包解析到的 commit 与摘要的锁文件。 | 由 `ct get` 写入消费方项目；本仓库不存锁文件，索引只提供 `tag` 与 `sha256` 供其决定取哪个 commit。 |
| `vendor/` | `ct get` 把包装进来的目录。 | 指消费方项目的 `vendor/<name>`；包仓库里若自带 `vendor/`，`copy_tree` 会跳过它，所以不会被安装、也不进摘要，随包发布的第三方源码要放 `third_party/`。 |
| `ct verify` | 离线校验 `vendor/` 与 `ct.lock` 摘要的命令。 | 上面 `Usage` 的第三步；只比对摘要，不读 `ct.pkg`、不联网。 |
| `ct update` | 离线按 `ct.pkg` 对照 `ct.lock` 里钉住的 commit 重解依赖并重写锁。 | 上面 `Usage` 的第二步；不重新查索引。 |
| `tools/refresh-index.sh` | 重建整个 `index` 的脚本。 | 本仓库根的 `tools/refresh-index.sh`：遍历 `packages.txt`，取每个仓库最高 `v*` tag，clone 后调用 `gen-index.sh` 覆盖 `index`；一条提交只带 `index`，所以工作树里 `docs/`、`tools/` 的改动必须先提交。 |
| `tools/gen-index.sh` | 生成或替换单条索引行的脚本。 | `tools/gen-index.sh <index-file> <package-dir> <git-url> <tag>`，从 `ct.pkg` 读 `name` / `version`，算摘要后写一行。 |
| `tools/repos.txt` | 记录所有 ct-pkg 仓库发布状态的清单。 | 本仓库的 `tools/repos.txt`，格式 `name \| tag \| content \| description`，无 tag 记 `-`；`tag` 列由 `tools/sync-repos-tags.sh` 从 `index` 派生。 |
| `tools/check-layout.sh` | 门禁：单元目录必须与命名空间一致。 | 默认遍历工作区（本仓库向上两级）下所有 `*/ct.pkg`；带参数时只检查指定包根。 |
| `tools/check-char-host.sh` | 门禁：同一映射宿主上的方法名必须全仓唯一。 | 按 `(宿主, 方法)` 分组扫描 `*.m.ct`；宿主声明带 `const` / `volatile` 也算失败，因为类型键会丢弃限定符。 |
| nightly workflow | 每天定时重建索引并提交的 CI 工作流。 | `.github/workflows/index.yml`，cron `0 18 * * *`（Asia/Shanghai 02:00），也可用 `workflow_dispatch` 手动触发。 |
| `clib` | ct-lang 里原先存放 C 映射的目录，已删除并入 `std` 包。 | 本仓库不含该目录；`Published` 节用来说明 `std` 承接了它原来的映射。 |
| `S0` | 项目阶段的第一个切片，只做需求、文档与目录骨架。 | 历史阶段名：`hashmap` / `dict` 曾停留在「有骨架、无实现、无 tag」，两者现已发布 `0.1.0` 并进入 `index`。 |
