# std 缺口分析：从语言基本类型推导

盘点时间：2026-11-06，基线为 `std 0.2.0`（str / fs / utf8 / vec / map / arena / test / num / math 九个模块）。

## 0. 前提（不做假设的部分）

CT 的类型词来自 [language-spec.md](../../../ct/docs/language-spec.md) 的内建表：
`void` / `char` / `short` / `int` / `long` / `long long` / `float` / `double` / signed·unsigned 变体 /
`struct` / `enum` / 定长数组 / 裸指针。**没有**：泛型、变参、异常、闭包、`bool` 内建类型
（`bool` 只是 `<stdbool.h>` 的拼写，落回整数）、自动派生（eq/hash/toString）。

这三条限制直接决定了哪些东西**做不出来**，后面的判断都以此为准：

1. 没有泛型 → 容器只能一种元素一个类型，或者退化成 `void *` 丢类型；
2. 没有变参 → `printf(fmt, ...)` 这种签名写不出来，格式化只能是「一个个 append」；
3. 没有自动派生 → struct 的相等/哈希/打印必须手写，std 无法用宏或反射代劳。

现有九个模块的实际 API（用于判断「今天怎么写」）：

| 模块 | 现有方法 |
| --- | --- |
| `std::str::String` | `len` `find` `findChar` `startsWith` `endsWith` `copy` `slice` `concat` `toLower` `toUpper` `compare` `toInt` `toDouble` |
| `std::fs::FsOps` | `exists` `readFile` `writeFile` `list` |
| `std::utf8::Utf8Ops` | `decode` `codepointCount` `encode` |
| `std::vec` | `VecInt` / `VecStr`：`init` `len` `push` `pop` `at` `free` |
| `std::map` | `MapStrInt` / `MapIntPtr`：`init` `put` `get` `len` `clear` `free` |
| `std::arena` | `init` `alloc` `reset` `freeAll` |
| `std::test` | `init` `checkTrue` `checkEqInt` `checkEqStr` `report` |
| `std::num` | `Long` 7 / `LLong` 7 / `Char` 7（`abs` `clamp` `max` `min` `toStr` `toString` `toBase` / ctype 7 个） |
| `std::math` | `Math`（`sqrt` `fabs`）+ `Float` 5 + `Real` 9 |

## 1. 总表

列说明：**真缺口** = 不是「多写一行」能解决的；**依赖** = 纯 CT（自实现，不调库）/ libc / POSIX；
**OO 形态** = 映射式（`.m.ct` + shim）/ 原生 OO（`.h.ct`）/ 不该包。

### 1.1 字符串（`char *`，映射式）

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| `trim` / `trimLeft` / `trimRight` | 手写双指针循环，10 行起 | **是** | libc（`isspace`） | 映射式，`String` 或新 trait | 必备 |
| `split(sep, out, cap)` | `strchr` 循环 + `copy`，20 行，易漏最后一段 | **是** | libc | 映射式 | 必备 |
| `replace(old, new, out, cap)` | 循环 + 长度预算，容易越界 | **是** | libc | 映射式 | 常用 |
| `contains` / `equals` / `isEmpty` / `charAt` | `find(x) >= 0` / `compare(x) == 0` / `len() == 0` / `s[i]` | 否（一行） | — | 不新增 | 不做 |
| `trim` 之外的空白判断 | `Char.isSpace()` | 否 | — | — | — |
| `repeat(n, out, cap)` | 循环 `concat` | 弱 | 纯 CT | 映射式 | 可选 |
| `padLeft` / `padRight` | 手写循环 | 弱 | 纯 CT | 映射式 | 可选 |
| 严格解析 `parseInt(&end)` / 带进制 | `toInt` 只有 `atoi`，无错误位置 | **是**（解析器/CLI 必需） | 纯 CT | 映射式 | 常用 |
| `toFixed(prec)` / 宽度填充 | 自己 `snprintf` | **是** | libc | 映射式 | 常用 |

