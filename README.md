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

Ten packages are registered as of 2026-11-08. Versions differ because the index
always names each remote's highest `v*` tag: `std`, `sql`, `png` and `net-posix`
are at `0.2.0`; `hal`, `hal-posix`, `zlib`, `sqlite`, `json` and `curl` are at
`0.1.0`. The withdrawn `1.0.0` / `1.0.1` tags are gone from every remote and the
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

### Manual refresh, commit and push

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
does not equal the local `HEAD`. A dirty work tree (anything other than `index`)
makes the script exit before it writes.

For tests against a local bare repository, override both URLs:

```sh
INDEX_PUSH_URL=/tmp/remote.git INDEX_READ_URL=/tmp/remote.git \
    sh tools/refresh-index.sh --push
```

`tools/repos.txt` lives outside this repository. Its `tag` column is derived
from the published index; after a refresh, run `tools/sync-repos-tags.sh`
(or `--check` in CI) from the workspace root instead of editing tags by hand.

A repository without a `v*` tag is reported by name and URL; the run exits 1
and leaves `index` untouched, so a missing tag can never silently drop a line.

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

## 术语表（Glossary）

| 术语 | 含义 | 本包中的所指 |
| --- | --- | --- |
| `ct-pkg/index`（索引仓库） | 只放索引文件与刷新脚本的仓库，本身不发版。 | 本仓库；`tools/repos.txt` 中 `index` 一行的 `tag` 列为 `-`。 |
| 包仓库（package repository） | 每个包各自独立的仓库，根目录放 `ct.pkg` 与源码，发版时打 tag。 | 上文 `Published` 与 `Registered` 两节列出的 `github.com/ct-pkg/<name>`。 |
| `packages.txt` | 刷新索引的输入清单，一行一个仓库。 | 仓库根目录的 `packages.txt`，字段顺序是 `name url`，空格分隔，行序即刷新顺序。 |
| `#`（注释行） | 以 `#` 开头的行与空行都不参与解析。 | `packages.txt` 顶部的说明段；`refresh-index.sh` 的 `'' \| '#'*` 分支直接跳过，末尾 `hashmap` / `dict` 两行因此保持登记但没有索引行。 |
| `name` | 包名，同时是仓库名与 `ct.pkg` 的 `name` 键。 | `packages.txt` 第一列即仓库名；`gen-index.sh` 写入 `index` 的名字取自包内 `ct.pkg`，两者与 `github.com/ct-pkg/<name>` 必须一致。 |
| `version` | 包的语义化版本 `x.y.z`，只比较前三位数字。 | `index` 第二列，取自 `ct.pkg` 的 `version =`，当前八个包都是 `0.1.0`；`ct get name@range` 按这一列筛选并取满足范围的最低版本。 |
| `git-url` | 克隆源码用的仓库地址。 | `index` 第三列（`packages.txt` 第二列），如 `https://github.com/ct-pkg/hal`。 |
| `tag` / `v*` | 指向一次发布的 git 标签，约定为 `v<version>`。 | `index` 第四列记录实际 tag；`refresh-index.sh` 用 `sort -V` 取远端最高的 `v*` tag，因此每个包在索引里只有一行，只能表达一条版本线。 |
| `sha256`（digest / 摘要） | 按路径排序后，把每个文件的相对路径、换行与内容依次汇入同一个 SHA-256 流得到的摘要。 | `index` 第五列 `sha256:<64 hex>`；`gen-index.sh` 生成，`ct get` 取回后比对，不一致报 `does not match the index`。 |
| 摘要排除名单 | 不属于包内容、不计入摘要的目录名。 | `.git`、`vendor`、`.ctcache` 之外的所有普通文件都会进摘要；`gen-index.sh` 的 `find` 与 `ct` 的 `sha_collect` 跳过同一组名字。 |
| `ct get` | 把一个 spec 解析成具体版本、克隆进 `vendor/` 并写锁的取包命令。 | 三种来源：以 `.`、`/` 开头或带 `file://` 的 spec 走本地目录；裸名先查 `--index`（或 `CT_INDEX`）指定的索引，命中则按该行的 `git-url` / `tag` / `sha256` 取；未命中或无索引时按 `CT_REGISTRY`（默认 `https://github.com/ct-pkg`）当 git 源取满足范围的 tag。 |
| `ct.lock` | 记录每个已取包解析到的 commit 与摘要的锁文件。 | 由 `ct get` 写入消费方项目；本仓库不存锁文件，索引只提供 `tag` 与 `sha256` 供其决定取哪个 commit。 |
| `vendor/` | `ct get` 把包装进来的目录。 | 指消费方项目的 `vendor/<name>`；包仓库里若自带 `vendor/`，`copy_tree` 会跳过它，所以不会被安装、也不进摘要，随包发布的第三方源码要放 `third_party/`。 |
| `ct verify` | 离线校验 `vendor/` 与 `ct.lock` 摘要的命令。 | 上面 `Usage` 的第三步；只比对摘要，不读 `ct.pkg`、不联网。 |
| `ct update` | 离线按 `ct.pkg` 对照 `ct.lock` 里钉住的 commit 重解依赖并重写锁。 | 上面 `Usage` 的第二步；不重新查索引。 |
| `tools/refresh-index.sh` | 重建整个 `index` 的脚本。 | 本仓库根的 `tools/refresh-index.sh`：遍历 `packages.txt`，取每个仓库最高 `v*` tag，clone 后调用 `gen-index.sh` 覆盖 `index`。 |
| `tools/gen-index.sh` | 生成或替换单条索引行的脚本。 | `tools/gen-index.sh <index-file> <package-dir> <git-url> <tag>`，从 `ct.pkg` 读 `name` / `version`，算摘要后写一行。 |
| `tools/repos.txt` | 记录所有 ct-pkg 仓库发布状态的清单。 | ct-pkg 工作区根的 `tools/repos.txt`（不在 index 仓库内），格式 `name \| tag \| content \| description`，无 tag 记 `-`。 |
| nightly workflow | 每天定时重建索引并提交的 CI 工作流。 | `.github/workflows/index.yml`，cron `0 18 * * *`（Asia/Shanghai 02:00），也可用 `workflow_dispatch` 手动触发。 |
| `clib` | ct-lang 里原先存放 C 映射的目录，已删除并入 `std` 包。 | 本仓库不含该目录；`Published` 节用来说明 `std` 承接了它原来的映射。 |
| `S0` | 项目阶段的第一个切片，只做需求、文档与目录骨架。 | `Registered` 表中 `hashmap` / `dict` 的 `State`：有骨架、无实现、无 tag。 |
