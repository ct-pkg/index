# `char *` 宿主方法名台账

复核时间：2026-11-08
复核范围：全仓 `*.m.ct`（排除 `.git`、`.ctbuild`）
复核结果：`tools/check-char-host.sh` 扫描到 **300 个方法 / 27 个宿主**，其中 `char *` 宿主 **38 个方法**，无重复。

> 基线变化：任务初始 23 个 `char *` 方法；第一批 7 个占位（png、zlib、net-posix）落地后为 30；
> hal-posix 的 `GpioName` 新增 `read` / `write` 后为 32；sqlite 的 `DbPath` 新增 `openSqliteDb`
> 后为 33；sql 的 `Entry` 新增 `select` / `insert` / `update` / `delete` 后为 37；
> 2026-11-08 对账时 `std::str::String` 已删除 `copyFrom`，回落至 36，curl 的 `CurlEntry`
> 新增 `openCurl` 后为 **37**；json 的 `Text` 新增 `toDoc` 后当前为 **38**。
>
> 本次以脚本实测为准修正了两处旧账：全仓此前记为 215，实际是 **214**（`copyFrom` 已从
> `String.m.ct` 删除但仍留在文档里）；`char *` 此前记为 37，实际是 **36**，加 curl 后为 **37**。
>
> 句柄类型名的现状：`NetSocket`、`SqliteDB`、`SqliteStmt`、`PngReader`、`CurlEasy` 已是 CT
> 可见的 CamelCase；`std::io` 的 `IoFile` 在 0.20.3 类型别名发布后也已生效，`File` 的
> `read` / `write` / `close` 现在映射到 `IoFile *` 宿主。

## 1. 为什么这份台账必须存在

`char *` 是全仓公共映射宿主。映射方法在编译器里的键是 **（宿主, 方法名）**：

- 同一宿主上的方法名必须唯一，**签名不参与消歧**。`len(s)` 与 `len(s, n)` 不能共存。
- 不同宿主之间允许同名。`close` 已经同时存在于 `IoFile *`（`std::io`）、`SqliteDB *`、
  `NetSocket *` 和 `PngReader *` 上，互不影响。
- 解析作用域是当前编译单元 import 的可达闭包。两个包各自新增 `len()` 时都能单独编译通过，
  **只有调用点同时看到两边才会报错**——这是“调用时才炸”的懒失败，无法靠单个包的编译验证发现。
- `map_type_key` 会丢弃任意位置的 `const` / `volatile`。`const char *` 会与 `char *` 折叠成同一宿主，
  在 ct 0.20.0 起直接产生歧义（v0.19.1 是旧行为，只是暂时能过）。

所以规则是：新增方法前先查本台账，落地后回填；重名与 `const` 孪生宿主由
[`tools/check-char-host.sh`](../tools/check-char-host.sh) 在提交前拦截。

历史名（仅用于检索旧文档与旧讨论）：`ct_io_file` → `IoFile`（0.20.3 类型别名发布前曾以
`void *` 映射，现已改为 `IoFile *`，见 §2.3）、`ct_net_socket` → `NetSocket`、`ct_sqlite_db` → `SqliteDB`、
`ct_sqlite_stmt` → `SqliteStmt`、`ct_png_reader` → `PngReader`。
C 侧 helper 符号名不变，改名只影响 CT 可见拼写。

## 2. 当前占用（38）

### 2.1 `std::str::String` — 14 个

