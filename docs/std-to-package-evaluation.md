# 评估：把 `std/` 整体移出 ct-lang，改为 ct-pkg 普通包

> 评估日期：2026-11-06 ｜ 性质：**只读评估**，未改语言仓库、未在 ct-pkg 建包
> 数据来源：`ct` 工作树（v0.19.1 + 未提交的 OO 化改动）与 ct-pkg 现有机制
> **方向声明**：本文取代 2026-11-06 早间的《`std/` 与 `clib` 重叠调研》。那份文档回答的是「clib 能否并入 std」，
> 方向已反转；其中「4 组重叠 / 0 组可互换」的测量仍然有效，但结论不再是本轮的依据。

## 0. 结论

**技术上能迁，但现在不值得迁。** 建议先不做，或只做「发布解耦、安装仍内置」的轻量版（§7）。

三条支撑判断：

1. **收益目前是理论值，成本是每个项目永久的。**
   `std` 在 ct 仓库 498 个 commit 里只占 **1 个**（`91a7809`，2026-11-02 引入），OO 化改造至今仍未提交；
   而编译器发版节奏是 **v0.18.0 → v0.19.1 隔 1 天**。「改一行要等编译器发版」的真实等待约等于 1 天，
   不是季度。代价却是每个使用方从「`-I share/ct`」变成「`ct.pkg` + `ct.lock` + `vendor/` + `ct get` + `ct install`」。
2. **迁移的真实工作量极小，所以它也不该被当成大工程来换收益。**
   代码侧只有 **32 行 import**（13 个文件）；如果保留 `std` 命名空间，**调用点一行都不用改**。
   真正的难点不在迁移，而在迁完之后的三件事：编译器 CI 失去 std 门禁、首跑体验丢失、索引只能给最新版。
3. **兼容方案 ②（薄转发）在当前语言里不成立。** 实测：两个 trait 对同一宿主类型映射同名方法，
   编译期直接报 `ambiguous type-host map`；语言没有 re-export。转发只能靠复制，那就是 ③ 的成本。

如果目标只是「std 能独立打 patch」，轻量解耦（§7）能拿到 80% 的收益、0 个使用方成本；只有当确实出现
「不同项目要钉不同 std 版本」时，才值得升级为真包。

---

## 1. 迁移后的形态

### 1.1 包名与版本起点

| 项 | 建议值 | 理由 |
| --- | --- | --- |
| 包名 | `std`（若编译器未硬编码该名字）；否则 `stdx` | 包名 = `vendor/<name>` 目录名，也是 import 的第一段 |
| 版本起点 | **`0.1.0`** | OO 化刚做完且未提交，API 还在动；此时写 `1.0.0` 等于给一个 4 天大的库发稳定性承诺 |
| `licence` | 与编译器一致（见 `ct/LICENSE` / `LICENSE.EXCEPTION`） | 包规范只约定不校验 |
| `ct.pkg` 其他键 | 无 `dep`、无 `cflags`、无 `ldflags` | std 只用 ISO C 头（stdio/stdlib/string/dirent），不链接额外库 |
| `requires` | `ct >= 0.20.0`（OO 形态所需的最低编译器） | **只告警不拒装**，所以必须同时写进 README |

### 1.2 两版命名空间方案

#### N1：保留 `std` 命名空间（推荐）

`import std::str::String` 不变，包仓库根目录就是今天的 `std/`：

```
ct-pkg/std/
├── ct.pkg
├── LICENSE
├── README.md
├── str/   String.m.ct + String.shim.h
├── fs/    Fs.m.ct + Fs.shim.h
├── utf8/  Utf8Ops.m.ct + Utf8Ops.shim.h
├── vec/   Vec.h.ct
├── map/   Map.h.ct
├── arena/ Arena.h.ct
└── test/  Test.h.ct
```

**但有一个机制缺口**：`ct install` 现在按包打印 `-I vendor/<pkg>`（[phase18](../../../ct/docs/design/phase18.md) 明确写
「命令含 `-I vendor/clib`」）。若 std 的 `-I` 是 `vendor/std`，`import std::str::String` 会去找
`vendor/std/std/str/String.m.ct`，解析不到。两条落地路径：

