---
phase-id: draft-gate-zero-input
status: draft
---

# 草案：门禁零输入不得静默通过

> 未定稿。不占正式编号、不排期、不派工、不开工（主规范 6.7.1 PN-12 / PN-14）。
> 追溯：`IDX-3`（分析：`docs/planning/analysis/AN-IDX-3.md`）

## 目标

`check-layout.sh` 与 `check-char-host.sh` 在扫描集合为空时报错退出，而不是打印
`ok: 0 …` 并 `exit 0`。

## 范围

**做什么**

- 两个脚本在零包/零单元时 `exit 1`，stderr 打印扫描根、已找到的包数量与修复提示
  （完整工作区或 `CT_PKG_ROOT`）。
- 显式传参但参数目录没有 `ct.pkg` 时同样失败（当前是 `skip` 后继续）。
- 在 `tools/` 自测中补两条负例（空目录 → 退出 1 且 stderr 命中提示语）。

**不做什么**

- 不改目录/命名空间一致性、宿主方法名唯一性的判定逻辑。
- 不改 `CT_PKG_ROOT` 语义与 CI 的克隆布局。

## 依赖

- 无外部依赖，可立即开工。
- 与 `draft-index-refresh-unblock` 的联动：若那里选 B，`gates.yml` 的克隆源会变，
  本 phase 的负例需覆盖"克隆源为空"的情形。

## 已知风险

- 从静默绿变红后，若 CI 克隆步骤失败会被读成"门禁坏了"；触发信号：克隆成功仍报
  "未找到任何包"。缓解：报错里同时打印扫描根与包数量。
