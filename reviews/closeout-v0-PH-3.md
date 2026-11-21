# 收口对照 — v0-PH-3

| 项 | 值 |
| --- | --- |
| phase | `v0-PH-3` |
| 追溯 | `IDX-6` / `AN-IDX-6` |
| 授权 | `docs/decisions/D-4.md` |
| 收口版本 | `v0.3.0` |
| 收口日期 | 2026-11-21 |
| 结论 | 通过 |

## 1. 交付物 × 任务

| 任务 | 交付物 | 验收命令 | 原始输出 | 提交 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | 判定根改为 `<pkg>/<ns-root>`，子树外计 `skipped` | `CT_PKG_ROOT=/Users/samxx/trae-ws bash tools/check-layout.sh` | rc=0；0 FAIL；`ok: 68 namespaced units`；`skipped 33 units outside ns-root` | `b39970a` | 通过 |
| T2 | `ns-root` 不存在即失败；路径规范化 | 夹具 `ns-root = missing`；`src/`、`./src` | rc=1 + `ns-root 'missing' is not a directory`；规范化均 rc=0 | `e89759a` | 通过 |
| T3 | 自测新增四条 | `bash tools/gate-selftest.sh` | `summary: 12 passed, 0 failed` | `57d8f8f` | 通过 |
| T4 | 文档写明判定口径与 `skipped` 语义 | `grep -c 'ns-root' README.md`；`grep -c 'skipped' README.md` | `12`；`5` | `eed5c1b` | 通过 |

红证提交 `57d8f8f` 的 baseline 为 `255b2af`，只含夹具；实现提交
`b39970a` / `e89759a` 紧随其后。T1 后夹具 11 passed / 1 failed，T2 后
12 passed / 0 failed。

## 2. 退出判据

### 2.1 完整工作区：FAIL 0，68 + 33

```text
$ CT_PKG_ROOT=/Users/samxx/trae-ws bash tools/check-layout.sh
ok: 68 namespaced units match their directory
skipped 33 units outside ns-root
rc=0
```

`68 + 33 = 101`，等于改动前基线的带 namespace 单元数。

### 2.2 FAIL 行由 47 降为 0

```text
baseline（1286f05^）: 47 of 101 namespaced units do not match their directory
current               : 0 FAIL；68 checked；33 skipped
```

未新增其它包；`skipped` 的 33 个全部落在 `nexcore/experiments/**`（32）与
`ct-fsguard/test/**`（1），即 `ns-root` 之外的测试/实验夹具。

### 2.3 `ns-root = src` 且目录匹配

```text
$ CT_PKG_ROOT=ws-src-ok bash tools/check-layout.sh
ok: 1 namespaced units match their directory
rc=0
```

### 2.4 `ns-root = src` 且目录不匹配

```text
$ CT_PKG_ROOT=ws-src-bad bash tools/check-layout.sh
FAIL  hello/src/a/c/x.ct: namespace a::b expects directory a/b

1 of 1 namespaced units do not match their directory
rc=1
```

### 2.5 `ns-root` 之外的单元跳过

```text
$ CT_PKG_ROOT=ws-src-outside bash tools/check-layout.sh
ok: 0 namespaced units match their directory
skipped 1 units outside ns-root
rc=0
```

### 2.6 `ns-root = missing`

```text
$ CT_PKG_ROOT=ws-missing bash tools/check-layout.sh
FAIL  hello: ns-root 'missing' is not a directory

1 package(s) have an invalid ns-root
rc=1
```

### 2.7 自测

```text
$ bash tools/gate-selftest.sh
...
summary: 12 passed, 0 failed
rc=0
```

### 2.8 任务清单可独立验收

任务清单见 `docs/phases/v0-PH-3/card.md`；四项均有独立命令与提交，本节 §1 逐项
贴了原始输出。

## 3. Issue 去向

| 条目 | 去向 | 证据 |
| --- | --- | --- |
| `IDX-6` | `done` | 本 phase 八条退出判据；全工作区 0 FAIL / 68 / 33 |

## 4. 回顾

| 教训 | 落点 |
| --- | --- |
| 判定目录必须读清单里的 `ns-root`，不能假设包根就是单元根 | `gate:tools/check-layout.sh` |
| `ns-root` 之外的命名空间夹具要显式计 `skipped`，不能静默丢弃 | `spec:docs/decisions/D-4.md` |
| 绝对计数会随包内容移动；判据应以 FAIL 0 且 checked + skipped 不减少为准 | `spec:docs/phases/v0-PH-3/card.md 退出判据 1` |
| 夹具必须创建空的 `ns-root` 目录，否则“缺失 ns-root”分支会掩盖“子树外跳过”用例 | `gate:tools/gate-selftest.sh` |

## 5. Battle / 决策

本轮未新增 battle：D-4 已裁定“只判定 `<pkg>/<ns-root>/` 子树、子树外计
`skipped`、缺失 `ns-root` 报错”，其余为实现层选择；四条夹具把该裁定固化为
可执行判据。

## 6. 遗留

- `skipped` 的 33 个单元仍是测试/实验夹具；若未来其中出现真实发布单元，应移到
  `ns-root` 内，不能靠 `skipped` 长期豁免。
- char-host 的 7 组重名不在本 phase 范围，仍待独立条目。
