> **过期提示**：本文为某时点的历史记录，其中的数量与接口已过时，现状见 [docs/std-oo-coverage.md](std-oo-coverage.md)。

# ct-pkg × CT v0.19.1 重新评估与落地记录

> 评估日期：2026-11-04
> 边界：只改本仓库（`/Users/samxx/vscspace/ct-pkg`）；未动 `ct` 源码、其他项目、`index/`；未 commit、未 push。

## 0. 结论

- 本机编译器：`ct v0.19.1`。
- 源码锚点：tag `v0.19.1` = commit `4176c63`；本机 ct 仓库 HEAD = `c27da3d`，即 `v0.19.1-1-gc27da3d`。这 1 个提交只改了 `Makefile` 注释与 `test/docs/check-docs.py` 的门禁计数扫描，**没有语言行为差异**。
- 四个此前各包撞到的缺口，v0.19.1 状态如下：
  - **recipe 层强转 / `sizeof` / 多语句**：部分修复。内建类型强转（`(size_t)len`）、宏常量（`AF_INET` / `SQLITE_TRANSIENT`）、空指针字面量（`0`）可用；`sizeof(struct tag)` 实测可编过；**任意 C 类型名（`z_stream` / `socklen_t` / `sqlite3`）仍被拒**，**多语句 recipe 仍被拒**。
  - **跨单元 `Drop`**：**未修复**。消费单元仍会得到一个空实现的 `static <S>_Drop_drop`，定义单元的 `impl` 被静默丢弃，无诊断。
  - **`.m.ct` 不许 `#ct-raw`**：**未修复**。`ct build` 报 `a .m.ct unit allows only #include and #define in its prologue`。
  - **prologue 不进生成的 `.h`**：对 `.m.ct` 而言**仍是设计如此**（prologue 只进消费者的 `.c`）；`.h.ct` 自己的 prologue 会进它生成的 `.h`（实测）。
- 采纳 3 个包的直接 recipe 迁移：`net-posix`、`sqlite`、`png`。`zlib` 因 `sizeof(z_stream)` 是 typedef 而暂不迁；`clib` / `hal` / `hal-posix` 无适用项。
- 全部 7 个包验证通过（详见 §5）；`-Wall -Wextra` 构建零警告。
- 新发现一个 ct 侧缺陷：`ct check` 单车单文件路径把 `unit_is_map` 硬置 0，导致带类型宿主的 `.m.ct`（本仓库 `png/Png.m.ct`）被误报 `a type host is only allowed in a .m.ct unit`；`ct build` 正常。本仓库不改 ct，只记录并绕开。

## 1. 版本锚点与取证方式

```text
$ ct --version
ct v0.19.1

$ git -C /Users/samxx/vscspace/ct describe --tags
v0.19.1-1-gc27da3d

$ git -C /Users/samxx/vscspace/ct rev-parse --short HEAD
c27da3d

$ git -C /Users/samxx/vscspace/ct tag --list 'v0.19*'
v0.19.1
```

- 仓库里**没有 CHANGELOG 文件**；版本差异取自 tag 提交、`docs/language-spec.md`、`docs/tutorial.md`、`docs/roadmap.md` 与 `issues/README.md` 台账。
- `v0.19.1` tag 提交说明（节选）：*“Patch release carrying the v0.19.0 re-evaluation fixes … ct check's column-bearing diagnostics and its import negative case … CTC_VERSION moves to 0.19.1”*。
- HEAD 的额外提交 `c27da3d`：`chore(gate): scan Makefile for a stale hard-gate count`，diff 仅 `Makefile` + `test/docs/check-docs.py`。

### 1.1 v0.19.x 带来的能力（相对 v0.18.1）