### 1.2 字节缓冲与视图（新 substrate）

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| `Buffer`（拥有内存、可增长） | 每个调用点自己 `malloc` + `realloc` + `len/cap` 三元组 | **是**（全仓最大的重复） | libc | 原生 OO | **必备** |
| `Slice`（`char *ptr; int len`，不拥有） | 没有；只能用 `(ptr,len)` 两个参数各传各的 | **是** | 纯 CT | 原生 OO | **必备** |
| `Slice.equals` / `Slice.find`（非 NUL 结尾） | `memcmp` / `memchr` 手写 | **是**（只在有 Slice 后成立） | libc | 原生 OO | 常用 |
| `Buffer.appendInt/Str/Double` | 无 | **是** | libc | 原生 OO | 必备（见 §2） |
| `memcpy` / `memset` 的 OO 外壳 | 直接调，一行 | 否 | — | **不该包**：`void *` 没有合法宿主，包了只是歧义 | 不做 |

### 1.3 容器与算法

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| `VecInt.sort()` / `VecStr.sort()` | 手写冒泡/插入，20–40 行 | **是** | 纯 CT | 原生 OO（加进现有 trait） | 必备 |
| `sortBy(cmp)`（struct 数组） | 手写 | **是** | 纯 CT | 原生 OO，`int (*cmp)(const void*, const void*)` | 常用 |
| `binarySearch(x, &idx)` / `indexOf` | 手写 | **是** | 纯 CT | 原生 OO | 常用 |
| `dedupe()`（有序去重） | 手写下标压缩 | 弱 | 纯 CT | 原生 OO | 可选 |
| `Vec.insert(i,x)` / `remove(i)` | 手写 `memmove` | **是** | libc | 原生 OO | 常用 |
| `Vec.reserve(n)` / `clear()` / `set(i,x)` | 无；`set` 只能碰公开字段 | 弱 | libc | 原生 OO | 可选 |
| `Map.delete(key)` | **没有**，只能 `clear()` 全清 | **是**（map 因此不能当缓存用） | 纯 CT（墓碑标记） | 原生 OO | 必备 |
| `Map.keys(&vec)` / `forEach` | 无，遍历不了 | **是** | 纯 CT | 原生 OO | 常用 |
| `Map` 自动扩容 / 自定义 key | 固定容量，满了 `put` 失败 | 弱（可先 `init` 估大） | libc | 原生 OO | 可选 |
| `Map` 泛型化（任意 key/value） | 不可能 | 语言限制 | — | **不该做**：没有泛型，只能加 `MapLongPtr` 这类复制品 | 不做 |

### 1.4 格式化 / IO

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| 多值格式化（`"%d/%s"`） | **写不出来**（`clib::Stdio.printf` 只有一个值槽） | **是**（最影响日常的一块） | libc | 原生 OO：`Buffer.putInt(...)` 链式 append | 必备 |
| 格式化到字符串 | 自己 `snprintf` + 估算 `cap` | **是** | libc | 同上 | 必备 |
| `stderr` 输出 | `#include <stdio.h>` + `fprintf(stderr,…)`，或没有 | **是** | libc | 映射式（命名空间宿主 `Io.eprint`） | 常用 |
| 读 stdin（整行 / 全部） | `fgets` / `read` 手写循环 | **是** | libc | 映射式或 `Buffer` 方法 | 常用 |
| 读命令行参数 | `main(int argc, char **argv)` | 否（语言已给） | — | 不做 | — |
| `getenv` | 自己 `#include <stdlib.h>` | 弱 | libc | 映射式（`char *` 宿主 `getenv`） | 常用 |
| 文件整读整写 | `fs.readFile` / `writeFile` 已有 | 否 | — | — | — |

