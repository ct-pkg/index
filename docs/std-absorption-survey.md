> **过期提示**：本文为某时点的历史记录，其中的数量与接口已过时，现状见 [docs/std-oo-coverage.md](std-oo-coverage.md)。

# ct-pkg 全景：哪些模块可以迁进 std

> 评估对象：`ct-pkg/` 下全部包的**模块/单元**（不是包）。
> 结论口径：以“模块自身是否引入外部依赖”为唯一机械边界，涉及取舍的地方逐条写代价。
> 本文所有判定都能按 `文件:行` 复核；实测部分是本机跑出来的输出，不是推断。

---

## 0. 结论先行

| 结论 | 内容 |
| --- | --- |
| **建议迁** | 没有任何**整模块**属于“零外部依赖”档。真正值得做的是两处**吸收**：`clib::Str.toInt/toDouble` → `std::str::String`；`clib::Num` → 新模块 `std::num`。两者都只依赖 libc、不引入任何 `-l`，且全工作区 0 个有效调用点。 |
| **建议不迁** | `clib::Stdio`（API 太弱）、`clib::Math` / `clib::Real`（要 `-lm`，且只是 libm 薄封装）、`net-posix`、`hal-posix`、`hal`（契约包，不是标准库）。 |
| **绝对不能迁** | `zlib`（`-lz`）、`png`（`-lpng -lz`）、`sqlite`（`-lsqlite3`）。 |
| **版本** | std `0.1.0 → 0.2.0`（纯新增）；clib 下一版直接定 **`2.0.0`**，把待发版本里的破坏性改动和本次删减合成一次，不补发 1.x。 |
| **包依赖** | `requires` 只校验编译器版本，**不能**表达包依赖；包依赖是 `dep`。实测 `dep = std@^0.1.0` 可递归拉取、顺序正确、`-I` 正确。clib 2.0.0 不需要这条边。 |

---

## 1. 判定规则

| 档 | 定义 | 迁移门槛 |
| --- | --- | --- |
| **零外部依赖** | 单元无 `#include`、无外部符号（纯 CT 或纯 CT + shim 内自洽代码） | 机制上可迁 |
| **仅 libc / POSIX** | 只 include 标准 C 头或 POSIX 头，链接只需 libc（**不需要额外 `-l`**） | 逐模块权衡 |
| **必须有第三方 C 库** | include 第三方头或链接 `-l<lib>` | 留在原处 |

补充一条硬边界：**迁移不得改变 std 的包级链接需求**。`ct install` 会把 lock 里所有包的 `cflags` / `ldflags` 合并成一条命令（`Pkg.h.ct:1276-1299`），所以往 std 的 `ct.pkg` 里加 `-lm`，等于给**每一个** std 用户加 `-lm`，哪怕他只用 `std::vec`。

---

## 2. 全景表

### 2.1 std（基线，已在包内）

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| std | `arena/Arena.h.ct` | `.h.ct` | `<stdlib.h>`（`Arena.h.ct:27`） | libc | 基线 |
| std | `vec/Vec.h.ct` | `.h.ct` | `<stdlib.h>`（`:42`） | libc | 基线 |
| std | `map/Map.h.ct` | `.h.ct` | `<stdlib.h>` `<string.h>`（`:50-51`） | libc | 基线 |
| std | `str/String.m.ct` + `String.shim.h` | `.m.ct` + shim | `<string.h>`（`String.shim.h:30`） | libc | 基线 |
| std | `utf8/Utf8Ops.m.ct` + `Utf8Ops.shim.h` | `.m.ct` + shim | **无**（shim 无 include，纯 C 实现） | 无 | 基线（std 里唯一的零依赖单元） |
| std | `fs/Fs.m.ct` + `Fs.shim.h` | `.m.ct` + shim | `<stdio.h>` `<string.h>` `<dirent.h>` `<sys/stat.h>`（`:35-38`） | libc + **POSIX** | 基线（说明 std 已不是“任何平台可编”） |
| std | `test/Test.h.ct` | `.h.ct` | `<stdio.h>` `<string.h>`（`:24-25`） | libc | 基线 |

> 关键事实：`std` 的 `fs` 模块已经依赖 POSIX（`dirent.h` / `sys/stat.h`）。所以“std 现在是任何平台都能编”这个前提本身只在**不 import `std::fs`** 时成立；模块是惰性的，import 才展开。这削弱了“加 POSIX 模块会毁掉平台中立”的绝对性，但没有削弱“不要给 std 加链接标志”。

