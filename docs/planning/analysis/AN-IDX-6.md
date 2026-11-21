# AN-IDX-6：`check-layout.sh` 未按 `ns-root` 解析命名空间目录

追溯：`IDX-6` ｜ 分析日期：2026-11-21 ｜ 主张：REQ

## 1. 问题陈述

`tools/check-layout.sh` 把单元目录与包根比较：

```text
rel = <file> 去掉 <package-root>/ 前缀
want = namespace 的 `::` 换成 `/`
rel 的目录部分必须等于 want
```

但包契约允许 `ns-root` 指向子目录，编译器按 `<ns-root>/<namespace path>` 解析。
于是 `ns-root = src` 的包必然误报。

2026-11-21 对本地完整工作区（`/Users/samxx/trae-ws`，20 个仓）实测：

| 包 | `ns-root` | 有命名空间的单元 | 按包根判定 FAIL | 按 ns-root 判定 FAIL |
| --- | --- | --- | --- | --- |
| `ct-fsguard` | `src` | 3 | 3 | 0 |
| `nexcore` | `src` | 44 | 44 | 0 |
| 其余 13 个有命名空间的包 | `.` 或缺省 | 54 | 0 | 0 |
| **合计** | | **101** | **47** | **0** |

结论：47 条 FAIL 全部来自两个 `ns-root = src` 的包，折算到 `ns-root` 之后为 0。
门禁在真实工作区长期红，任何真实回归都会被这 47 行噪声淹没。

另有 `ct-json`（`src`）与 `rill-dsl`（`ct/src`）当前没有带命名空间的单元，暂不
暴露问题，但同样受该缺陷影响。

### 命名空间单元落在 `ns-root` 之外的情况

- `nexcore/experiments/**`：32 个带 `namespace` 的 `.ct`，全部在 `src` 之外；
- `ct-fsguard/test/fsguard/.../AltWalk.m.ct`：1 个，在 `src` 之外。

它们都是测试夹具/实验目录，不参与包发布。若一律判红，会把这两个包从"误报"变成
"无法通过"。因此判定范围应限定为 `<ns-root>` 子树；子树外的单元不套用本规则。

## 2. 范围

**做什么**

- `check-layout.sh` 读取包的 `ct.pkg`，取 `ns-root`（缺省或为空按 `.`），只对
  `<pkg>/<ns-root>/` 下的 `.ct` 套用"目录 == namespace 路径"的判定。
- `ns-root` 指向不存在的目录时，报一条独立错误（不静默当成 `.`）。
- 输出保留现有格式与计数口径，FAIL 行附 `<ns-root>` 相对路径，便于定位。
- 自测补四条夹具：`ns-root = src` 且匹配、`ns-root = src` 但目录错、单元在
  `ns-root` 之外（跳过）、`ns-root` 指向不存在的目录（失败）。

**不做什么**

- 不改 `check-char-host.sh`（它按宿主分组，与目录无关）。
- 不改 `gen-index.sh` 对 `ns-root` 的必填校验与摘要算法。
- 不为 `experiments/`、`test/` 里的夹具补 namespace 或移动文件。
- 不改编译器判定，也不改 `ct build --ns-root` 的行为。

## 3. 验收判据

| # | 命令 | 阈值 |
| --- | --- | --- |
| 1 | `CT_PKG_ROOT=/Users/samxx/trae-ws bash tools/check-layout.sh` | FAIL 行 0；输出 `ok: 68 namespaced units` 并另报 `skipped 33 units outside ns-root`；68 + 33 = 改动前的 101 |
| 2 | 同一命令的 FAIL 行数 | 由改动前的 47 降为 0，且不新增其它包 |
| 3 | 夹具：`ns-root = src`、`src/a/b/x.ct` 声明 `namespace a::b;` | rc=0 |
| 4 | 夹具：`ns-root = src`、`src/a/c/x.ct` 声明 `namespace a::b;` | rc=1，提示 `expects directory a/b` |
| 5 | 夹具：`ns-root = src`、`test/a/x.ct` 声明 `namespace a;` | rc=0（子树外不判定） |
| 6 | 夹具：`ns-root = missing` | rc=1，提示 `ns-root 'missing' is not a directory` |
| 7 | `bash tools/gate-selftest.sh` | `summary: … 0 failed`（含新增四条） |

判据里的绝对数字是 2026-11-21 开发机实测值（该根下 101 个单元：子树内 68、子树外
33）。包仓内容变化会让数字移动，届时以「FAIL 行 0、checked + skipped 不减少」为准。

## 4. 依赖与风险

**依赖**：无外部依赖；只用 shell 与现有 `ct.pkg` 字段。

**风险**

| 风险 | 触发信号 |
| --- | --- |
| 旧仓没有 `ns-root`，按 `.` 兜底后判定不变 | 这些包的 FAIL 数与非 0 计数与改动前一致 |
| 把 `ns-root` 之外的真实源码也豁免掉 | 若某包把源码放在 `ns-root` 外且带命名空间，门禁不再覆盖；触发信号是该包 `ct build` 报目录不匹配 |
| `ns-root` 指向不存在的目录被静默当成 `.` | 夹具 6 未变红；按判据 6 拦截 |
| `ns-root` 里含尾斜杠或 `./` 前缀导致路径拼接错 | 夹具改用 `src/` 复测；实现需先规范化 |
