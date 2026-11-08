# ct-pkg OO 覆盖率盘点

统计口径（可复现）：

- 统计范围：各包的模块单元（`std/std/**`、`hal/hal/**`、`hal-posix/**`、`zlib/**`、`png/**`、`sqlite/**`、`net-posix/**`、`sql/**`），不含 `tests/`、`demo.ct`、`examples/`。
- `trait` 方法数 = 各单元 `pub trait { … }` 块里的方法声明条数。
- 自由函数数 = `grep -rn '^pub [a-z]' --include='*.ct' --include='*.h.ct'` 中不属于 `pub trait` / `pub struct` 的行。
- **对外能力总数 = trait 方法 + 自由函数**；**OO 覆盖率 = trait 方法 / 能力总数**。

盘点时间：2026-11-06。复核时间：2026-11-07（按当前实现全表重算；当日 sql 包补齐 CRUD 后纳入统计）。`clib/` 目录已删除，`Stdio` 已并入 `std::io`，本文不再单列 clib。

## 1. 总表

| 包 | 模块 | 对外形态 | trait 方法 | 自由函数 | 能力总数 | OO 覆盖率 |
| --- | --- | --- | ---: | ---: | ---: | --- |
| std | `str` / `String`（映射式 + `String.shim.h`） | OO（类型宿主 `char *`） | 15 | 0 | 15 | 15/15 |
| std | `fs` / `FsOps`（映射式 + `Fs.shim.h`） | OO（类型宿主 `char *`） | 4 | 0 | 4 | 4/4 |
| std | `utf8` / `Utf8Ops`（映射式 + `Utf8Ops.shim.h`） | OO（类型宿主 `char *`） | 3 | 0 | 3 | 3/3 |
| std | `vec` / `VecIntOps` + `VecStrOps` | 原生 OO（`.h.ct`） | 12 | 0 | 12 | 12/12 |
| std | `map` / `MapStrIntOps` + `MapIntPtrOps` | 原生 OO（`.h.ct`） | 12 | 0 | 12 | 12/12 |
| std | `arena` / `ArenaOps` | 原生 OO（`.h.ct`） | 4 | 0 | 4 | 4/4 |
| std | `test` / `TestOps` | 原生 OO（`.h.ct`） | 5 | 0 | 5 | 5/5 |
| std | `num` / `Int` + `Long` + `LLong` + `Char`（映射式 + `Num.shim.h`） | OO（类型宿主） | 28 | 0 | 28 | 28/28 |
| std | `math` / `Math` + `Float` + `Real`（映射式 + `Real.shim.h`） | OO（命名空间 / 类型宿主） | 16 | 0 | 16 | 16/16 |
| std | `io` / `Stdout` + `Path` + `File`（映射式 + `Io.printf`） | OO（命名空间 / 类型宿主）+ 1 个自由函数 | 8 | 1 | 9 | 8/9 |
| **std 小计** | | | **107** | **1** | **108** | **107/108** |
| hal | `Uart` / `Gpio` / `Clock` / `Log` | 原生 OO（纯 trait） | 6 | 0 | 6 | 6/6 |
| **hal 小计** | | | **6** | **0** | **6** | **6/6** |
| hal-posix | `PosixHal`（3 个 `map trait … for instance posix_hal`）+ `GpioName`（`char *`） | 原生 OO（实例映射）+ 映射式 | 7 | 0 | 7 | 7/7 |
| **hal-posix 小计** | | | **7** | **0** | **7** | **7/7** |
| zlib | `zlib.m.ct` / `Init` + `Codec` + `Buffer` + `Text` | OO（类型宿主 `z_stream *` / `char *`） | 11 | 0 | 11 | 11/11 |
| png | `Png.m.ct` / `Api` + `Handle` + `PathImage` | OO（命名空间 + `PngReader *` + `char *`） | 17 | 0 | 17 | 17/19 |
| png | `Image.h.ct` | **纯函数式**（`pub fn`） | 0 | 2 | 2 | |
| sqlite | `Sqlite.m.ct` / `Conn`+`Statement`+`Binding`+`Column`+`Lib`+`DbPath`（映射式 + 薄包装结构体保幂等） | OO（类型宿主 `SqliteDB *` / `SqliteStmt *` / `char *` + 命名空间入口） | 29 | 0 | 29 | 29/29 |
| net-posix | `net.m.ct` / `Net` + `Sock.m.ct` / `Sock` + `Addr.m.ct` / `Addr` | OO（命名空间 + `NetSocket *` + `char *`） | 22 | 0 | 22 | 22/32 |
| net-posix | `Socket.h.ct` | **纯函数式**（`pub fn`） | 0 | 10 | 10 | |
| **四个绑定包小计** | | | **79** | **12** | **91** | **79/91** |
| sql | `Sql.m.ct` / `Entry` + `Select` + `Insert` + `Update` + `Delete`（纯 CT 库，语义在 `Sql.shim.c`） | OO（`char *` 入口 + 4 个命名 struct 句柄） | 75 | 0 | 75 | 75/75 |
| **sql 小计** | | | **75** | **0** | **75** | **75/75** |
| **全仓合计** | | | **274** | **13** | **287** | **274/287** |