### 1.5 文件系统与路径

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| `join` / `basename` / `dirname` / `extname` / `normalize` | `strrchr` + `concat` 手写，边界多 | **是** | 纯 CT | 映射式（`std::fs` 新 trait `PathOps`，宿主 `char *`） | 必备 |
| `remove` / `rename` / `mkdir` | `#include <stdio.h>` / `<sys/stat.h>` 自己调 | **是** | libc / POSIX | 映射式 | 常用 |
| `isDir` / `size` / `mtime` | `stat` 手写 | **是** | POSIX | 映射式 | 常用 |
| `cwd` / `absolute` | `getcwd` 手写 | **是** | POSIX | 映射式 | 常用 |
| `walk`（递归） | `list` + 手动递归 | 弱 | POSIX | 原生 OO（回调式） | 可选 |
| `glob` / 通配 | 无 | 弱 | 纯 CT | 可选 | 可选 |

### 1.6 时间

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| 单调时钟（毫秒 / 纳秒） | `clock_gettime` 自己写，或依赖 hal-posix | **是** | POSIX（`CLOCK_MONOTONIC`） | 映射式（`Clock.nowMs/nowNs`） | 必备 |
| 墙钟时间戳 | `time(0)` 手写 | **是** | libc | 映射式 | 必备 |
| 时间差 / 格式化经过时间 | 减法 + 手写换算 | 弱 | 纯 CT | 映射式 | 常用 |
| 日期分解（年月日时分秒，UTC） | `gmtime` 手写 | 弱 | libc | 映射式 | 可选 |
| 本地日期 / 时区 / DST | `localtime` + `TZ` | **不该进 std**：时区数据库与平台差异会把标准库变成 libc 的镜子 | — | — | 不做 |

### 1.7 数值、位与字符

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| 有符号 `clamp` / `min` / `max` / `abs` | `std::num::Long` / `LLong` 已有 | 否 | — | — | — |
| `unsigned long` / `unsigned long long` 宿主 | 无；位运算却最需要无符号 | **是** | 纯 CT | 映射式（新增 `ULong` / `ULLong`） | 常用 |
| `popcount` / `clz` / `ctz` / `rotl` / `rotr` | 手写循环，5–15 行 | **是** | 纯 CT | 映射式（同上） | 常用 |
| `test/set/clear` 位、`isPowerOfTwo` | `v & (1<<i)` 一行 | 否 | 纯 CT | 映射式（顺手） | 可选 |
| 溢出安全 `add/sub/mul` | 手写边界判断，易错 | **是**（解析器/计费） | 纯 CT（可搬 `__builtin_*_overflow` 的语义） | 映射式 | 可选 |
| ctype 其余 6 个（`isAlnum` `isPunct` `isXdigit` `isCntrl` `isPrint` `isGraph`） | 自己 `#include <ctype.h>` | 弱（补全性） | libc | 映射式（扩 `Char`） | 常用 |
| `Math` 的 `pow` / `log` / `exp` / 三角 / `fmod` / `hypot` | 自己 `#include <math.h>` | 弱（补全性） | libc + `-lm`（已进 `ldflags`） | 映射式（扩 `Math`） | 常用 |
| `Float` / `Real` 的 `min` / `max` / `clamp` | 手写三元 | 弱 | 纯 CT | 映射式 | 可选 |
| 哈希 `hash()`（`char *` / 整数 / 字节段） | map 里的 `hash_str` 是 `static`，外部用不到 | **是**（自定义 key 的前提） | 纯 CT | 映射式 + `hashBytes` | 常用 |
| 自定义 key 的 map | 只能复制一份 map 代码 | **是**，但需要回调式设计 | 纯 CT | 原生 OO（`init(hash_fn, eq_fn, free_fn)`） | 可选 |

