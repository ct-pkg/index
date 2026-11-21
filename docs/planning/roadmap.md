# 路线图 — ct-pkg/index

> 角色：主编（EDITOR）。本文件只做编排：排顺序、写依赖与边界，不决定"做什么"
> （条目内容归需求池，R-1），不改条目的 `what`（P-1）。
>
> 草案按主规范 6.7.1 PN-12 命名：目录 `docs/phases/draft-<slug>/`，卡头
> `phase-id: draft-<slug>` + `status: draft`，不占正式编号，不排期、不派工、
> 不开工（PN-14）。定稿走 PN-13 的原子动作；授权来自 `docs/decisions/` 的
> decision。编号账本：`docs/planning/phase-id-ledger.md`（window: W3）。

## 0. 已定稿 phase

| phase | 追溯 | 状态 | 授权 |
| --- | --- | --- | --- |
| `v0-PH-0` | `IDX-1` / `AN-IDX-1` | 已开卡，退出判据待第 5 条（nightly 绿） | `docs/decisions/D-1.md` |
| `v0-PH-1` | `IDX-3` / `AN-IDX-3` | 已开卡，待实现 | `docs/decisions/D-2.md` |

`v0-PH-0` 覆盖已推送的三个实现提交：`3f0e1bb`、`3c636d5`、`0cdb132`。

## 1. 顺序与依赖（草案）

| 顺序 | 草案 | 追溯 | 能否开工 | 依赖 | 边界 |
| --- | --- | --- | --- | --- | --- |
| — | ~~`draft-index-refresh-unblock`~~ | AN-IDX-1 | — | — | 已于 2026-11-21 定稿为 `v0-PH-0`（D-1） |
| — | ~~`draft-gate-zero-input`~~ | AN-IDX-3 | — | — | 已于 2026-11-21 定稿为 `v0-PH-1`（D-2），要求 v1 发布前完成 |
| 1 | `draft-index-push-parity` | AN-IDX-4 | 是；I10 硬错已在 `7a0c7cd` 修复，不属于本草案 | 无 | 只补 `package.sh` 的快进断言与推送后回读，不合并两条推送入口 |
| 2 | `draft-readme-single-source` | AN-IDX-2 | 是；版本表已去版本化（`0cdb132`），剩余为"由 CI 生成或引用"的增量 | 无 | 只改 README 与静态列表，不引入表格自动生成 |

序号 1、2 互不依赖，可并行。

## 2. 未入图条目

| 条目 | 原因 |
| --- | --- |
| `IDX-5` | 归属 CT 仓的字段契约与摘要算法定义（见 AN-IDX-5）；本仓单方面实现会造成索引行与消费端不一致，不排入本仓路线图。触发条件写在分析文件里，条件满足后重新评估。 |

## 3. 定稿前置（PN-13 / PN-15）

任一条草案转正式卡时，必须在同一次提交里完成：

1. 目录改名 `docs/phases/draft-<slug>/` → `docs/phases/v<M>-PH-<n>/`；
2. 卡头改正式编号、删 `status: draft`、补齐 6.2 全部开卡必填字段（含任务清单与
   `version-minor`）；
3. `docs/planning/phase-id-ledger.md` 追加一行。

授权只能来自 `docs/decisions/` 的 decision（含 `target`、`signer`、`date`），或本
文件同一行同时含 `draft-<slug>`、`v<M>-PH-<n>` 与 `authorized`。作者自行去掉
`draft` 不算授权。已按此流程完成一次：`draft-index-refresh-unblock` → `v0-PH-0`
（`docs/decisions/D-1.md`）。