| 能力 | 来源 | 对包作者的意义 |
| --- | --- | --- |
| `ct check <file>` | v0.19.0 `db4cae4` | 只走解析/语义路径，不写 `.c`；有 finding 时 exit 1，text 用 `error:`，JSON 带 `"severity":"error"` |
| 调用点实参个数检查 | 19.1 `45532e8` | 函数/trait 方法少传或多传参数会报 `arity mismatch` |
| 粗粒度实参类型检查 | 19.2 `a158a8b` | 指针深度、结构体 tag 等明显不匹配会报 `type mismatch` |
| trait 方法歧义 + 跨单元 impl 签名漂移 | 19.3 `d2d1869` | 裸调用命中多个 trait、impl 参数类型漂移会告警 |
| `ct check` 接受 `.m.ct`（SH-49） | `4b9946b` | 映射单元终于有单文件检查入口 |
| `ct check` 诊断带列号（SH-50） | `5edfbd1` / `4176c63` | 定位到列，不再只有 `file:line:` |
| C99 合规的 `for` 静态初始化提升 | `528d7c5` | 生成物不再依赖 GNU 扩展，gcc 12 `-std=c99` 可编 |

注意：这些主要是**诊断与生成物合规性**的改进，v0.19.1 本身是 patch release，没有新增语言语法。

## 2. 仓库现状复核

用户给的计数与实测一致：

| 类型 | 实测 | 用户计数 | 结论 |
| --- | --- | --- | --- |
| `.ct` | 6 | 6 | 一致 |
| `.m.ct` | 7 | 7 | 一致 |
| `.h.ct` | 11 | 11 | 一致 |
| `ct.pkg` | 7 | 7 | 一致 |

- 6 个 `.ct`：`hal/examples/fake-uart/main.ct`、`net-posix/demo/{server,client}.ct`、`png/demo/main.ct`、`sqlite/test/demo.ct`、`zlib/test/demo.ct`。
- 7 个 `.m.ct`：`clib/clib/{Math,Stdio,String}.m.ct`、`net-posix/net/net.m.ct`、`png/Png.m.ct`、`sqlite/sqlite/Sqlite.m.ct`、`zlib/zlib.m.ct`。
- 11 个 `.h.ct`：`hal/{Clock,Gpio,Log,Uart}.h.ct`、`hal/examples/fake-uart/FakeUart.h.ct`、`hal-posix/PosixHal.h.ct`、`net-posix/net/Socket.h.ct`、`png/Image.h.ct`、`sqlite/{Db,Stmt}.h.ct`、`zlib/Stream.h.ct`。
- 7 个 `ct.pkg`：`clib`、`hal`、`hal-posix`、`sqlite`、`zlib`、`png`、`net-posix`。

## 3. 四个已知缺口的逐项判定

| 缺口 | v0.19.1 状态 | 实测证据 |
| --- | --- | --- |
| prologue 不进生成的 `.h` | **未变，且是设计如此**：`.m.ct` 的 `#include` / `#define` 只展开到消费者 `.c`；`.h.ct` 自己的 prologue 会进它的 `.h` | 见 §3.1 |
| recipe 不能强转 | **部分修复**：内建类型强转可用；任意 C 类型名仍不可用 | 见 §3.2 |
| recipe 不能 `sizeof(C 类型)` | **部分修复**：`sizeof(struct tag)` 可编过；`sizeof(<typedef>)` 仍被拒 | 见 §3.2 |
| recipe 不能多语句 | **未修复** | 见 §3.2 |
| 跨单元 `Drop` 的 impl 被静默丢弃 | **未修复** | 见 §3.3 |
| `.m.ct` 不许 `#ct-raw` | **未修复** | 见 §3.4 |

### 3.1 prologue 的落点

探针 `/tmp/pr1`：`a/A.h.ct` 顶部写 `#include <stdio.h>`，消费单元 `import a::A;`。

```text
$ ct build -I . main.ct -o out
'cc' -std=c99 '.ctbuild/main.c' '.ctbuild/A.c' '-o' 'out'
```

`.ctbuild/A.h` 确实带 prologue：

```c
#include <stdio.h>

struct a_Point {
    int x;
    int y;
};
```

而 `net-posix` 的构建里，`.m.ct` 的 prologue 只出现在 `.c`：

