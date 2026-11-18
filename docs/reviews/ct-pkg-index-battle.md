# 包索引仓提案：现状核对、三场对抗与裁定

| 项 | 值 |
| --- | --- |
| 对象 | [ct-pkg-index-proposal.md](/Users/samxx/dsh-ws/ct-lang/docs/proposals/ct-pkg-index-proposal.md) |
| 配套 | [ct-pkg-package-maintainer-rules.md](/Users/samxx/dsh-ws/ct-lang/docs/proposals/ct-pkg-package-maintainer-rules.md) |
| 性质 | 设计评审（一轮对抗）；不改提案、不排期、不代替目标组做受理决定 |
| 基线 | CT `v0.63.2`（2026-11-17）；`ct-pkg/index` 当前 checkout |
| 评审方式 | 三场两席对抗（主张席 / 反证席）+ 客户端现状实测 + 裁判席 |
| 证据边界 | 只读评审；实测均在 `/tmp` 完成；未修改任何仓库文件 |

---

## 0. 结论

**方向受理，原文条款不受理。** 索引由 CI 生成、allowlist、release dispatch + 定时扫描、失败关闭、报告、原子替换这些架构判断成立；但提案把“索引仓能做的”和“CT 必须先支持的”混在一起，且有三个会直接产生错误行为的问题：

1. **全量多版本 + MVS 会让裸名安装静默降级到最老版**（实测 `ct get demo` 在 `0.1.0` / `0.2.0` 两行索引下锁 `0.1.0`）。
2. **“收录所有 semver tag”与身份校验、历史回填三者矛盾**；现有包的大量旧 tag 没有 `publisher` / `ns-root`，不能回填；现有五字段索引里的 `hal` 在 v0.63.2 下直接失败。
3. **digest 权威没有落地**；`ct pkg digest` 不存在，现有 `gen-index.sh` 与客户端已发生可复现的 drift。

建议将本提案拆成两份工作：**索引仓建设**（allowlist、生成器、CI、报告、迁移）和**CT 接口需求**（无 range 取最新、`ct pkg digest`、index pin/verify、yank、身份一致性检查）。签名不作为 v1 门槛。

---

## 1. 现状核对（CT v0.63.2）

提案的六字段格式不是新设计，客户端已经支持：