- **N1-a（推荐）**：`ct install` 改为打印一个 `-I vendor`（所有包共用的根），而不是逐包 `-I vendor/<pkg>`。
  对现有包等价（`vendor/clib/Num.m.ct` 在 `-I vendor` 下同样是 `clib::Num`），对 std 则刚好成立。
  改动量：包工具里生成 `-I` 的那一处 + 其单测/文档。
- **N1-b**：仓库里再嵌一层 `std/`（`vendor/std/std/str/...`）。不改工具，但违反包规范
  「包根目录就是包根，不嵌套子目录」，且目录名和包名重复，**不推荐**。

#### N2：改名为 `stdx`（或 `ctstd`）

```
import stdx::str::String;
```

- 包仓库布局与 N1 相同，只是仓库/包名变为 `stdx`。
- 好处：新旧 std 前缀不同，可以在同一 `-I` 列表里共存，是 ③ 双轨唯一可行的前提。
- 代价：**32 行 import 全改**（ct 仓库 `test/std` 29 行 + ct-markdown 示例 3 行），外加文档里的 ~25 处引用。
- 语义代价：一个语言的标准库不叫 `std`，教程、搜索结果、既有习惯全部对不上。

> 命名空间是否被编译器硬编码由另一路同学确认；本评估不预设结论。
> 若编译器对 `std` 有特殊处理，则 N2 是唯一可行方案；若没有，N1 明显更便宜。

### 1.3 迁出后还需要什么

| 项 | 现状 | 迁移后 |
| --- | --- | --- |
| 安装 | `install.sh` 复制 `std/` 到 `share/ct/std`（第 168–201 行，约 34 行） | 删除该段；或改为「预装包」见 §7 |
| 发现 | 用户手抄 `-I ~/.local/share/ct` | 用户执行 `ct install` 打印的 `-I vendor` |
| 门禁 | `selfhost/check-all.sh` 第 10 道 `test/std/run.sh` | 从编译器 CI 删除，迁到包仓库 |
| 文档 | `docs/tutorial.md` 有 4 处 std 示例 | 改为指向包仓库；语言仓库只留一句「std 是包」 |

---

## 2. ct-pkg 现有机制能否承接

### 2.1 需要补什么

| 缺口 | 现状 | 要补的 |
| --- | --- | --- |
| manifest | 无 | `ct.pkg`：`name` / `version` / `licence` / `requires` |
| 索引 | `index/index` 3 行 | 追加 `std 0.1.0 <url> v0.1.0 sha256:<64hex>`，并把仓库登记进 `index/packages.txt` 与 `index/tools/repos.txt` |
| lock | 无 | 消费方 `ct.lock` 增加一行；`vendor/std/` 进 `vendor/` |
| CI | 编译器内 12 个 fixture + 156 行 `run.sh` | 在新仓库复刻宿主（macOS arm64 / Linux x86_64）+ 目标机（aarch64 QEMU）两腿 |

### 2.2 现有格式是否够用

**够用的部分**

- 无依赖，索引行的 `name version url tag sha256` 足够；`dep` 为空。
- 摘要按全目录递归计算，std 共 **1,338 行 / 10 个源文件**（4 个 `.h.ct`、3 个 `.m.ct`、3 个 `.shim.h`），
  对摘要与 `ct verify` 都是零压力。
- `.h.ct` 与 `.shim.h` 都能进包：`hal` 已经是纯 `.h.ct` 包，`clib` 已经带 shim。

**不够用的部分（三条，按严重度排）**

1. **索引只收录每个仓库的「最高 `v*` tag」**（`index/packages.txt` 注释与 `refresh-index.sh` 的行为）。
   这意味着索引里永远只有一个 std 版本。老编译器需要旧 std 时，索引给不了；
   而 `requires` 只告警不拒装，用户会装到不兼容版本后才发现。缓解办法只有「手动 checkout 旧 tag 用 `file://` 安装」。
2. **`ct install` 的 `-I` 粒度与嵌套命名空间冲突**（见 §1.2 N1-a）：不改包工具就必须给包根再嵌一层目录。
3. **离线安装退化**：`ct get` 依赖 git（包管理路径唯一的子进程/网络点）。今天 `install.sh` 装完就有 std；
   拆包后首次使用必须联网或随仓库带 `vendor/`。

---

## 3. 影响面盘点（行数级）

### 3.1 代码