```c
/* .ctbuild/client.c 顶部 */
#include "net.shim.h"
#include <sys/types.h>

#include "Socket.h"
```

`.ctbuild/Socket.h` 没有任何 `#include`（只有注释提到“includes this header”）。结论：`.m.ct` prologue 不进 `.h` 在 v0.19.1 仍未改变；这是 batch 38/39 明确写下的设计，不是回归。

### 3.2 recipe 的参数文法

| 写法 | 结果 |
| --- | --- |
| `memset(p, 0, (size_t)n)` | 编译并运行通过 |
| `accept(fd, 0, 0)` | 编译并运行通过（`0` 作为空指针常量） |
| `memset(p, 0, sizeof(struct sockaddr_in))` | 编译并运行通过 |
| `memset((struct sockaddr_in *)p, 0, 1)` | `error: map argument '(struct sockaddr_in *)p' is not allowed` |
| `{ memset(p, 0, 1); memset(p, 1, 1); }` | `error: a map call must name a function` |
| `deflateInit_(strm, level, ZLIB_VERSION, sizeof(z_stream))` | `error: map recipe names 'z_stream' but it is not a binding parameter` |

结论：可安全依赖的是**内建类型强转、宏常量、空指针字面量**；`sizeof(struct tag)` 虽实测可用，但文档只承诺 `sizeof <绑定参数>`，属于实现容忍，不建议新代码依赖；typedef 名与任意类型名仍不可用；多语句仍被拒。

### 3.3 跨单元 `Drop`

探针 `/tmp/pr3b`：`a/A.h.ct` 里 `pub struct Res { int x; } use Drop;`，`impl Drop for Res { void drop() { self->x = 99; } }`；消费单元 `delete r;`。

```text
$ ct build -I . main.ct -o out
'cc' -std=c99 '.ctbuild/main.c' '.ctbuild/A.c' '-o' 'out'
exit=0
```

定义单元 `.ctbuild/A.c`：

```c
static void __attribute__((unused)) a_Res_Drop_drop(void *self) {
    struct a_Res *_self = (struct a_Res *)self;
    _self->x = 99;
}
```

消费单元 `.ctbuild/main.c`：

```c
static void __attribute__((unused)) a_Res_Drop_drop(void *self) {
    struct a_Res *_self = (struct a_Res *)self;
    (void)_self;
}
```

消费单元的 `drop` 是空实现，构建 exit 0、无 warning。这与 `issues/README.md` 的 SH-38 记录一致（“跨单元 impl Handback 需跨单元 impl 表（`Drop` 同样没有）”），v0.19.1 未改变。

### 3.4 `.m.ct` 里的 `#ct-raw`

```text
$ ct build -I . main.ct -o out
./m/m.m.ct:4:1: error: a .m.ct unit allows only #include and #define in its prologue
ctc: 1 error(s) generated
exit=1
```

补充：`ct check m/m.m.ct` 对同一文件 exit 0 —— 因为 check 路径把 `unit_is_map` 置 0（见 §4），prologue 白名单根本没生效。**不能拿 `ct check` 的绿色当作 `.m.ct` 合法性的证明**。

## 4. 新发现的 ct 侧缺陷（不修，只记录）

`ct check` 的单文件路径在 `selfhost/ct-ast/tool/driver/Driver.h.ct:295` 把 `self->p->unit_is_map = 0`，随后直接解析，没有像 `Module.load_unit` 那样按文件名恢复 `is_map`。结果是：

```text
$ ct check png/Png.m.ct
png/Png.m.ct:45:22: error: a type host is only allowed in a .m.ct unit
exit=1
```

`Png.m.ct` 第 45 行正是 `map trait Handle for type void *`；`ct build` 能正常编译并跑通 demo。因此：

- 本仓库不把 `ct check png/Png.m.ct` 当作门禁；
- 其余 6 个无类型宿主的 `.m.ct` 用 `ct check` 均 exit 0；
- 该缺陷应反馈给 ct 主线，不在本仓库修补。