### 2.2 clib

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| clib | `clib/Stdio.m.ct` | `.m.ct` | `<stdio.h>`（`:9`）；映射 `puts`/`printf` | libc | 仅 libc，需权衡 → **不迁** |
| clib | `clib/Math.m.ct` | `.m.ct` | `<math.h>`（`:9`）；映射 `sqrt`/`fabs` | **`-lm`**（glibc；macOS/musl 折进 libc） | 仅 libc/libm → **不迁** |
| clib | `clib/Str.m.ct` | `.m.ct` | `<stdlib.h>`（`:19`）；映射 `atoi`/`atof` | libc | 仅 libc → **吸收进 `std::str`** |
| clib | `clib/Num.m.ct` + `Num.shim.h` | `.m.ct` + shim | `<ctype.h>` `<stdlib.h>`（`:20-21`）；shim `<ctype.h>` `<stdio.h>`（`:17-18`），14 个 `static inline`（`snprintf`、`toupper` 等） | libc | 仅 libc → **迁入 `std::num`** |
| clib | `clib/Real.m.ct` + `Real.shim.h` | `.m.ct` + shim | `<math.h>`（`:13`）；shim `<stdio.h>`（`:13`），`ct_double_to_str` | **`-lm`** + libc | 仅 libc/libm → **不迁** |

证据补充：`clib/ct.pkg` 的 `ldflags = -lm` 是包级的，不分模块。`Num.shim.h` 的 14 个函数全部是 `static inline`，展开后只调 `snprintf` / `ctype` 宏，无第三方符号。

### 2.3 zlib

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| zlib | `zlib.m.ct` + `zlib.shim.h` | `.m.ct` + shim | `<zlib.h>`（`zlib.m.ct:18`、`zlib.shim.h:21`）；`zt_deflate_init` / `zt_inflate_init` 调 `deflateInit` / `inflateInit` | `-lz` | 必须第三方 → 留 |
| zlib | `Stream.h.ct` | `.h.ct` | `<stdlib.h>` `<zlib.h>`（`:21-22`） | `-lz` | 必须第三方 → 留 |
| — | `test/demo.ct` | fixture | `<zlib.h>` | `-lz` | 测试，不参与迁移 |

### 2.4 png

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| png | `Png.m.ct` + `Png.shim.h` | `.m.ct` + shim | `<png.h>` `<stdlib.h>` `<string.h>`（`Png.shim.h:4-6`） | `-lpng -lz` | 必须第三方 → 留 |
| png | `Image.h.ct` | `.h.ct` | `<stdlib.h>`（`:1`）+ `import png::Png;`（`:2`） | 经 Png 需要 `-lpng -lz` | 必须第三方（传递）→ 留 |
| — | `demo/main.ct` | fixture | `<stdio.h>` 等 | — | 测试，不参与迁移 |

### 2.5 sqlite

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| sqlite | `Db.h.ct` | `.h.ct` | `<sqlite3.h>`（`:11`） | `-lsqlite3` | 必须第三方 → 留 |
| sqlite | `Stmt.h.ct` | `.h.ct` | `<sqlite3.h>`（`:11`） | `-lsqlite3` | 必须第三方 → 留 |
| sqlite | `sqlite/Sqlite.m.ct` + `Sqlite.shim.h` | `.m.ct` + shim | `<sqlite3.h>`（`Sqlite.m.ct:16`、`Sqlite.shim.h:14`） | `-lsqlite3` | 必须第三方 → 留 |

### 2.6 net-posix

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| net-posix | `net/net.m.ct` + `net.shim.h` | `.m.ct` + shim | `<arpa/inet.h>` `<errno.h>` `<netinet/in.h>` `<string.h>` `<sys/socket.h>` `<sys/types.h>`（`:27-32`） | libc（POSIX socket）；另需 `cflags = -D_POSIX_C_SOURCE=200809L` | 仅 POSIX，需权衡 → **不迁** |
| net-posix | `net/Socket.h.ct` | `.h.ct` | 无 include，但 `import net::net;`（`:20`） | 同上（传递） | 仅 POSIX（传递）→ **不迁** |

