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
index                          the generated package index (one line per version)
packages.txt                   the repositories the index is built from
tools/refresh-index.sh         rebuild `index` from packages.txt
tools/gen-index.sh             write or replace one index line (six fields)
tools/package.sh               checked publish / release: push, refresh, verify
tools/package-check.sh         read-only release lint (no compiler needed)
tools/package-check-selftest.sh  fixtures and expected exit codes for the lint
tools/verify-index.sh          replay every index row through `ct get`
tools/sync-repos-tags.sh       derive the `tag` column of tools/repos.txt
tools/check-layout.sh          gate: unit directory == namespace
tools/check-char-host.sh       gate: method-name uniqueness per mapping host
tools/repos.txt                release manifest (name|tag|content|description)
docs/                          cross-package decision records
.github/workflows/index.yml    nightly index refresh
.github/workflows/gates.yml    nightly workspace gates
```

## The index file

`index` is the plain-text package index `ct get --index` reads. One line per
released version (six fields, the format `ct` v0.54.0+ consumes):

```
name version publisher git-url tag sha256:<64 lowercase hex>
```

`ct get` resolves a name against this list, clones `git-url` at `tag`, checks
the fetched tree against the digest and pins the commit in `ct.lock`. There is
no HTTP service and no database: the file is the index.

`publisher` is the shared-store identity: `ct` installs into
`$CT_HOME/pkg/<publisher>/<name>/<version>`, so a row without it is unusable
even when the tag and digest are correct. `gen-index.sh` reads `publisher` and
`ns-root` from the tag's `ct.pkg` and refuses to write a row when either is
missing, so every row in `index` carries all six fields.

The digest is the one `ct get` computes: the SHA-256 of every regular file's
relative path, a newline and the file's bytes, in sorted order, skipping `.git`,
`vendor` and `.ctcache`. CI workflows and READMEs are therefore part of the
digest: `refresh-index` checks out the tag and digests that tree, so any file
present at tag time is fine, but nothing may be added or edited under an
existing tag — that needs a new version and a new tag.

## Published

`packages.txt` is the admission list of the registry. Versions are not repeated
here: `index` is the only source of truth for what is published.

| Repository | Packages it publishes |
| --- | --- |
| https://github.com/ct-pkg/std | `std` |
| https://github.com/ct-pkg/http | `http` |
| https://github.com/ct-pkg/sse | `sse` |
| https://github.com/ct-pkg/llm-sse | `llm-sse` |
| https://github.com/ct-pkg/process | `process` |
| https://github.com/ct-pkg/token | `token` |
| https://github.com/ct-pkg/json | `json` |
| https://github.com/ct-pkg/fsguard | `fsguard` |
| https://github.com/ct-pkg/rill-dsl | `rill` up to 0.23.1, `rill-dsl` from 0.23.2 |
| https://github.com/ct-pkg/nexcore | `nexcore` |

`std` is the CT standard library moved out of ct-lang, and it now owns the C
mappings that used to live in `clib` (which was deleted, not archived).

### Repositories not registered

`hal`, `hal-posix`, `zlib`, `png`, `net-posix`, `sqlite`, `sql`, `curl`,
`hashmap` and `dict` still exist, but their tagged `ct.pkg` carries no
`publisher` or `ns-root`, so no row can be generated for them. They are absent
from `packages.txt` and have no line in `index`; a re-release that carries both
keys puts them back in the list like any other package.

The generator refuses to mix publishers across versions of one package: the
newest tag defines the identity, and older tags with a different publisher are
reported and skipped.

### Frozen transitional scripts

The shell tools stay usable but stop growing. Frozen means no new index-side
policy: no new row fields, no new row formats and no new admission rules
invented here. Three kinds of change are allowed and expected:

| Change | Rule |
| --- | --- |
| contract sync | the contract or `ct` changes first; these scripts follow in the same window, editing the mirrored rules directly |
| bug fix | current behaviour contradicts the contract, crashes, or misjudges a package |
| retirement | a script or check is deleted once `ct` covers it |

No compatibility promise. Nothing in this repository is publicly released yet,
so the mirrored rules — the digest recipe in `gen-index.sh` and the strict lint
in `package-check.sh` — are edited in place when the contract moves. There is no
dual-format support, no compatibility shim and no deprecation window for a row
shape: `index` carries six fields only.

## Regenerating the index

`packages.txt` names the repositories. The nightly workflow runs
`tools/refresh-index.sh --all-tags`, which resolves every `v*` tag, clones each
repository once, checks out each tag and lets `tools/gen-index.sh` add or
replace its line. A release only needs to push a tag; the next pass picks it
up, or dispatch the workflow by hand.

The same script carries the manual workflow; no flags means "newest tag per
repository, refresh only":

```sh
sh tools/refresh-index.sh                  # rewrite index, leave it uncommitted
sh tools/refresh-index.sh --dry-run        # per-version old -> new + unified diff
sh tools/refresh-index.sh --commit         # rewrite and commit the index file only
sh tools/refresh-index.sh --push           # commit, then push HEAD:main over SSH
sh tools/refresh-index.sh --all-tags       # index every v* tag, not just the newest
sh tools/refresh-index.sh --allow-rewrite  # accept a changed digest (escape hatch)
```

`INDEX_PACKAGES` and `INDEX_FILE` override the input list and the output file,
which is how the scripts are tested against local fixtures.

Two guards run before anything is written:

- **identity**: a row is only written when the tag's `ct.pkg` has `publisher`
  (not `local`) and `ns-root` (relative, no `..`, directory exists), and when
  the tag is exactly `v<version>`. In `--all-tags` mode an older tag that fails
  is reported and skipped; the newest tag failing aborts the run.
- **immutability**: an already indexed `name version` may not change its
  digest. A moved tag is reported with both digests and the run aborts unless
  `--allow-rewrite` is passed. This is the local half of tamper detection; the
  consumer half is `tools/verify-index.sh` plus the digest in `ct.lock`.

The generator also refuses to mix publishers across versions of one package:
the newest tag's `publisher` defines the identity, and older tags with a
different one are reported as skipped.

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

## Package lifecycle

`tools/package.sh` is the single entry point for publishing. The old
`publish-package.sh` / `release-package.sh` split only differed in how the
remote repository comes into existence; everything after the tag push was
duplicated. The merged script keeps one copy of that path:

```
preflight -> push main + tag -> wait for the tag -> rebuild index ->
verify the row with `ct get` -> commit + push index -> sync repos.txt
```

| Command | What it does |
| --- | --- |
| `tools/package.sh check [<name> ...]` | Read-only preflight: clean tree, `v<version>` matches `ct.pkg`, `tools/package-check.sh`, `check-layout.sh` per package, `check-char-host.sh` over the workspace. Never invokes `ct`. |
| `tools/package.sh verify <name> <version>` | Replays one existing index row with `ct get`. Exits non-zero when no compiler is found; this is the guard the `no-ct` CI job exercises. |
| `tools/package-check.sh [--strict] <dir>` | The release lint itself: PK-1/2/5/8 (the read-only criteria that used to come from the compiler) plus release and optional strict checks. Pure shell, no compiler, no network, no writes. |
| `tools/package.sh publish <name>` | Creates the repository through the GitHub REST API (RESTie) when missing, pushes `main` and the tag from `tools/repos.txt`, reads `content` back to prove the push landed, then runs the shared index pipeline. Needs `GITHUB_TOKEN` (or `GH_TOKEN`). |
| `tools/package.sh release <name> <tag>` | For an already-committed tag: same preflight, push, index pipeline. Only needs git plus the token for the HTTPS push. |
| `tools/verify-index.sh [--index <file>] [--name <name>]` | Replays each row in an isolated `HOME` / `CT_HOME` with `ct get --index`, then compares the digest in `ct.lock` with the index row. This is the end-to-end check `refresh-index.sh` cannot do by itself. |
| `tools/sync-repos-tags.sh [--check] [<index-file> <manifest>]` | Derives the `tag` column of `tools/repos.txt` from `index` (field 5 of a six-field row). `--check` reports drift and exits 1 without writing. |

The index holds one line per version. `ct get` selects the newest version when
the range is omitted (`*`) and the lowest satisfying version (MVS) for an
explicit range, so the whole index is rebuilt rather than appended to. Indexed
versions are immutable: a changed digest needs a new version, never an edit.

Both index pushes use the same guard as `refresh-index.sh --push`: before
pushing, `package.sh` fetches `origin/main` and refuses unless the remote tip is
an ancestor of `HEAD` (a fast-forward); after pushing it reads the remote tip
back with `git ls-remote`; it never passes `--force`. A rejected push leaves the
local commit in place and names both sides, so the operator can integrate and
rerun.

**Temporary discipline (until `ct index refresh` exists).** Every push of
`index` must be preceded by a replay that actually ran. `package.sh` now aborts
when no compiler is found instead of warning (get-contract I10), and there is no
bypass flag: an audit marker would have to live in the index row, whose format
is owned by the contract, so a bypass could not be recorded truthfully. A
machine without `ct` therefore cannot publish; publish from one that has it.

### Release lint (`tools/package-check.sh`)

The release lint lives here, in shell, so publishing no longer depends on an
installed compiler. It is read-only: no network, no writes to the package tree,
no caches. Exit status is 0 on success and 1 on failure; every failure goes to
stderr with the manifest or file and, where it exists, the line.

| Code | Source | Check |
| --- | --- | --- |
| PK-1 | moved from `ct pkg check` | `ct.pkg` exists and is readable |
| PK-2 | moved | `name` / `publisher` / `version` / `ns-root` present; `publisher != local` |
| PK-5 | moved | `ns-root` is relative, has no `..`, and is an existing directory |
| PK-8 | moved | no absolute `-I` in the package tree (skips `.git`, `docs`, `issues`, `battle`, `test`, `*.md`, and files above 262144 bytes) |
| R1 | new | `name` / `publisher` match `[A-Za-z0-9][A-Za-z0-9._-]*`, no `..`, no `/` |
| R2 | new | `version` is `x.y.z` |
| R3 | new | if HEAD is tagged, a `v<version>` tag must be among its tags; a missing git checkout or a not-yet-tagged HEAD is a warning |
| S1 | new, `--strict` | a namespaced unit sits in `<ns-root>/<namespace path>/` |
| S2 | new, `--strict` | `dep` specs parse and no package is repeated |
| S3 | new, `--strict` | `requires` parses as `ct` plus a version range |
| S4 | new, `--strict` | `c-boundary`, when present, is `strict` or `allow` |
| S5 | new, `--strict` | no build artifacts, cache directories or `vendor/` |

PK-8 is stronger than the compiler check in two ways: it walks the whole tree
instead of a bounded queue of directories, and it reports the file and line
number. Everything else keeps the compiler's semantics, including the token
value parse for the identity keys and the same skip list and size cap.

Boundary between check and publish:

- `package-check.sh` and `package.sh check` never invoke `ct` and do not read
  `CT_BIN`. A compiler is only used at the end of `publish` / `release`, to
  replay the fresh index row with `ct get`; that step is skipped with a warning
  when no `ct` / `ct-ast` is on `PATH`.
- `ct` keeps the consumer-side validation (`ct get` / `ct install` / `ct
  verify`). Its `pkg check` subcommand stays untouched during the transition;
  removing it is the compiler repository's decision.

`tools/package-check-selftest.sh` builds its fixtures in a temporary directory
and prints every command, expected exit code and observed output.

## CI workflows

| Workflow | What it does |
| --- | --- |
| `.github/workflows/index.yml` | Nightly `--all-tags` refresh; syncs `tools/repos.txt`; commits and pushes `index` and the manifest, or does nothing when both are unchanged. Also `workflow_dispatch`. |
| `.github/workflows/gates.yml` | Checks out `index` under `ws/index`, clones every package in `packages.txt` beside it, then runs `gate-selftest.sh`, `check-layout.sh`, `check-char-host.sh` and `sync-repos-tags.sh --check`. This is what makes the workspace gates run without a developer's staging directory. |

## Gate scripts

| Script | What it checks |
| --- | --- |
| `tools/check-layout.sh [package ...]` | Every unit that declares `namespace A::B;` sits in `<package-root>/A/B/`. With no arguments it walks every `*/ct.pkg` in the workspace. Units without a namespace (C bindings and their `.m.ct` shims) are exempt. |
| `tools/check-char-host.sh` | The compiler keys a mapped method by `(host, method)` and ignores the signature, so two packages may each add `len()` on `char *` and only clash at a call site that sees both. The script groups every `map trait ... for type\|namespace ...` block by host and fails on a duplicate name, and on a host declared `const` / `volatile` (the type key drops those qualifiers). |
| `tools/gate-selftest.sh` | Fixture-based self-test for the two gates above: empty workspace, missing `ct.pkg`, matching and mismatching namespaces, packages without mapped methods, duplicate methods and `const` hosts. Runs without a package checkout. |

Both gates walk two levels up from `tools/`, i.e. the ct-pkg workspace root,
because the packages are separate repositories. `CT_PKG_ROOT` overrides that
root; when the variable is unset **or empty** the default `tools/../..` is used,
so an unset variable is not an error. A root that contains no `*/ct.pkg`, on the
other hand, is a failure: both scripts exit 1 and print the resolved root, the
package count and a hint to set `CT_PKG_ROOT`, instead of reporting `ok: 0`.
The diagnostic begins with `check-layout: no packages found` or
`check-char-host: no packages found`, so a CI log shows the failure directly.
That keeps a broken CI clone from looking green. `tools/package.sh check` runs
the same gates before a release, together with `tools/package-check.sh` and the
workspace-wide `check-char-host.sh`.

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

## Review drafts

| File | Subject |
| --- | --- |
| [docs/reviews/ct-pkg-index-battle.md](docs/reviews/ct-pkg-index-battle.md) | Review of the package-index proposal: current-state check, three adversarial battles, rulings and minimum acceptance set. |
| [docs/reviews/ct-pkg-index-proposal-v2-draft.md](docs/reviews/ct-pkg-index-proposal-v2-draft.md) | Revised proposal draft (not accepted) incorporating the review's P0/P1 conditions. |

## Usage

```sh
export CT_INDEX=$PWD/index
ct get <publisher>/<name>@<version>   # e.g. std/std@0.3.2
ct install                            # offline check; prints the build command
ct verify                             # offline digest check against ct.lock
```

A bare name is only unambiguous when the index has one publisher for it. Every
committed row now carries `publisher`, so qualified names resolve for every
registered package.

## 术语表（Glossary）

| 术语 | 含义 | 本包中的所指 |
| --- | --- | --- |
| `ct-pkg/index`（维护仓库） | 发布索引、跨包决策文档与发布/门禁脚本所在的仓库，本身不是 ct 包、不发版。 | 本仓库；没有 `ct.pkg`，不在 `packages.txt` 中，`ct get` 永远不会把它当作包解析。 |
| 包仓库（package repository） | 每个包各自独立的仓库，根目录放 `ct.pkg` 与源码，发版时打 tag。 | `packages.txt` 列出的 `github.com/ct-pkg/<name>`。 |
| `packages.txt` | 刷新索引的输入清单，一行一个仓库。 | 仓库根目录的 `packages.txt`，字段顺序是 `name url`，空格分隔，行序即刷新顺序；刻意不含 `index` 自身。 |
| `#`（注释行） | 以 `#` 开头的行与空行都不参与解析。 | `packages.txt` 顶部的说明段；`refresh-index.sh` 的 `'' \| '#'*` 分支直接跳过。需要临时停用某个仓库时把它注释掉即可。 |
| `name` | 包名，同时是仓库名与 `ct.pkg` 的 `name` 键。 | `packages.txt` 第一列即仓库名；`gen-index.sh` 写入 `index` 的名字取自包内 `ct.pkg`，两者与 `github.com/ct-pkg/<name>` 必须一致。 |
| `version` | 包的语义化版本 `x.y.z`，只比较前三位数字。 | `index` 第二列，取自 `ct.pkg` 的 `version =`。`ct get` 省略范围（或写 `*`）时取最新版本，显式范围取满足范围的最低版本（MVS）。 |
| `publisher` | 发布方；与 `name` 组成 `<publisher>/<name>`，是共享包库路径的第一段。 | `index` 第三列，取自 `ct.pkg` 的 `publisher =`，不能是保留字 `local`。缺这一列的旧五字段行仍可被 `ct` 解析，但无法落共享包库。 |
| `git-url` | 克隆源码用的仓库地址。 | `index` 第四列（`packages.txt` 第二列），如 `https://github.com/ct-pkg/hal`。 |
| `tag` / `v*` | 指向一次发布的 git 标签，约定为 `v<version>`。 | `index` 第五列记录实际 tag；`refresh-index.sh` 用 awk 按三段数字比较给 `v*` tag 排序（BSD `sort` 没有 `-V`），默认只收最高一个，`--all-tags` 收全部。 |
| `ns-root` | 包内单元树根，相对包根、不含 `..`、目录必须存在。 | 不进 `index`；写入消费方的 `ct.lock`，`ct build` 用它拼 `-I <store>/<publisher>/<name>/<version>/<ns-root>`。 |
| `sha256`（digest / 摘要） | 按路径排序后，把每个文件的相对路径、换行与内容依次汇入同一个 SHA-256 流得到的摘要。 | `index` 第六列 `sha256:<64 hex>`；`gen-index.sh` 生成，`ct get` 取回后比对，不一致报 `does not match the index`。 |
| 摘要排除名单 | 不属于包内容、不计入摘要的目录名。 | `.git`、`vendor`、`.ctcache` 之外的所有普通文件都会进摘要；`gen-index.sh` 的 `find` 与 `ct` 的 `sha_collect` 跳过同一组名字。 |
| `ct get` | 把一个 spec 解析成具体版本、取回源码、落共享包库并写锁的命令。 | 三种来源：以 `.`、`/` 开头或带 `file://` 的 spec 走本地目录；名字先查 `--index`（或 `CT_INDEX`）指定的索引，命中则按该行的 `git-url` / `tag` / `sha256` 取；未命中或无索引时按 `CT_REGISTRY`（默认 `https://github.com/ct-pkg`）当 git 源取。自 v0.62.0 起不再写 `vendor/`。 |
| `ct.lock` | 记录每个已解析包的发布方、版本、来源、commit、`ns-root` 与摘要的 v2 锁文件。 | 由 `ct get` 写入消费方项目；本仓库不存锁文件，索引只提供 `tag` 与 `sha256` 供其决定取哪个 commit。 |
| 共享包库（store） | 每用户共享的包目录 `$CT_HOME/pkg/<publisher>/<name>/<version>/`。 | `ct get` / `ct install` / `ct build` 的包来源；同版本重装摘要相同即 no-op，不同即硬错。 |
| `ct verify` / `ct update` | 离线校验与重解命令；不读索引、不联网。 | `ct verify` 比对 store 与 `ct.lock` 摘要，`--strict` 拒绝 `dir` 行；`ct update` 按锁里钉住的版本重写锁。 |
| `tools/refresh-index.sh` | 重建整个 `index` 的脚本。 | 遍历 `packages.txt`，每个仓库 clone 一次，按 tag 调用 `gen-index.sh`；默认最高 tag，`--all-tags` 收全部版本。校验 `publisher` / `ns-root` / tag 与 version 一致，并拒绝已收录版本改摘要。一条提交只带 `index`，所以工作树里 `docs/`、`tools/` 的改动必须先提交。 |
| `tools/gen-index.sh` | 生成或替换单条索引行的脚本。 | `tools/gen-index.sh <index-file> <package-dir> <git-url> <tag>`，从 `ct.pkg` 读 `name` / `version` / `publisher` / `ns-root`，校验后算摘要，写六字段一行。 |
| `tools/package.sh` | 发布与发版的统一入口。 | `check` 只读预检；`publish` 经 GitHub API 建仓后推 main/tag；`release` 推已有 tag。两者都走同一条「推包 → 等 tag 可见 → 重建索引 → `ct get` 回放 → 提交并推索引 → 同步 repos.txt」流水线。`check` 路径不调用 `ct`，编译器只在最后回放索引行时使用。 |
| `tools/package-check.sh` | 发布 lint 的独立只读入口。 | `bash tools/package-check.sh [--strict] <包目录>`；PK-1/2/5/8 与 CT 既有检查等价，R1–R3 为发布新增，`--strict` 追加 S1–S5。不联网、不写包树、不建缓存、不依赖编译器；失败写 stderr 并带文件/行，0=通过、1=失败。 |
| `tools/package-check-selftest.sh` | lint 的夹具与回归脚本。 | 在临时目录生成正/负例（缺键、`publisher = local`、ns-root 绝对/含 `..`/不存在、绝对 `-I`、tag 与 version 不一致、namespace 目录不一致等），逐条打印命令、期望退出码与实际输出。 |
| `tools/verify-index.sh` | 用真实 `ct get` 回放索引行的校验脚本。 | 在隔离的 `HOME` / `CT_HOME` 里逐行 `ct get --index`，再把 `ct.lock` 的摘要与索引行比对；这是 `refresh-index.sh` 自己做不到的端到端检查。 |
| `tools/repos.txt` | 记录所有 ct-pkg 仓库发布状态的清单。 | 本仓库的 `tools/repos.txt`，格式 `name \| tag \| content \| description`，无 tag 记 `-`；`tag` 列由 `tools/sync-repos-tags.sh` 从 `index` 派生。 |
| `tools/check-layout.sh` | 门禁：单元目录必须与命名空间一致。 | 默认遍历工作区（本仓库向上两级）下所有 `*/ct.pkg`；带参数时只检查指定包根；`CT_PKG_ROOT` 可改工作区根。 |
| `tools/check-char-host.sh` | 门禁：同一映射宿主上的方法名必须全仓唯一。 | 按 `(宿主, 方法)` 分组扫描 `*.m.ct`；宿主声明带 `const` / `volatile` 也算失败，因为类型键会丢弃限定符；同样支持 `CT_PKG_ROOT`。 |
| nightly workflows | 每天定时重建索引、跑跨包门禁的 CI 工作流。 | `.github/workflows/index.yml`：cron `0 18 * * *`（Asia/Shanghai 02:00）`--all-tags` 刷新并提交；`.github/workflows/gates.yml`：cron `0 19 * * *`，把包仓库 clone 到 `ws/` 后跑两个门禁与 manifest 漂移检查。两者都支持 `workflow_dispatch`。 |
| `clib` | ct-lang 里原先存放 C 映射的目录，已删除并入 `std` 包。 | 本仓库不含该目录；`Published` 节用来说明 `std` 承接了它原来的映射。 |
| `S0` | 项目阶段的第一个切片，只做需求、文档与目录骨架。 | 历史阶段名：`hashmap` / `dict` 曾停留在「有骨架、无实现、无 tag」，两者现已发布 `0.1.0` 并进入 `index`。 |