### 1.8 错误与可选值

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| 错误码 + 出参 | 全仓统一约定：返回 `0/-1`，值走 `out` | 否 | — | — | 保持 |
| `Option` / `Result` | 可以用 `struct { int ok; int val; }`，但每类型一份 | 语言限制 | — | **不该进 std**：见 §3.3 | 不做 |
| 错误码 → 文案 | ERRNO 用 `strerror`；自有码各写各的 | 弱 | libc | 映射式 | 可选 |
| 空指针安全 | `String` / `fs` 已做，`vec` / `map` 未做 | 弱（一致性问题） | — | 不改语义 | 可选 |

### 1.9 bool 与 enum

| 能力 | 今天怎么写 | 真缺口 | 依赖 | OO 形态 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| `bool` | `int` 0/1，或 `#include <stdbool.h>` | **不是包能解决的**：`bool` 是语言内建问题 | — | **不该包**：`map trait Bool for type int` 会把方法挂到每个 int 上（已明确禁止） | 不做 |
| 布尔格式化 / 解析 | `v ? "true" : "false"` | 否（一行） | — | 不做 | 不做 |
| enum → 字符串 | 手写 `switch` | 语言限制（无反射） | — | 不该 | 不做 |
| struct 的 eq / hash / toString | 手写 | 语言限制（无派生） | — | 不该 | 不做 |

## 2. 三块 substrate：为什么它们排在最前面

缺口表里 60% 的条目不是缺一个函数，而是缺一个**共同的底座**。今天每个模块各自发明一套
`out + cap` / `ptr + len`，导致能力无法组合：

### 2.1 `Slice`（借用视图，纯 CT）

```ct
pub trait SliceOps {
    int  len();
    int  at(int i);
    int  equals(Slice *other);
    int  find(char c);
    Slice sub(int start, int end);   /* 注意：值返回，不分配 */
}

pub struct Slice {
    char *ptr;
    int   len;
} use SliceOps;
```

它解决的是「非 NUL 结尾」这一整类问题：`fs.readFile` 读进来的是长度已知的字节，
`utf8.decode` 需要一个不写到结尾的窗口，协议解析要按 offset 前进。今天这些只能用
「临时写个 `\0` 再还原」这种脏办法。

代价：值返回 `Slice` 需要 CT 支持按值返回带 vptr 的 struct（现有 OO 结构都靠指针调用，
**这一点必须先实测**；若不支持，就改成 `sub(int,int,Slice *out)`）。

### 2.2 `Buffer`（拥有内存，原生 OO）

```ct
pub trait BufferOps {
    int  init(int cap);
    int  reserve(int n);
    int  append(char *data, int n);
    int  appendStr(char *s);
    int  putInt(int v);
    int  putLong(long v);
    int  putDouble(double v, int prec);
    int  putChar(char c);
    char *data();
    int  len();
    int  cap();
    void clear();
    void free();
}
```

`append*` 系列就是 CT 在没有变参时的**格式化答案**：`buf.putStr("x="); buf.putInt(n);`
写起来不如 `printf` 短，但它是这个语言里唯一能组合、能多值、能复用缓冲的形态。
`Buffer` 一落地，`fmt`、`readAll`、`join`、JSON 序列化都变成它的方法，不需要再各造缓冲。

### 2.3 `fmt`（格式化）

`"%d".format(x)` 这种「格式串当宿主」只能做到**一个值**，和 `clib::Stdio.printf` 的天花板一样，
不解决多值问题（配方里也不能第二次引用同一个参数）。所以不建议把 `format` 挂在 `char *` 上，
而是：

- `Buffer` 上的 `putInt/putStr/putDouble` = 多值格式化；
- `char *` 上补 `toFixed` / 严格 `parseInt` = 单值转换；
- `clib::Stdio` 保持不动（用户已明确暂不迁）。

## 3. 逐条回答点名的十块

### 3.1 布尔与字节

`int` 当布尔**可以接受**，不是缺口：C 的整条生态如此，CT 的 `int` 是真值语义，改成 `Bool` 只会
在每次条件判断上插入转换。`bool` 若要成为一等公民，属于语言改动（加类型词 + 真值规则），
不属于 std 包。字节侧的真缺口是 `Buffer`，不是 `bool`。