提供方单元：`std/std/str/String.m.ct`（映射块见 `String.m.ct:66-81`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `len` | `std/std/str/String.m.ct` | `char *` | 字节长度，不含结尾 NUL | 2026-11-06 |
| `find` | `std/std/str/String.m.ct` | `char *` | 子串首次出现位置，未找到返回 -1 | 2026-11-06 |
| `findChar` | `std/std/str/String.m.ct` | `char *` | 单字节首次出现位置，未找到返回 -1 | 2026-11-06 |
| `startsWith` | `std/std/str/String.m.ct` | `char *` | 前缀判断 | 2026-11-06 |
| `endsWith` | `std/std/str/String.m.ct` | `char *` | 后缀判断 | 2026-11-06 |
| `copy` | `std/std/str/String.m.ct` | `char *` | 复制进调用方缓冲区 `out`（容量 `cap`），返回状态码 | 2026-11-06 |
| `slice` | `std/std/str/String.m.ct` | `char *` | 取 `[start, end)` 写入 `out`（容量 `cap`），返回状态码 | 2026-11-06 |
| `concat` | `std/std/str/String.m.ct` | `char *` | 追加到 `out`（容量 `cap`），返回状态码 | 2026-11-06 |
| `toLower` | `std/std/str/String.m.ct` | `char *` | 转小写写入 `out`（容量 `cap`），返回状态码；接收者不被修改 | 2026-11-06 |
| `toUpper` | `std/std/str/String.m.ct` | `char *` | 转大写写入 `out`（容量 `cap`），返回状态码；接收者不被修改 | 2026-11-06 |
| `compare` | `std/std/str/String.m.ct` | `char *` | 按字节比较 | 2026-11-06 |
| `copyTo` | `std/std/str/String.m.ct` | `char *` | 原始拷贝：恰好 `n` 字节到 `dst`，无 NUL、不检查容量 | 2026-11-06 |
| `toInt` | `std/std/str/String.m.ct` | `char *` | `atoi` 语义解析整数 | 2026-11-06 |
| `toDouble` | `std/std/str/String.m.ct` | `char *` | `atof` 语义解析浮点数 | 2026-11-06 |

> 当前签名均为 `toLower(s, out, cap)` / `toUpper(s, out, cap)` 形式：**不是原地转换**，而是写入调用方
> 缓冲区；模块内没有方法会改写接收者，因此 `const char *` 实参（字符串字面量）也可安全调用。
>
> `copyFrom` 已删除，不再占用 `char *` 宿主：旧写法 `dst.copyFrom(src, n)` 现在写作
> `src.copyTo(dst, n)`。上一版台账仍把它计入 15 个，是本次对账修正的 1 个差额来源。

### 2.2 `std::fs::FsOps` — 4 个

提供方单元：`std/std/fs/Fs.m.ct`（映射块见 `Fs.m.ct:33-38`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `exists` | `std/std/fs/Fs.m.ct` | `char *` | 路径是否存在 | 2026-11-06 |
| `readFile` | `std/std/fs/Fs.m.ct` | `char *` | 读整个文件到调用方缓冲区 | 2026-11-06 |
| `writeFile` | `std/std/fs/Fs.m.ct` | `char *` | 把字符串写入文件 | 2026-11-06 |
| `list` | `std/std/fs/Fs.m.ct` | `char *` | 目录项列举到调用方缓冲区 | 2026-11-06 |

### 2.3 `std::io::Path` — 1 个

提供方单元：`std/std/io/File.m.ct`（映射块见 `File.m.ct:13-15`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `open` | `std/std/io/File.m.ct` | `char *` | 按模式打开文件，返回 C 句柄的 CT 可见类型是 `IoFile *` | 2026-11-06 |

> **返回类型是 `IoFile *`**。`IoFile` 是 0.20.3 类型别名发布后才在 CT 侧可见的拼写，
> `std_io_*` helper 的 C 签名不变。
>
> 同一单元里 `File` 的 `read` / `write` / `close` 挂在 `IoFile *` 宿主上
> （`File.m.ct:25-31`），共 3 个方法；它们不属于 `char *`，只进入 §5 的全仓总数。

### 2.4 `std::utf8::Utf8Ops` — 3 个

提供方单元：`std/std/utf8/Utf8Ops.m.ct`（映射块见 `Utf8Ops.m.ct:41-45`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `decode` | `std/std/utf8/Utf8Ops.m.ct` | `char *` | 解码一个码点到 `int *` | 2026-11-06 |
| `codepointCount` | `std/std/utf8/Utf8Ops.m.ct` | `char *` | 统计码点数量，非法 UTF-8 返回 -1 | 2026-11-06 |
| `encode` | `std/std/utf8/Utf8Ops.m.ct` | `char *` | 把码点编码进调用方缓冲区 | 2026-11-06 |

### 2.5 `png::PathImage` — 2 个（原占位，已落地）

提供方单元：`png/png/Png.m.ct`（映射块见 `Png.m.ct:72-75`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `readImage` | `png/png/Png.m.ct` | `char *` | 按路径解码 PNG，错误文本写入 `err` 缓冲 | 2026-11-07 |
| `writeImage` | `png/png/Png.m.ct` | `char *` | 把 RGBA 缓冲写成 PNG 文件 | 2026-11-07 |

### 2.6 `zlib::Text` — 3 个（原占位，已落地）

