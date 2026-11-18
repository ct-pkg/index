# AN-IDX-1：nightly 索引刷新的 fail-closed 阻塞

追溯：`IDX-1` ｜ 分析日期：2026-11-18 ｜ 主张：REQ

## 1. 问题陈述

`tools/refresh-index.sh` 对每个仓库取最新 `v*` tag，要求该 tag 的 `ct.pkg` 同时带
`publisher` 与 `ns-root`，且 tag 等于 `v<version>`；任一包的最新 tag 校验失败即整次
中止、`index` 保持不动（fail-closed）。这是刻意设计：`ct` v0.54.0 起包安装路径为
`$CT_HOME/pkg/<publisher>/<name>/<version>`，缺身份的行装不上。

现状是 `packages.txt` 同时列了 20 个仓，其中 9 个的最新 tag 仍缺身份：
`hal`、`hal-posix`、`zlib`、`png`、`net-posix`、`sqlite`、`sql`、`hashmap`、`dict`。
因此 `.github/workflows/index.yml` 每夜都会失败，自动刷新实际停摆，`index` 只能靠
人工 `--commit` / `--push` 或 `--only` 维护。

## 2. 范围

**做什么**

- 让 nightly 重新变绿，且不删除仍可被消费的旧行。
- 二选一后落库（见第 4 节），两者都需要在 roadmap 定稿时明确。

**不做什么**

- 不改 `refresh-index.sh` 的 fail-closed 语义（它是防止不可安装行的唯一闸门）。
- 不改 `ct` 仓，不为旧 tag 补 `publisher` / `ns-root`（tag 不可变，补键只能发新版本）。
- 不动已发布的 `index` 行；`zlib`、`png` 等旧行在消费端仍可解析（五字段兼容）。

## 3. 验收判据

两条都要满足：

| # | 命令 | 阈值 |
| --- | --- | --- |
| 1 | `sh tools/refresh-index.sh --dry-run --all-tags` | 退出码 0；输出含 `summary:` 行；无 `aborted:` |
| 2 | `wc -l < index` 与刷新前对比 | 行数不减（当前 20）；每条已有 `name version` 仍在 |

## 4. 依赖与风险

**依赖**：用户对以下两项裁定（EDITOR 不得自选）：

- **A 补包定义**：9 个仓各自补 `publisher` / `ns-root` 并重发版本（至少 patch）。
  代价是 9 个仓各发一轮；收益是历史线统一，`--all-tags` 可回填。
- **B 拆分清单**：`packages.txt` 只留已迁移的 10 个仓，旧仓移到 `packages.txt.legacy`
  并由单独的手工流程维护。代价是旧仓不再自动刷新；收益是零成本今夜变绿。

**风险**

- 选 B 后，旧仓的安全更新不会被自动收录，需人工 `--only` 刷新；触发信号是某个旧仓
  发版后 `index` 行不变。
- 选 A 前若有仓把 `publisher` 改成与既有行不同的值，会触发 publisher 漂移保护而跳过
  旧版本；触发信号是刷新输出里出现 `publisher … differs` 跳过行。
- 两者都不做时 nightly 持续红，且失败会掩盖其它包真实的新版本（失败发生在首个坏仓，
  后面的仓可能根本没被扫到）。