### 2.7 hal

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| hal | `Uart.h.ct` | `.h.ct`，`pub trait Uart`（`:14`） | 无 | 无 | **零依赖**，但 **不迁**（契约包） |
| hal | `Gpio.h.ct` | `.h.ct`，`pub trait Gpio`（`:13`） | 无 | 无 | 同上 |
| hal | `Clock.h.ct` | `.h.ct`，`pub trait Clock`（`:12`） | 无 | 无 | 同上 |
| hal | `Log.h.ct` | `.h.ct`，`pub trait Log`（`:13`） | 无 | 无 | 同上 |
| — | `examples/fake-uart/*` | 示例（`.h.ct` + `.ct`） | `<stdio.h>` | libc | 示例，不参与迁移 |

### 2.8 hal-posix

| 包 | 模块/单元 | 实现形态 | 外部依赖 | 链接需求 | 判定 |
| --- | --- | --- | --- | --- | --- |
| hal-posix | `PosixHal.h.ct` | `.h.ct` | `<unistd.h>` `<time.h>`（`:16-17`）；`import Uart/Gpio/Clock/Log` | libc（POSIX）；`cflags = -D_POSIX_C_SOURCE=200809L` | 仅 POSIX，需权衡 → **不迁** |

---

## 3. 建议迁的

### 3.1 先纠正一个前提：clib 没有“零外部依赖”模块

五个单元逐个 `#include` 了 `<stdio.h>` / `<stdlib.h>` / `<ctype.h>` / `<math.h>`（见 2.2 表）。按本文档的机械规则，“零依赖可整块迁”的集合是**空集**；全景里唯一的零依赖单元是 std 自己的 `utf8`（已在内）和 hal 的四个 trait（不属于标准库）。

所以下面不是“搬模块”，而是两处**吸收**——它们都落在“仅 libc”档，但都**不引入 `-l`**，满足第 1 节的硬边界。

### 3.2 吸收一：`clib::Str` 的两个方法 → `std::str::String`

| 项 | 结论 |
| --- | --- |
| 落点 | `std/str/String.m.ct` 的 `pub trait String` 增加 `int toInt(); double toDouble();`，映射到 `atoi` / `atof`（与 clib 现行语义一致） |
| 新增 include | `<stdlib.h>`（现在只有 shim 里的 `<string.h>`） |
| 撞名 | 无。`grep 'toInt\|toDouble' std/**/*.ct` 零命中（本次实测） |
| 调用点 | 0 个有效调用点（见 3.4） |
| import 影响 | 不需要新增 import：用户本来就 import `std::str::String` |
| 链接 | 不变（`atoi`/`atof` 在 libc） |

### 3.3 吸收二：`clib::Num` → 新模块 `std::num`

| 项 | 结论 |
| --- | --- |
| 落点 | 新建 `std/num/Num.m.ct` + `std/num/Num.shim.h`，命名空间 `std::num`；整体搬 `Num` / `Long` / `LLong` 三个 trait 与 14 个 `static inline` |
| 撞名 | 无。std 现有模块目录只有 `arena fs map str test utf8 vec`；没有 `num`，也没有 `abs/clamp/min/max` 之类整型扩展 |
| 调用点 | 0 个有效调用点（见 3.4） |
| import 影响 | 老代码从 `import clib::Num;` 改成 `import std::num;`；方法拼写不变（`v.clamp(1, 9)`） |
| 链接 | 不变（shim 只用 `snprintf` / `ctype`，libc） |
| 与 `std::str` 的关系 | 独立模块，不互相 import；`toStr` 返回 `char *`，可直接喂给 `std::str::String` 的方法 |

### 3.4 调用点影响面（实测）

在 `/Users/samxx/vscspace` 下（排除 `ct-pkg/`）对 `*.ct` 检索 `clib::`，结果**只有 1 个文件**：

```
/Users/samxx/vscspace/ct/examples/wave1-demo/src/main.ct
    import clib::String;   ← clib 1.0.0 之后已不存在这个单元
    import clib::Stdio;
    import clib::Math;
```

也就是说：**当前工作区没有任何**使用 `clib::Str` / `clib::Num` 的代码；唯一一处引用还是坏的（`clib::String` 在 v1.0.0 工作树里已被删除）。这次删除的真实破坏面是 0，代价只是顺手修掉这个示例。

### 3.5 兼容转发：不可行，只能一次性删除

教科书做法是让 clib 留一个 `Str` 只含 `toInt`，内部转发到 std。这条路走不通：