## 5. 逐包结论与验证

| 包 | 判定 | 实际改动 | 验证结果 |
| --- | --- | --- | --- |
| `clib` | **已在用，不适用**：3 个 `.m.ct` 全是直接 C 调用，无 shim | 无 | `ct check` 3/3 通过；教程 demo 输出 `strlen=2 / strcmp<0=1 / sqrt=4 / fabs=3 / done` |
| `hal` | **不适用**：4 个 `.h.ct` + FakeUart demo，无 recipe/shim | 无 | `ct build -I . examples/fake-uart/main.ct` 后实跑：`FakeUart.sent = 17` |
| `hal-posix` | **不适用**：1 个 `.h.ct`，只做 trait 映射与实例 | 无 | 教程 demo 实跑：`hello from hal-posix` + `ping` |
| `sqlite` | **可迁移 → 已迁移** | `exec` / `exec_cb` / `bind_text` 改为直接 recipe；shim 删除 3 个转发器，保留 `open_v2` / `prepare` / `column_text` | demo 输出与 `expected.out` 一致；`-Wall -Wextra` 零警告；`ct check` 通过 |
| `zlib` | **有风险 → 暂不迁** | 无 | `sizeof(struct z_stream_s)` 实测可编过且 demo 通过，但依赖内部 struct tag；`sizeof(z_stream)` 被拒。保留两个 shim |
| `png` | **可迁移 → 已迁移** | `write_to_file` 改为直接 recipe；shim 删除 `ct_png_write_to_file` | demo 实跑输出与 README 一致；`-Wall -Wextra` 零警告；`ct check` 受 §4 缺陷阻塞 |
| `net-posix` | **可迁移 → 已迁移** | `socket` / `listen` / `accept` / `close` / `error_text` 改为直接 recipe；shim 删除 6 个转发器，保留 `fill` / `bind` / `connect` / `send` / `recv` / `errno` | echo server/client 实跑通过；`-Wall -Wextra` 零警告；`ct check` 通过 |

### 5.1 变更后的 recipe 形态

`net-posix/net/net.m.ct`：

```ct
socket()                -> socket(AF_INET, SOCK_STREAM, 0);
bind(fd, host, port)    -> ct_net_bind(fd, host, port);
listen(fd, backlog)     -> listen(fd, backlog);
accept(fd)              -> accept(fd, 0, 0);
connect(fd, host, port) -> ct_net_connect(fd, host, port);
send(fd, buf, len)      -> ct_net_send(fd, buf, len);
recv(fd, buf, len)      -> ct_net_recv(fd, buf, len);
close(fd)               -> close(fd);
err()                   -> ct_net_errno();
error_text(code)        -> strerror(code);
```

`sqlite/sqlite/Sqlite.m.ct`：

```ct
exec(db, sql)             -> sqlite3_exec(db, sql, 0, 0, 0);
exec_cb(db, sql, cb, ud)  -> sqlite3_exec(db, sql, cb, ud, 0);
bind_text(st, idx, s, n)  -> sqlite3_bind_text(st, idx, s, n, SQLITE_TRANSIENT);
```

`png/Png.m.ct`：

```ct
write_to_file(image, path, buffer, stride) -> png_image_write_to_file(image, path, 0, buffer, stride, 0);
```

## 6. 实测命令与真实输出

### 6.1 sqlite

```text
$ ct get /Users/samxx/vscspace/ct-pkg/sqlite
vendored 1 package(s)
$ ct install
ct build -I vendor/sqlite --ldflags '-lsqlite3' <unit>.ct -o build
$ ct build -I vendor/sqlite --cflags '-Wall -Wextra' --ldflags '-lsqlite3' src/main.ct -o build
'cc' -std=c99 -Wall -Wextra -I 'vendor/sqlite/sqlite' '.ctbuild/main.c' '.ctbuild/Db.c' '.ctbuild/Stmt.c' -lsqlite3 '-o' 'build'
$ ./build
open=0
create=0
prepare_insert=0
step_insert=101
step_insert=101
prepare_select=0
row 1: id=1 name=alice
row 2: id=2 name=bob
rows=2
closed
```

