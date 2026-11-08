# `std/` 与 `clib` 重叠调研：能不能合并

> 调研日期：2026-11-06 ｜ 性质：**只读调研，未改任何包、未改语言仓库**
> 数据来源：`ct` 仓库工作树（`ct v0.19.1` 之后）与 `ct-pkg/clib` 工作树 / `v1.0.0` tag。
> 阶段编号无关：本文只讨论两个库的边界，不引入新 Phase。

## 0. 结论（先给判断）

**不建议合并。** 两边不是同一层的东西，重叠面很窄：

| 指标 | `std` | `clib`（工作树） | `clib`（v1.0.0 已发布） |
| --- | --- | --- | --- |
| 单元 | 7 个 `.h.ct` | 6 个 `.m.ct` | 3 个 `.m.ct` |
| 导出 | 51 个 `pub` 函数 + 11 个 `pub` struct | 9 个 trait / 49 个方法 | 3 个 trait / 7 个方法 |
| 与对方语义重叠 | 4 个函数（`len` / `compare` / `find` / `starts_with`） | 7 个方法（`String.strlen`、`String.strcmp`、`Str.len`、`Str.compare`、`Str.indexOf`、`Str.contains`、`Str.startsWith`） | 2 个方法（`strlen`、`strcmp`） |

- **完全重叠（同语义同契约、可直接互换）：0 组。**
- 4 组语义重叠全部属于「语义相同、契约不同」：`std` 是**有界 / 空指针安全 / 失败即返回值**的库函数，
  `clib` 是**零成本、契约即 C 类型**的映射。按你给的三分法，这 4 组都是**第 2 类（分层）**，
  不是第 1 类（真重叠）。
- 其余导出面互不覆盖：`clib` 独有数学、stdio、ctype、数值格式化、`atoi`/`atof`；
  `std` 独有容器、arena、fs、utf8、test。数量上算「各自独有」的是绝大多数。

一句话：**看起来像两套字符串函数，实际是一套「安全库」和一套「C 调用语法糖」，合并会同时破坏两者的定位。**

---

## 1. 第一步：导出面清单

### 1.1 `clib`（ct-pkg，namespace `clib`）

已发布 `v1.0.0`（`ct.pkg` 注释自述「Three .m.ct units」，tag 树只有 `Math` / `Stdio` / `String`）；
工作树另有 `Str` / `Num` / `Real` 三个**未提交**单元与 shim（`git status` 显示 `??`，`ct.pkg` 仍写 1.0.0）。
下表的「方法数」按工作树统计，括注发布状态。

| 单元 | trait 宿主 | 导出方法 | 数 |
| --- | --- | --- | --- |
| `Math.m.ct` | namespace | `sqrt` / `fabs` | 2 ✅v1.0.0 |
| `Stdio.m.ct` | namespace | `puts` / `printf`（单 int 形参） | 2 ✅v1.0.0 |
| `String.m.ct` | namespace | `strlen` / `strcmp` / `memcpy` | 3 ✅v1.0.0 |
| `Str.m.ct` | `char *` | `len` / `compare` / `equals` / `startsWith` / `contains` / `indexOf` / `toInt` / `toDouble` | 8 ⬜未提交 |
| `Num.m.ct` | `int` | `abs` / `isDigit` / `isAlpha` / `isSpace` / `isUpper` / `isLower` / `toUpper` / `toLower` / `clamp` / `max` / `min` / `toStr` / `toString` / `toBase` | 14 ⬜未提交 |
| `Num.m.ct` | `long` / `long long` | `Long` / `LLong`：`abs` / `toStr` / `toString` | 3 + 3 ⬜未提交 |
| `Real.m.ct` | `float` / `double` | `Float`：`abs` / `sqrt` / `floor` / `ceil` / `round`；`Real` 另加 `isNan` / `isInf` / `toStr` / `toString` | 5 + 9 ⬜未提交 |

形态特征（决定合并难度的关键）：
- 全部是 `.m.ct` 映射单元，**调用点展开为普通 C 调用**，生成物零 `clib_` 符号、无 wrapper / vtable。
- 入口是 **trait 方法**（`s.len()`、`clib::String.strlen(..)`），依赖 `map trait` 配方与 `static inline` shim。
- `ct.pkg` 带 `ldflags = -lm`、有独立版本号、有索引行 → 走 `ct get` / `ct install` / 独立发版。

### 1.2 `std`（语言仓库 `std/`）