- `.m.ct` 的映射（`map trait ... ->`）只能写 C 表达式，**不能写 CT 函数体**，无法调用 `std::str::String` 的方法；
- 即使允许，两个 trait 对同一个宿主（`char *`）映射同名方法，编译器会报 `ambiguous type-host map` 硬错误；
- shim 是 `static inline` C，也调不回 CT 侧。

结论：吸收一旦发生，`clib::Str` / `clib::Num` 必须**同版本删除**，没有过渡态。由于调用点为 0，这是可接受的。

---

## 4. 建议不迁的（逐条说代价）

| 模块 | 技术上的代价 | 判断 |
| --- | --- | --- |
| `clib::Stdio` | 不引入 `-l`，但 API 是 `puts` + `printf(char*, int)`；后者只能打印一个整数。搬进 std 等于把一个做不了格式化的 API 锁进标准库，之后想改又是一次破坏。 | 不迁。等 std 有基于 `String` 的格式化设计再一次性做对，届时可从 clib 删。 |
| `clib::Math` | 要 `-lm`。std 的 `ct.pkg` 目前**没有任何 `ldflags`**；加上以后每个 std 用户（哪怕只用 `std::vec`）的命令行都会多 `-lm`。另外它只是 `sqrt`/`fabs` 两个薄封装，语义为零。 | 不迁。留在 clib，用的人自己付 `-lm`。 |
| `clib::Real` | 同上（`-lm`），且 `isNan`/`isInf` 依赖 `<math.h>` 的宏，`toStr` 依赖 shim 里的 `snprintf`。 | 不迁。 |
| `net-posix` | 不引入第三方库，但把 std 的依赖面从“libc + `fs` 用到的少量 POSIX”扩到“socket 网络栈”，还要求 `-D_POSIX_C_SOURCE=200809L`（`ct.pkg` 里是包级 cflags，会强加给所有 std 用户）；跨平台面明显收窄。 | 不迁。网络本来就该是可选的独立包。 |
| `hal-posix` | POSIX 绑定（`unistd.h`/`time.h`），且它的意义来自实现 `hal` 的 trait。进 std 会让 std 承担“某个平台的 HAL 实现”。 | 不迁。 |
| `hal`（`Uart`/`Gpio`/`Clock`/`Log`） | 零依赖、零链接，机械上完全可迁。但它是**硬件契约包**，和 `hal-posix` 成对发布；搬进 std 会让标准库承担硬件抽象，且 `hal-posix` 的四处 `import Uart/Gpio/Clock/Log` 全部断掉。收益（少一个依赖）远小于语义损失。 | 不迁。 |

关于“std 会从任何平台可编退到 POSIX 平台可编”这条：`std::fs` **已经**依赖 `<dirent.h>` / `<sys/stat.h>`（`std/fs/Fs.shim.h:35-38`），所以这个退步对 fs 已经发生过；但由于 import 是惰性的，不 import `std::fs` 的项目仍然只编到 libc。真正会**无条件**影响所有用户的是包级 `ldflags`，这也是 Math/Real 被否的决定性理由。

---

## 5. 绝对不能迁的

| 包 | 依赖 | 一句话 |
| --- | --- | --- |
| zlib | `<zlib.h>` + `-lz` | 需要装 zlib 开发包。 |
| png | `<png.h>` + `-lpng -lz` | 需要 libpng + zlib；`Image.h.ct` 通过 `import Png` 传递依赖。 |
| sqlite | `<sqlite3.h>` + `-lsqlite3` | 需要 libsqlite3 开发包。 |

如果把它们并进 std，`ct get std` 会连源码一起下载，`ct install` 会把 `-lsqlite3` / `-lpng` 合并进**每个** std 用户的链接命令（`Pkg.h.ct:1276-1299`），只用 `std::vec` 的项目会直接链接失败。

---

## 6. `math` 专项

- 实际 include：`clib/clib/Math.m.ct:9` → `#include <math.h>`；`Real.m.ct:13` 同样是 `<math.h>`，`Real.shim.h:13` 另加 `<stdio.h>`。
- 实际映射：`sqrt` / `fabs`（Math）、`fabsf/sqrtf/floorf/ceilf/roundf` 与 `fabs/sqrt/floor/ceil/round/isnan/isinf`（Real）。
- 链接：`clib/ct.pkg` 写死 `ldflags = -lm`。glibc 下 `sqrt`/`fabs` 在独立的 `libm.so`，必须 `-lm`；macOS 的 libSystem 与 musl 把 libm 折进 libc，**不写也能过**。所以“部分平台需要显式 `-lm`”成立，不能按“libc 自带”处理。
- 结论：`Math`/`Real` 计入“仅 libc/POSIX 档里的 libm 子档”，**不迁**，理由是会给 std 引入包级 `-lm`。