| 位置 | 规模 | 迁移动作 |
| --- | --- | --- |
| ct 仓库 `test/std/**` | **12 个 `.ct`，672 行**；import 语句 **29 行** | 随包迁走；若 N1 则 import 一字不改 |
| ct 仓库 `test/std/run.sh` | **156 行** | 迁到包仓库 CI；其中「目录隐含 namespace」「pub struct 名 = 文件名」的断言属于 std 布局，必须一起搬 |
| ct 仓库 `selfhost/check-all.sh` | 2 行（注释 + `run_gate`） | 删除该门禁（12 → 11 道） |
| ct 仓库 `install.sh` | 约 **34 行**（std 复制段）+ 3 行提示 | 删除或改为预装 |
| ct-markdown | **1 文件 38 行，3 条 import**（`examples/v0.19.1/04-std-library/std_demo.ct`） | N1：只改 `-I`；N2：改 3 行 import |
| ct-album | **0 行** | 无需迁移。其 `spec.md` 第 378 行已明确「不引入 std，自写 `FsUtil`」，理由是「直接依赖 CT 源码树路径不可移植」——这恰好是 std 打包要解决的问题 |
| ct-nc / ct-NexCore / ct-radio / ct-sentence-making / ct-tunnel | **0 行**（合计 509 个 `.ct`） | 无需迁移 |
| 工作区总计 | 7 个 ct-* 项目、**554 个 `.ct` 文件**，只有 **1 个文件** import std | 迁移面实际只覆盖测试与一个示例 |

### 3.2 文档

- ct 仓库：`docs/tutorial.md` 4 处、`std/README.md` 16 处、`std/str/README.md`、`std/str/tutorial.md` 与
  `std/vec/tutorial.md`（两个 `tutorial.md` 后续均已并入各自目录的 README 并删除）各数处，合计 **约 25–30 处**需要改指向或随之搬迁。
- ct-markdown：`examples/v0.19.1/README.md`、`verify.sh`（`CT_STD` 默认 `~/.local/share/ct`）、
  以及两份历史评估文档提到 std 路径。历史文档可不动，运行脚本必须改。
- 全工作区引用已安装 std 的脚本只有 2 个：`ct/install.sh` 与 `ct-markdown/.../verify.sh`。

### 3.3 结论

**迁移本身是「小手术」**：32 行 import + 1 个示例 + 1 个门禁脚本。真正改变的是**分发模型**，不是代码量。
因此「迁移很麻烦」不能作为反对理由；反对理由只能是 §6 的收益/成本判断。

---

## 4. 自举风险

- **实测：`selfhost/` 对 `import std::` 的引用为 0 处。** 编译器 L0 → L1 → L2 → ct-ast 的构建链只依赖 C 编译器，
  不依赖任何 CT 包。所以「ct-lang 不含内置库」**不会**让编译器构建需要先装包。
  这一条是本次评估中风险最低的：自举链路原样成立。
- 真正被削弱的不是构建，而是**验证**：第 10 道门禁 `test/std/run.sh` 是编译器 CI 里唯一「语言改动是否打坏 std」的信号。
  拆包后：
  - 编译器仓库不再能离线验证 std（要么 CI 跨仓 checkout 包仓库，引入网络/兄弟仓库依赖；
  - 要么在 `test/` 里再放一份 std 副本，退化成 ③ 的双轨）。
  - 结果：一次语言层破坏性改动（比如 trait 解析规则）可能先在**包**的 CI 炸，而不是在编译器 CI 炸，
    反馈链变长，且旧版 std 仍会对新编译器「看起来能装」。
- 打包侧能支撑的：包 CI 可以用 `requires` + 多编译器矩阵（v0.19.x / 当前 / HEAD）来补这个信号。
  成本是包仓库的 CI 要维护一组编译器版本，而不是一个。

---

## 5. 兼容策略对比

先说两条**实测硬约束**（决定了哪些策略可行）：

1. 两个 `.m.ct` 对同一宿主类型映射**同名方法** → 编译期硬错误：
   `error: ambiguous type-host map for method 'len' on type 'char *'`。
   所以「旧 `std` 留薄转发、新包同名方法」不可能共存。
2. 同一条 `-I` 列表里存在两份同名单元（`std/str/String.m.ct`）→ **不报错，静默取第一个 `-I`**。
   所以双轨并存不会提醒你，只会让 `-I` 顺序决定用哪份。