| 单元 | namespace | 导出函数 | 数 | pub struct |
| --- | --- | --- | --- | --- |
| `str/Str.h.ct` | `std::str` | `len` / `find` / `find_char` / `starts_with` / `ends_with` / `copy` / `slice` / `concat` / `lower` / `upper` / `compare` | 11 | `Str` |
| `vec/Vec.h.ct` | `std::vec` | `int_{init,len,push,pop,at,free}` / `str_{init,len,push,pop,at,free}` | 12 | `Vec` / `VecInt` / `VecStr` |
| `arena/Arena.h.ct` | `std::arena` | `init` / `alloc` / `reset` / `free_all` | 4 | `Arena` |
| `fs/Fs.h.ct` | `std::fs` | `exists` / `read_file` / `write_file` / `list` | 4 | `Fs` |
| `utf8/Utf8.h.ct` | `std::utf8` | `decode` / `encode` / `length` | 3 | `Utf8` |
| `test/Test.h.ct` | `std::test` | `init` / `check_true` / `check_eq_int` / `check_eq_str` / `report` | 5 | `Test` |
| `map/Map.h.ct` | `std::map` | `str_int_{init,put,get,len,clear,free}` / `int_ptr_{…}` | 12 | `Map` / `MapStrInt` / `MapIntPtr` |
| **合计** | | | **51** | **11** |

形态特征：
- 全部是 `.h.ct`，**带函数体**的 `pub` 自由函数（不是 trait 方法，因为跨单元 trait 方法是 `static`）。
- 目录 = namespace，`-I` 显式解析（D17-2：编译器**无**默认搜索路径），随语言仓库发布，
  `install.sh` 装到 `share/ct/std`，并由 `test/std/run.sh`（第 11 道硬门禁）覆盖。
- 无 `ct.pkg`、无版本号、无 `ldflags`、无索引行。

### 1.3 功能分类对照

| 功能类 | `std` | `clib` |
| --- | --- | --- |
| 字符串长度 / 比较 / 查找 / 前后缀 | ✅ 有界、空安全 | ✅ 裸 `strlen` / `strcmp` / `strstr` |
| 字符串复制 / 切片 / 拼接 | ✅ 定长缓冲，越界返 `-1` | ❌（只有无界 `memcpy`） |
| 整串大小写 | ✅ `lower` / `upper` 就地改写 | ❌（只有单字符 `toUpper` / `toLower`） |
| 字符分类 | ❌ | ✅ `isDigit` / `isAlpha` / `isSpace` / `isUpper` / `isLower` |
| 数值 ↔ 字符串 | ❌ | ✅ `toInt` / `toDouble` / `toStr` / `toString` / `toBase` |
| 数学 | ❌ | ✅ `sqrt` / `fabs` / `floor` / `ceil` / `round` / `isNan` / `isInf` |
| stdio | ❌（内部用，不导出） | ✅ `puts` / `printf` |
| 容器 | ✅ `Vec` / `Map` | ❌ |
| 堆分配 | ✅ `Arena` | ❌ |
| 文件系统 | ✅ `Fs` | ❌ |
| UTF-8 | ✅ `Utf8` | ❌ |
| 测试断言 | ✅ `Test` | ❌ |

---

## 2. 重叠矩阵

### 2.1 完全重叠（同语义 + 同契约，可互相替换）

**0 组。** 每对「看起来一样」的函数都在契约上分叉：

| 候选对 | 分叉点 |
| --- | --- |
| `std::str::len` vs `String.strlen` / `Str.len` | 返回 `int` vs `size_t`(`unsigned long`)；`NULL` 返 0 vs 未定义；`const char *` vs `char *` |
| `std::str::compare` vs `String.strcmp` / `Str.compare` | 归一化为 `-1/0/1` 且 `NULL→""` vs 原样返回 `strcmp` 符号 |
| `std::str::find` vs `Str.indexOf` | 同语义（偏移或 `-1`），但空指针行为不同、实现一为 `strstr` 一为 shim |
| `std::str::starts_with` vs `Str.startsWith` | 契约最接近（`strncmp` 前缀长度），仅差 `NULL` 守卫与返回类型拼写 |

### 2.2 部分重叠（同语义、不同契约/粒度）