> 注：`clib/` 已不存在，旧表里的 clib 2/2 不再单列；`Stdio` 已并入 `std::io`，计入 std 的 `io` 行。
>
> sql 的归属：它**不是绑定包**——不链接任何系统库（`sql/ct.pkg` 无 `ldflags`、无 `cflags`，`requires = ct >= 0.20.3`），
> SQL 文本构建语义由包自己的 `sql/sql/Sql.shim.c` 实现。因此它单列为“纯 CT 库”，**不计入四个绑定包小计**，
> 只在全仓合计里相加：trait 199 + 75 = 274，能力 212 + 75 = 287。

### 1.1 每个数字的来源

**std**

- `str`：`std/std/str/String.m.ct` 的 `String` trait，15 个方法 → 15/0/15。
- `fs`：`std/std/fs/Fs.m.ct` 的 `FsOps` trait，4 个方法 → 4/0/4。
- `utf8`：`std/std/utf8/Utf8Ops.m.ct` 的 `Utf8Ops` trait，3 个方法 → 3/0/3。
- `vec`：`std/std/vec/Vec.h.ct`，`VecIntOps` 6 + `VecStrOps` 6 = 12 → 12/0/12。
- `map`：`std/std/map/Map.h.ct`，`MapStrIntOps` 6 + `MapIntPtrOps` 6 = 12 → 12/0/12。
- `arena`：`std/std/arena/Arena.h.ct` 的 `ArenaOps` trait，4 个方法 → 4/0/4。
- `test`：`std/std/test/Test.h.ct` 的 `TestOps` trait，5 个方法 → 5/0/5。
- `num`：`std/std/num/Num.m.ct`，`Int` 7 + `Long` 7 + `LLong` 7 + `Char` 7 = 28 → 28/0/28。
- `math`：`std/std/math/Math.m.ct` 的 `Math` 2 + `std/std/math/Real.m.ct` 的 `Float` 5 + `Real` 9 = 16 → 16/0/16。
- `io`：`std/std/io/Stdout.m.ct` 的 `Stdout` 4 + `std/std/io/File.m.ct` 的 `Path` 1 + `File` 3 = 8 个 trait 方法；`std/std/io/Io.h.ct` 的 `pub int printf(...)` 为 1 个自由函数 → 8/1/9。
- **std 小计**：15+4+3+12+12+4+5+28+16+8 = **107**；自由函数 1；总数 108；覆盖率 107/108。

**hal / hal-posix**

- hal：`hal/hal/Uart.h.ct` 的 `Uart` 2 + `hal/hal/Gpio.h.ct` 的 `Gpio` 2 + `hal/hal/Clock.m.ct` 的 `Clock` 1 + `hal/hal/Log.h.ct` 的 `Log` 1 = **6** → 6/0/6。
- hal-posix：`hal-posix/PosixHal.h.ct` 的 `Uart` 2 + `Gpio` 2 + `Log` 1 = 5（instance 映射）+ `hal-posix/GpioName.m.ct` 的 `GpioName` 2 = **7** → 7/0/7。

**四个绑定包**

- zlib：`zlib/zlib/zlib.m.ct`，`Init` 2 + `Codec` 4 + `Buffer` 2 + `Text` 3 = **11**；`Stream.h.ct` 已删除，自由函数 **0** → 11/0/11。
- png：`png/png/Png.m.ct`，`Api` 9 + `Handle` 6 + `PathImage` 2 = **17**；`png/png/Image.h.ct` 的 `open_file` + `write_file` = **2** 个自由函数 → 17/2/19。`Handle` 挂在 `PngReader *`（`void *` 已不再被映射），`PathImage` 挂在 `char *`。
- sqlite：`sqlite/sqlite/Sqlite.m.ct`，`Conn` 8 + `Statement` 4 + `Binding` 4 + `Column` 7 + `Lib` 5 + `DbPath` 1 = **29**；自由函数 **0** → 29/0/29。`DbPath` 是 `char *` 宿主上的 `openSqliteDb`（`Sqlite.m.ct:82-84` 声明，`130-132` 映射）。
- net-posix：`net-posix/net/net.m.ct` 的 `Net` 10 + `net-posix/net/Sock.m.ct` 的 `Sock` 10 + `net-posix/net/Addr.m.ct` 的 `Addr` 2 = **22**；`net-posix/net/Socket.h.ct` 的 `socket_*` 自由函数 **10** → 22/10/32。
- **四个绑定包小计**：trait 11+17+29+22 = **79**；自由函数 0+2+0+10 = **12**；总数 91；覆盖率 79/91。