提供方单元：`zlib/zlib/zlib.m.ct`（映射块见 `zlib.m.ct:78-82`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `deflate` | `zlib/zlib/zlib.m.ct` | `char *` | 以 `strlen` 为输入长度的一次性压缩 | 2026-11-07 |
| `inflate` | `zlib/zlib/zlib.m.ct` | `char *` | 显式 `inLen` 的一次性解压（压缩输入可为二进制） | 2026-11-07 |
| `deflateBound` | `zlib/zlib/zlib.m.ct` | `char *` | 计算 deflate 输出上界 | 2026-11-07 |

> `zlib` 在 `z_stream *` 宿主上也有 `deflate` / `inflate`。这是**不同宿主同名**，按规则允许；
> 调用点按接收者类型解析，不会歧义。

### 2.7 `net::Addr` — 2 个（原占位，已落地）

提供方单元：`net-posix/net/Addr.m.ct`（映射块见 `Addr.m.ct:33-36`），目标宿主 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `openSocket` | `net-posix/net/Addr.m.ct` | `char *` | 解析 `host:port`，建立出站 TCP 连接，返回 `NetSocket *` | 2026-11-07 |
| `openListener` | `net-posix/net/Addr.m.ct` | `char *` | 解析 `host:port`，建立监听套接字，返回 `NetSocket *` | 2026-11-07 |

### 2.8 `GpioName`（hal-posix）— 2 个

提供方单元：`hal-posix/GpioName.m.ct`（映射块见 `GpioName.m.ct:31-34`），目标宿主 `char *`。
该单元没有 namespace，trait 名就是 `GpioName`；接收者是设备名，如 `"gpio17"`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `read` | `hal-posix/GpioName.m.ct` | `char *` | 按 `gpio<N>` 设备名读引脚值，非法名返回 -1 并置 `EINVAL` | 2026-11-07 |
| `write` | `hal-posix/GpioName.m.ct` | `char *` | 按 `gpio<N>` 设备名写引脚值，非法名返回 -1 并置 `EINVAL` | 2026-11-07 |

> `read` / `write` 与 `std::io::File` 宿主上的同名方法属于**不同宿主**（`std::io` 是 `IoFile *`，
> 见 §2.3），按规则允许。

### 2.9 `sqlite::DbPath` — 1 个

提供方单元：`sqlite/sqlite/Sqlite.m.ct`（映射块见 `Sqlite.m.ct:133-135`），目标宿主 `char *`。
该 trait 没有类型参数接收者，接收者是数据库路径；`const char *` 写法被禁止（限定符会折叠宿主），
因此宿主声明只能是 `char *`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `openSqliteDb` | `sqlite/sqlite/Sqlite.m.ct` | `char *` | 以路径为接收者打开数据库，成功返回 `SqliteDB *`，失败返回 `0` | 2026-11-07 |

> 与 `sqlite::Lib` 的 `open` / `open_v2` 不是重名：那是 namespace 宿主上的显式出参形式，
> `openSqliteDb` 是 `char *` 宿主上的接收者形式，两者最终都落到 `ct_sqlite_open*` helper。

### 2.10 `sql::Entry` — 4 个

提供方单元：`sql/sql/Sql.m.ct`（trait 声明 `25-30`，映射块 `32-37`），目标宿主 `char *`。
接收者是表名，四个入口分别创建一种语句 builder；`select` 为首期已落地，`insert` / `update` /
`delete` 为本轮补齐的 CRUD 方法。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `select` | `sql/sql/Sql.m.ct` | `char *` | 以表名为接收者创建 SELECT builder，返回 `sql_Select *` | 2026-11-07 |
| `insert` | `sql/sql/Sql.m.ct` | `char *` | 以表名为接收者创建 INSERT builder，返回 `sql_Insert *` | 2026-11-07 |
| `update` | `sql/sql/Sql.m.ct` | `char *` | 以表名为接收者创建 UPDATE builder，返回 `sql_Update *` | 2026-11-07 |
| `delete` | `sql/sql/Sql.m.ct` | `char *` | 以表名为接收者创建 DELETE builder，返回 `sql_Delete *` | 2026-11-07 |