### 6.2 net-posix

```text
$ ct build -I vendor/net-posix --cflags '-Wall -Wextra -D_POSIX_C_SOURCE=200809L' src/server.ct -o build/server
'cc' -std=c99 -Wall -Wextra -D_POSIX_C_SOURCE=200809L -I 'vendor/net-posix/net' '.ctbuild/server.c' '.ctbuild/Socket.c' '-o' 'build/server'
$ ./build/client 40555 "final net-posix"
connected to 127.0.0.1:40555
sent 15 bytes
received 15 bytes: final net-posix
$ cat server.log
listening on 127.0.0.1:40555
client connected
echoed 15 bytes
client closed
```

### 6.3 png

```text
$ CPATH=/opt/homebrew/include LIBRARY_PATH=/opt/homebrew/lib ct build -I vendor/png --cflags '-Wall -Wextra' --ldflags '-lpng -lz' src/main.ct -o build
'cc' -std=c99 -Wall -Wextra -I 'vendor/png' '.ctbuild/main.c' '.ctbuild/Image.c' -lpng -lz '-o' 'build'
$ ./build
wrote /tmp/ct-png-out.png (4x4 RGBA)
read: 4x4 stride=16
pixel(2,1): 135 110 90 255
```

### 6.4 zlib 回归

```text
$ ct build -I vendor/zlib --cflags '-Wall -Wextra' --ldflags '-lz' src/main.ct -o build
'cc' -std=c99 -Wall -Wextra -I 'vendor/zlib' '.ctbuild/main.c' '.ctbuild/Stream.c' -lz '-o' 'build'
$ ./build
in=17
deflate=1
packed=16
inflate=1
out=17
roundtrip=ok
```

### 6.5 Wave 1 回归

```text
$ ct build -I . examples/fake-uart/main.ct -o /tmp/fake-uart-v191
'cc' -std=c99 '.ctbuild/main.c' '.ctbuild/Uart.c' '.ctbuild/FakeUart.c' '-o' '/tmp/fake-uart-v191'
$ /tmp/fake-uart-v191
[fake-uart] send 6 byte(s)
[fake-uart] send 4 byte(s)
[fake-uart] send 7 byte(s)
FakeUart.sent = 17
```

### 6.6 `ct check`

```text
$ ct check net-posix/net/net.m.ct            # exit 0，无输出
$ ct check sqlite/sqlite/Sqlite.m.ct         # exit 0，无输出
$ ct check zlib/zlib.m.ct                    # exit 0，无输出
$ ct check clib/clib/String.m.ct             # exit 0，无输出
$ ct check clib/clib/Stdio.m.ct              # exit 0，无输出
$ ct check clib/clib/Math.m.ct               # exit 0，无输出
$ ct check png/Png.m.ct
png/Png.m.ct:45:22: error: a type host is only allowed in a .m.ct unit
exit=1                                        # §4 的 ct 侧缺陷
$ ct check src/client.ct
src/client.ct:8:1: error: 'import' is not supported in compile mode
exit=1                                        # 带 import 的单元仍是已知限制
```

## 7. 落地改动清单