| 策略 | 具体做法 | 代价 | 可行性 |
| --- | --- | --- | --- |
| **① 一次性破坏 + 迁移表** | 编译器某一版删除 `share/ct/std`；用户改用 `vendor`；N1 下 import 不变 | 旧项目构建时报 `cannot resolve import 'std/...'`（错误清晰）；迁移表 1 行：装包 + 换 `-I` | **可行，最便宜**（N1 几乎零源码改动；N2 改 32 行 import） |
| **② ct 仓库保留极薄转发单元** | 在 `std/str/String.m.ct` 里只写 `map trait` 指向 C 函数 | 同名 trait 同宿主 → 硬错误；语言无 re-export；只能复制 187 行 shim，等于双轨 | **当前语言下不可行**（除非先加「re-export / 别名」语言特性） |
| **③ 双轨一个版本周期** | 两份 std 并存（旧仓 + 包） | 必须改名（否则静默 shadow / 重名冲突）；1,338 行 ×2 + 两套测试；std 正在改（OO 化未提交），漂移几乎必然 | **技术上可行，但成本 > 收益**；仅当已经选了 N2 才考虑 |

**迁移表（若选 ①+N1）**

| 旧 | 新 |
| --- | --- |
| `ct build -I ~/.local/share/ct main.ct` | `ct get std@^0.1` → `ct install` → 执行它打印的命令（含 `-I vendor`） |
| `import std::str::String;` | 不变 |
| `selfhost/check-all.sh` 第 10 道 | 删除（std 门禁移到包仓库） |

---

## 6. 发布收益 vs 成本：值不值

### 6.1 收益（可量化的部分）

| 收益 | 现实大小 |
| --- | --- |
| std 改一行不必等编译器发版 | 当前编译器发版间隔 **1 天**（v0.18.0 2026-11-02 → v0.19.1 2026-11-03）；std 至今 **1 个 commit**。真实等待成本接近 0 |
| 下游可钉死 std 版本 | **真收益**：今天 `-I share/ct` 的内容随「装的是哪个编译器」漂移，项目无法声明自己依赖的 std 版本；`ct.lock` 能解决 |
| std 可独立 CI / 多编译器矩阵 | 中等收益，但需要新仓库长期维护两腿（宿主 + QEMU）CI |
| 语言仓库变小 | 1,338 行 / 10 文件，对 498 commit 的仓库没有实质影响 |

### 6.2 成本

| 成本 | 承担者 | 量级 |
| --- | --- | --- |
| 每个项目新增 `ct.pkg` + `ct.lock` + `vendor/` + 安装步骤 | **每个使用方、永久** | 一次性 3 个文件 + 1 条命令；CI 每次多一步 `ct get/verify` |
| 首跑体验：「装完编译器就能用 std」消失 | 每个新用户 | 从 0 步变 2 步（get + install），且首次要联网 |
| 编译器 CI 失去 std 门禁 | 语言维护者 | 反馈链变长，破坏性语言改动可能晚发现 |
| 索引只能给最新版 | 老编译器用户 | 索引无法交付兼容旧编译器的 std |
| 过渡期的静默 shadow | 迁移中的用户 | 旧 `share/ct/std` 未删时，`-I` 顺序决定行为，且不报错 |
| 文档双仓库 | 维护者 | 教程、README、示例都要跟包走 |

### 6.3 判断

**现在不值。** 决定性的不是「包机制不成熟」（它够用），而是：

- 想解决的问题（发版解耦）当前的实际痛感 ≈ 0：std 4 天 1 个 commit，编译器每天都能发版；
- 换来的成本由每个使用方永久承担，而且**首跑体验**这一条直接对抗 Phase 17 的「开箱可用」承诺；
- 一旦拆出，编译器 CI 对 std 的覆盖会断，这是**质量回退**，不是中性的架构调整。

反过来说，如果真实需求是「std 可以独立 patch，且不同项目能钉不同版本」，那就该拆——这两条是包模型独有的、
轻量解耦给不了的。按目前的证据（1 个真实使用文件、0 个生产项目依赖），还没到那一步。

---

## 7. 若坚持要拆分：最小路径 / 更轻的替代

### 7.1 最小路径（约 6 步，不改语言代码语义）

