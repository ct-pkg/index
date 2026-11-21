---
phase-id: v0-PH-3
version-minor: 3
spec-version: 1.17.0
---

# v0-PH-3 — `check-layout.sh` 按 `ns-root` 判定命名空间目录

> 正式 phase。追溯 `IDX-6`（分析 `docs/planning/analysis/AN-IDX-6.md`）；
> 授权 `docs/decisions/D-4.md`；草案来源 `draft-layout-ns-root`。
> 实现由执笔人（DEV）承担；规划会话只维护卡面与判据（`AGENTS.md` 0.3）。

## 目标

`check-layout.sh` 按 `<pkg>/<ns-root>/<namespace path>` 判定命名空间目录，消除
`ns-root = src` 包的 47 条误报，同时不放过真实的目录不匹配。

## 范围

**做什么**

- 读取每个包 `ct.pkg` 的 `ns-root`；缺省或为空按 `.`。
- 只对 `<pkg>/<ns-root>/` 子树内的 `.ct` 套用「目录 == namespace 路径」判定；
  子树外带 `namespace` 的单元计入 `skipped` 并单独报告。
- `ns-root` 指向不存在的目录时 rc=1，提示 `ns-root '<值>' is not a directory`。
- 规范化 `ns-root` 的尾斜杠与 `./` 前缀后再拼接。
- `tools/gate-selftest.sh` 增加四条夹具：匹配、目录错、子树外跳过、`ns-root` 不存在。

**不做什么**

- 不改 `check-char-host.sh`、`gen-index.sh` 与摘要算法。
- 不移动、修改任何包内的 `experiments/`、`test/` 夹具。
- 不改编译器侧 `ct build --ns-root` 的语义。
- 不改零输入行为（已由 `IDX-3` 的修复收敛）。

## 交付物

| # | 路径 |
| --- | --- |
| T1 | `tools/check-layout.sh`（判定根 + `skipped` 计数） |
| T2 | `tools/check-layout.sh`（`ns-root` 不存在与规范化） |
| T3 | `tools/gate-selftest.sh`（四条新夹具） |
| T4 | `README.md`、`AGENTS.md`（判定口径说明） |

## 任务清单

| # | 交付物 | 验收命令 | 提交 | 可单独回滚 |
| --- | --- | --- | --- | --- |
| T1 | 判定根改为 `<pkg>/<ns-root>`，子树外计 `skipped` | `CT_PKG_ROOT=/Users/samxx/trae-ws bash tools/check-layout.sh` → FAIL 0；`ok: 68 namespaced units` 且 `skipped 33` | `fix(gates): judge layout against ns-root` | 是 |
| T2 | `ns-root` 不存在即失败；路径规范化 | 夹具 `ns-root = missing` → rc=1 且提示 `is not a directory`；`ns-root = src/` 行为与 `src` 相同 | `fix(gates): reject a missing ns-root and normalise it` | 是 |
| T3 | 自测新增四条 | `bash tools/gate-selftest.sh` → `summary: 12 passed, 0 failed` | `test(gates): cover ns-root in the layout selftest` | 是 |
| T4 | 文档写明判定口径与 `skipped` 语义 | `grep -c 'ns-root' README.md` ≥ 2；`grep -c 'skipped' README.md` ≥ 1 | `docs(gates): document the ns-root layout rule` | 是 |

## 退出判据

1. `CT_PKG_ROOT=/Users/samxx/trae-ws bash tools/check-layout.sh` FAIL 行 0，输出
   `ok: 68 namespaced units` 与 `skipped 33 units outside ns-root`；两数之和等于
   改动前的 101（数字随包内容移动时以 FAIL 0 且 checked+skipped 不减少为准）；
2. 同一命令的 FAIL 行数由 47 降为 0，且不新增其它包；
3. 夹具 `ns-root = src` + `src/a/b/x.ct`（`namespace a::b;`）→ rc=0；
4. 夹具 `ns-root = src` + `src/a/c/x.ct`（`namespace a::b;`）→ rc=1，提示
   `expects directory a/b`；
5. 夹具 `ns-root = src` + `test/a/x.ct`（`namespace a;`）→ rc=0（子树外不判定）；
6. 夹具 `ns-root = missing` → rc=1，提示 `ns-root 'missing' is not a directory`；
7. `bash tools/gate-selftest.sh` 输出 `summary: 12 passed, 0 failed`；
8. 任务清单每项可独立验收（6.6 T-6）。

## 依赖

- `IDX-3` 的修复（门禁零输入）先收口：两者同改 `check-layout.sh` 与
  `gate-selftest.sh`，并行会产生冲突。
- 无外部依赖；不需要包仓改 `ns-root`，也不需要重新发版。

## 已知风险

| 风险 | 触发信号 |
| --- | --- |
| 子树外的真实源码从此不受门禁覆盖 | 某包把源码放在 `ns-root` 之外且带 `namespace`；`ct build --ns-root` 报目录不匹配 |
| 旧仓缺 `ns-root` 按 `.` 兜底后判定变化 | 这些包的 FAIL 数或 checked 计数与改动前不同 |
| 绝对计数（68 / 33）随包内容移动而失效 | 退出判据 1 已改为以 FAIL 0 与总数不减为准 |
| 与 `IDX-3` 的修复同文件冲突 | rebase 冲突或自测用例丢失 |
| `skipped` 变成隐藏问题的口袋 | `skipped` 增长但无人复核；触发信号是该计数持续上升 |

## 规范版本

开卡时生成块头 `version=1.17.0`（`spec-version` 字段同上）。

## version-minor

`3`，收口版本 `v0.3.0`（PN-2：`MINOR == n`）。
