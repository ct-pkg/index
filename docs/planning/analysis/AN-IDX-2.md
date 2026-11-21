# AN-IDX-2：README 与 index 的版本漂移

追溯：`IDX-2` ｜ 分析日期：2026-11-18 ｜ 主张：REQ

> **状态：已关闭（2026-11-21）。** 三件事中的两件半由 `0cdb132` 达成：版本列与
> 2026-11-08 日期已删除，静态列表与 `packages.txt` 行数一致（10），摘要覆盖面已说明。
> 残余为 Usage 示例过期，登记为 `IDX-7`；对应草案 `draft-readme-single-source`
> 同日关闭，未占正式编号。

## 1. 问题陈述

`index` 由 nightly 生成，README 的「Published」表由人工维护，两条路径必然漂移。
当前 README 表是 2026-11-08 的快照：12 个包、版本停在 `std 0.2.0` / `json 0.1.0`
/ `curl 0.1.0`；而 `index` 已是 20 行，其中 `http`、`sse`、`llm-sse`、`process`、
`token`、`fsguard`、`rill`、`nexcore` 八个包在表里完全不存在。

`tools/sync-repos-tags.sh --check` 只守 `tools/repos.txt`，没有覆盖 README。

## 2. 范围

**做什么**

- 删除 README 的版本与日期列，改为一句"版本以 `index` 为准"并链接到文件。
- 保留包名与仓库地址的静态列表（这部分是稳定事实，可人工维护，但须与
  `packages.txt` 一致）。
- 在同一节补一段：摘要覆盖 CI 配置与 README，因此改文档也必须发新版本；这是
  防篡改优先于发布便利的刻意取舍。

**不做什么**

- 不做 README 版本表的自动生成或 CI 校验（那是"保留表格"路线的配套，本项选择
  直接去掉表格，从制度上消灭漂移源）。
- 不改 `index` 文件格式，不改 `repos.txt` 的派生方式。

## 3. 验收判据

| # | 命令 | 阈值 |
| --- | --- | --- |
| 1 | `grep -cE '^\| `[a-z-]+` \| https://github.com/ct-pkg/[a-z-]+ \| `[0-9]+\.[0-9]+\.[0-9]+` \|' README.md` | 0（表格中不再有版本列） |
| 2 | `grep -c '2026-11-08' README.md` | 0（快照日期不再出现） |
| 3 | README 列出的仓库数 = `grep -vc '^#\|^$' packages.txt` | 相等（20） |

## 4. 依赖与风险

**依赖**：无外部依赖；可与 IDX-3 / IDX-4 并行。

**风险**

- 去掉版本表后，新用户需要多跳一次链接才能看到版本；触发信号是 issue 里反复问
  "有哪些包"。缓解：在静态列表旁给出一个 `ct get --index` 的一行示例。
- 静态列表与 `packages.txt` 再次漂移；触发信号是两者行数不等（判据 3 已覆盖）。