| # | 能力 | `std` | `clib` | 判定 |
| --- | --- | --- | --- | --- |
| 1 | 取长度 | `std::str::len` | `String.strlen`、`Str.len` | 第 2 类（薄封装 vs 安全封装） |
| 2 | 字典序比较 | `std::str::compare` | `String.strcmp`、`Str.compare` | 第 2 类 |
| 3 | 子串定位 | `std::str::find` | `Str.indexOf`（`Str.contains` 是其布尔派生） | 第 2 类 |
| 4 | 前缀判定 | `std::str::starts_with` | `Str.startsWith` | 第 2 类（唯一接近可直接互换的一组） |
| 5 | 大小写 | `std::str::lower` / `upper`（整串，就地） | `Num.toUpper` / `toLower`（单字符，`unsigned char` 修正） | 第 3 类（粒度不同，各自场景） |
| 6 | 字符串复制 | `std::str::copy`（有界） | `String.memcpy`（无界、非字符串语义） | 第 3 类（不同操作，不是同一能力） |

### 2.3 各自独有

| `std` 独有 | `clib` 独有 |
| --- | --- |
| `vec`（12）、`map`（12）、`arena`（4）、`fs`（4）、`utf8`（3）、`test`（5）、`str` 中 7 个（`find_char` / `ends_with` / `copy` / `slice` / `concat` / `lower` / `upper`） | `Math`（2）、`Stdio`（2）、`Str` 的 4 个（`equals` / `contains` / `toInt` / `toDouble`）、`Num`（14）、`Long`/`LLong`（6）、`Float`/`Real`（14） |

量级：`std` 侧 51 个函数里 4 个进入重叠（7.8%）；`clib` 工作树 49 个方法里 7 个（14.3%）。
若只看**已发布**的 `clib v1.0.0`（7 个方法），重叠是 2 个（`strlen` / `strcmp`），比例 29% ——
发布面越小、重叠占比越高的错觉，来自 v1.0.0 只覆盖三个 namespace trait；
工作树的演进方向（类型宿主、ctype、格式化、数学）恰好是 `std` 明确不做的领域。

---

## 3. 第二步：重叠性质

按「真重叠 / 分层 / 分工」分类：

- **第 1 类（语义相同、实现不同 → 可合）**：**没有**。四组语义重叠全都伴随契约差异，
  合并任何一组都必须先选定一种契约，等于放弃另一边的承诺。
- **第 2 类（薄封装 vs 安全封装 → 分层）**：上表 #1–#4，共 4 组。
  证据：`std::str` 的每个入口都有空指针守卫与容量参数，失败返 `-1`/`NULL`；
  `clib` 的配方直接落到 `strlen`/`strcmp`，`ct.pkg` 与 README 明确写「声明里的 C 类型就是全部契约，CT 不额外加安全层」。
- **第 3 类（看似相近、场景不同 → 分工）**：上表 #5–#6。
  `std` 的 `lower/upper` 是「整串就地改写」，`clib` 的 `toUpper/toLower` 是「单字符，且修正负 `char` 的 UB」——
  后者服务于逐字符扫描，前者服务于规范化；`copy` 与 `memcpy` 是两种不同承诺（有界字符串复制 vs 任意字节块拷贝）。

补充一个「非重叠但同源」的事实：`std::fs` 内部用 `fopen`/`fwrite`，`std::test` 内部用 `printf`，
`std::vec`/`std::map` 内部用 `malloc` —— 这些是**库实现细节**，`std` 不把它们导出成 API；
`clib` 导出的正是这些底层入口。两者是「使用者」与「提供者」的关系，不是重复实现。

---

## 4. 第三步：合并的真正障碍

### 4.1 版本归属

- `std` 的版本 = 编译器版本：随 `ct` 仓库发布，随 tag 走，`install.sh` 落盘到 `share/ct/std`；
  **没有独立版本号，也不可能有**（它随语言安装）。
- `clib` 有独立 `ct.pkg`（`version = 1.0.0`）、独立 tag、独立索引行，走 MVS 范围解析
  （`dep = clib@^1.0.0`），可单独升级、可锁 `ct.lock`。
- 合并方向各自的代价：
  - `clib → std`：用户失去「单独升级 `clib`」的能力，`ct get` / `ct verify` / 索引 / lock 一条链全废；
    想升级映射层只能升编译器。
  - `std → clib`：语言的「开箱可用」承诺消失（`import std::str::Str` 变成要 `ct get` + `-I vendor/...`），
    `test/std/run.sh` 这道硬门禁失去对象，且 `std` 会被一个 README 自称「**演示级**、不是 libc 绑定」的包接管。
- 现成的反证：`clib` 工作树已比 `v1.0.0` 多出 6 个单元 / 42 个方法且**尚未发版**，
  说明它需要「先写、后发」的独立节奏；`std` 同期跟着 Phase 17 的七模块一次成型。
  两种发版节奏已经实测分叉。

### 4.2 ABI / 兼容规则

