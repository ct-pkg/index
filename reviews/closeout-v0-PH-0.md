# 收口对照 — v0-PH-0

| 项 | 值 |
| --- | --- |
| phase | `v0-PH-0` |
| 追溯 | `IDX-1` / `AN-IDX-1` |
| 授权 | `docs/decisions/D-1.md` |
| 收口版本 | `v0.0.0` |
| 收口日期 | 2026-11-21 |
| 结论 | 通过 |

## 1. 交付物 × 任务

| 任务 | 交付物 | 验收命令 | 原始输出 | 提交 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | `packages.txt` 收窄为 10 行 | `grep -vc '^#\|^$' packages.txt` | `10` | `3f0e1bb` | 通过 |
| T2 | `index` 重建为 26 行六字段 | `wc -l < index`；`awk 'NF != 6' index` | `26`；无输出 | `3c636d5` | 通过 |
| T3 | 删除五列兼容分支；manifest 跟随索引 | `grep -c 'n >= 5' tools/sync-repos-tags.sh`；`bash tools/sync-repos-tags.sh --check` | `0`；`ok: repos.txt tags match ...` | `0cdb132` | 通过 |
| T4 | README / AGENTS 同步新口径 | `grep -ci 'five-field' README.md`；`grep -c '20 个仓' AGENTS.md` | `0`；`0` | `0cdb132` | 通过 |

## 2. 退出判据

### 2.1 全量 dry-run 无变化

```text
$ sh tools/refresh-index.sh --all-tags --dry-run
fetched  std v0.19.0
fetched  std v0.3.1
fetched  std v0.3.0
fetched  http v0.2.1
fetched  sse v0.13.0
fetched  sse v0.12.0
fetched  sse v0.11.0
fetched  llm-sse v0.1.0
fetched  process v0.1.1
fetched  process v0.1.0
fetched  token v0.1.1
fetched  token v0.1.0
fetched  json v0.6.1
fetched  json v0.6.0
fetched  json v0.5.0
fetched  json v0.4.0
fetched  json v0.3.0
fetched  json v0.2.0
fetched  json v0.1.1
fetched  fsguard v0.5.0
fetched  fsguard v0.4.0
fetched  fsguard v0.1.0
fetched  rill-dsl v0.23.3
fetched  rill-dsl v0.23.2
fetched  rill-dsl v0.23.1
fetched  nexcore v0.14.1
note: older tags skipped (missing shared-store identity or drifted version):
        std v0.18.0: publisher std differs from ct of the newest tag
        std v0.17.0: publisher std differs from ct of the newest tag
        std v0.16.0: publisher std differs from ct of the newest tag
        std v0.15.0: publisher std differs from ct of the newest tag
        std v0.14.0: publisher std differs from ct of the newest tag
        std v0.13.0: publisher std differs from ct of the newest tag
        std v0.12.0: publisher std differs from ct of the newest tag
        std v0.11.0: publisher std differs from ct of the newest tag
        std v0.3.2: publisher std differs from ct of the newest tag
        std v0.2.0: ... is missing 'publisher' (required since ct v0.54)
        std v0.1.0: ... is missing 'publisher' (required since ct v0.54)
        http v0.2.0: ... is missing 'publisher' (required since ct v0.54)
        http v0.1.0: ... is missing 'publisher' (required since ct v0.54)
        rill-dsl v0.23.0: no ct.pkg
        rill-dsl v0.22.0: no ct.pkg
        nexcore v0.14.0: no ct.pkg
        nexcore v0.13.0: no ct.pkg
summary: 0 changed, 0 added, 0 removed, 26 unchanged
index: no changes
[dry-run] would write .../index (26 lines); no files were modified
[dry-run] would not commit (index unchanged)
[dry-run] would not push
rc=0
```

> 为可读性，长临时路径与重复诊断行以 `...` 缩写；`summary:` 与退出码逐字保留。

### 2.2 六字段

```text
$ awk 'NF != 6' index
# no output
```

### 2.3 manifest 与索引一致

```text
$ bash tools/sync-repos-tags.sh --check
ok: repos.txt tags match /Users/samxx/dsh-ws/ct-pkg-index/tools/../index
rc=0
```

### 2.4 五列兼容分支已删除

```text
$ grep -c 'n >= 5' tools/sync-repos-tags.sh
0
```

### 2.5 nightly 恢复的可核对锚点

```text
gh run view 44839248351 -R ct-pkg/index
workflowName: index
conclusion: success
status: completed
headSha: 0cdb132a179a9cfab5e339da9fec856ec4f29fcc
url: https://github.com/ct-pkg/index/actions/runs/44839248351
```

### 2.6 任务清单可独立验收

任务清单见 `docs/phases/v0-PH-0/card.md`；四项均有独立命令与提交，且本节
§1 逐项贴了原始输出。

## 3. Issue 去向

| 条目 | 去向 | 证据 |
| --- | --- | --- |
| `IDX-1` | `done` | 本 phase 的六条退出判据与 CI run |
| `IDX-2` | `done`（已由 `0cdb132` 达成，IDX-7 另记残余） | README 版本表已删；残余 Usage 示例为 `IDX-7` |

## 4. 回顾

| 教训 | 落点 |
| --- | --- |
| fail-closed 刷新器只能列当前契约仓，否则一个旧仓会阻断全部刷新 | `spec:AGENTS.md §1 当前状态` |
| README 的手写版本快照必然漂移，版本只以 `index` 为准 | `rejected:恢复手写版本表（IDX-2）` |
| nightly 的最终证据是 CI run，不是本地 dry-run | `spec:docs/phases/v0-PH-0/card.md 退出判据 5` |

## 5. 遗留

- `IDX-7`：README Usage 示例仍写 `std/std@0.3.2`，为 `IDX-2` 的残余单行修正；
  不属本 phase 的退出判据，保留在需求池。
- `std v0.19.0` 的 tag 在 2026-11-19 曾发生移动；索引当前值与 tag 当前内容一致
  （全量 dry-run 无变化），但发布端仍应避免移动已发布 tag。
