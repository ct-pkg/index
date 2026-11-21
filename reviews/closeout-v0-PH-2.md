# 收口对照 — v0-PH-2

| 项 | 值 |
| --- | --- |
| phase | `v0-PH-2` |
| 追溯 | `IDX-4` / `AN-IDX-4` |
| 授权 | `docs/decisions/D-3.md` |
| 收口版本 | `v0.2.0` |
| 收口日期 | 2026-11-21 |
| 结论 | 通过 |

## 1. 交付物 × 任务

| 任务 | 交付物 | 验收命令 | 原始输出 | 提交 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | `publish_index` 快进断言 + 推送后回读 | `grep -c 'merge-base --is-ancestor' tools/package.sh`；夹具 `publish_index: remote ahead` | `1`；rc≠0、远端 tip 不变 | `955062e` | 通过 |
| T2 | `sync_manifest` 套用同一保护 | 同上两条判据对 `repos.txt` 推送成立 | `1`；rc≠0、远端 tip 不变 | `a56cb7a` | 通过 |
| T3 | 本地 bare 仓自测 | `bash tools/push-parity-selftest.sh` | `summary: 4 passed, 0 failed` | `949dfde` | 通过 |
| T4 | README 写明推送保护 | `grep -c 'fast-forward' README.md`；`grep -c -- '--force' tools/package.sh` | `1`；`0` | `a66b81e` | 通过 |

红证提交 `949dfde` 的 baseline 为 `352735a`，只含夹具；实现提交
`955062e` / `a56cb7a` 紧随其后。T1 后夹具 3 passed / 1 failed，T2 后
4 passed / 0 failed。

## 2. 退出判据

### 2.1 推送前读取远端 tip、推送后回读

```text
$ grep -c 'ls-remote' tools/package.sh
5
```

### 2.2 快进断言

```text
$ grep -c 'merge-base --is-ancestor' tools/package.sh
1
```

### 2.3 不使用 force

```text
$ grep -c -- '--force' tools/package.sh
0
```

### 2.4 远端领先：拒绝且远端 tip 不变

```text
== publish_index: remote ahead ==
  rc=1
  | ERROR: remote main (b19aed8...) at .../publish-ahead/remote.git is not an ancestor of HEAD (f34a298...); refusing a non-fast-forward index push
  -> PASS  remote-ahead push is refused and the remote tip is unchanged

== sync_manifest: remote ahead ==
  rc=1
  | ERROR: remote main (03396db...) at .../sync-ahead/remote.git is not an ancestor of HEAD (eaef4b8...); refusing a non-fast-forward tools/repos.txt push
  -> PASS  remote-ahead manifest push is refused and the remote tip is unchanged
```

### 2.5 远端一致：推送成功且回读等于本地 HEAD

```text
== publish_index: remote consistent ==
  rc=0
  |   ok    index committed and pushed
  -> PASS  consistent push succeeds and the remote tip equals local HEAD

== sync_manifest: remote consistent ==
  rc=0
  |   ok    tools/repos.txt: std -> v0.2.0
  -> PASS  consistent manifest push succeeds and the remote tip equals local HEAD
```

### 2.6 自测汇总

```text
$ bash tools/push-parity-selftest.sh
...
summary: 4 passed, 0 failed
rc=0
```

### 2.7 任务清单可独立验收

任务清单见 `docs/phases/v0-PH-2/card.md`；四项均有独立命令与提交，本节 §1 逐项
贴了原始输出。

## 3. Issue 去向

| 条目 | 去向 | 证据 |
| --- | --- | --- |
| `IDX-4` | `done` | 本 phase 七条退出判据；push-parity 4/0 |

## 4. 回顾

| 教训 | 落点 |
| --- | --- |
| 索引有两条推送路径，保护必须共享同一个 helper，不能各写一份 | `gate:tools/push-parity-selftest.sh` |
| 远端领先的诊断必须同时给 URL 与两侧 sha，否则仍停在 git 层 | `spec:README.md Package lifecycle` |
| 回读失败不自动重试、不 force，保留本地提交由人处理 | `spec:docs/decisions/D-3.md` |

## 5. Battle / 决策

本轮未新增 battle：D-3 已对“失败是否重试 / 是否 force”作出裁定（不重试、
不 force），其余为实现层选择；夹具把该裁定固化为可执行判据。

## 6. 遗留

- 回读与推送之间仍有并发窗口；按 D-3 报错并人工重跑，不引入远端锁。
