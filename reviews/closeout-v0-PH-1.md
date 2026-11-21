# 收口对照 — v0-PH-1

| 项 | 值 |
| --- | --- |
| phase | `v0-PH-1` |
| 追溯 | `IDX-3` / `AN-IDX-3` |
| 授权 | `docs/decisions/D-2.md` |
| 收口版本 | `v0.1.0` |
| 收口日期 | 2026-11-21 |
| 结论 | 通过 |

## 1. 交付物 × 任务

| 任务 | 交付物 | 验收命令 | 原始输出 | 提交 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | layout 零输入断言 + 显式参数校验 | `CT_PKG_ROOT=$(mktemp -d) bash tools/check-layout.sh` | rc=1，stderr 含 `check-layout: no packages found` | `1286f05` | 通过 |
| T2 | char-host 零包断言 | `CT_PKG_ROOT=$(mktemp -d) bash tools/check-char-host.sh` | rc=1，stderr 含 `check-char-host: no packages found` | `41ea365` | 通过 |
| T3 | 自测夹具 + CI 步骤 | `bash tools/gate-selftest.sh` | `summary: 8 passed, 0 failed` | `9580405` | 通过 |
| T4 | 文档写明默认根与零输入行为 | `grep -c 'no packages found' AGENTS.md`；`grep -c 'no packages found' README.md`；规范同步 | `1`；`2`；`ok` | `ae2fe05` + `39ad043` | 通过 |

## 2. 退出判据

### 2.1 空根：两个脚本均 rc=1

```text
$ CT_PKG_ROOT=$(mktemp -d) bash tools/check-layout.sh
check-layout: no packages found under /var/folders/.../tmp.XXXX (expected .../*/ct.pkg)
check-layout: set CT_PKG_ROOT to the workspace root that holds the package checkouts
rc=1

$ CT_PKG_ROOT=$(mktemp -d) bash tools/check-char-host.sh
check-char-host: no packages found under /var/folders/.../tmp.XXXX (expected .../*/ct.pkg)
check-char-host: set CT_PKG_ROOT to the workspace root that holds the package checkouts
rc=1
```

### 2.2 未设置/为空时按默认根解析

在临时工作区 `<tmp>/ws/index/tools` 放脚本、`<tmp>/ws/pkg/ct.pkg` 放一个正常包：

```text
$ env -u CT_PKG_ROOT bash tools/check-layout.sh
ok: 1 namespaced units match their directory
rc=0

$ env -u CT_PKG_ROOT bash tools/check-char-host.sh
ok: 0 methods on 0 hosts, no duplicates
rc=0

$ CT_PKG_ROOT= bash tools/check-layout.sh
ok: 1 namespaced units match their directory
rc=0
```

### 2.3 完整工作区输出与改动前逐字一致

以 `1286f05^` 的 `check-layout.sh` / `check-char-host.sh` 为基线，均在
`CT_PKG_ROOT=/Users/samxx/trae-ws` 下运行：

```text
layout baseline: 47 FAIL；47 of 101 namespaced units do not match their directory
layout current : 47 FAIL；47 of 101 namespaced units do not match their directory
diff baseline/current: empty

char-host baseline: 7 FAIL；746 methods on 56 hosts; failures listed above
char-host current : 7 FAIL；746 methods on 56 hosts; failures listed above
diff baseline/current: empty
```

### 2.4 自测

```text
$ bash tools/gate-selftest.sh
...
summary: 8 passed, 0 failed
rc=0
```

### 2.5 语法

```text
$ for f in tools/check-layout.sh tools/check-char-host.sh tools/gate-selftest.sh tools/package.sh; do bash -n "$f" || exit 1; done
rc=0
```

### 2.6 任务清单可独立验收

任务清单见 `docs/phases/v0-PH-1/card.md`；四项均有独立命令与提交，本节 §1 逐项
贴了原始输出。

## 3. Issue 去向

| 条目 | 去向 | 证据 |
| --- | --- | --- |
| `IDX-3` | `done` | 本 phase 六条退出判据；`gate-selftest.sh` 8/0 |

## 4. 回顾

| 教训 | 落点 |
| --- | --- |
| 门禁的“零输入”必须与“默认根”分开判定，否则把变量缺省误判成错误 | `spec:AGENTS.md 0.1 门禁入口` |
| 文档判据要写实际诊断字符串，不能只写“必须红” | `gate:docs/phases/v0-PH-1/card.md T4` |
| 完整工作区仍有无关的红（layout 47、char-host 7 组重名），不能用它们的红绿判断本 phase | `spec:docs/planning/analysis/AN-IDX-3.md 风险` |

## 5. 遗留

- 完整工作区的 layout 47 条 FAIL 由 `v0-PH-3` 处理；char-host 的 7 组重名不在
  本 phase 范围，仍待独立条目。
- `v0-PH-1` 的实现提交在分工裁定前由规划会话完成；按 `deviation:
  split-planning-and-implementation`，本轮由执笔人复核并留痕，独立 VERIFY
  会话尚未建立。