**sql（纯 CT 库，不计入四个绑定包）**

- sql：`sql/sql/Sql.m.ct`，`Entry` 4 + `Select` 20 + `Insert` 15 + `Update` 19 + `Delete` 17 = **75** 个 trait 方法；自由函数 **0** → 75/0/75。`Entry` 挂在 `char *`（`select` / `insert` / `update` / `delete` 四个入口），`Select` / `Insert` / `Update` / `Delete` 分别挂在 `struct sql_Select *` / `struct sql_Insert *` / `struct sql_Update *` / `struct sql_Delete *`；`sql/ct.pkg` 无 `ldflags`，构建语义在 `Sql.shim.c`，因此不并入绑定包小计。链式 bind 改造（0.2.0）后每类语句多了 `bind*` 定参方法，`sql_*` 映射条目合计 75，与 `tools/check-char-host.sh` 的输出一致。

**全仓**

- 合计：trait 107(std) + 6(hal) + 7(hal-posix) + 79(绑定包) + 75(sql) = **274**；自由函数 1 + 0 + 0 + 12 + 0 = **13**；能力总数 **287**；覆盖率 **274/287**。

## 2. clib：迁移前 / 迁移后

`clib/` 目录已删除；`Stdio` 已并入 `std::io`。本节保留 2.0.0 迁移时的历史对照，当前计数以 §1 为准。

上一轮问题里提到的 clib 旧状态，先纠正一处事实：**`Num` 不是纯函数式**。它在 `clib/Num.m.ct` 里是
`map trait Num for type int`，14 个方法全部是 trait 方法（映射式 OO）；`Long` / `LLong` 同理。
真正纯函数式的只有后来那几个绑定包的 `.h.ct`。

| 模块（2.0.0 之前） | 对外形态 | trait 方法 | 自由函数 | 说明 |
| --- | --- | ---: | ---: | --- |
| `String` | 已删除（1.0.0 → 工作树） | 0 | 0 | `strlen` / `strcmp` / `memcpy` |
| `Str` | OO（类型宿主 `char *`） | 2 | 0 | 只剩 `toInt` / `toDouble` |
| `Num` | OO（类型宿主 `int`） | 14 | 0 | 接收者是 `int`，所有整数都长方法 |
| `Long` / `LLong` | OO（类型宿主 `long` / `long long`） | 6 | 0 | 各 3 个 |
| `Math` | OO（命名空间宿主） | 2 | 0 | `sqrt` / `fabs` |
| `Float` / `Real` | OO（类型宿主 `float` / `double`） | 14 | 0 | 5 + 9 |
| `Stdio` | OO（命名空间宿主） | 2 | 0 | `puts` / 单值 `printf` |

迁移后（2.0.0）：`Math` → `std::math::Math`，`Float`/`Real` → `std::math`，`Num`/`Long`/`LLong` →
`std::num`，`Str.toInt/toDouble` → `std::str::String`。`Num` 的 `int` 宿主一度被拆成 `Long`/`LLong`
（整数）和 `Char`（ctype）；2026-11-07 用户裁决取消 `int` 宿主禁令后，当前 `std::num` 重新包含
`Int` → `int`（7 个方法，见 §1）。clib 一度只剩 `Stdio` 2 个方法，后续 `Stdio` 已并入 `std::io`
（`Stdout` 4 个 trait 方法 + `Io.printf` 1 个自由函数），`clib/` 目录已删除。

## 3. 「应该 OO 化」的统一标准

ct-pkg 里的包不应套同一条规则。按 std 已经跑通的两类形态分：

### 3.1 映射式：给已存在的 C 能力加方法外壳

适用条件（三条同时满足）：

1. 能力**已经存在**于 C 库或系统头文件里，包不实现语义；
2. 接收者是 C 的标量或指针（`int`、`char *`、`double`、`long`、`char`）；
3. 每个方法能落成**一个 C 表达式**，写不下的形状放进 `<Trait>.shim.h` 的 `static inline`。