---

## 7. 包机制实测（`dep` vs `requires`）

### 7.1 `requires` 不是包依赖

`pkg_check_requires` 的实现（`Pkg.h.ct:1562-1584`）：去掉可选的 `ct` 前缀后，把剩下的字符串当**版本范围**去比对编译器版本；比对失败只打印警告，返回 0（不影响退出码）。因此：

- `requires = ct >= 0.20.0` ✔ 正确用法；
- `requires = std@^0.1.0` ✘ 会被当成范围解析失败，静默给出错误结论（“requires 'std@^0.1.0', but this is v…”），**不会**触发任何下载。

包与包之间的依赖是 `dep`（`read_manifest`，`Pkg.h.ct:399-408`，可重复，最多 16 条；递归深度上限 8，`Pkg.h.ct:24-27`）。

### 7.2 实测 A：直接依赖 std（本地目录源）

```
$ ct get /Users/samxx/vscspace/ct-pkg/std@^0.1.0
vendored 1 package(s)
$ cat ct.pkg
dep = /Users/samxx/vscspace/ct-pkg/std@^0.1.0
$ cat ct.lock
std 0.1.0 dir /Users/samxx/vscspace/ct-pkg/std sha256:2e205b25…
$ ct install
ctc: package 'std' requires 'ct >= 0.20.0', but this is v0.19.1
ct build -I vendor/std <unit>.ct -o build
```

### 7.3 实测 B：传递依赖（clib 副本 `dep = std`）

```
$ ct get /tmp/.../clib2@^1.0.0
vendored 2 package(s)
$ cat ct.lock
std  0.1.0 dir /Users/samxx/vscspace/ct-pkg/std sha256:2e205b25…
clib 1.0.0 dir /tmp/.../clib2            sha256:489f474c…
$ ct install
ctc: package 'std' requires 'ct >= 0.20.0', but this is v0.19.1
ct build -I vendor/std -I vendor/clib --ldflags '-lm' <unit>.ct -o build
```

- 顺序：**依赖先于使用者**（`get` 先递归依赖，再把父包复制进 `vendor/`，`Pkg.h.ct:941-948`），所以 `-I vendor/std` 在 `-I vendor/clib` 前面；
- `ct install` 只为**根项目的直接依赖**校验 lock（`Pkg.h.ct:1257-1272`），但会为 **lock 里的每一条** 打印 `-I` 并合并其 flags（`:1276-1299`）；
- 用这条命令编译同时 import 两个包的程序，实测通过并运行正确。

### 7.4 对本次迁移的含义

- 若 clib 保留的模块将来要用 std（例如高层封装），`dep = std@^0.2.0` 现在就能用，无需改工具。
- 本次吸收后，clib 2.0.0 剩下的 `Stdio` / `Math` / `Real` **不 import std**，因此**不需要**加这条依赖；加了只会让所有 clib 用户被迫多装一个包。
- 转发层不可行（3.5），所以也不存在“clib 依赖 std 来保兼容”的选项。

---

## 8. 版本与索引

### 8.1 clib 的版本债

工作树相对 `v1.0.0` 的实际改动（`git status`）：

```
 M README.md
 D clib/String.m.ct        ← v1.0.0 的 clib::String 被删除
 M ct.pkg
?? clib/Num.m.ct  Num.shim.h  Real.m.ct  Real.shim.h  Str.m.ct
```

`clib::String` 的删除本身就是破坏性变更，按 semver 下一版已经是 **2.0.0**，不是 1.x。因此本次再删 `Str` / `Num` **不会额外增加版本成本**：建议一次性合成 `clib 2.0.0 = { Stdio, Math, Real }`，不补发一个没人用的中间版本。`v1.0.0` tag 保留，需要 `clib::String` 的人仍可取到。

### 8.2 std 的版本

`0.1.0 → 0.2.0`：纯新增（`String.toInt/toDouble`、`std::num`），对现有 std 用户无破坏。0.x 允许 minor 破坏，但这次不需要。

### 8.3 发布顺序

```
std v0.2.0  →  clib v2.0.0  →  index refresh
```

先让 `toInt/toDouble` 在 std 里可用，再删 clib 的旧拼写，避免出现“两边都没有”的窗口。两个包各自打 tag、各自进索引；它们的发布节奏**不因为这次吸收而绑定**（没有 `dep` 边）。

