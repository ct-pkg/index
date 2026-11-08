> **过期提示**：本文为某时点的历史记录，其中的数量与接口已过时，现状见 [docs/std-oo-coverage.md](std-oo-coverage.md)。

# Phase 2 计划（草案）：生态 Wave 2 · 真实 C 库映射包（SQLite 首发）

> 中文 · [English](#english)
>
> **状态：规划中（草案，待用户确认）** · 拟议版本：`v0.20.0`
> 前置：[Phase 18](../../../ct/docs/design/phase18.md) 的包规范 / 索引 / CI 门禁与 [Phase 19](../../../ct/docs/design/phase19.md) 的 `ct check`；
> 本阶段**不改语言、不改编译器行为**，只新增外部包、探针与 CI 门禁。
> 本文件只记录计划，不描述现状；现状见 [README](../../../ct/README.md) 与 [language-spec](../../../ct/docs/language-spec.md)。
>
> **阶段编号说明：本项目阶段编号自成体系（Phase 2），与 ct-lang 的 phase 编号无关；文中 `v0.20.0` 是 ct 编译器的拟议版本串，不是阶段号。**

---

## 中文

### 1. 目标与出口

| 项 | 内容 |
| --- | --- |
| 目标 | 一次纳入四个**系统自带**的真实 C 库映射包——`sqlite`（首发）、`zlib`、`png`、`net-posix`——固化「真实库映射包」的三层规范（`.m.ct` 零成本面、C shim 适配面、`.h.ct` 所有权面），并验证 `dep` 依赖链（`png → zlib`）与多包 CI 复用 |
| 出口 | 四个包经索引收录，`ct get` → `ct verify` → `ct install` 打印的命令 → 编译运行在**宿主**（macOS arm64 / Linux x86_64）与**目标机**（Linux aarch64 + QEMU）输出一致；raw 层生成物**零 wrapper**；`ct build` 无语义 warning + C 编译器 `-Wall -Wextra` 零警告 + demo 实跑输出符合预期；`ct check` 仅作为**无 import 的单文件单元**的可选附加项；12 道本地硬门禁不变 |
| 版本 | **Phase 2 ↔ `v0.20.0`**（D2-1，待确认）；阶段内不 bump |
| 回退 | 包、demo、CI job 与索引行全部是新增面；删除即回退，编译器零改动 |

### 2. 非目标

- **不做 C 头自动解析 / bindgen**（属独立工具议题，见 [评估报告](../../../ct/docs/history/reports/evaluation-2026-11-03-v0181/evaluation-2026-11-03-v0181.md) 的 S6）。
- **不纳入系统未自带的库**（cJSON / jansson、mbedTLS、OpenSSL、libuv、SDL2 / raylib / GLFW、FreeType、miniaudio、zstd / lz4、libwebp、PCRE2 等）：当前包模型**不编译随包 C 源码**，只声明并链接系统库；是否允许 vendored 需单独立项（D2-12）。
- 不包装 SQLite 的全部 API：虚拟表、session、serialize、16 位接口、负载扩展等留待按需增补。
- `png` 只做**简化 API**（`png_image`），不覆盖依赖 `setjmp` 的完整读写 API。
- 不做 ORM、不解析 SQL、不做连接池、不做线程封装。
- **不 vendored / 不内置上游源码或 amalgamation**：链接系统 `libsqlite3` / `libz` / `libpng` / POSIX socket（D2-5、D2-11）。
- 不引入跨单元 `Drop`，不新增语言特性，不改 L0 / L1 / L2 / ct-ast 的行为。
- 不做 Windows；不新增本地硬门禁（沿用 Phase 18 的 D18-8 口径）。

### 3. 现状与约束（已实测）

| 约束 | 事实 | 出处 |
| --- | --- | --- |
| 映射单元 | `.m.ct` 零产物、零 wrapper；只允许 `#include` / `#define` / `import` / `pub trait` / `map` / `_Static_assert` | [batch38 §3.5、§5](../../../ct/docs/history/design/batch38-map-unit/spec.md) |
| 静态 trait | 不能 `impl`、不能进 `use`、不能作类型、不能装箱；每个 trait 的方法上限为 64（`MAX_METHODS`） | 同上；[language-spec §4.10](../../../ct/docs/language-spec.md) |
| prologue | `#include` / `#define` 只展开进**消费者 `.c` 顶部**，**不进 `.h`** | [batch38 §6.5](../../../ct/docs/history/design/batch38-map-unit/spec.md) |
| shim | `<base>.shim.h` / `<base>.shim.c` 与 `<base>.m.ct` 同目录同名；编译器自动 `#include` 并加 `-I`；同名跨目录硬报错 | [batch39](../../../ct/docs/history/design/batch39-shim-layer/spec.md) |
| C 宏常量 | **全大写**标识符在表达式里按原样发射（`SQLITE_ROW`、`SQLITE_TRANSIENT` 可直接用），由 C 预处理器展开 | [Expr.h.ct](../../../ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L1959-L1970) |
| C 类型 | 头文件类型名（`sqlite3`、`sqlite3_stmt`）可作局部 / 参数类型；`const char *`、`void **`、函数指针参数均可用 | [language-spec §4.12、§4.19](../../../ct/docs/language-spec.md)；[std/fs](../../../ct/std/fs/Fs.h.ct)、[std/map](../../../ct/std/map/Map.h.ct) |
| 生命周期 | `Drop` / `Handback` 的发射函数是 `static`，**跨单元不可用** → 包必须暴露显式 `close` / `finalize` | [AGENTS §2](../../../ct/AGENTS.md)；[bindings/README §5](../../../ct/bindings/README.md) |
| 公共头 | 生成的 `.h` 不含 prologue → `.h.ct` 的公共 struct **不得**按值暴露 `sqlite3 *`，句柄一律存 `void *` | [batch38 §6.5](../../../ct/docs/history/design/batch38-map-unit/spec.md) |
| 构建元数据 | `ct.pkg` 的 `cflags` / `ldflags` / `requires` 由 `ct install` 折进一条命令 | [package-guide §2](../../../ct/docs/package-guide.md) |

### 4. SQLite API 面分类

以「应用常用面」为准，分四类；每一类都有明确落点，不留「待定」。

| 类 | 承载 | 覆盖 |
| --- | --- | --- |
| **A. `.m.ct` 直映** | 无外部状态、单次调用的函数 | 连接：`open_v2` / `close_v2` / `errmsg` / `errcode` / `extended_errcode` / `busy_timeout` / `changes` / `total_changes` / `last_insert_rowid` / `get_autocommit` / `libversion` / `errstr` / `free`；语句：`prepare_v2` / `finalize` / `step` / `reset` / `clear_bindings` / `data_count` / `bind_parameter_count` / `stmt_readonly`；绑定：`bind_null` / `bind_int` / `bind_int64` / `bind_double` / `bind_parameter_index`；列：`column_count` / `column_name` / `column_type` / `column_int` / `column_int64` / `column_double` / `column_bytes` / `column_decltype`；value：`value_type` / `value_int` / `value_int64` / `value_double` / `value_bytes` |
| **B. C shim** | recipe 写不出的形状（析构器、窄化、回调、变参） | `bind_text` / `bind_blob`（析构器固定 `SQLITE_TRANSIENT`，另给 `*_static` 用 `SQLITE_STATIC`）；`column_text` / `column_blob`（把 `const unsigned char *` / `const void *` 收窄为 `const char *` / `const void *`）；`exec`（带回调 + `void *userdata`）；`mprintf` / `snprintf`（变参 → 固定参数）；`create_function_v2`（回调 + `userdata`）；`config`（仅在需要 `SQLITE_CONFIG_SERIALIZED` 时提供固定包装） |
| **C. `.h.ct` 所有权面** | 有状态封装、错误翻译、显式生命周期 | `Db`（open / close / errmsg / exec / changes）；`Stmt`（prepare / finalize / step / reset / bind_* / column_* / column_text）；可选只读游标 `Row` |
| **D. 不支持（留待按需）** | 明确拒绝，避免半成品 | 虚拟表 / `create_module`、session、serialize / deserialize、16 位接口、`scanstatus`、`auto_extension`、`load_extension`（安全面单独评估）、Windows |

> 分批原则：**B 与 C 之间不复制语义**——C 层的实现调用 A/B 两层（包内 dogfood），保证零成本面被真实使用。

### 5. 包设计

| 项 | 取值 |
| --- | --- |
| 仓库 / 包名 | `github.com/ct-pkg/sqlite`；`name = sqlite`（仓库名 = 包名） |
| 命名空间 | `sqlite`（包根目录名 = 命名空间，满足「目录 = namespace」） |
| 版本 | 首发 `0.1.0`；API 冻结并补齐目标机验收后升 `1.0.0`（D2-8） |
| 许可证 | `licence = PublicDomain`（上游 SQLite 为公有领域），包内 `LICENSE` 说明「SQLite 公有领域 + 包内 `.ct` 代码 MIT」（D2-10） |
| 链接 | `ldflags = -lsqlite3`；`requires = ct >= 0.17.0`（`ct build` 一步到位与 shim 的前置） |
| 依赖 | 无 `dep`（不依赖 `hal` / `clib`） |

```
ct-pkg/sqlite/
├── ct.pkg
├── LICENSE
├── README.md            # 用法、生命周期、错误码约定
├── sqlite.m.ct          # A 层 + 类型宿主（namespace sqlite）
├── sqlite.shim.h        # B 层（header-only，static inline）
├── Db.h.ct              # C 层：连接所有权
├── Stmt.h.ct            # C 层：语句所有权与读写
├── Value.h.ct           # 可选：value 参数对象（回调场景，struct 名 ValueArg）
└── test/
    ├── demo.ct
    └── demo.expected.out
```

- `sqlite.m.ct` 的 shim 基名是 `sqlite`，因此 shim 头必须是 `sqlite.shim.h`（同目录同名，batch39 硬约束）。
- 所有 `.m.ct` 的 trait 必须 `pub`；`Db` / `Stmt` 的公共 struct 用 `void *h` 存句柄，**不**在头里暴露 `sqlite3 *`。
- A 层按主题拆 trait，避开单 trait 64 方法上限，也避开 Phase 19 的同名方法歧义：
  `Conn` / `Statement` / `Binding` / `Column` / `Value` / `Lib`（trait 名不与 `Db` / `Stmt` 等 struct 重名）。
- 类型宿主（句柄方法）：`map trait Conn for type sqlite3 *` 与 `map trait Statement for type sqlite3_stmt *`；
  调用写法 `db.errmsg()` / `stmt.step()`，展开为 `sqlite3_errmsg(db)` / `sqlite3_step(stmt)`。
- 常量不导入：`SQLITE_OK` / `SQLITE_ROW` / `SQLITE_DONE` / `SQLITE_OPEN_*` 直接以 C 宏使用（D2-6）；
  绝不导出同名 CT 全局（会与头里的宏定义冲突）。

`ct.pkg` 示例：

```ini
name = sqlite
version = 0.1.0
licence = PublicDomain
ldflags = -lsqlite3
requires = ct >= 0.17.0
```

A 层映射示例：

```c
namespace sqlite;
#include <sqlite3.h>

pub trait Conn {
    int  open_v2(const char *path, sqlite3 **out, int flags);
    int  close(sqlite3 *db);
    const char *errmsg(sqlite3 *db);
    int  errcode(sqlite3 *db);
    int  busy_timeout(sqlite3 *db, int ms);
    int  exec(sqlite3 *db, const char *sql);
    int  changes(sqlite3 *db);
    sqlite3_int64 last_insert_rowid(sqlite3 *db);
}

map trait Conn for namespace sqlite {
    open_v2(path, out, flags) -> sqlite3_open_v2(path, out, flags, 0);
    close(db)                 -> sqlite3_close_v2(db);
    errmsg(db)                -> sqlite3_errmsg(db);
    errcode(db)               -> sqlite3_errcode(db);
    busy_timeout(db, ms)      -> sqlite3_busy_timeout(db, ms);
    exec(db, sql)             -> ct_sqlite_exec_plain(db, sql);
    changes(db)               -> sqlite3_changes(db);
    last_insert_rowid(db)     -> sqlite3_last_insert_rowid(db);
}
```

C 层示例（显式生命周期，不依赖 `Drop`）：

```ct
pub struct Db {
    void *h;
}

pub int  db_open(Db *db, const char *path);   /* 失败时 db->h 仍可传给 db_close */
pub void db_close(Db *db);                    /* 幂等：置 h = 0；用 sqlite3_close_v2 */
pub int  db_exec(Db *db, const char *sql);
pub const char *db_errmsg(Db *db);

pub struct Stmt {
    void *h;
    void *db;                                 /* 只用于文档化「先 finalize 再 close」 */
}

pub int  stmt_prepare(Db *db, Stmt *st, const char *sql);
pub void stmt_finalize(Stmt *st);             /* 幂等：置 h = 0 */
pub int  stmt_step(Stmt *st);
pub int  stmt_reset(Stmt *st);
pub int  stmt_bind_int(Stmt *st, int idx, int v);
pub int  stmt_bind_text(Stmt *st, int idx, const char *s, int n);
pub int  stmt_column_int(Stmt *st, int i);
pub const char *stmt_column_text(Stmt *st, int i);
```

### 5.1 其余三个包的映射要点

| 包 | 面 | 要点 |
| --- | --- | --- |
| `zlib` | A 层：`compress` / `uncompress` / `crc32` / `adler32` / `deflate` / `inflate` / `deflateEnd` / `inflateEnd`；shim：`deflateInit_` / `inflateInit_`（上游是宏，需固定 `ZLIB_VERSION` 与 `sizeof(z_stream)`）；`z_stream` 用头文件 struct（[std/fs](../../../ct/std/fs/Fs.h.ct) 的 `struct stat st;` 已证明头文件 struct 可作局部变量） |
| `png` | A 层：`png_image_begin_read_from_file` / `png_image_begin_read_from_memory` / `png_image_finish_read` / `png_image_free`；C 层：`Image` 所有权与 `image_free`；`dep = zlib@^1`；只做简化 API，`setjmp` 完整 API 不做 |
| `net-posix` | A 层：`socket` / `bind` / `listen` / `accept` / `connect` / `send` / `recv` / `shutdown` / `close`（由仓库内 [bindings/posix-socket](../../../ct/bindings/posix-socket/) 提升为包）；C 层：`Socket` 所有权 + `socket_close`；`errno` 是**小写**宏，CT 侧不可见 → shim 提供 `ct_net_last_error()` / `ct_net_strerror(int)` |

三个包共用同一套包骨架与 CI job 模板；差别只在单元数量、shim 内容与 `dep`。

### 6. 切片

| 切片 | 内容 | 主要改动面 | 出口 |
| --- | --- | --- | --- |
| **2.0** | **能力探针与 API 冻结** | `test/ast/**` 新增探针；本文件 §4、§5.1 定稿 | 6 个探针在 `-Wall -Wextra -Werror` 下编译运行通过；任何不可行形状在进入 2.1 前改走 shim，并记入能力账本 |
| **2.1** | **SQLite 包骨架与 A/B 层** | 外部仓库 `ct-pkg/sqlite`：`ct.pkg` / LICENSE / README / `sqlite.m.ct` / `sqlite.shim.h` | 生成物中**零** `sqlite_*` wrapper 符号，只有 `sqlite3_*` 直调；`ct install` 打印的命令含 `-lsqlite3` |
| **2.2** | **SQLite 类型宿主与 C 层** | `sqlite.m.ct` 的类型宿主；`Db.h.ct` / `Stmt.h.ct` | `db.errmsg()` / `stmt.step()` 展开为普通 C 调用；demo 建库→建表→插入→查询→收尾；ASAN + LSAN 干净 |
| **2.3** | **`zlib` 包** | `zlib.m.ct` + `zlib.shim.h` + 可选 `Stream.h.ct` | `compress` / `uncompress` 往返一致；`deflateInit_` 经 shim；生成物零 wrapper |
| **2.4** | **`png` 包（依赖 `zlib`）** | `ct-pkg/png`：`png.m.ct` + `Image.h.ct`，`ct.pkg` 带 `dep = zlib@^1` | 索引能递归解析 `png → zlib`；读一张固定 PNG 得到确定像素并打印；`ct verify` 绿 |
| **2.5** | **`net-posix` 包** | `ct-pkg/net-posix`：`net.m.ct` + `Socket.h.ct` + shim | 本机 `socket` 回环收发一次；显式 `socket_close`；`errno` 经 shim 读取 |
| **2.6** | **demo、CI 与索引** | `examples/sqlite-demo` / `examples/wave2-demo`；`packages.yml` 的 wave2 job 矩阵；`ct-pkg/index` 追加四行 | 四包在宿主与 aarch64/QEMU 端到端绿；`ct verify` 绿；索引可解析 |
| **2.7** | **文档与收口** | 本文件状态、roadmap 中英版本记录、`package-guide` / `bindings/README` 的真实库示例、glossary（如需）、五处 `CTC_VERSION` | `v0.20.0` tag + push |

#### 2.0 能力探针（必须先做，结果决定 2.1 的形状）

| 探针 | 断言 | 不通过时的退路 |
| --- | --- | --- |
| **P1** 头文件类型名 + 类型宿主 | 局部 `sqlite3 *db;` 可声明；`db.errmsg()` 命中 `for type sqlite3 *` | 类型宿主改 `for type void *`，消费侧用 `void *` 句柄（会失去 `sqlite3_stmt *` 区分） |
| **P2** 二级指针出参 | `sqlite3 **out` 作参数；`sqlite::Conn.open_v2(path, &db, flags)` 可编译 | 改 shim `ct_sqlite_open(const char *path, void **out, int flags)`，CT 侧参数为 `void **` 并由 shim 内转 |
| **P3** 函数指针实参 + C 宏 | 静态 trait 参数 `int (*cb)(void *, int, char **, char **)`；调用点传 `SQLITE_TRANSIENT` | 回调改 shim 的固定枚举入口；宏改 shim 访问器（如 `ct_sqlite_transient()`） |
| **P4** `const unsigned char *` 返回 | 直接声明该返回类型时 `-Werror` 不告警 | 由 shim 收窄为 `const char *`（默认方案） |
| **P5** shim 回调 + userdata | `ct_sqlite_exec_cb(db, sql, cb, ud)` 端到端 | 只提供无回调 `exec`，回调场景留待 2.4 之后 |
| **P6** 跨单元 dogfood | `Db.h.ct` `import sqlite;`，消费者再 `import Db`；`ct get file://…` 后 `ct build` 通过 | 拆包为 `sqlite-raw` + `sqlite`（`dep` 引用），但受 `MAX_PKG_DEPS 16` 约束 |

#### 2.1–2.2 SQLite 关键约束

- A 层 recipe **只能是一层调用**；需要析构器 / 窄化 / 变参的一律进 shim，不进 recipe。
- 所有 shim 都是 header-only `static inline`；包内**不**出现 `.shim.c`（避免 `cc` 行多一个源文件与跨平台编译差异）。
- C 层**必须**先 `stmt_finalize` 再 `db_close`；`db_close` 用 `sqlite3_close_v2` 兜底，但文档仍要求在正常路径显式 finalize。
- C 层 `db_open` 失败时也允许 `db_close`（幂等），避免「打开失败还得判断要不要关」的样板。
- 错误码不翻译成枚举，只透传 `sqlite3_errcode` / `extended_errcode` 与 `errmsg`；包不吞错误。

#### 2.6 测试与门禁

- 仓库内 `examples/sqlite-demo`：建库（临时文件）→ 建表 → 插入两行 → 查询 → 打印固定文本 → 关闭；期望输出由真实二进制生成。
- 仓库内 `examples/wave2-demo`：`zlib` 压缩 / 解压往返、`png` 读固定图、`net-posix` 回环收发，一次覆盖三个包。
- `packages.yml` 新增 wave2 job 矩阵（四个包共用一份模板）：
  - 宿主 job：`ct get --index <pkg>` → `ct verify` → 执行 `ct install` 打印的命令 → 运行 demo 比对；
  - 目标机 job：`aarch64-linux-gnu-gcc` + `qemu-aarch64`，CI 里安装 `libsqlite3-dev:arm64` / `zlib1g-dev:arm64` / `libpng-dev:arm64`。
- Linux 宿主 job 需要 `libsqlite3-dev` / `zlib1g-dev` / `libpng-dev`（Ubuntu runner 默认可能只有运行时）；macOS runner 自带 SDK。
- `ct build` 无语义 warning；C 编译器在 `-Wall -Wextra` 下零警告；demo 实跑输出符合预期。`ct check` 仅作为**无 `import` 的单文件单元**的可选附加项（如有 warning，逐条记录理由）。
- **不新增本地硬门禁**：探针挂在既有 `check-ast.sh` / `test/run.sh` 的层里；包门禁留在 CI。

### 7. 顺序与依赖

| 顺序 | 切片 | 理由 |
| --- | --- | --- |
| 1 | 2.0 探针 | 先证明形状可行，避免包写到一半才发现类型 / 回调不可写 |
| 2 | 2.1 SQLite 骨架 + A/B 层 | 零成本面是包的立身之本；先让它单独可验收 |
| 3 | 2.2 SQLite 类型宿主 + C 层 | 依赖 A/B 两层（dogfood），并验证显式生命周期 |
| 4 | 2.3 `zlib` | A 层最短路径；同时验证「宏初始化 → shim」这一形状 |
| 5 | 2.4 `png` | 依赖 2.3 的 `zlib`；验证 `dep` 链与索引递归解析 |
| 6 | 2.5 `net-posix` | 与 2.3 / 2.4 无交集，可并行；验证小写宏 `errno` 的 shim 路径 |
| 7 | 2.6 demo / CI / 索引 | 聚合验收；索引在 CI 生成 |
| 8 | 2.7 收口 | 文档与版本 |

### 8. 版本与发布

- Phase 2 ↔ `v0.20.0`（D2-1）；阶段内不 bump。
- 包自身版本独立：四包均以 `0.1.0` 首发，API 冻结并过目标机后升 `1.0.0`（D2-8）；包 tag 与编译器 tag 无耦合。
- 收口：五处 `CTC_VERSION` 同步；goldens 仅版本 token 变化；`v0.20.0` tag。
- 中间里程碑用非版本 tag（如 `phase2-probes`、`phase2-sqlite`、`phase2-wave2`）。

### 9. 全局 DoD

1. `bash selfhost/check-all.sh` 全绿，且**仍是 12 道**（不新增本地硬门禁）。
2. 既有 CI job + `packages.yml` 的 wave2 job 矩阵（四包 × 宿主 / aarch64-QEMU）全绿。
3. 四个包在宿主与目标机端到端跑通：`ct get` → `ct verify` → `ct install` 打印的命令 → 运行输出一致；`png` 的 `dep → zlib` 能递归解析。
4. 每个包的 A 层生成物 grep 不到该包的 wrapper 符号（`sqlite_` / `zlib_` / `png_` / `net_`）；调用点只有上游 C 函数与 shim 的 `ct_*`。
5. `ct build` 无语义 warning、C 编译器 `-Wall -Wextra` 零警告、demo 实跑输出符合预期；`ct check` 仅作**无 `import` 的单文件单元**的可选附加项；ASAN / UBSAN / LSAN 干净。
6. 文档中英双语；`package-guide`、`bindings/README`、roadmap、glossary（如需）同步。
7. 编译器行为不变；L0 / L1 / L2 / ct-ast 零改动；零网络契约不变（`ct get` 仍走 git，`ct build` 仍调本地 `cc`）。

### 10. 决策（待用户确认）

| 编号 | 议题 | 拟议结论 | 状态 |
| --- | --- | --- | --- |
| **D2-1** | 编号与版本 | Phase 2 ↔ `v0.20.0`；阶段内不 bump | ⬜ 待确认 |
| **D2-2** | 包名与仓库 | 四包名为 `sqlite` / `zlib` / `png` / `net-posix`，仓库 `ct-pkg/<pkg>`，命名空间同名 | ⬜ 待确认 |
| **D2-3** | 分层 | 三层（A `.m.ct` / B shim / C `.h.ct`），C 层调用 A/B 层（dogfood） | ⬜ 待确认 |
| **D2-4** | 生命周期 | 显式 `close` / `finalize` / `image_free` / `socket_close`，幂等；不用跨单元 `Drop` | ⬜ 待确认 |
| **D2-5** | 链接模型 | 链接系统库（`-lsqlite3` / `-lz` / `-lpng` / POSIX socket），不 vendored / 不内置 amalgamation | ⬜ 待确认 |
| **D2-6** | 常量 | 直接用 C 宏（`SQLITE_OK` / `SQLITE_ROW` / `SQLITE_TRANSIENT` / `Z_OK` / `PNG_FORMAT_RGBA` …），不导出同名 CT 全局 | ⬜ 待确认 |
| **D2-7** | 回调 | shim 提供带 `void *userdata` 的转发；包不生成 thunk、不做闭包 | ⬜ 待确认 |
| **D2-8** | 包版本 | 四包均首发 `0.1.0`；A+C 面冻结并过目标机后 `1.0.0` | ⬜ 待确认 |
| **D2-9** | 门禁位置 | 不新增本地硬门禁；探针挂既有层，包门禁在 CI | ⬜ 待确认 |
| **D2-10** | 许可证 | 各包沿用上游（`PublicDomain` / `Zlib` / `libpng`）；包内 `.ct` 代码 MIT，`LICENSE` 双段说明 | ⬜ 待确认 |
| **D2-11** | Phase 2 包集 | 只收**系统自带**的四包 `sqlite` / `zlib` / `png` / `net-posix`；`png` 只用简化 API；其余系统库留 Wave 3，非系统库留 Wave 4 | ⬜ 待确认 |
| **D2-12** | 非系统库策略 | 当前**不允许**包内置 / vendored 上游 C 源码（包模型只链接系统库）；确需随包源码时单独立项，不夹带进 Phase 2 | ⬜ 待确认 |

**旧 → 新编号对照（D20 → D2）**

| 旧编号 | 新编号 | 备注 |
| --- | --- | --- |
| D20-1 … D20-12 | D2-1 … D2-12 | 本文件 §10 的现行决策 |
| D20-13 … D20-18 | D2-13 … D2-18 | 历史讨论（2026-11-03 现状评估吸收报告的待拍板清单）；尚未写入 §10 |

> 旧编号出现在历史讨论/交接记录中，以本表映射（如 D20-11 → D2-11、D20-16 → D2-16）。

### 11. 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 二级指针 / 头文件 typedef 类型在 CT 侧不可用 | 高（决定 A 层能否 1:1） | 2.0 的 P1 / P2 先验证；不可行则整体走 shim + `void *`，A 层降为薄面 |
| `const unsigned char *` 与 `const char *` 的指针兼容告警 | 中 | 统一由 shim 收窄；CT 面只暴露 `const char *` / `const void *` |
| 回调函数名 / 链接属性 | 中 | 只允许 C 兼容签名的 `static` 函数；shim 入口先验证；失败则回调留到后续阶段 |
| `zlib` / `png` 的头文件 struct 与宏初始化（`deflateInit_`） | 中 | 2.0 补一个 `z_stream` 探针；宏一律经 shim 展开，不在 recipe 里拼 `sizeof` |
| `png` 简化 API 覆盖面有限 | 中 | 明确只承诺 `png_image`；完整 API 与 `setjmp` 错误处理留待后续，不在 Phase 2 承诺 |
| 四包 CI 成本 + 系统库缺失 | 中 | 一份 job 模板复用四包；宿主装 `libsqlite3-dev` / `zlib1g-dev` / `libpng-dev`，目标机装对应 `:arm64` |
| 上游许可证差异（公有领域 / Zlib / libpng） | 低 | 每包 `LICENSE` 双段说明；`ct.pkg` 的 `licence` 只作约定 |
| 单 trait 64 方法 / 单元 256 函数上限 | 中 | 按主题拆 trait；A 层天然按连接 / 语句 / 绑定 / 列拆分 |
| 索引刷新与实际 tag 不同步 | 低 | 沿用 Phase 18 的夜间 `refresh-index.sh` 与 `ct verify` |

### 12. 包清单与阶段归属

> 下表是**待建包**的完整清单，按「系统是否自带」分档；Phase 2 只收 A 档里的四个，其余是后续候选，不构成承诺。

| 档 | 库 / 包 | 系统自带（macOS + Linux） | 归属 |
| --- | --- | --- | --- |
| 已完成 | `clib`（string / stdio / math）、`hal`、`hal-posix` | — | Wave 1（Phase 18） |
| **A（Phase 2）** | `sqlite`、`zlib`、`png`（`dep → zlib`）、`net-posix` | ✅ | Phase 2 |
| **B（Wave 3）** | `curl`、`expat`、`libxml2`、`ncurses`、`libffi`、`bzip2` | ✅ | Phase 3 候选；都是系统自带，但面大或需 TTY / 回调，单包一个切片 |
| **C（Wave 4）** | `cJSON` / `jansson`、`mbedTLS`、`OpenSSL`、`libuv`、`SDL2` / `raylib` / `GLFW`、`FreeType`、`miniaudio`、`zstd` / `lz4`、`libwebp`、`PCRE2` | ❌（需先装或随包） | Phase 4 候选，**前置 D2-12**：先决定是否允许包内置上游源码 |
| **D（嵌入式轨道）** | `stm32-hal` / `stm32-ll`（CMSIS）、`esp-idf`（gpio / uart / i2c / spi / wifi / rtos）、`freertos`、`lvgl`、`littlefs` / `fatfs`、`lwip`、`nimble` | ❌（随 SDK） | 独立轨道，优先级最高（原计划重点）；需先解决「随 SDK 源码 / 交叉编译」的包模型 |
| 不计划 | FFmpeg、Qt / GTK、glib | — | 面过大，除非用户另行指定 |

**为什么不全塞进 Phase 2**：每个包 = 一个外部仓库 + 一份 licence + 一组系统库安装 + 一条目标机 job；四包已把 Wave 1（三包）翻倍。把 B/C/D 档一起拉进来会让 `v0.20.0` 失去可验收边界，也会把「真实库映射规范是否成立」这个核心问题淹没在移植工作里。

---

## English

> **Phase numbering: this project numbers its phases independently (Phase 2), unrelated to ct-lang's phase numbering; `v0.20.0` is the proposed compiler version string, not a phase number.**

### 1. Goal and exit

Ship four **system-provided** real C-library mapping packages in one phase — `sqlite` (the first),
`zlib`, `png`, `net-posix` — and use them to fix the three-layer convention for real-library packages:
a zero-cost `.m.ct` surface, a C-shim adaptation surface, and an owning `.h.ct` surface, while exercising
one `dep` chain (`png → zlib`) and a shared CI template.

Exit: all four packages are indexed; `ct get` → `ct verify` → the command `ct install` prints → compile and
run produce identical output on the **host** (macOS arm64 / Linux x86_64) and the **target** (Linux aarch64
under QEMU); each raw layer emits **zero wrappers**; `ct build` produces no semantic warnings, the C compiler is warning-free under `-Wall -Wextra`, and the demos' runtime output matches expectations; `ct check` is only an optional add-on for single-file units without `import`; the local hard gates stay at 12. Proposed version `v0.20.0`; rollback only removes the new
packages, demos, CI jobs and index lines, leaving the compiler untouched.

### 2. Non-goals

No C-header parsing or bindgen. **No non-system libraries** (cJSON / jansson, mbedTLS, OpenSSL, libuv,
SDL2 / raylib / GLFW, FreeType, miniaudio, zstd / lz4, libwebp, PCRE2): the current package model compiles
no bundled C sources and only links system libraries; allowing vendored sources needs its own decision
(D2-12). No full SQLite API (virtual tables, session, serialize, 16-bit interfaces, extension loading
stay out). `png` covers only the simplified `png_image` API, not the `setjmp`-based full API. No ORM, SQL
parsing, pooling or threading wrappers. No vendored SQLite / zlib / libpng or amalgamation (link the
system libraries). No cross-unit `Drop` and no language change; no Windows; no new local hard gate.

### 3. Constraints (measured)

`.m.ct` emits nothing and only carries `#include` / `#define` / `import` / `pub trait` / `map` /
`_Static_assert`; static traits cannot be `impl`ed, adopted, used as a type or boxed, and cap at 64
methods per trait. A prologue reaches the consumer's `.c` only, never the generated `.h`, so public structs hold
handles as `void *`. Shims live beside the mapping unit as `<base>.shim.h` / `<base>.shim.c`; a header-only
`static inline` shim is the plan. All-caps identifiers are emitted verbatim, so `SQLITE_ROW`,
`SQLITE_TRANSIENT` and `SQLITE_OPEN_*` work once the prologue is present. Header type names (`sqlite3`,
`sqlite3_stmt`), `const char *`, `void **` and function-pointer parameters are all supported. `Drop` /
`Handback` emitters are `static` and therefore unavailable across units, so the package must expose
explicit `close` / `finalize`. `ct.pkg`'s `cflags` / `ldflags` / `requires` reach the `ct install`
command.

### 4. API surface

| Class | Carrier | Coverage |
| --- | --- | --- |
| **A. direct `.m.ct`** | stateless single calls | connection (`open_v2` / `close_v2` / `errmsg` / `errcode` / `extended_errcode` / `busy_timeout` / `changes` / `total_changes` / `last_insert_rowid` / `get_autocommit` / `libversion` / `errstr` / `free`); statement (`prepare_v2` / `finalize` / `step` / `reset` / `clear_bindings` / `data_count` / `bind_parameter_count` / `stmt_readonly`); binding (`bind_null` / `bind_int` / `bind_int64` / `bind_double` / `bind_parameter_index`); columns (`column_count` / `column_name` / `column_type` / `column_int` / `column_int64` / `column_double` / `column_bytes` / `column_decltype`); values (`value_type` / `value_int` / `value_int64` / `value_double` / `value_bytes`) |
| **B. C shim** | shapes a recipe cannot spell | `bind_text` / `bind_blob` (destructor pinned to `SQLITE_TRANSIENT`, plus a `*_static` variant); `column_text` / `column_blob` (narrow `const unsigned char *` / `const void *`); `exec` with a callback and `void *userdata`; `mprintf` / `snprintf` (variadic → fixed); `create_function_v2`; `config` only for a fixed `SQLITE_CONFIG_SERIALIZED` wrapper |
| **C. `.h.ct` owning surface** | state, error translation, explicit lifetime | `Db` (open / close / errmsg / exec / changes), `Stmt` (prepare / finalize / step / reset / bind_* / column_* / column_text), optional read-only `Row` |
| **D. unsupported** | refused outright | virtual tables / `create_module`, session, serialize, 16-bit APIs, `scanstatus`, `auto_extension`, `load_extension`, Windows |

The C layer calls the A and B layers (dogfood) rather than duplicating their semantics.

### 5. Package design

Repository `github.com/ct-pkg/sqlite`, package name `sqlite`, namespace `sqlite`, first release `0.1.0`
(→ `1.0.0` once frozen), `licence = PublicDomain` with a `LICENSE` that states SQLite's public domain
status and the MIT licence of the `.ct` code, `ldflags = -lsqlite3`, `requires = ct >= 0.17.0`, no `dep`.

```
ct-pkg/sqlite/
├── ct.pkg
├── LICENSE
├── README.md
├── sqlite.m.ct          # the direct surface plus the type hosts
├── sqlite.shim.h        # header-only shim
├── Db.h.ct              # connection ownership
├── Stmt.h.ct            # statement ownership and I/O
├── Value.h.ct           # optional: value parameters for callbacks
└── test/{demo.ct,demo.expected.out}
```

Public `Db` / `Stmt` structs store `void *h`, never `sqlite3 *`, because the generated header carries no
prologue. Traits split by topic (`Conn` / `Statement` / `Binding` / `Column` / `Value` / `Lib`, so trait
names do not collide with the `Db` / `Stmt` structs) to stay under the
64-method cap and avoid Phase 19's same-name ambiguity. Type hosts `for type sqlite3 *` and
`for type sqlite3_stmt *` give `db.errmsg()` / `stmt.step()`. Constants stay C macros; exporting same-name
CT globals would collide with the header's macros.

The C layer requires `stmt_finalize` before `db_close` in the normal path; `db_close` uses
`sqlite3_close_v2` as a backstop and is idempotent, and `db_open` failure still permits `db_close`.

### 5.1 The other three packages

| Package | Surface | Notes |
| --- | --- | --- |
| `zlib` | direct: `compress` / `uncompress` / `crc32` / `adler32` / `deflate` / `inflate` / `deflateEnd` / `inflateEnd`; shim: `deflateInit_` / `inflateInit_` (upstream macros, pinned `ZLIB_VERSION` and `sizeof(z_stream)`); `z_stream` as a header struct | header structs by value are proven by `struct stat st;` in [std/fs](../../../ct/std/fs/Fs.h.ct) |
| `png` | direct: `png_image_begin_read_from_file` / `_from_memory`, `png_image_finish_read`, `png_image_free`; owning `Image` + `image_free`; `dep = zlib@^1` | simplified API only; no `setjmp` full API |
| `net-posix` | direct: `socket` / `bind` / `listen` / `accept` / `connect` / `send` / `recv` / `shutdown` / `close` (promoted from [bindings/posix-socket](../../../ct/bindings/posix-socket/)); owning `Socket` + `socket_close`; shim: `ct_net_last_error()` / `ct_net_strerror(int)` because `errno` is a lowercase macro invisible to CT | real package form of the in-repo example |

The four packages share one skeleton and one CI job template; only unit count, shim content and `dep` differ.

### 6. Slices

| Slice | Content | Surface | Exit |
| --- | --- | --- | --- |
| **2.0** | capability probes and a frozen API surface | `test/ast/**`, this file §4 / §5.1 | six probes compile and run under `-Wall -Wextra -Werror`; any impossible shape moves to a shim before 2.1 and is booked in the capability ledger |
| **2.1** | SQLite skeleton plus the direct and shim layers | external `ct-pkg/sqlite`: `ct.pkg` / LICENSE / README / `sqlite.m.ct` / `sqlite.shim.h` | the generated C has zero `sqlite_*` wrappers, only direct `sqlite3_*` calls; the `ct install` command carries `-lsqlite3` |
| **2.2** | SQLite type hosts and owning layer | `sqlite.m.ct` type hosts; `Db.h.ct` / `Stmt.h.ct` | `db.errmsg()` / `stmt.step()` expand to plain C; the demo creates, inserts, selects and tears down; ASAN + LSAN clean |
| **2.3** | `zlib` package | `zlib.m.ct` + `zlib.shim.h` (+ optional `Stream.h.ct`) | `compress` / `uncompress` round-trip; `deflateInit_` goes through the shim; zero wrappers |
| **2.4** | `png` package (depends on `zlib`) | `ct-pkg/png`: `png.m.ct` + `Image.h.ct`, `ct.pkg` with `dep = zlib@^1` | the index resolves `png → zlib` recursively; reading a fixed PNG yields deterministic pixels; `ct verify` green |
| **2.5** | `net-posix` package | `ct-pkg/net-posix`: `net.m.ct` + `Socket.h.ct` + shim | one loopback send/receive; explicit `socket_close`; `errno` read through the shim |
| **2.6** | demos, CI and index | `examples/sqlite-demo` / `examples/wave2-demo`, a `packages.yml` wave2 job matrix, four index lines | all four packages green on host and aarch64/QEMU; `ct verify` green; the index resolves |
| **2.7** | docs and close | this file, roadmap, `package-guide`, `bindings/README`, glossary, five `CTC_VERSION` sites | `v0.20.0` tagged and pushed |

**Probes (2.0)**: P1 header-typedef handle + type host; P2 `sqlite3 **` out-parameter; P3
function-pointer argument plus a C macro (`SQLITE_TRANSIENT`); P4 `const unsigned char *` return under
`-Werror`; P5 shim callback with userdata; P6 cross-unit dogfood (`Db.h.ct` imports `sqlite`, a consumer
imports `Db`) through `ct get file://`. P7 (added for `zlib`) checks a header struct by value
(`z_stream`) and a macro initializer routed through a shim. Each has a documented fallback (type host on
`void *`, a `void **` shim, a fixed shim entry, shim narrowing, callback postponed, a split `sqlite-raw`
package, or a `.h.ct` wrapper that mirrors the stream state).

**Testing and gates (2.6)**: `examples/sqlite-demo` does create → table → insert → select → close;
`examples/wave2-demo` does a zlib round-trip, reads a fixed PNG and does a loopback socket exchange, with
expectations from the real binaries. One `packages.yml` job template runs `ct get --index <pkg>` →
`ct verify` → the printed `ct install` command → the demo on the host and on `aarch64-linux-gnu-gcc` +
`qemu-aarch64` (installing `libsqlite3-dev` / `zlib1g-dev` / `libpng-dev` and their `:arm64` counterparts);
`ct build` produces no semantic warnings, the C compiler is warning-free under `-Wall -Wextra`, and the demos' runtime output matches expectations; `ct check` is only an optional add-on for single-file units without `import`; no new local hard gate — the probes
hang off existing layers and package gates stay in CI.

### 7. Order

2.0 → 2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6 → 2.7. Probes first so the packages are not half-written
when a shape turns out unwritable; SQLite proves the full three-layer pattern; `zlib` proves the macro-shim
path; `png` then proves the `dep` chain; `net-posix` is independent and can run in parallel with 2.3/2.4.

### 8. Versioning and release

Phase 2 ↔ `v0.20.0`, no mid-phase bump; each package has its own version (`0.1.0` → `1.0.0` once frozen
and passing the target leg). At close the five `CTC_VERSION` sites move in lockstep, the goldens change by
the version token only, and `v0.20.0` is tagged. Intermediate milestones use non-version tags.

### 9. Global DoD

1. `bash selfhost/check-all.sh` is green and **still runs 12 gates**.
2. Existing CI jobs plus the new `packages.yml` wave2 job matrix (four packages × host / aarch64-QEMU)
   are green.
3. All four packages run end to end on host and target, and `png`'s `dep → zlib` resolves recursively.
4. No package's raw layer emits its wrapper prefix (`sqlite_` / `zlib_` / `png_` / `net_`); call sites use
   only upstream C functions and the shim's `ct_*` calls.
5. `ct build` produces no semantic warnings, the C compiler is warning-free under `-Wall -Wextra`, and the demos' runtime output matches expectations; `ct check` is only an optional add-on for single-file units without `import`; ASAN / UBSAN / LSAN are clean.
6. Docs are bilingual; `package-guide`, `bindings/README`, roadmap and glossary move in lockstep.
7. Compiler behaviour is unchanged; L0 / L1 / L2 / ct-ast are untouched; network-free holds.

### 10. Decisions to confirm

| ID | Topic | Proposal |
| --- | --- | --- |
| **D2-1** | number and version | Phase 2 ↔ `v0.20.0`, no mid-phase bump |
| **D2-2** | names and repositories | `sqlite` / `zlib` / `png` / `net-posix`, repositories `ct-pkg/<pkg>`, same-name namespaces |
| **D2-3** | layering | A `.m.ct` / B shim / C `.h.ct`, with the C layer calling A/B (dogfood) |
| **D2-4** | lifetime | explicit `close` / `finalize` / `image_free` / `socket_close`, idempotent; no cross-unit `Drop` |
| **D2-5** | linking | system libraries (`-lsqlite3` / `-lz` / `-lpng` / POSIX sockets), nothing vendored |
| **D2-6** | constants | C macros directly (`SQLITE_OK` / `Z_OK` / `PNG_FORMAT_RGBA` …), no same-name CT globals |
| **D2-7** | callbacks | the shim forwards a callback with `void *userdata`; the package generates no thunks |
| **D2-8** | package version | all four start at `0.1.0`, `1.0.0` once frozen and passing the target leg |
| **D2-9** | gate placement | no new local hard gate; probes hang off existing layers, package gates stay in CI |
| **D2-10** | licence | inherit upstream (`PublicDomain` / `Zlib` / `libpng`); `.ct` code MIT, stated in `LICENSE` |
| **D2-11** | Phase 2 package set | only the four system-provided packages; `png` uses the simplified API; other system libraries wait for wave 3, non-system ones for wave 4 |
| **D2-12** | non-system libraries | packages may **not** bundle or vendor upstream C sources today; a real need becomes its own proposal, not part of Phase 2 |

**Old → new ID mapping (D20 → D2)**

| Old | New | Note |
| --- | --- | --- |
| D20-1 … D20-12 | D2-1 … D2-12 | current decisions in §10 |
| D20-13 … D20-18 | D2-13 … D2-18 | historical discussion (2026-11-03 state-review to-confirm list); not yet in §10 |

> Old IDs appear in historical discussions and handoff notes; use this table to map them (e.g. D20-11 → D2-11, D20-16 → D2-16).

### 11. Risks

The `sqlite3 **` / header-typedef shapes may be unusable (P1/P2 decide; fallback to a shim and `void *`);
`const unsigned char *` narrowing gets pushed into the shim; callback linking is validated by P5 and
otherwise postponed; the `zlib` / `png` header structs and the `deflateInit_` macro are covered by P7 and
push all macro initialisation into shims; `png` promises only the simplified API; four packages multiply
CI cost, so one job template is reused and the dev packages (`libsqlite3-dev` / `zlib1g-dev` /
`libpng-dev`, plus `:arm64`) are installed explicitly; the 64-method and 256-function caps are handled by
splitting traits; licence differences are stated per package; the index stays refreshed nightly.

### 12. Package inventory and staging

> The full candidate list, split by whether the host ships the library. Phase 2 takes only the four in
> tier A; everything else is a later candidate, not a commitment.

| Tier | Libraries / packages | System-provided (macOS + Linux) | Stage |
| --- | --- | --- | --- |
| done | `clib`, `hal`, `hal-posix` | — | wave 1 (Phase 18) |
| **A (Phase 2)** | `sqlite`, `zlib`, `png` (`dep → zlib`), `net-posix` | ✅ | Phase 2 |
| **B (wave 3)** | `curl`, `expat`, `libxml2`, `ncurses`, `libffi`, `bzip2` | ✅ | Phase 3 candidate; system-provided but large-surface or TTY/callback-heavy, one package per slice |
| **C (wave 4)** | `cJSON` / `jansson`, `mbedTLS`, `OpenSSL`, `libuv`, `SDL2` / `raylib` / `GLFW`, `FreeType`, `miniaudio`, `zstd` / `lz4`, `libwebp`, `PCRE2` | ❌ | Phase 4 candidate, gated on D2-12 (allowing bundled sources) |
| **D (embedded track)** | `stm32-hal` / `stm32-ll` (CMSIS), `esp-idf` (gpio / uart / i2c / spi / wifi / rtos), `freertos`, `lvgl`, `littlefs` / `fatfs`, `lwip`, `nimble` | ❌ (ship with SDKs) | separate track, highest priority; needs a package model for SDK-sourced sources and cross builds |
| not planned | FFmpeg, Qt / GTK, glib | — | too large unless explicitly requested |

**Why not fold everything into Phase 2**: each package is an external repository plus a licence, system
library installs and a target job; four packages already double wave 1 (three). Pulling tiers B/C/D in
would erase `v0.20.0`'s acceptance boundary and bury the real question — whether the mapping convention
holds — under porting work.
