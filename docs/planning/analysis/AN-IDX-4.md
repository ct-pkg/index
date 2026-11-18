# AN-IDX-4：package.sh 的索引推送缺同级保护

追溯：`IDX-4` ｜ 分析日期：2026-11-18 ｜ 主张：REQ

## 1. 问题陈述

索引有两条推送路径，保护等级不同：

- `tools/refresh-index.sh --push`：推送前 fetch 远端 `main` 并断言其为 HEAD 祖先
  （拒绝非快进）、不接受 `--force`、推送后 `git ls-remote` 回读并与本地 HEAD 比对。
- `tools/package.sh` 的 `publish_index`：`git add index` → `commit` →
  `git push origin main`，没有快进断言，也没有回读。

主发布路径（`publish` / `release`）走的正是后者。若远端在此期间被夜间 bot 或他人推进，
非快进推送会失败但报错信息停留在 git 层面；若推送"成功"而远端被并发覆盖，本地不会察觉。

## 2. 范围

**做什么**

- 在 `publish_index`（以及 `sync_manifest` 的提交推送）里复用 `refresh-index.sh --push`
  的三段保护：快进断言、禁 `--force`、推送后回读校验。
- 失败时给出可操作提示，且不重试、不 force。

**不做什么**

- 不合并两条推送路径为一个函数（`refresh-index.sh` 是独立入口，保持可单独调用）。
- 不改 `refresh-index.sh --push` 的既有行为。
- 不引入远端锁或 CI 以外的并发协调机制。

## 3. 验收判据

| # | 命令 | 阈值 |
| --- | --- | --- |
| 1 | `grep -c 'ls-remote' tools/package.sh` | ≥ 2（推送前读取远端 tip + 推送后回读） |
| 2 | `grep -c 'merge-base --is-ancestor' tools/package.sh` | ≥ 1 |
| 3 | `grep -c -- '--force' tools/package.sh` | 0 |
| 4 | 本地 bare 仓夹具：远端 `main` 领先本地时调用索引推送步骤 | 退出码非 0；远端 tip 不变 |
| 5 | 同一夹具：远端未领先时推送 | 退出码 0；`git ls-remote` 的 tip 等于本地 HEAD |

## 4. 依赖与风险

**依赖**：需要一个本地 bare 仓夹具（可放在 `tools/` 自测里，不联网）。与 IDX-1
无依赖，可并行。

**风险**

- 回读与推送之间仍有窗口，并发推送仍可能发生；触发信号是回读不一致。缓解：回读
  失败即报错并要求人工重跑，不做自动重试。
- 夹具若使用真实远端会污染仓库；约束是只用 `file://` 本地 bare 仓。
