# 路线图 — ct-pkg/index

> 角色：主编（EDITOR）。本文件只做编排：排顺序、写依赖与边界，不决定"做什么"
> （条目内容归需求池，R-1），不改条目的 `what`（P-1）。
>
> **本仓首次建立 roadmap，尚无已定稿 phase。** 下列四项均为草案（主规范 6.7.1
> PN-12）：目录为 `docs/phases/draft-<slug>/`，不占用、也不预留正式编号
> `v<M>-PH-<n>`，不排期、不派工、不开工（PN-14）。定稿须走 PN-13 的原子动作，
> 授权来自 decision 或本文件带 `authorized` 的行（PN-15）；当前没有任何一行带
> `authorized`。

## 1. 顺序与依赖

| 顺序 | 草案 | 追溯 | 能否开工 | 依赖 | 边界 |
| --- | --- | --- | --- | --- | --- |
| 1 | `draft-index-refresh-unblock` | AN-IDX-1 | 否，阻塞 | 用户在 A / B 之间裁定 | 只动 `packages.txt` 与文档，不改 `refresh-index.sh` 的 fail-closed 语义，不改 `ct` 仓 |
| 2 | `draft-gate-zero-input` | AN-IDX-3 | 是 | 无 | 只加零输入断言与负例，不改门禁判定逻辑；若顺序 1 选 B，需同步确认 `gates.yml` 的克隆源 |
| 3 | `draft-index-push-parity` | AN-IDX-4 | 是 | 无 | 只补 `package.sh` 的快进断言与回读，不合并两条推送入口 |
| 4 | `draft-readme-single-source` | AN-IDX-2 | 是 | 无 | 只改 README 与静态列表，不引入表格自动生成 |

顺序 2、3、4 互不依赖，可并行；顺序 1 阻塞但不阻塞其余三项——它不是其余三项的
前置条件，只决定 nightly 何时恢复。之所以列在第一，是因为它决定 `index` 的自动
更新是否继续工作。

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
`draft` 不算授权。