- `ct get` 接受 `name version publisher git-url tag sha256:<hex>`，也兼容旧的五字段行；同一 `name` 可以多行，取满足范围的最低版本（MVS）。见 [Pkg.h.ct:2103](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2103)、[Pkg.h.ct:2147](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2147)。
- `ct get` 支持 `<publisher>/<name>`；裸名跨 publisher 歧义会硬错（SP-014），见 [Pkg.h.ct:2126](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2126)、[需求 SP-014](/Users/samxx/dsh-ws/ct-lang/docs/planning/ct-pkg-shared-store-requirements.md#L43)。
- 包作者指南已经写明六字段，见 [package-guide.md:103](/Users/samxx/dsh-ws/ct-lang/docs/package-guide.md#L103)。

提案需要补充的现状：

| 事实 | 证据 | 对提案的影响 |
| --- | --- | --- |
| 空 range / `*` 下 MVS 选最低 | [Pkg.h.ct:2147](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2147)；实测见 §8 | 全量索引会让 `ct get demo` 装最老版；必须新增 latest 规则 |
| `ct pkg digest` 不存在 | `ct pkg check` 只查 PK-1/2/5/8，[Pkg.h.ct:1632](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1632) | 提案 §6.4 的“同一套算法”目前无可执行权威实现 |
| 现有索引仓是五字段、每包一行，当前 checkout 已落后 | [index](../../index#L1)；README 仍写“只列最高 tag” | 提案 §0“index 仓尚不存在”按 ct-pkg 语境不准确；需要写替换/升级/另建 |
| 现有索引的旧行在 v0.63.2 下不可消费 | 实测 `ct get --index ct-pkg-index/index hal` 报 `is missing 'publisher'` | “冻结旧索引”不够；旧行对当前客户端是坏的 |
| 旧 tag 大量缺身份 | `std v0.1.0` / `v0.2.0` 的 `ct.pkg` 无 `publisher`、`ns-root`；反证席统计 24 个 `v*` tag 中 15 个缺身份（需按包复核） | §8“收录所有 tag”+ §6 身份校验 + §11 回填历史三者矛盾 |
| 客户端不校验行内 publisher/version 与 `ct.pkg` | 实测索引写 `evil`、包内写 `good`，`ct get evil/demo` 成功并锁成 `good/demo` | 需要明确“谁是身份权威”，或给客户端加检查 |
| 客户端无索引验签、lock 不记 index 身份 | [Pkg.h.ct:2057](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2057) 只 `fopen`；lock 行见 [Pkg.h.ct:1029](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1029) | “可签名/可 pin”目前没有消费端 |
| tag 解析只取前三段数字 | `version_parse` 用 `sscanf("%d.%d.%d")` 且 `n>=1`，[Pkg.h.ct:444](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L444) | `1`、`1.2`、`1.2.3-rc1` 会被 `version_parse` 接受；`git_pick_tag` 还会先剥 `v`，所以 `v1` 也能走 tag 路径。必须收窄 tag 语法 |
| 客户端有行/路径/文件数上限 | `MAX_PKG_LINE=1024`、`MAX_PKG_PATH=512`、`MAX_DIGEST_FILES=4096`，[Pkg.h.ct:25](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L25)、[Pkg.h.ct:131](/Users/samxx/dsh-ws/ct-lang/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L131) | 生成器必须 fail closed，不能静默截断 |

---

## 2. Battle 1：每版本一行 vs 每包一行

### 2.1 主张席（每版本一行）

1. **MVS 的 min 依赖历史行存在**。两行索引下 `demo@>=0.1.0` 锁 `0.1.0`；删掉 `0.1.0` 行后同一范围锁 `0.2.0`。这不是可选优化，而是解析结果变化。
2. **可复现与回滚**。`ct.lock` 只钉包自身 commit/digest；`ct get` 不把 lock 当解析源。没有旧行时，无 store 的新环境无法从旧 lock 重建。
3. **撤回粒度**。每版本一行可以只撤回坏版本；每包一行撤回最新版时，要么老项目无法重建，要么继续把坏版本当唯一可见版本。
4. **体积和 diff**。索引是文本，12 包约 150B/行；追加式 release 只加一行，比每包一行“改一行”更容易 review。
5. **客户端已经支持多行**。旧仓“每包一行”是 `refresh-index.sh` 取最高 tag 的策略，不是格式契约。

### 2.2 反证席（每包一行 / 受控窗口）

1. **空 range / `*` 会装最老版**。MVS 取最低，`ct get demo`、`ct get demo@*` 在双行索引下都锁 `0.1.0`；当前单行索引把这个问题藏住了。
2. **旧漏洞版本永远可解析**。没有客户端 yank/advisory 语义，保留旧行等于保留一条永久可安装的路径；删行又挡不住固定旧 index 或已有 cache/store 的人。
3. **回填不可行**。旧 tag 缺 `publisher`/`ns-root`，`ct get` 直接失败；能进全量的只是契约迁移后的 tag，恰好可能不含旧编译器最需要的旧 `std`。
4. **旧 lock 不靠全量行**。lock 自带 commit/digest，store 在时 `ct install` 仍可离线安装；复现旧版本应靠 index 快照/tag pin，而不是活索引里的永久旧行。
5. **攻击面**。低版本可以被后补进索引，MVS 下会被裸名或 `*` 选中；latest-only 无法表达“更低版本”，反而少一条投毒路径。

### 2.3 裁判席：部分受理

**受理“多版本行”格式**，因为依赖范围和 MVS 确实需要历史版本；**不受理“全量直出、无 latest 规则、删行即撤回”**。

接受条件：

1. **新增 latest 规则**：无 range 取最高（CT 改动），range 仍 MVS；或者索引额外提供 `latest` 视图供 `ct get` 读取。二者必须选一个，否则不能上线。
2. **append-only，只收满足当前身份契约的版本**；每个包定义“首个有效 tag”；pre-identity tag 进独立 legacy 索引或不收。
3. **撤回用独立 yank/advisory**，客户端可消费；删行只作为“新解析不可见”的辅助手段，不宣称是安全撤销。
4. **旧 lock 复现**要区分两种情况：store 还在时 `ct install` 可离线；store 不在、又没有旧行时，必须靠 index 快照/archive，不能只靠 `ct.lock`。

如果目标组不愿改 CT 的 latest 行为，那么活索引只能继续每包一行；多版本行放 `index.archive` / `index.full`，但依赖范围解析仍不完整——这条路要明确写出来，不能假装两者兼得。

---

## 3. Battle 2：签名并验签 vs 只靠 pin

### 3.1 主张席（签名 + 客户端验签）

1. **当前信任根只是文件路径**。`CT_INDEX` 指向任意本地文件，`ct get` 不看来源；`ct.lock` 不记 index commit/签名者。签名若不进客户端，等于没有。
2. **受保护分支与 CI 同域**。能改 index workflow、换 action、偷 token 的人，也能用 CI secret 签名；密钥必须与 CI 写权限分离（维护者硬件 key / 2-of-3 / OIDC keyless）。
3. **首次 clone 是 TOFU**。签名把信任从 CA/DNS/默认分支收缩到固定 key，且可离线验证；pin 只对“已带外验证过的 pin”生效。
4. **可复现 ≠ 可信**。可复现的恶意索引仍是恶意；allowlist 挡不住已允许仓库被投毒。签名提供可归因、可撤回的 provenance。

### 3.2 反证席（pin 优先）

1. **签名不防回滚/重放**。撤回后重放“撤回前的合法签名索引”，验签仍通过；pin commit/摘要直接拒绝。抗回滚要 TUF 级新鲜度，是另一量级工程。
2. **CI 内签名不越权**。密钥进 CI secret，就等于“能改 CI 的人能签”；OIDC keyless 的证书身份是 repo+workflow+ref，能推 main 的人仍能拿合法证书。真正拦住写权限者的是 PR 审核 + 行级语义检查 + pin。
3. **客户端没有验证器**。Pkg 层只有 SHA-256；没有 `ct index verify`，没有 keyring 约定；失败关闭会卡死离线机，失败开放等于没做。
4. **签名不约束“这行该不该在”**。被攻破的维护者合并一行恶意记录，签名照样通过；逐行审版本/digest 变化比签整份文件更有用。
5. **pin 零新密码学**。`git rev-parse` + `shasum` 即可判定 index 身份；把 index commit/摘要写进 lock 是可执行的。

### 3.3 裁判席：v1 受理 pin，签名暂不受理

1. **先做 index 身份 pin**：`ct.lock` 记录 index url/commit/sha256（v3 或兼容注释头）；`ct get` / `ct install --locked` 默认校验。没有这个，“可 pin”是空话。
2. **索引改动走 PR + CODEOWNERS + 受保护分支**；CI 只生成，合并留人工痕迹；不要让 bot 直接 push main。
3. **签名作为 v2/条件项**：若做，优先 **signed tag/commit + `git verify-tag`**（维护者硬件 key，非 CI secret），或 OIDC keyless + 客户端信任根；不要 detached `index.sig` 无人验。
4. **若 v1 不做签名，删掉“可签名”的既成事实口吻**，明写“v1 无来源认证；控制是 allowlist + 受保护提交 + 可复现生成 + pin”。签名也不防回滚，仍需 pin + advisory。

---

## 4. Battle 3：CT 提供 digest vs 共享脚本

### 4.1 主张席（`ct pkg digest`）

1. **digest 是客户端验收承诺**。客户端每次重算并硬失败；只有 CT 自己的代码能结构性保证“我会算什么”。
2. **现有 drift 都在适配层**。CT 用 `stat` 跟随符号链接、任意深度跳过 `.git/vendor/.ctcache`、`strcmp` 排序、4096/512 上限；`gen-index.sh` 用 `find -type f`、顶层排除、`LC_ALL=C sort`、`cat`。实测嵌套 `vendor/`、文件/目录符号链接、4096/4097、换行文件名都会分叉。
3. **成本低**。已有 `pkg check` 入口和 `dir_digest`；新增只读子命令不需要新依赖。
4. **可版本化**。索引/报告记录 `# generator ct vX.Y.Z`；旧行永不用新生成器重算；语义变更升 schema，客户端对未知 schema 失败关闭。

### 4.2 反证席（共享脚本 / 小库）

1. **发布解耦**。索引 CI 绑定 CT 版本会拖慢 nightly；复现旧行需要当年 CT 与工具链，脚本在 index 仓 git 里可永久重放。
2. **脚本可以 fail closed**。超 4096、近 512、符号链接环、FIFO/设备、换行名、CRLF 不确定等一律不写索引；错误方向只是“少收录”。
3. **权威在验收端**。最终验收是真实 `ct get --index` 能消费生成的索引；脚本 + golden + 真实客户端比“命令存在”更直接。
4. **现有 drift 是 bug，不是脚本形态必然错**。修好 `find`/`stat`/嵌套 vendor 并加 fixture 即可；CT 的 `dir_digest` 自身还有绝对路径长度依赖，命令也会继承。

### 4.3 裁判席：长期契约受理 CT 命令，过渡期只接受 canonical 脚本

1. **向 CT 提 `ct pkg digest <dir>`**（只读、无网络、调 `dir_digest`），作为独立交付；索引 CI pin CT 版本，索引/报告记录生成器版本。
2. **命令落地前**，脚本必须：病态 fixture 全覆盖；不确定就拒绝写索引；生成后用真实 `ct get`/`ct install` 消费并比对 digest；不能直接复用现有 `gen-index.sh`。
3. **修 CT digest 的边界**（符号链接是否跟随、路径长度、文件数上限），或者索引只接受 canonical 树（无符号链接、无保留目录名、路径/文件数受限）。否则“同一 tag 重跑逐字节一致”不成立。
4. **索引 schema 带算法版本**；旧行冻结，语义变更新 schema + 迁移，不让旧行被新生成器重算。

---

## 5. 其余必须修的条款

| 级别 | 问题 | 建议 |
| --- | --- | --- |
| P1 | §8“同名跨 publisher 用 publisher/name 消歧；生成器发现歧义即失败”自相矛盾 | 两行都收；只在 `(publisher,name,version)` 重复且 url/tag/digest 不一致时失败；裸名歧义留给 `ct get`（SP-014 的测试正需要双 publisher 索引） |
| P1 | 客户端不校验 index 行的 publisher/version 与 `ct.pkg` 一致 | 要么 `ct get` 加一致性检查，要么明确“`ct.pkg` 是权威，index publisher 只是查找键”；不能两边都默认对方校验 |
| P1 | tag 语法未定 | 收窄为 `v?X.Y.Z`，明确 prerelease/build/两段版本排除；`version_parse` 现在会接受 `1`、`1.2`、`1.2.3-rc1`，`git_pick_tag` 还会剥 `v` |
| P1 | §6.5“同版本原子替换” vs §8“不重建同版本” | 重跑同 tag 必须逐字节一致（no-op）；digest 变化 hard fail + report，不替换；替换只用于新增版本 |
| P1 | §6.1 定时扫描只写“尚未收录的 repo” | 会漏掉已有包的新 tag；改为扫描所有 allowlist repo 的 tags 与 index 差集 |
| P1 | 撤回只删行/标记，无客户端语义 | 加 yank/advisory 列表；`ct get` 默认跳过 yanked，精确 pin 可覆盖；否则明确“只影响新解析” |
| P2 | 排序/确定性未定义 | 按 `(publisher,name,version numeric)` 排序，`LC_ALL=C`；报告里的时间/commit 不进 index；“逐字节一致”只断言 index，报告另算 |
| P2 | reports 每次时间戳导致空转 diff | 报告作为 artifact 或仅在 index 变化时提交；报告时间不参与 index 确定性 |
| P2 | 索引行/路径长度未约束 | `MAX_PKG_LINE=1024`、`MAX_PKG_PATH=512`；生成器超限必须 fail closed，不能静默截断 |
| P2 | 迁移只写“冻结旧索引” | 旧索引五字段且 `hal` 直接失败；需逐包列首个有效 tag、旧 tag 进 legacy、旧索引重定向/公告、包仓补新 release |
| P2 | 没有 owner/SLA/回滚/安全联系 | 索引仓要有 CODEOWNERS、allowlist 审核 SLA、坏索引回滚流程、安全联系人 |
| P2 | CI 安全未写 | pin third-party actions、最小权限、PR 不带 secret、生成/发布分 job、禁止 `pull_request_target` 带 secret |
| P2 | §0 没有现状核对 | 加一张“已交付/待交付”表，否则读起来像要重造客户端 |

---

## 6. 受理建议

### 6.1 对 §14 五个问题的建议

| 问题 | 建议 |
| --- | --- |
| 1. 是否受理 | **部分受理**：受理 CI 生成 + allowlist + dispatch/扫描 + 失败关闭 + 报告；P0 修完前不进入实现 |
| 2. dispatch + 定时扫描 | 受理。dispatch 只当“提示”，不信任 payload；定时扫描**所有** allowlist 包的 tags；加 concurrency/重试 |
| 3. 签名与验签 | v1 先 pin，不把签名当门槛；若做签名，signed tag/commit + 客户端 `git verify-tag` 或 OIDC keyless，不做无人验的 `index.sig` |
| 4. digest 接口 | 向 CT 提 `ct pkg digest`；过渡期 canonical 脚本 + fail-closed + 真实 `ct get` 验收；不复用旧 `gen-index.sh` |
| 5. 新 index 仓与首版范围 | 若目标为 ct-pkg：**替换/退役**现有 `ct-pkg/index`，不要双写；首版只收满足当前身份契约的 tag，旧 tag 进 legacy，不做全量回填 |

### 6.2 责任拆分

| 能力 | 归属 | 现状 |
| --- | --- | --- |
| 六字段索引、`publisher/name`、裸名歧义、MVS | CT | 已交付，无需重做 |
| 无 range 取最新 | CT | 缺失；不改则不能上全量索引 |
| `ct pkg digest` | CT | 缺失；索引生成器的权威依赖 |
| index pin / verify | CT | 缺失；`ct.lock` 不记 index 身份 |
| yank/advisory 消费 | CT | 缺失；只有索引侧标记不够 |
| 行内 publisher/version 与 `ct.pkg` 一致性 | CT 或索引生成器 | 当前客户端不校验；需明确权威 |
| allowlist、生成器、CI、报告、迁移 | 索引仓 | 本提案的主体 |
| 旧 tag 的前置身份修复 | 包仓 | 需补新 release，不能回填 pre-identity tag |

---

## 7. 最小验收集

1. 索引行能被 pinned `ct` 解析；`ct get pub/name@range` 选对版本；无 range 选最新（新规则）。
2. 同一 `(pub,name,version)` 不同 digest 必须失败；同内容重跑逐字节一致。
3. 双 publisher 同名包都能收录；裸名 `ct get name` 报歧义并给出两个限定名。
4. index 行与 `ct.pkg` 的 publisher/version 不一致时，按选定策略失败或明确告警。
5. digest fixture：嵌套 `vendor/`、文件/目录/循环符号链接、4096/4097、512 路径、CRLF、换行文件名；要么与 CT 一致，要么 fail closed。
6. tag 语法：`v1`、`1.2`、`1.2.3-rc1`、`1.2.3+build` 按规则拒绝/忽略，不产生碰撞。
7. 新 tag 在没有 dispatch 时能被定时扫描发现；重复 dispatch 幂等；并发运行不产生冲突。
8. 撤回后新解析拿不到 yanked 版本；旧 lock+store 仍可安装；无 store 时可用 index 快照/archive 重建。
9. 迁移：旧五字段索引明确退役；pre-identity tag 不进新索引；当前契约 tag 能消费。
10. pin：index commit 不匹配时 `ct install --locked` 失败；回滚/重放有明确处置。

---

## 8. 复现附录

以下实验均在 `/tmp` 完成，未修改仓库。

### 8.1 裸名/空范围在双行索引下选最老版

```text
index:
  demo 0.1.0 acme <url> v0.1.0 sha256:...
  demo 0.2.0 acme <url> v0.2.0 sha256:...

ct get --index ./index demo        -> 0.1.0
ct get --index ./index demo@*      -> 0.1.0
ct get --index ./index demo@>=0.1.0 -> 0.1.0
ct get --index ./index demo@^0.2.0 -> 0.2.0
```

### 8.2 现有五字段索引在 v0.63.2 下不可消费

```text
$ INDEX=/path/to/ct-pkg-index/index
$ ct get --index "$INDEX" hal
ctc: '.../ct.pkg' is missing 'publisher'
rc=1
```

### 8.3 `gen-index.sh` 与 `ct` 的 digest 分叉

同一棵树、基线与顶层 `vendor/` 一致；差异出现在：

```text
嵌套 vendor/：gen 收录，ct 跳过          -> digest DIFF
符号链接文件：gen 的 find 跳过，ct 的 stat 收录 -> digest DIFF
```

### 8.4 index publisher 与 `ct.pkg` 不一致仍能安装

```text
index: demo 0.1.0 evil <url> v0.1.0 sha256:<匹配>
ct.pkg: publisher = good

$ ct get --index ./index evil/demo
installed 1 package(s)
ct.lock: good/demo 0.1.0 git ... sha256:<匹配>
```

### 8.5 没有 `ct pkg digest`

```text
$ ct pkg --help
usage: ct install [--force]
...
# 只路由到 install_main；没有 digest 子命令
```

---

## 9. 待目标组裁定

1. 目标仓是替换 `ct-pkg/index`，还是另建新仓？两条路的迁移成本不同。
2. 是否接受 CT 侧为“无 range 取最新”和 `ct pkg digest` 开需求；若都不做，索引只能保持 latest-only。
3. v1 是否接受“pin 先行、签名延后”；若签名，采用 signed tag/commit 还是 OIDC keyless。
4. 旧 tag 的 legacy 索引是否保留、给谁用、保留多久。
5. 索引仓的 owner、allowlist 审核 SLA、坏索引回滚/安全响应联系人。