### 8.4 索引只有最高 tag 的后果

`refresh-index.sh` 每个仓库只收最高 `v*` tag。因此：

- std 发了 `0.2.0` 之后，`ct get std@^0.1.0` 在索引里**解析不到**（`^0.1.0` 不允许 0.2.0）；想要 0.1.0 只能用 `file://` 或本地目录源；
- clib 发了 `2.0.0` 之后，`ct get clib@^1.0.0` 同样解析不到，`v1.0.0` 只剩 git 历史里的 tag。

结论：**发版即不可回退到旧版本（通过索引）**，所以 0.2.0 / 2.0.0 必须在功能和文档上定稿再打 tag。索引限制本身不会因为这次拆分母块而放大——不合并成一个大包，反而保住了两套版本号各自演进的能力。

---

## 9. 可直接执行的迁移清单

### 9.1 std（目标 `v0.2.0`）

1. `std/str/String.m.ct`：在 `pub trait String` 末尾加 `int toInt();`、`double toDouble();`，并在映射块加 `toInt(s) -> atoi(s);`、`toDouble(s) -> atof(s);`；prologue 增 `#include <stdlib.h>`。
2. 新建 `std/num/Num.m.ct` 与 `std/num/Num.shim.h`：从 `clib/clib/` 原样搬入，`namespace clib;` 改 `namespace std::num;`（trait 名 `Num`/`Long`/`LLong` 不变）。
3. 测试：
   - `tests/str/` 增加 `"42".toInt()`、`"3.5".toDouble()` 两个断言；
   - 新建 `tests/num/` fixture（`clamp`/`min`/`max`/`toStr`/`toBase` 至少各一条）；
   - `tests/run.sh` 的模块布局检查要加 `num`（当前是 7 个目录，变 8 个），通过数从 10 变 11。
4. 文档：`std/README.md` 模块表加 `num`，`std/str` 的 README/tutorial 补两个方法；`ct.pkg` 版本改 `0.2.0`。
5. 打 `v0.2.0`，走一次 `refresh-index`。

### 9.2 clib（目标 `v2.0.0`）

1. 删除 `clib/clib/Str.m.ct`、`clib/clib/Num.m.ct`、`clib/clib/Num.shim.h`。
2. `ct.pkg` 版本改 `2.0.0`；`ldflags = -lm` **保留**（Math/Real 还要）。
3. README / `docs/tutorial.md` 删掉 Str/Num 章节，改为一句“已并入 `std::str` / `std::num`，见 std 0.2.0”。
4. 不添加 `dep = std`。
5. 打 `v2.0.0`，等 std 0.2.0 已进索引后再 `refresh-index`。

### 9.3 不在本次范围

- 修 `ct/examples/wave1-demo/src/main.ct`（它 import 的 `clib::String` 早已不存在）——ct 侧动作，单独安排。
- `clib::Stdio` 的迁移：等 std 有格式化 API 后另开一轮。
- ct 仓库的 `std/` 删除与 `install.sh` / `check-all.sh`：ct 侧收尾，本包不动。

---

## 10. 证据索引

| 事实 | 位置 |
| --- | --- |
| `ct install` 为每个 lock 条目打印 `-I`、合并 cflags/ldflags | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1276-1299` |
| `ct install` 只校验根项目直接依赖 | `Pkg.h.ct:1257-1272` |
| `dep` 是包依赖、可重复 | `Pkg.h.ct:399-408` |
| 依赖先于父包入 lock（`-I` 顺序） | `Pkg.h.ct:941-948` |
| `requires` 只比对编译器版本、仅告警 | `Pkg.h.ct:1562-1584` |
| 依赖上限 16、深度 8 | `Pkg.h.ct:24-27` |
| clib 单元 include 列表 | `clib/clib/{Stdio,Math,Str,Num,Real}.m.ct`、`Num.shim.h`、`Real.shim.h` |
| 第三方包 include 与 `-l` | `zlib/zlib/zlib.shim.h:21`、`png/png/Png.shim.h:4`、`sqlite/sqlite/Sqlite.shim.h:14`、各包 `ct.pkg` |
| std 的 POSIX 依赖 | `std/std/fs/Fs.shim.h:35-38` |
| 全工作区 clib 调用点 = 1 个（且已坏） | `ct/examples/wave1-demo/src/main.ct` |
