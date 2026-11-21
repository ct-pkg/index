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
| `v0-PH-0` | `IDX-1` / `AN-IDX-1` | 已收口 2026-11-21（`v0.0.0`，[对照](reviews/closeout-v0-PH-0.md)） | `docs/decisions/D-1.md` |
| `v0-PH-1` | `IDX-3` / `AN-IDX-3` | 已收口 2026-11-21（`v0.1.0`，[对照](reviews/closeout-v0-PH-1.md)） | `docs/decisions/D-2.md` |
| `v0-PH-2` | `IDX-4` / `AN-IDX-4` | 已收口 2026-11-21（`v0.2.0`，[对照](reviews/closeout-v0-PH-2.md)） | `docs/decisions/D-3.md` |
| `v0-PH-3` | `IDX-6` / `AN-IDX-6` | 已收口 2026-11-21（`v0.3.0`，[对照](reviews/closeout-v0-PH-3.md)） | `docs/decisions/D-4.md` |

`v0-PH-0` 覆盖已推送的三个实现提交：`3f0e1bb`、`3c636d5`、`0cdb132`。

## 1. 草案状态

**当前草案**

无。

**已处置的五份**

| 草案 | 追溯 | 结果 |
| --- | --- | --- |
| `draft-index-refresh-unblock` | AN-IDX-1 | 2026-11-21 定稿为 `v0-PH-0`（D-1） |
| `draft-gate-zero-input` | AN-IDX-3 | 2026-11-21 定稿为 `v0-PH-1`（D-2），要求 v1 发布前完成 |
| `draft-index-push-parity` | AN-IDX-4 | 2026-11-21 定稿为 `v0-PH-2`（D-3） |
| `draft-readme-single-source` | AN-IDX-2 | 2026-11-21 关闭：目标已由 `0cdb132` 达成，残余项登记为 `IDX-7` |
| `draft-layout-ns-root` | AN-IDX-6 | 2026-11-21 定稿为 `v0-PH-3`（D-4） |

关闭的草案不占正式编号，因此账本没有对应行（PN-7 只管已分配的号）。
`v0-PH-2` 的实现由执笔人承担。新的需求先入需求池，再按是否需要成组交付决定
走草案 / phase，还是直接做一次普通修正（如 `IDX-7`）。

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