### 3.2 切片 / 视图

**真缺口，且应统一。** 现在 `String.slice` 是「拷贝到 out+cap」，`utf8`/`fs` 也是各写一套
`out+cap`。统一的表示应该是 `Slice`（`char *` + `int`），现有 `out+cap` 接口保留作为「拷贝出口」，
新接口一律返回 `Slice`。不做泛型 `Slice<T>`（没有泛型），只做字节视图；`int` 视图等真的出现需求再说。

### 3.3 错误与可选值

**不该做 `Result` / `Option`。** 没有泛型的结果是：`IntOption`、`StrOption`、`PtrOption`……
每种一份，且 `use` 会再加一个 vptr。收益是「调用点看起来像 Rust」，代价是每个 API 多一层装箱，
而 CT 现有的 `0/-1 + out` 已经是零成本且全仓一致的。真正缺的是**错误文案**，不是错误类型。

### 3.4 算法

**真缺口，且都在 `vec` 上。** `sort` 是必备；`binarySearch` / `insert` / `remove` / `sortBy` 是常用。
实现放 `VecInt` / `VecStr` 的现有 trait 里（原生 OO），排序自己写（插入排序对小数组够快，
不要为 `qsort` 引入 `void *` 比较函数的类型擦除）。别新增 `std::sort` 命名空间宿主——那样又回到
「数据和操作分离」，与 `vec` 的 OO 形态打架。

### 3.5 格式化

**这是最真实的缺口。** 结论：`format` / `print` 不该做成 `printf` 的仿制品（签名写不出来），
应该做成 `Buffer` 的 append 方法 + `char *` 上的单值转换（§2.3）。`Stdio` 保持现状。

### 3.6 时间与日期

**单调时钟与墙钟都是必备**，但应分两个宿主，语义不能混：
`Clock.nowMs()`（单调，只用于算间隔）与 `Time.nowUnix()`（墙钟，可能被 NTP 调整）。
日期分解只做到 UTC；本地时区/夏令时明确不做（那是 tzdata 的职责，不是标准库的）。

### 3.7 路径

**真缺口，零依赖，纯字符串。** `join` / `basename` / `dirname` / `extname` / `normalize`
应进 `std::fs`，宿主仍是 `char *`，但要**新开一个 trait**（`PathOps`）——同一个宿主上两个 trait
若有同名方法会触发 `ambiguous type-host map`，所以 `FsOps` 不能直接加同名项。
语义只承诺 POSIX（`/`），不猜 Windows。

### 3.8 字符分类

clib 的 `Num` 里混着的 ctype 已经迁到 `std::num::Char`（7 个）。**缺口是补全**：C 的 ctype 有
11 个谓词，现在只有 5 个，缺 `isAlnum` / `isPunct` / `isXdigit` / `isCntrl` / `isPrint` / `isGraph`。
依赖 libc，映射式，扩展现有 `Char` 即可，不需要新模块。

### 3.9 内存

`Arena` 已经覆盖「批量分配、整体释放」。**不建议**再加分配器抽象：CT 没有泛型，
`Alloc` 接口只能靠函数指针，结果是每次分配一次间接调用，且 `malloc` 本来就够用。
`memset` / `memcpy` **不该包 OO**：`void *` 不是合法宿主，包成 `char *` 宿主又会和
`String.copy` 语义重叠（一个有 `\0` 边界，一个按长度）。需要「按长度」的语义，应该落在
`Slice` / `Buffer` 上。

### 3.10 位操作与整数边界

