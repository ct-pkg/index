# AN-IDX-3：门禁在零输入时静默通过

追溯：`IDX-3` ｜ 分析日期：2026-11-18 ｜ 主张：REQ

## 1. 问题陈述

`tools/check-layout.sh` 与 `tools/check-char-host.sh` 默认向上两级找包（可用
`CT_PKG_ROOT` 覆盖）。找不到任何 `ct.pkg` 时，两者都进入"零个单元"分支：

- `check-layout.sh`：`checked=0`、`mismatched=0` → 打印
  `ok: 0 namespaced units match their directory` → `exit 0`
- `check-char-host.sh`：`total=0`、`hosts=0` → 打印
  `ok: 0 methods on 0 hosts, no duplicates` → `exit 0`

这不是"报错不够友好"，而是**假绿**：单独 clone 本仓运行、CI 里克隆步骤静默失败、
`CT_PKG_ROOT` 拼错，都会得到成功退出码。门禁的价值完全依赖"输入非空"，而这一点
目前没有任何断言。

## 2. 范围

**做什么**

- 两个脚本在扫描集合为空时退出 1，并在 stderr 说明原因与期望：
  例如 `未找到任何包：<root> 下没有 */ct.pkg；请在完整工作区运行或设置 CT_PKG_ROOT`。
- 显式传参但参数目录不含 `ct.pkg` 时，同样视为失败（现在是 `skip` 后继续）。
- 补两条负例进 `tools/` 自测（空目录 → 退出 1 且 stderr 有提示）。

**不做什么**

- 不改门禁的判定逻辑（目录/命名空间一致性、宿主方法名唯一性）。
- 不改 `CT_PKG_ROOT` 的语义与 CI 的克隆布局。

## 3. 验收判据

| # | 命令 | 阈值 |
| --- | --- | --- |
| 1 | `CT_PKG_ROOT=$(mktemp -d) bash tools/check-layout.sh` | 退出码 1；stderr 含 `未找到任何包` |
| 2 | `CT_PKG_ROOT=$(mktemp -d) bash tools/check-char-host.sh` | 退出码 1；stderr 含 `未找到任何包` |
| 3 | 在完整工作区运行两条命令 | 退出码 0，且输出中的单元数 > 0 |
| 4 | 新自测脚本 | 退出码 0，覆盖上述两条负例 |

## 4. 依赖与风险

**依赖**：无；不依赖 IDX-1 的裁定，也不依赖 `ct` 二进制。

**风险**

- 若某仓的 `ct.pkg` 全部被删/改名，门禁从"静默绿"变成"红"，会被误读为门禁坏了；
  触发信号是 CI 在克隆成功后仍报"未找到任何包"。缓解：报错里打印扫描根与已找到的
  包数量。
- `gates.yml` 里克隆列表来自 `packages.txt`；若 IDX-1 选 B（拆清单），CI 的克隆源
  也要跟着改，否则会出现零输入红。这一联动必须在 IDX-1 定稿时一并确认。