> sql 的四种语句还各自占一个命名 struct 宿主（2026-11-08 链式 bind 改造后：
> `struct sql_Select *` 20 个方法、`struct sql_Insert *` 15 个、`struct sql_Update *` 19 个、
> `struct sql_Delete *` 17 个，合计 71 个）。它们不属于 `char *`，但会进入 §5 的全仓总数；
> sql 整体贡献 75 个映射方法（`char *` 上 4 个 + 四个句柄上 71 个）。

### 2.11 `curl::CurlEntry` — 1 个

提供方单元：`curl/curl/Client.m.ct`（trait 声明 `CurlEntry`，映射块 `map trait CurlEntry for type char *`），
目标宿主 `char *`。接收者是 URL，唯一入口创建一个 `CurlEasy *` 句柄；其余能力全部挂在
`CurlEasy *` 上，`char *` 上不再有第二个方法。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `openCurl` | `curl/curl/Client.m.ct` | `char *` | 以 URL 为接收者创建 curl easy 句柄，失败返回 `0` | 2026-11-08 |

> 未占用 `open`：`std::io::Path` 已有 `open`。`openCurl` 加入前已用本台账与
> `tools/check-char-host.sh` 双重核对，无重名。
>
> curl 另外新增两个宿主：`CurlEasy *` 33 个方法、`namespace curl` 4 个方法。它们不属于
> `char *`，但会进入 §5 的全仓总数。

### 2.12 `json::Text` — 1 个

提供方单元：`json/json/Json.m.ct`（trait 声明 `Text`，映射块 `map trait Text for type char *`），
目标宿主 `char *`。接收者是 JSON 文本，唯一入口返回一个 `JsonDoc *`；解析失败返回 `0`，
此时 doc 已被释放、错误码也随之丢失，需要错误详情时要自己 `newDoc()` 再调用 `Doc.parse`。

| 方法名 | 提供方单元 | 目标宿主 | 一句话语义 | 加入日期 |
| --- | --- | --- | --- | --- |
| `toDoc` | `json/json/Json.m.ct` | `char *` | 以 JSON 文本为接收者建 doc 并解析，失败返回 `0` | 2026-11-08 |

> 未占用 `open`：`std::io::Path` 已有 `open`。`toDoc` 加入前已用本台账与
> `tools/check-char-host.sh` 双重核对，无重名。
>
> json 另外新增两个宿主：`JsonNode *` 19 个方法、`JsonDoc *` 14 个方法，以及
> `namespace json` 7 个构造器。它们不属于 `char *`，但会进入 §5 的全仓总数。
> 设计过程中曾规划的 `toJSON()`（`char *` → `JsonNode *`）已按 R2 裁决删除，
> 未占用任何名字。

## 3. 原占位名状态（已批准）

任务下达时，以下 7 个名字被预留为“已批准、待落地”，用于避免两批并行时撞名：

| 方法名 | 计划提供方 | 批准状态 | 复核状态 |
| --- | --- | --- | --- |
| `readImage` / `writeImage` | png | 已批准 | **已落地**（`Png.m.ct:72-75`） |
| `openSocket` / `openListener` | net-posix | 已批准 | **已落地**（`Addr.m.ct:33-36`） |
| `deflate` / `inflate` / `deflateBound` | zlib | 已批准 | **已落地**（`zlib.m.ct:78-82`） |

这 7 个名字与 §2.1–§2.4 的 22 个名字互不重复，已全部转入 §2 的正式台账。
如果其中任何一项被回滚，名字仍按“已批准、待落地”保留，不得被其他包占用。
`GpioName` 的 `read` / `write` 不属于这 7 个占位名，是本轮新增的正式占用，见 §2.8。

## 4. 准入流程

1. **查台账**：确定目标宿主后，先在本文按宿主检索方法名；`char *` 还要跑一遍
   `tools/check-char-host.sh`。
2. **写进设计**：设计文档必须写明方法名、目标宿主、提供方单元和语义；同名不同签名不算区分。
3. **占位**：与他包并行时，先在本台账登记“已批准、待落地”，再动手实现。
4. **落地回填**：实现合入后，把占位行转入正式表格，补齐提供方单元、加入日期与语义。
5. **复核**：提交前运行 `tools/check-char-host.sh`，必须输出 `ok: ... no duplicates`。
6. **禁止孪生宿主**：不得新增 `const char *`、`const void *`、`volatile ...` 等带限定符的宿主声明；
   需要 `const` 语义时改在参数上写 `const`，不要写进宿主类型。