1. 先提交当前的 OO 化工作树，并打 `v0.20.0`（否则包要从一个未提交状态切出）。
2. 新建 `ct-pkg/std` 仓库，根目录放 `ct.pkg` + 现有 7 个模块目录（N1）。
3. 包工具改为打印 `-I vendor`（N1-a），并补单测。
4. 把 `test/std/**` + `run.sh` 迁到包仓库 CI（宿主两腿 + aarch64 QEMU），断言布局的检查一起搬。
5. 编译器仓库：删 `install.sh` 的 std 复制段与 `check-all.sh` 第 10 道；`docs/tutorial.md` 改为指向包。
6. 发一版编译器，并在其 release note 里给「一次性破坏」迁移表（§5）。

### 7.2 更轻的替代（推荐先做这个）

目标只解耦**发布**，不解耦**安装**：

- 给 std 建独立版本号与独立 tag/CI（例如 `std-v0.20.0`），源码仍放在 ct 仓库 `std/`；
- `install.sh` 继续预装 std 到 `share/ct`（首跑与离线不受影响）；
- 需要钉版本的少数项目用 `ct get file://<ct 仓库>/std` 或索引条目覆盖预装版本；
- 编译器 CI 保留第 10 道门禁，std 破坏性改动仍在这里先炸。

这条路径拿到「std 独立发 patch」「可钉版本」两项收益，成本只是多一个 tag 约定和一条 CI 作业；
不引入 `vendor/`、不打断首跑、不丢门禁。等真正出现「多版本并存」需求时，再走 §7.1。

---

## 8. 作废与保留的结论

- **作废**：2026-11-06 早间《`std/` 与 `clib` 重叠调研》中「把 clib 并入 std」的方向结论。
  方向已反转为本评估。
- **仍然有效**：该文档的两组实测——同宿主同名方法会 `ambiguous type-host map`、`.m.ct` 只能 import `.m.ct`
  ——在本评估里成了「兼容策略 ② 不可行」的依据。
- **新增实测**：两条 `-I` 指向同名单元时**静默取第一个**（不报错）；`clib` 的 `.m.ct` 层在 `-O2` 下
  导入成本 **+8 字节**（16,840 → 16,848），在 `-O0` 下因 `static inline` 全量落地而 **+16.6 KB**（16,840 → 33,480）。
  结论：**打包本身不改变程序体积**——std 迁出前后编译进二进制的仍是「被 import 的那些单元」，
  `std` 从不是「默认编进去的面」。真正的体积变量是 shim 的优化级别，与包化无关。

## 9. 证据索引

| 内容 | 位置 / 命令 |
| --- | --- |
| std 模块清单与行数 | `wc -l ct/std/*/*.ct ct/std/*/*.h` → 1,338 行 / 10 文件 |
| std 引入与改动频率 | `git -C ct log --oneline -- std` → 1 个 commit（`91a7809`，2026-11-02） |
| 发版节奏 | `git -C ct log -1 --format=%ad v0.18.0` / `v0.19.1` → 2026-11-02 / 2026-11-03 |
| 工作区真实使用者 | 7 个 ct-* 项目 554 个 `.ct`，仅 ct-markdown 1 个文件 import std |
| ct-album 的回避理由 | `ct-album/.trae/specs/ct-album-v1/spec.md` 第 378 行 |
| 自举不依赖 std | `grep import std:: ct/selfhost` → 0 处 |
| 门禁与安装耦合 | `test/std/run.sh` 156 行；`selfhost/check-all.sh` 第 85 行；`install.sh` 168–201 行 |
| 包规范（根目录/键/索引格式） | [package-guide.md](../../../ct/docs/package-guide.md) §2–§3 |
| 索引与发布流程 | [index/packages.txt](../packages.txt)、[tools/repos.txt](../tools/repos.txt)、[phase2.md](phase2.md) |
| 重复同名单元的静默行为 | 实测：`ct build with_std.ct -I ct -I <dup>` 退出 0，取第一个 `-I` |
| 同宿主同名方法 | 实测：`error: ambiguous type-host map for method 'len' on type 'char *'` |
| `.m.ct` 的 import 与函数体限制 | [Module.h.ct](../../../ct/selfhost/ct-ast/frontend/module/Module.h.ct) 第 429 行；Parser 第 514 行起 |
