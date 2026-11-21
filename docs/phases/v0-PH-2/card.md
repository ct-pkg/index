---
phase-id: v0-PH-2
version-minor: 2
spec-version: 1.17.0
---

# v0-PH-2 — 索引推送补齐同级保护

> 正式 phase。追溯 `IDX-4`（分析 `docs/planning/analysis/AN-IDX-4.md`）；
> 授权 `docs/decisions/D-3.md`；草案来源 `draft-index-push-parity`。
> 实现由执笔人（DEV）承担；规划会话只维护卡面与判据（`AGENTS.md` 0.3）。

## 目标

`tools/package.sh` 推送 `index` 与 `tools/repos.txt` 时，具备与
`refresh-index.sh --push` 相同的保护：推送前拒绝非快进、永不 `--force`、推送后
回读远端 tip。

## 范围

**做什么**

- `publish_index` 推送前：fetch 远端 `main`，断言远端 tip 是本地 `HEAD` 的祖先；
  远端领先即失败，提示远端 URL 与两侧 sha。
- `publish_index` 推送后：`git ls-remote` 回读远端 `main`，与本地 `HEAD` 比对；
  不一致即失败。
- `sync_manifest` 的提交推送套用同一组保护。
- 失败一律中止并保留本地提交，不自动重试、不 force。
- 新增本地 bare 仓夹具：远端领先 → 拒绝且远端 tip 不变；远端一致 → 成功回读。

**不做什么**

- 不合并 `refresh-index.sh --push` 与 `package.sh` 两个入口。
- 不改 `refresh-index.sh --push` 的既有行为。
- 不引入远端锁、租约或 CI 以外的并发协调。
- 不改 `verify_row` 的回放语义（I10 已在 `7a0c7cd` 单独修复）。
- 不改推送内容与索引行格式。

## 交付物

| # | 路径 |
| --- | --- |
| T1 | `tools/package.sh`（`publish_index`） |
| T2 | `tools/package.sh`（`sync_manifest`） |
| T3 | `tools/push-parity-selftest.sh` |
| T4 | `README.md`（Package lifecycle 一节） |

## 任务清单

| # | 交付物 | 验收命令 | 提交 | 可单独回滚 |
| --- | --- | --- | --- | --- |
| T1 | `publish_index` 快进断言 + 推送后回读 | `grep -c 'merge-base --is-ancestor' tools/package.sh` ≥ 1；夹具“远端领先”用例 rc≠0 且远端 tip 不变 | `fix(pkg): verify the index push is fast-forward and read it back` | 是 |
| T2 | `sync_manifest` 套用同一保护 | 同上两条判据对 `repos.txt` 推送成立；夹具覆盖两处调用 | `fix(pkg): guard the repos.txt push the same way` | 是 |
| T3 | 本地 bare 仓自测（两例） | `bash tools/push-parity-selftest.sh` → `summary: … 0 failed`；脚本只使用 `file://` 本地仓 | `test(pkg): add a push-parity selftest with local bare remotes` | 是 |
| T4 | README 写明推送保护 | `grep -c 'fast-forward' README.md` ≥ 1；`grep -c -- '--force' tools/package.sh` = 0 | `docs(pkg): document the index push guards` | 是 |

## 退出判据

1. `grep -c 'ls-remote' tools/package.sh` ≥ 2（含推送后回读）；
2. `grep -c 'merge-base --is-ancestor' tools/package.sh` ≥ 1；
3. `grep -c -- '--force' tools/package.sh` = 0；
4. 夹具“远端 `main` 领先”：推送步骤退出码非 0，远端 tip 不变；
5. 夹具“远端一致”：推送步骤退出码 0，回读 tip 等于本地 `HEAD`；
6. `bash tools/push-parity-selftest.sh` 输出 `summary: … 0 failed`；
7. 任务清单每项可独立验收（6.6 T-6）。

## 依赖

- 无外部依赖；夹具只用 `file://` 本地 bare 仓，不联网、不需要 token。
- 与 `v0-PH-0` / `v0-PH-1` 无依赖，可并行。

## 已知风险

| 风险 | 触发信号 |
| --- | --- |
| 回读与推送之间仍有并发窗口 | 回读不一致；按 D-3 报错并人工重跑，不自动重试 |
| 夹具误用真实远端污染仓库 | 自测出现 `github.com`；约束为只允许 `file://` bare 仓 |
| 快进断言阻断了合法的首次推送 | 远端 `main` 不存在；断言需把“远端无 ref”视为可推送 |
| 失败中止后留下本地未推提交 | `git status` 显示本地领先；提示中给出重跑命令，不自动 reset |

## 规范版本

开卡时生成块头 `version=1.17.0`（`spec-version` 字段同上）。

## version-minor

`2`，收口版本 `v0.2.0`（PN-2：`MINOR == n`）。