`Long` / `LLong` 解决了有符号整数；**无符号宿主是缺口**（`ULong` / `ULLong`），因为
`popcount` / 移位 / 位掩码在有符号数上语义不干净。**仍然不能挂 `int` 宿主**——理由和这次
迁移一致：`int` 是程序里最常见的类型，挂上去等于给每个整数加方法，歧义面最大。
位扫描用 shim 里的可移植循环实现，不依赖 `__builtin_*`（避免把编译器内建变成 std 的隐式要求）。

### 3.11 哈希

`hash_str` / `hash_int` 现在是 `map` 内部的 `static`，**确实该公开**：自定义 key 的第一步。
建议 `std::hash`：`char *` 宿主 `s.hash()`、`Long`/`LLong` 这里不再加（`hash()` 与已有方法不冲突），
外加 `hashBytes(char *p, int n)`。**但不要急着做「自定义 key 的 map」**：那需要
`init(hash_fn, eq_fn)` 的回调式设计，属于新模块，优先级低于补齐日常能力。

## 4. 依赖分级汇总

| 等级 | 条目 | 备注 |
| --- | --- | --- |
| **纯 CT** | `Slice`、`Buffer` 的增长逻辑、`vec.sort/binarySearch/insert/remove`、`map.delete/keys`、`trim/split/replace`、`parseInt`、路径五个函数、位运算、哈希、时间差 | shim 里可自实现，不新增链接参数 |
| **libc** | `fmt` 的 `snprintf`、`toFixed`、ctype 补全、`remove/rename`、`getenv`、stdin、`strerror` | 不需 `-l` |
| **POSIX** | 单调时钟（`clock_gettime`）、`stat` / `mkdir` / `getcwd` / `walk`（`dirent`） | 需要 `-D_POSIX_C_SOURCE` 或平台头；**这点和 net-posix 的教训一致，必须显式记录，不能偷偷加** |
| **不该进 std** | `bool` 类型、`Option`/`Result`、enum/struct 派生、泛型 map、`memcpy`/`memset` 包装、本地时区、分配器抽象 | 语言限制或收益为负 |

## 5. 建议的落地顺序

按「底座 → 叶子」排，每一步都能独立发版：

1. **`std::slice`**（`Slice`）+ 实测值返回带 vptr 的 struct 是否可用；
2. **`std::buf`**（`Buffer` + `put*`）——格式化、读入、拼接都落在它上面；
3. **`vec` 算法**：`sort` / `sortBy` / `binarySearch` / `insert` / `remove`；
4. **`map`**：`delete` / `keys`；
5. **字符串补全**：`trim` / `split` / `replace` / 严格 `parseInt` / `toFixed`；
6. **`std::fs` 路径**（`PathOps`）+ `remove/rename/mkdir/stat`；
7. **`std::time`**（单调 + 墙钟，UTC only）；
8. **`std::num` 补无符号与位运算**，**`Char` 补 6 个谓词**，**`Math` 补幂/对数/三角**；
9. **`std::hash`**、`std::io`（stderr / stdin / getenv）——最后做，因为它们最不影响正确性。

前 3 步做完，日常程序里「拼字符串 / 排序 / 读文件后解析」这三类手写代码就消灭了。

## 6. 总判断

**按上面补齐（第 1–8 步），一个只用 CT 写日常程序的人基本不会被迫自己手写基础件**：
字符串处理、容器算法、格式化、路径、时间、数值与位运算都有 OO 入口，且每项都能说清
「用哪个模块的哪个方法」。

仍然会剩下的，只有语言层面无解的三类：

1. **泛型容器**（`Map<任意 key, 任意 value>`、`Vec<struct>`）——没有泛型，只能复制模板或退回
   `void *`；这不是 std 的债；
2. **日历/时区/DST**——会引入 tzdata 与平台分歧，明确划出 std 边界；
3. **并发**（线程、锁、原子）——不属于「基本类型能力」，且需要 POSIX，应另立包。

如果只允许做三件事，就做 **`Slice`、`Buffer`、`vec.sort`**：它们覆盖了「手写循环」出现频率最高的三个场景。
