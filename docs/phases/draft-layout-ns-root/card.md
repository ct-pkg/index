---
phase-id: draft-layout-ns-root
status: draft
---

# 草案：`check-layout.sh` 按 `ns-root` 解析命名空间目录

> 未定稿。不占正式编号、不排期、不派工、不开工（主规范 6.7.1 PN-12 / PN-14）。
> 追溯：`IDX-6`（分析：`docs/planning/analysis/AN-IDX-6.md`）

## 目标

`check-layout.sh` 按 `<pkg>/<ns-root>/<namespace path>` 判定命名空间目录，使
`ns-root = src` 的包不再产生误报；真实匹配错误仍然失败。

## 范围

**做什么**

- 读取每个包 `ct.pkg` 的 `ns-root`（缺省或为空按 `.`），只对 `<pkg>/<ns-root>/`
  子树内的 `.ct` 套用目录判定。
- `ns-root` 指向不存在的目录时单独报错，不静默回退为 `.`。
- FAIL 行改用相对 `ns-root` 的路径，保留现有输出格式与计数口径。
- `tools/gate-selftest.sh` 增加四条夹具：匹配、目录错、子树外跳过、`ns-root`
  不存在。

**不做什么**

- 不改 `check-char-host.sh`、`gen-index.sh` 与摘要算法。
- 不移动或修改任何包内的 `experiments/`、`test/` 夹具。
- 不改编译器侧 `ct build --ns-root` 的语义。
- 不改零输入行为（已由门禁零输入修复收敛）。

## 依赖

- 无外部依赖。
- 与门禁零输入修复（`IDX-3`）共享 `check-layout.sh` 与 `gate-selftest.sh`，须在其
  改动之上实现；该修复目前待 VERIFY 复核，本草案开工前应确认其已收口，避免同文件
  冲突。

## 已知风险

- 判定范围收缩到 `ns-root` 子树后，放在子树外的真实源码不再受门禁覆盖；触发信号是
  这类包的 `ct build --ns-root` 报目录不匹配。
- 旧仓缺 `ns-root` 时按 `.` 兜底，判定与现在一致；触发信号是这些包 FAIL 数变化。
- `ns-root` 带尾斜杠或 `./` 前缀时路径拼接出错；触发信号是新夹具在规范化前失败。
- 与 `IDX-3` 的修复同文件并发修改导致冲突；触发信号是 rebase 冲突或自测用例丢失。
