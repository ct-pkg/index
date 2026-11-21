---
phase-id: v0-PH-0
version-minor: 0
spec-version: 1.17.0
---

# v0-PH-0 — 解除 nightly 索引刷新的阻塞

> 正式 phase。追溯 `IDX-1`（分析 `docs/planning/analysis/AN-IDX-1.md`）；
> 授权 `docs/decisions/D-1.md`；草案来源 `draft-index-refresh-unblock`。

## 目标

让 nightly `refresh-index.sh --all-tags` 重新退出 0，且 `index` 只保留生成器能够
复现的六字段行。

## 范围

**做什么**

- `packages.txt` 只保留 tagged `ct.pkg` 带 `publisher` / `ns-root` 的仓库；
- 全量重建 `index`：移除 5 列旧行，回填可生成的历史版本；
- 删除 `tools/sync-repos-tags.sh` 的五列兼容分支；
- README 与 `AGENTS.md` 同步新口径（未注册仓库、冻结语义、临时纪律）。

**不做什么**

- 不改 `refresh-index.sh` 的 fail-closed 语义；
- 不改 `ct` 仓，不为旧 tag 补键（tag 不可变）；
- 不处理 I10 回放硬错（属 `draft-index-push-parity` / AN-IDX-4）；
- 不引入发布门槛、零输入门禁、README 自动化（各自草案）。

## 交付物

| # | 路径 |
| --- | --- |
| T1 | `packages.txt` |
| T2 | `index` |
| T3 | `tools/sync-repos-tags.sh`、`tools/repos.txt` |
| T4 | `README.md`、`AGENTS.md` |

## 任务清单

| # | 交付物 | 验收命令 | 提交 | 可单独回滚 |
| --- | --- | --- | --- | --- |
| T1 | `packages.txt` 由 20 行收窄为 10 行 | `grep -vc '^#\|^$' packages.txt` → `10` | `3f0e1bb` | 是；回滚后 nightly 恢复中止 |
| T2 | `index` 重建为 26 行六字段 | `wc -l < index` → `26`；`awk 'NF != 6' index` 无输出 | `3c636d5` | 是；回滚后旧 10 行回到索引 |
| T3 | 五列兼容分支删除，manifest 跟随索引 | `grep -c 'n >= 5' tools/sync-repos-tags.sh` → `0`；`bash tools/sync-repos-tags.sh --check` → rc=0 | `0cdb132` | 是 |
| T4 | README / AGENTS 与新口径一致 | `grep -ci 'five-field' README.md` → `0`；`grep -c '20 个仓' AGENTS.md` → `0` | `0cdb132` | 是 |

## 退出判据

1. `sh tools/refresh-index.sh --all-tags --dry-run` 输出
   `summary: 0 changed, 0 added, 0 removed, 26 unchanged`；
2. `awk 'NF != 6' index` 无输出；
3. `bash tools/sync-repos-tags.sh --check` 退出 0；
4. `grep -c 'n >= 5' tools/sync-repos-tags.sh` 输出 `0`；
5. GitHub Actions 的 `index` 工作流一次运行 `conclusion=success`（定时或手动
   dispatch 均可），作为 nightly 恢复的可核对锚点；
6. 任务清单每项可独立验收（6.6 T-6）。

## 依赖

- 用户 2026-11-20 的方案 A 裁定（立即移出旧仓）；
- `docs/decisions/D-1.md` 的定稿授权。

## 已知风险

| 风险 | 触发信号 |
| --- | --- |
| 旧仓从索引消失后，已依赖它们的消费者解析失败 | `ct get hal@0.1.0` 报 not found；旧仓重新发版并加回 `packages.txt` 后应恢复 |
| 历史版本回填把未验证的行写入索引 | `bash tools/verify-index.sh --name <pkg>` 出现 mismatch |
| nightly 被其他仓的新问题再次阻断 | `index` 工作流再次出现 `failure` |
| 消费者仍按五列思维解析 `index` | 外部工具报字段缺失；本仓已无五列行可对照 |

## 规范版本

开卡时生成块头 `version=1.17.0`（`spec-version` 字段同上）。

## version-minor

`0`，收口版本 `v0.0.0`（PN-2：`MINOR == n`）。
