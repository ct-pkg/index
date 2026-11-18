---
phase-id: draft-index-push-parity
status: draft
---

# 草案：package.sh 的索引推送补齐同级保护

> 未定稿。不占正式编号、不排期、不派工、不开工（主规范 6.7.1 PN-12 / PN-14）。
> 追溯：`IDX-4`（分析：`docs/planning/analysis/AN-IDX-4.md`）

## 目标

`tools/package.sh` 推送 `index` 时具备与 `refresh-index.sh --push` 相同的保护：
推送前拒绝非快进、永不 `--force`、推送后回读校验远端 tip。

## 范围

**做什么**

- `publish_index` 与 `sync_manifest` 的推送复用三段保护：fetch 远端 `main` 并断言
  其为 HEAD 祖先；推送后 `git ls-remote` 与本地 HEAD 比对；失败即报错，不重试。
- 失败提示写到远端 URL 与两侧 sha，便于人工判断。
- 用本地 bare 仓夹具覆盖"远端领先 → 拒绝"与"远端一致 → 成功回读"两例。

**不做什么**

- 不合并 `refresh-index.sh --push` 与 `package.sh` 两个入口。
- 不改 `refresh-index.sh --push` 的既有行为。
- 不引入远端锁、租约或 CI 以外的并发协调。

## 依赖

- 无外部依赖；夹具只用 `file://` 本地 bare 仓，不联网。

## 已知风险

- 回读与推送之间仍有并发窗口；触发信号：回读不一致。处置：报错并人工重跑，不自动
  重试、不 force。
- 夹具若误用真实远端会污染仓库；约束：仅本地 bare 仓。