- `std` 的签名是**编译器发行承诺的一部分**：`pub` 自由函数、固定 `const char *` 形参、`int` 返回值，
  教程与 `test/std/run.sh` 直接依赖；改动要按向后兼容审。
- `clib` 的兼容规则是包级 semver + MVS 范围，允许在 `0.x` / 主版本内破坏性调整（`v1.0.0` 只有 3 个 trait，
  工作树直接换成了「namespace 宿主 + 类型宿主」两代并存）。
- 合并后只能选一套：选 `std` 规则 → `clib` 的快速演进被冻结；选 `clib` 规则 → 语言标准库可以按包的节奏破坏，
  与「`std` 随编译器发布」矛盾。

### 4.3 导入成本

- `std`：显式 `-I`（D17-2 无默认搜索路径），但**无需安装、无网络、无 lock**；
  `install.sh` 给出建议 `-I` 行。
- `clib`：`ct get` → `ct install` → 抄它打印的 `ct build` 命令；额外获得 `-lm`、版本锁定与 `ct verify`。
- 两个方向的迁移成本：
  - `clib → std`：现有 `import clib::String;` 等语句（`examples/wave1-demo`、`.github/workflows/packages.yml`
    的宿主 + aarch64-QEMU 两半）全改；且 `std` 没有 `ct.pkg`，`ldflags = -lm` 无处安放，
    用户得手动 `--ldflags '-lm'` —— 这正是 Phase 18.5 要消灭的手工步骤。
  - `std → clib`：7 个模块 / 51 个函数全部改成 vendor 内源码 + 版本约束；语言仓库体积变小，
    但新用户从「无需安装」变成「先 `ct get`」，且 `std` 的七模块测试面转移成一个包的 CI 面。

### 4.4 一个被忽略的技术硬约束（比上面三条更硬）

编译器规定：**`.m.ct` 只能 `import` 另一个 `.m.ct`**（`Module.h.ct` 第 429 行），
且 `.m.ct` 只能承载 `pub trait` / `map` / `#include` / `#define` / `import`，
**不能有函数体**（Parser 白名单，第 514 行起）。

推论：
- `std` 的 `.h.ct` 自由函数带函数体，**不可能**改写进 `clib` 的 `.m.ct`；
- `clib` 的映射配方也**不可能**为 `std` 的 `.h.ct` 提供零成本展开。
- 即使把两个目录放进同一棵树，也只会得到「`.m.ct` 层 + `.h.ct` 层并存」——
  也就是今天的样子，只是少了一个 `ct.pkg` 和一条索引行。
- 也就是说：**「合并」在物理上只能合并目录，不能合并层次**。这决定了它省不下任何概念负担。

---

## 5. 第四步：三种方案

### 方案 A：吸收（`clib` 并入 `std/`，索引移除）

| 维度 | 评估 |
| --- | --- |
| 改动面 | 6 个 `.m.ct` + 3 个 shim 搬进 `std/`；`ct.pkg` 删除；索引删 1 行；`examples/wave1-demo` 与 `packages.yml`（宿主 + QEMU 两半）改 import；`clib` 仓库归档 |
| 用户影响 | 现有 `dep = clib@^1` 的 `ct.lock` 全部失效；`-lm` 从自动变成手工；`ct verify` 不再覆盖映射层 |
| 语言承诺 | `std` 从「有界、失败即返回值」变成混入无限定 C 语义；「开箱可用」反而退化（`-lm` 要手传） |
| 维护成本 | 语言仓库 +6 单元 +3 shim + 系统库依赖；`test/std/run.sh` 需要感知系统 libm；`clib` 原来独立的版本/索引/CI 全部转嫁 |

### 方案 B：下沉（`std` 中面向 C 库封装的部分移入 `clib`，`std` 只留语言必需）

| 维度 | 评估 |
| --- | --- |
| 改动面 | `std::str` 的 4 个重叠函数退场或转调 `clib`；但 `clib` 是包、`std` 随语言发布 → `std` 必须对 `clib` 产生 `dep`，而 `std` 没有 `ct.pkg`，**结构上无处声明**；只能靠用户手动 `ct get clib`，等于把标准库拆成可选依赖 |
| 用户影响 | 七模块测试与教程全部要加 `-I vendor/clib`；「不安装即可用」的承诺破裂 |
| 语言承诺 | 最大破坏：语言自带的字符串能力变成第三方版本约束下的产物 |
| 维护成本 | 双仓库联动发版；包索引故障会直接打断标准库构建 |

> 方案 B 的致命点：**`std` 不是包，无法声明 `dep`**。要做「下沉」必须先给 `std` 发明包形态
> （打包、版本、索引），那是另一个阶段的工作量，且与 D17-2「随 `install.sh` 安装」相冲突。

