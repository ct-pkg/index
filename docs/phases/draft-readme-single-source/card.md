---
phase-id: draft-readme-single-source
status: draft
---

# 草案：README 版本信息单一来源

> 未定稿。不占正式编号、不排期、不派工、不开工（主规范 6.7.1 PN-12 / PN-14）。
> 追溯：`IDX-2`（分析：`docs/planning/analysis/AN-IDX-2.md`）

## 目标

README 不再保存任何版本与快照日期，版本信息只以 `index` 文件为准。

## 范围

**做什么**

- 删除「Published」表的 Version 列与 2026-11-08 快照日期，改为一句"版本以 `index`
  为准"，附一条 `ct get --index ./index <publisher>/<name>@<version>` 示例。
- 静态列表保留包名与仓库地址，行数与 `packages.txt` 一致（当前 20）。
- 补一段摘要覆盖面说明：CI 配置与 README 计入摘要，因此改文档也须发新版本；
  这是防篡改优先于发布便利的取舍。

**不做什么**

- 不做 README 表格的自动生成或 CI 一致性校验（本项选择去掉表格，而不是守护表格）。
- 不改 `index` 格式、`gen-index.sh`、`sync-repos-tags.sh`。

## 依赖

- 无外部依赖。
- 若 `draft-index-refresh-unblock` 选 B（拆分 `packages.txt`），静态列表须以主清单
  为准并注明旧仓单列。

## 已知风险

- 去掉版本表后新用户需多跳一次；触发信号：反复出现"有哪些包/什么版本"的提问。
  缓解：示例命令与 `index` 链接放在同一段。
- 静态列表与 `packages.txt` 再次漂移；触发信号：两者行数不等（已列为验收判据）。