7. **允许跨宿主同名**：不同宿主上的同名方法不需要避让，但要在文档里说明为什么不是歧义。

## 5. 自动检查脚本

以下命令在 `index` 仓库根目录执行；脚本自身会向上两级找到 ct-pkg 工作区，扫描其中各包的 `*.m.ct`。

```sh
tools/check-char-host.sh
```

- 扫描全仓 `*.m.ct` 的 `map trait ... for type|namespace ... { ... }` 映射块，按宿主分组提取方法名。
- 检查一：同一宿主上的重复方法名。发现后非零退出，并打印双方（或全部）`文件:行号`。
- 检查二：宿主声明中带 `const` / `volatile`。发现后非零退出并打印声明位置——这些限定符会被
  `map_type_key` 丢弃，等价于孪生宿主。
- 宿主分组时只做归一化（折叠空白、去掉 `const`/`volatile`），报错信息保留原始拼写。
- 退出码：`0` 干净；`1` 有重复或限定符宿主。
- 兼容 macOS 自带 bash 3.2，只依赖 `awk`、`sed`、`sort`、`find`。
- 映射头 `map trait ... for type|namespace ... {` 必须写在同一行（当前全仓均满足）；跨行写法不会被识别。

脚本的统计范围是全部映射宿主（包括 `namespace` 宿主、`std::io` 的 `IoFile *`、sql 的四个 struct
句柄宿主，以及 curl 的 `CurlEasy *` / `namespace curl`、json 的两个句柄宿主 / `namespace json`），
所以全仓输出是 `300 methods on 27 hosts`；其中 `char *` 子集为 **38**，对应 §2。这 300 里包含
curl 贡献的 38 个方法（`char *` 上 1 个、`CurlEasy *` 上 33 个、`namespace curl` 上 4 个）与
json 贡献的 41 个方法（`char *` 上 1 个、`JsonNode *` 上 19 个、`JsonDoc *` 上 14 个、
`namespace json` 上 7 个）。脚本不处理 `.h.ct` 里的原生 OO trait，也不处理 `for instance`
映射：它们不是按类型键解析的映射宿主。

与上一次记账的差额：上一版记为 293 / 28 个宿主，本次为 300 / 27。增量来自 sql 的链式 bind
改造（0.2.0）：`Select` 16→20、`Insert` 11→15、`Update` 15→19、`Delete` 13→17，四类共 +16，
sql 整体为 75。宿主数减少 1 是因为 `namespace png` 的 9 个映射已不在当前源码里（`png/Png.m.ct`
只剩 `PngReader *` 与 `char *` 两段映射）；`std::io` 的 3 个方法由 `void *` 改名为 `IoFile *`，
数量不变。293 + 16 − 9 = 300，28 − 1 = 27。

### 5.1 逐宿主计数（2026-11-08）

宿主按脚本归一化后的键列出（`long long` 折叠为 `longlong`，`struct sql_* *` 折叠为
`structsql_* *`）：

| 宿主 | 方法数 | 宿主 | 方法数 |
| --- | ---: | --- | ---: |
| `char` | 7 | `char *` | 38 |
| `curl`（namespace） | 4 | `CurlEasy *` | 33 |
| `double` | 9 | `float` | 5 |
| `hal`（namespace） | 1 | `int` | 7 |
| `IoFile *` | 3 | `json`（namespace） | 7 |
| `JsonDoc *` | 14 | `JsonNode *` | 19 |
| `long` | 7 | `long long` | 7 |
| `net`（namespace） | 10 | `NetSocket *` | 10 |
| `PngReader *` | 6 | `sqlite`（namespace） | 5 |
| `SqliteDB *` | 8 | `SqliteStmt *` | 15 |
| `std::io`（namespace） | 4 | `std::math`（namespace） | 2 |
| `struct sql_Delete *` | 17 | `struct sql_Insert *` | 15 |
| `struct sql_Select *` | 20 | `struct sql_Update *` | 19 |
| `z_stream *` | 8 | | |
| **合计** | **300** | | |

`char *` 的 38 = 14(String) + 4(FsOps) + 1(Path) + 3(Utf8Ops) + 2(PathImage) + 3(Text) +
2(Addr) + 2(GpioName) + 1(DbPath) + 4(Entry) + 1(CurlEntry) + 1(json::Text)。

### 复核输出

```
$ tools/check-char-host.sh
ok: 300 methods on 27 hosts, no duplicates
```