| 文件 | 改动 |
| --- | --- |
| `net-posix/net/net.m.ct` | 新增 `#include <string.h>`；`socket` / `listen` / `accept` / `close` / `error_text` 改直接 recipe；`accept` 用 `accept(fd, 0, 0)` |
| `net-posix/net/net.shim.h` | 删除 `ct_net_socket`（该名称后续已改为 `NetSocket`） / `ct_net_listen` / `ct_net_accept` / `ct_net_close` / `ct_net_strerror`；保留 `fill` / `bind` / `connect` / `send` / `recv` / `errno`；更新头注释 |
| `net-posix/ct.pkg` | `requires = ct >= 0.19.1`；更新注释 |
| `net-posix/README.md` | manifest、`accept` 说明、shim/直连说明、编译器要求同步到 0.19.1 |
| `sqlite/sqlite/Sqlite.m.ct` | `exec` / `exec_cb` / `bind_text` 改直接 recipe；头注释说明 `void *` 隐式转换 |
| `sqlite/sqlite/Sqlite.shim.h` | 删除 `ct_sqlite_exec` / `ct_sqlite_exec_cb` / `ct_sqlite_bind_text`；保留 3 个 out-param/窄化 helper |
| `sqlite/ct.pkg` | `requires = ct >= 0.19.1` |
| `sqlite/README.md` | layer B 描述、manifest、编译器要求同步 |
| `png/Png.m.ct` | `write_to_file` 改直接 recipe |
| `png/Png.shim.h` | 删除 `ct_png_write_to_file` |

未改动：`clib/`、`hal/`、`hal-posix/`、`zlib/`、`index/`、`tools/`。

## 8. 未采纳项与原因

| 项 | 原因 |
| --- | --- |
| `zlib` 的 `deflate_init` / `inflate_init` 去 shim | 需要 `sizeof(z_stream)`，但 `z_stream` 是 typedef，recipe 拒绝；改成 `sizeof(struct z_stream_s)` 虽实测可编过，但依赖 zlib 内部 tag，可读性与稳定性都差 |
| `sqlite3_open_v2` / `prepare` 去 shim | `sqlite3 **` / `sqlite3_stmt **` 输出参数不是 `void **` 的隐式转换目标；recipe 又不能用 `(sqlite3 **)` 强转 |
| `sqlite3_column_text` 去 shim | `const unsigned char *` → `const char *` 需要窄化，recipe 不能写任意类型强转 |
| `png` 的 `image_new` / `set_rgba` / `finish_read` / 字段读取 | 需要 `png_image` 结构体构造与字段访问；recipe 不能命名该类型 |
| `net` 的 `bind` / `connect` | 需要栈上 `struct sockaddr_in` 构造、`htons`、`inet_pton`；recipe 不能写该类型 |
| `net` 的 `send` / `recv` 去 shim | 保留负长度守卫与 `ssize_t` → `int` 窄化 |
| `net` 的 `err` 去 shim | `errno` 是小写宏，CT 不能当变量引用 |
| `.m.ct` 里用 `#ct-raw` | v0.19.1 仍禁止；本仓库继续用 shim 承担手写 C |
| 跨单元 `Drop` | v0.19.1 仍静默丢弃 impl；本仓库所有需要销毁的包继续用显式 `close` / `free`，不新增 `Drop` |
| 依赖“prologue 进 `.h`” | 设计上 `.m.ct` prologue 不进 `.h`；本仓库公开头只放 `int` / `void *` 等不依赖 C 类型的字段 |

## 9. 待办清单

- [x] 复核 6 / 7 / 11 / 7 的文件计数。
- [x] 确认 v0.19.1 四个缺口的真实状态（§3）。
- [x] 迁移 `net-posix`、`sqlite`、`png` 的安全 recipe。
- [x] 三个包用 `ct build` + demo 实跑验证；`-Wall -Wextra` 零警告。
- [x] `clib` / `hal` / `hal-posix` / `zlib` 回归验证。
- [x] 把 `sqlite` / `net-posix` 的 `requires` 收紧到 `>= 0.19.1`（`png` 已是 0.19.1）。
- [ ] 向 ct 主线反馈三个缺陷（不在本仓库修）：`ct check` 的 `unit_is_map` 硬置 0、跨单元 `Drop` 静默丢弃、`.m.ct #ct-raw` 缺失。
- [ ] `png` 的 `ct check` 门禁等 ct 修复后再启用；在此之前只用 `ct build` + demo。
- [ ] `zlib` 是否迁移，等 ct 支持 `sizeof(<typedef>)` 或文档明确承诺 `sizeof(struct tag)` 后再评估。
- [ ] `index/` 条目与 tag 发布：按用户要求**本次未做**。
