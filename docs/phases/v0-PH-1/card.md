---
phase-id: v0-PH-1
version-minor: 1
spec-version: 1.17.0
---

# v0-PH-1 — 门禁零输入不得静默通过

> 正式 phase。追溯 `IDX-3`（分析 `docs/planning/analysis/AN-IDX-3.md`）；
> 授权 `docs/decisions/D-2.md`；草案来源 `draft-gate-zero-input`。
> 用户要求：在 v1 发布前完成。

## 目标

`check-layout.sh` 与 `check-char-host.sh` 在解析后的工作区根下找不到任何包时
报错退出；`CT_PKG_ROOT` 未设置或为空仍按默认工作区根解析，不视为错误。

## 范围

**做什么**

- 两个脚本在 `$repo` 下找不到任何 `*/ct.pkg` 时 `exit 1`，stderr 打印解析后的根、
  找到的包数量与修复提示；
- 保留并写明默认根语义：`CT_PKG_ROOT` 未设置或为空 → `tools/../..`；
- 显式传参但目录没有 `ct.pkg` 时失败（当前是 `skip` 后继续）；
- 新增 `tools/gate-selftest.sh`：空根、缺 `ct.pkg`、namespace 不一致、重复方法、
  `const` 宿主、正常包六类夹具；
- `gates.yml` 增加 selftest 步骤，防止回归。

**不做什么**

- 不改 namespace 一致性、宿主方法名唯一性的判定逻辑；
- 不改 `CT_PKG_ROOT` 指向有效工作区时的扫描范围与结果；
- 不引入第三方依赖，不改门禁的退出码 0/1 约定。

## 交付物

| # | 路径 |
| --- | --- |
| T1 | `tools/check-layout.sh` |
| T2 | `tools/check-char-host.sh` |
| T3 | `tools/gate-selftest.sh`、`.github/workflows/gates.yml` |
| T4 | `README.md`、`AGENTS.md` |

## 任务清单

| # | 交付物 | 验收命令 | 提交 | 可单独回滚 |
| --- | --- | --- | --- | --- |
| T1 | layout 零输入断言 + 显式参数校验 | `CT_PKG_ROOT=$(mktemp -d) bash tools/check-layout.sh` → rc=1，stderr 含 `no packages found` | `fix(gates): fail check-layout on an empty workspace` | 是 |
| T2 | char-host 零包断言 | 同目录跑 `check-char-host.sh` → rc=1，stderr 含 `no packages found` | `fix(gates): fail check-char-host when no package is found` | 是 |
| T3 | 自测夹具 + CI 步骤 | `bash tools/gate-selftest.sh` → `summary: 8 passed, 0 failed` | `test(gates): add a gate selftest and run it in CI` | 是 |
| T4 | 文档写明默认根与零输入行为 | `grep -c 'CT_PKG_ROOT' README.md` ≥ 1；`grep -c 'no packages found' AGENTS.md` ≥ 1 | `docs(gates): document the default workspace root` | 是 |

## 退出判据

1. 空根：`CT_PKG_ROOT=$(mktemp -d)` 下两个脚本均 rc=1，stderr 含 `no packages found`
   与解析后的根路径；
2. `CT_PKG_ROOT` 未设置或为空时，脚本按 `tools/../..` 解析（用 `bash -x` 或报错
   信息中的根路径可核对），不因变量缺省而失败；
3. 完整工作区（`CT_PKG_ROOT` 指向含包仓的目录）下，两个脚本的输出与改动前逐字
   一致（同一根下 `FAIL` 行数、`mismatched/checked` 计数、方法/宿主计数相同），
   不因本次改动新增或减少任何判定；
4. `bash tools/gate-selftest.sh` 输出 `summary: … 0 failed`；
5. `bash -n` 对四个脚本均通过；
6. 任务清单每项可独立验收（6.6 T-6）。

## 依赖

- 无外部依赖；`v0-PH-0` 的 `packages.txt` 收窄不改变本 phase 的判定逻辑。

## 已知风险

| 风险 | 触发信号 |
| --- | --- |
| CI 克隆失败从“静默绿”变成红，被误读为门禁损坏 | `gates` 工作流报 `no packages found`；报错同时打印根与包数，可直接区分克隆失败 |
| 本地在非工作区目录运行门禁现在会红 | 单独 clone 本仓直接跑脚本 → rc=1；按提示设置 `CT_PKG_ROOT` |
| 显式传参失败影响既有调用方 | 现有 `package.sh` 只传真实包目录；若有脚本传空目录，会立即暴露 |
| char-host 在“有包但无 `.m.ct`”时被误判为空 | 判据改为“包数量为 0 才失败”，无映射方法的包集合仍 rc=0 |

## 规范版本

开卡时生成块头 `version=1.17.0`（`spec-version` 字段同上）。

## version-minor

`1`，收口版本 `v0.1.0`（PN-2：`MINOR == n`）。