形态：`<Mod>.m.ct` 里 `pub trait` + `map trait … for type/namespace`，`+ <Mod>.shim.h`。
**收益**：调用点零成本、没有 vtable；缺点只有一个——`.m.ct` 不能单独出 C，只能被 import。

### 3.2 原生 OO：包自己持有数据

适用条件：包自己分配/释放内存、维护不变式、有明确生命周期。接收者是自己的 `struct`。

形态：`.h.ct` 里 `trait → struct(use) → impl`，实现留在同文件；方法**必须**是 trait 方法，
不再出口自由 `pub fn`。

### 3.3 纯绑定的边界：不新增 `.h.ct` 包装层

**判断依据变更（2026-11-07）**：本节原先把 sqlite 归入“不该 OO 化”，依据是 agent 自定的
风格判断——认为在既有 `.m.ct` 之上再包一层 `.h.ct` 收益为负。该结论已被用户否决：**OO 是
ct 的目标**。纯绑定模块的正确形态是 §3.1 的映射式类型宿主：`.m.ct` 直接把方法挂到
`SqliteDB *` / `SqliteStmt *` 这类 C 句柄上，生命周期需要兜底时在 shim 里用薄包装
结构体实现（sqlite 的 `close` / `finalize` 幂等就是这样做的）；**不新增 `.h.ct` 包装层**。
sqlite 已按此形态完成改造，§1 / §4 的计数已同步。

仍然成立的边界：

- 纯绑定 OO 化不会让类型系统自动变严；幂等、所有权这类语义必须在 shim 或薄包装结构体里显式
  实现，不能指望类型宿主顺带提供。
- 不要在 `.m.ct` 已有零成本映射的情况下再新增 `.h.ct` 的 trait 层；那是第三套写法，不是 OO 化
  的必要条件。
- `net-posix` / `png` 的剩余自由函数见 §4；是否继续推进由需求侧按“最大程度 OO”决定，本文
  不再预设“纯绑定不该 OO 化”的通用结论。

## 4. 逐包判定：还差多少活

> 本节数字均沿用 §1.1 的逐文件来源，不再重复。

| 包 | 该走哪类 | 现状 | 还差的活 |
| --- | --- | --- | --- |
| std | 映射式（str/fs/utf8/num/math/io）+ 原生 OO（vec/map/arena/test） | 107/108 | **0 个可执行项**。唯一自由函数是 `std::io::printf`：变参入口，当前 CT 的映射 recipe 无法转发变参，保持自由函数并在 §1 登记 |
| hal | 原生 OO（纯接口声明） | 6/6 | **0**；实现不在本包 |
| hal-posix | 原生 OO（实例映射）+ 映射式（`char *`） | 7/7 | **0** |
| zlib | 映射式 | 11/11 | **0**；`Stream.h.ct` 已删除，原 5 个自由函数已并入 `Buffer` / `Text` trait |
| png | 映射式 + 工厂函数 | 17/19 | **2 个**：`Image.h.ct` 的 `open_file` / `write_file`。它们与 `PathImage` 的 `readImage` / `writeImage` 重复，可评估删除或改为方法；是否推进由需求侧决定 |
| sqlite | 映射式（类型宿主 `SqliteDB *` / `SqliteStmt *` / `char *`；薄包装结构体保 `close` / `finalize` 幂等） | 29/29 | **0**，已完成 |
| net-posix | 映射式 + 自由函数 | 22/32 | **10 个**：`Socket.h.ct` 的 `socket_open` / `socket_bind` / `socket_listen` / `socket_accept` / `socket_connect` / `socket_send` / `socket_recv` / `socket_close` / `socket_err` / `socket_error_text`。`Sock` trait 已提供 `NetSocket *` 宿主；是否把这 10 个搬到类型宿主由需求侧决定 |
| sql | 映射式（`char *` 入口 + 4 个命名 struct 句柄；语义在包内 C shim） | 75/75 | **0**，已完成 |

### 结论

- **已完成 OO 化**：std 107/108（唯一例外是变参 `std::io::printf`）、hal 6/6、hal-posix 7/7、
  zlib 11/11、sqlite 29/29、sql 75/75。
- **真剩余项**：net-posix 10 个自由函数（`Socket.h.ct`）+ png 2 个自由函数（`Image.h.ct`），
  合计 12 个。
- 全仓：**274 个 trait 方法 / 13 个自由函数 / 287 个能力**，OO 覆盖率 **274/287**。
- sqlite 已证明纯绑定可以走 §3.1 的映射式类型宿主完成 OO 化，不需要新增 `.h.ct` 层；剩余 12 个
  自由函数是否推进，由需求侧按“最大程度 OO”决定，不再预设“纯绑定不该 OO 化”的结论。