### 方案 C：并存分工（保持两个，明确边界并写进文档）

| 维度 | 评估 |
| --- | --- |
| 改动面 | 仅文档：两边 README 互链 + 一段「何时用哪个」的判定规则；可选在 `glossary` 补一条 |
| 用户影响 | 零迁移；只需知道规则 |
| 语言承诺 | 不变：`std` = 有界、空安全、失败即返回值、随语言发布；`clib` = 零成本 C 调用拼写、独立发版、契约即 C 类型 |
| 维护成本 | 最低；两者继续各自生长，用规则而不是目录来防止漂移 |

**推荐 C**，理由按证据排序：

1. **重叠不是「实现重复」，是「接口分层」**：4 组重叠全部有契约差异，0 组可直接互换。
   合并只能二选一地牺牲一边的承诺，换不来代码量的实质下降（`std` 侧四个重叠函数连同注释约 55 行）。
2. **形态不可合并**：`.m.ct` 不能有函数体、只能 import `.m.ct`（第 4.4 节），
   合并目录后仍是两层——省掉的是一个 `ct.pkg` 和一条索引行，代价却是版本/ABI/导入三条链全断。
3. **版本节奏已实测分叉**：`clib` 工作树领先 `v1.0.0` 42 个方法仍未发版，`std` 跟 Phase 17 一次成型；
   强行同步会让两边都被对方的节奏绑住。
4. **`clib` 的自我定位与 `std` 相反**：`clib/README.md` 明写「**演示级的映射包，不是 libc 绑定**」
   「不做边界检查、不额外加安全层」。把它抬成标准库，或把标准库降成它，都是定位错误。

### 5.1 推荐方案的落地边界（只写规则，不动代码）

若采纳 C，建议把下面五条写进两边 README 与 `docs/`（本轮不执行）：

1. **`std` 不新增 `.m.ct`**：`std` 只收有函数体、有明确失败契约的 `.h.ct`；不为「少写一行 `strlen`」引入映射层。
2. **`clib` 不新增有界/安全 API**：`clib` 只做「C 类型即契约」的零成本拼写；一旦需要缓冲区/错误码/生命周期，
   属于 `std` 或用户代码。
3. **同名能力以契约为准**：`std::str::len`（空安全、`int`）与 `Str.len`（裸 `strlen`、`size_t`）各自保留，
   文档互相注明「另一边的语义不同」，不试图统一签名。
4. **新字符串能力只进 `std`**：`clib::Str` 冻结在「C 已有函数的拼写」范围（`equals` / `contains` / `indexOf`
   只是 `strcmp`/`strstr` 的形状适配），不再扩张成字符串库。
5. **版本各自独立**：`std` 随编译器 tag；`clib` 走 semver + 索引；两者之间不出现 `dep`。

### 5.2 触发重新评估的条件

只有当 **`std` 先获得包形态**（有 `ct.pkg`、版本号、索引行）时，方案 B 才从「结构不可能」变成「可讨论」——
那时版本归属与 ABI 规则才有统一的落点。在那之前不做合并。

---

## 6. 附：关键证据文件

| 内容 | 位置 |
| --- | --- |
| `clib` 已发布面（3 单元 / 7 方法） | `git -C clib ls-tree -r --name-only v1.0.0`；[ct.pkg](../clib/ct.pkg) |
| `clib` 自述定位与「不加安全层」 | [clib/README.md](../clib/README.md) |
| `clib` 映射与 shim | [Math.m.ct](../clib/clib/Math.m.ct)、[Str.m.ct](../clib/clib/Str.m.ct)、[Str.shim.h](../clib/clib/Str.shim.h)、[Num.m.ct](../clib/clib/Num.m.ct) |
| `std` 七模块与形态约定 | [std/README.md](../../../ct/std/README.md)、[Str.h.ct](../../../ct/std/str/Str.h.ct) |
| `std` 的发现方式（无默认搜索路径） | [phase17.md](../../../ct/docs/design/phase17.md) §17.2 / D17-2 |
| `.m.ct` 限制（只能 import `.m.ct`、不能有函数体） | [Module.h.ct](../../../ct/selfhost/ct-ast/frontend/module/Module.h.ct) 第 429 行；Parser 第 514 行起 |
| 索引现状（`clib 1.0.0` 一行） | [index/index](../index) |
| `clib` 的 CI / demo 使用点 | `ct/.github/workflows/packages.yml`；`ct/examples/wave1-demo/src/main.ct` |
