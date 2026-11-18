# 提案（修订草案 v2）：包索引仓的生成、签名与消费

> **状态：修订草案，未受理。** 本稿基于 [原提案](/Users/samxx/dsh-ws/ct-lang/docs/proposals/ct-pkg-index-proposal.md) 与
> [对抗评审](ct-pkg-index-battle.md)。是否受理、编号、落点与排期仍由目标项目组决定。
>
> 正文仍用 `index 仓`、`pkg 仓` 占位。与 v1 的主要差异见 §15。

## 0. 交付信息

| 项 | 内容 |
| --- | --- |
| 现象 | 消费者执行 `ct get <publisher>/<name>` 时，若未设置 `CT_INDEX`/`--index`，直接报 `no index resolver`；组织没有一份与当前 `ct.pkg` 契约一致、可审计、可 pin 的索引。 |
| 最小复现 | `ct get <publisher>/<name>`，rc≠0，stderr 含 `no index resolver`；设置一个索引文件后可解析。 |
| 期望行为 | 由 `index 仓` 在包 release 后生成/更新索引；索引确定、可 diff、可 pin；消费者只消费固定索引，不在客户端扫描组织。 |
| 影响范围 | 所有使用 publisher 限定名安装包的项目；不改变裸名经 `CT_REGISTRY` 的现有路径。 |
| 实测版本 | CT `v0.63.2`（2026-11-17）。六字段索引、`publisher/name`、裸名歧义、MVS 已在客户端交付；本提案主要改索引仓的生成与消费契约。 |
| 承诺对应 | 目标 `index 仓` 尚无索引契约；CT 侧新增需求见 §14.2。 |

### 0.1 现状核对（必须写进提案）

- `ct get` 已接受六字段 `name version publisher git-url tag sha256:<hex>`，并兼容旧五字段；同一 name 可多行，按 MVS 取最低满足版本。
- 裸名跨 publisher 歧义已在客户端硬错（SP-014）。
- `ct pkg digest` **不存在**；`ct pkg check <dir>` 只查 PK-1/2/5/8。digest 权威需要 CT 新命令或严格受限的过渡脚本。
- 现有 `ct-pkg/index` 是五字段、每包一行、仅最高 tag；当前 checkout 已落后，且旧行（如 `hal`）在 v0.63.2 下会因缺 `publisher` 失败。它是 legacy 索引，不是本提案的可用基线。
- 大量旧 tag（如 `std v0.1.0` / `v0.2.0`）没有 `publisher` / `ns-root`，不能回填进新索引。

## 1. 一句话

**索引由 `index 仓` 的 CI 生成，不由 `ct` 客户端扫描生成；新包在“首次有效 release”后进入索引；索引收录满足当前契约的版本，但“直接安装”默认取最新，依赖解析才走 MVS。**

## 2. 目标 / 非目标

**目标**

- 新增/发布包后，索引在可预期时间内更新；
- 索引行可追溯：包名、版本、publisher、git URL、tag、tree digest；
- 生成过程确定、可重放、可 diff；
- 支持固定 index commit/tag，消费者可审计；
- 消费者可用 `git clone` + `CT_INDEX` 消费。

**非目标**

- 不让 `ct` 内置 HTTP 客户端或 GitHub API；
- 不扫描组织下所有仓库并自动信任；
- 不代替包仓做构建/测试；
- 不自动决定包是否“可信”；
- 不改变 `CT_REGISTRY` 的裸名语义；
- v1 不把密码学签名作为门槛（见 §9；pin 先行）。

## 3. 索引是什么

索引是纯文本、空白分隔的六字段行：

`name version publisher git-url tag sha256:<64 hex>`

- 一行对应一个**满足当前 `ct.pkg` 契约的版本**；同一个包可以有多行。
- 依赖解析按版本范围取最低满足版本（MVS）。
- **直接安装（无 range）必须取最新版本**。建议 CT 侧修改：无 range 时取最高，有 range 时仍 MVS。若 CT 不改，`index` 仓必须额外提供 `latest` 视图并让 `ct get` 读取；否则本提案不能进入实现。
- tag 语法收窄为 `v?X.Y.Z`；`ct.pkg` 的 `version` 必须与 tag 的 `X.Y.Z` 完全一致。prerelease / build metadata / 两段版本不入索引。
- 索引首行建议写 `# index-schema: 1`（客户端跳过 `#` 注释），用于算法/字段演进；旧行不因生成器升级而重算。
- 单行长度必须小于客户端 `MAX_PKG_LINE=1024`；超限 fail closed。

索引是 `index 仓` 的构建产物，不是包仓的附属文件。

## 4. 仓库布局

- `index`：生成的纯文本索引；
- `index.sha256`：`index` 的摘要，便于手工/pin 校验；
- `latest`（可选）：若 CT 未改“无 range 取最新”，提供独立最新视图；不要把它混进六字段 `index`；
- `schema.md`：六字段、tag/版本规则、yank 规则；
- `packages.txt`：允许自动收录的 `pkg 仓` allowlist；
- `tools/gen-index`：生成器（固定版本、可重放）；
- `tools/pkg-digest`：过渡期 canonical digest 脚本（若 CT 尚无 `ct pkg digest`）；
- `.github/workflows/index.yml`：CI；
- `reports/`：每次生成的校验报告（成功/跳过/失败原因）；
- `index.archive`（可选）：legacy / pre-identity tag 的只读索引，不与活索引混用。

包仓不得直接写 `index 仓`；只有 `index 仓` 的 CI 能生成。索引改动建议走 PR + CODEOWNERS 审核，而不是 bot 直接 push 受保护分支。

## 5. 事件模型

| 事件 | 用途 | 说明 |
| --- | --- | --- |
| `repository_dispatch`（`pkg-release`） | 主路径，近实时 | 包仓 release/tag 后通知；payload 只当提示，**不信任**其中的 repo/tag，必须回 allowlist 与真实 refs 校验 |
| `schedule`（如每 15–60 分钟） | 兜底 | 扫描**所有** allowlist 包的 tags，与 index 差集；不是只扫“尚未收录的 repo” |
| `workflow_dispatch` | 手动 | 指定包/版本重跑 |
| org webhook + GitHub App/relay | 可选 | 仅当确实需要“新仓库近实时”时；成本高，不建议先做 |

GitHub Actions 没有原生的“组织下新建 repo”事件能直接触发另一个仓库的 workflow；新仓库仍以首次有效 release 为准。

## 6. 生成流程

1. 取事件：dispatch 的 repo/tag，或定时扫描 allowlist 的 tags；对已有包的新 tag 也要发现。
2. 过滤：必须在 `packages.txt`；有 `ct.pkg`；不是 archived/fork/private/空仓库；tag 符合 `v?X.Y.Z`；有可收录版本。
3. checkout 该 tag 到**固定短路径**临时目录；校验 `ct.pkg`：`name`、`publisher`、`ns-root`、`version` 与 tag/索引身份一致；`ns-root` 相对、存在、无 `..`；`publisher` 不是保留字。
4. 计算 tree digest：优先调用 `ct pkg digest`；没有该命令时，用 canonical 脚本并 fail closed。**禁止生成器与客户端各写一套语义不同的实现。**
5. 更新索引：同 `(publisher,name,version)` 且 url/tag/digest 相同 -> no-op；新版本 -> 追加；同 key 但 digest/url/tag 不同 -> **hard fail + report，不替换**；按 `(publisher,name,version numeric)` 排序，`LC_ALL=C`。
6. 在干净环境用生成的 index 跑一次 `ct get --index`/`ct install` 消费夹具；摘要必须匹配；依赖也要覆盖。
7. 失败只写报告、不写索引。
8. 提交与发布：只有 `index`（或 `index.sha256`）发生变化时才提交；报告作为 CI artifact 或按运行 ID 归档，不要因为报告时间戳产生空转 commit；打 index 版本 tag；签名若启用，另见 §9。
9. 消费者 `git fetch` + checkout 固定 commit/tag；不建议直接 `git pull` 生产索引。

## 7. 新仓库如何进入

- 不因“仓库创建”写入索引；没有 tag/`ct.pkg` 的仓库没有可消费版本。
- 首次合法 release 后，由包仓 workflow 发 `pkg-release`；未配置 dispatch 的，由定时扫描兜底。
- 新仓库需先进入 `packages.txt`（PR + 审核），再被扫描/接收。
- 被跳过的仓库在报告中写原因，不静默。
- 每个包定义“首个有效 tag”（满足 `publisher`/`ns-root` 契约）；pre-identity tag 不进活索引。

## 8. 版本、撤回与保留

- 收录满足当前契约的 tag；prerelease/draft 默认排除。
- **append-only**：不移动 tag、不重建同版本；内容变化只能发新 patch。
- 同 `(publisher,name,version)` 重跑必须逐字节一致；digest 变化按“tag 被移动”处理，hard fail，不替换。
- 同名跨 publisher 用 `publisher/name` 消歧；**索引生成器不得因跨 publisher 同名而失败**——两行都收。只有当 `(publisher,name,version)` 重复且 url/tag/digest 不一致，或身份不匹配时失败。裸名歧义留给 `ct get`。
- 撤回：优先用独立 yank/advisory（客户端可消费）；删除行只表示“新解析不可见”，不是安全撤销。已有 `ct.lock` + store 仍按 digest 安装；无 store 的复现需 index 快照/archive。
- 旧版本保留：活索引保留所有满足契约的版本；若需要容量控制，另建 archive/窗口，但不得静默删除导致旧 lock 无法重建。
- 历史 index 版本保留 tag，便于复现。

## 9. 安全与权限

- `packages.txt` 是 allowlist，不扫全组织；allowlist 变更走 PR + CODEOWNERS。
- `index 仓` 使用 GitHub App/细粒度 token，最小权限；token 只读包仓、只写 `index 仓`。
- CI 安全：pin third-party actions、最小 `permissions`、PR 不带 secret、生成/发布分 job、禁止 `pull_request_target` 带 secret。
- 包仓 tag 保护、2FA、CODEOWNERS；被攻破的包仓不能靠“自动发现”洗白。
- **v1 信任控制是 pin，不是签名**：`ct.lock` 记录 index url/commit/sha256；`ct get`/`ct install --locked` 校验；索引改动走受保护 PR，保留人工合并痕迹。
- 签名作为 v2/条件项：若启用，优先 signed tag/commit + `git verify-tag`（维护者硬件 key，非 CI secret），或 OIDC keyless + 客户端信任根；不做无人验证的 detached `index.sig`。签名不防回滚/重放，仍需 pin + advisory。
- 生成器记录自身版本、源 commit、生成时间；**index 本身确定**，报告可含时间，但不要把时间写进 index；报告不参与“逐字节一致”断言。
- 失败关闭：校验失败、digest 不一致、身份不匹配一律不写索引。

## 10. 客户端消费

- 消费者 `git clone`/`git fetch` `index 仓`，checkout 固定 commit/tag；
- `CT_INDEX=<checkout>/index ct get <publisher>/<name>[@<range>]`；
- 生产环境固定 index commit/tag，升级前 diff；
- 不在 `ct` 客户端内自动扫描组织；未来若要 `ct index update`，另立提案，只走 git 拉取，不内置 HTTP。
- **CT 侧请求**：无 range 取最新；`ct pkg digest`；index pin/verify；yank/advisory；行内 publisher/version 与 `ct.pkg` 的一致性检查（或明确 `ct.pkg` 为唯一权威）。

## 11. 迁移步骤

1. 建 `index 仓`，写 `schema.md`、`packages.txt`、生成器与 CI。
2. 逐包盘点：列出每个包**首个满足当前 `ct.pkg` 契约**的 tag；pre-identity tag 不进活索引。
3. 先收录少量当前契约包（例如已具备 `publisher`/`ns-root` 的 `std`、`json` 等），手工核对 digest 与 `ct get` 行为。
4. 生成首版 `index`，记录 index commit/sha256；在干净工程用 `CT_INDEX` 跑 `ct get`/`ct install`。
5. 通知包仓接入 release dispatch；定时扫描兜底。
6. 旧五字段索引**退役/重定向**，不是简单冻结：它对 v0.63.2 已经不可消费；旧编译器用户走 legacy 索引/旧 lock。
7. 需要进新索引但旧 tag 缺身份的包，由包仓补新 release（不能移动旧 tag）。

## 12. 验收建议

- 索引行能被 pinned `ct` 解析；`ct get pub/name@range` 选对版本；无 range 选最新。
- 同一 tag 重跑生成器，`index` 逐字节一致（同一 pinned 生成器、同一短路径）。
- 无 tag/无 `ct.pkg`/publisher 不匹配/身份不匹配的仓库不写入，报告有原因。
- 双 publisher 同名包都能收录；裸名 `ct get name` 报歧义并给出两个限定名。
- 撤回后新解析拿不到 yanked 版本；旧 lock+store 仍可复现；无 store 时可用 index 快照/archive 重建。
- 索引 commit 可 pin；`ct install --locked` 在 commit 不匹配时失败。
- 生成器失败不会留下半写索引（原子替换）。
- digest fixture：嵌套 `vendor/`、文件/目录/循环符号链接、4096/4097、512 路径、CRLF、换行文件名；要么与 CT 一致，要么 fail closed。
- tag 语法：`v1`、`1.2`、`1.2.3-rc1`、`1.2.3+build` 按规则拒绝/忽略，不产生碰撞。
- 新 tag 在没有 dispatch 时能被定时扫描发现；重复 dispatch 幂等；并发运行不产生冲突。

## 13. 风险

| 风险 | 处置 |
| --- | --- |
| 组织内新仓库被误收录 | allowlist + `ct.pkg` + 审核；不扫全 org |
| digest 算法漂移 | 优先 `ct pkg digest`；过渡脚本 fail closed；生成器固定版本；真实 `ct get` 验收 |
| GitHub API 限流/权限 | GitHub App/PAT、分页、缓存；失败不写 |
| tag 移动/重建 | 禁止；digest 变化即拒绝，要求新 patch |
| 索引供应链攻击 | allowlist、受保护 PR、pin、审计；签名作为 v2 条件项 |
| 客户端自动扫描 | 明确不做；只消费固定索引 |
| 全量旧版本被 MVS 选中 | 无 range 取最新；yank/advisory；依赖范围显式 |
| 旧 tag 无法回填 | 只收当前契约 tag；包仓补新 release；legacy 索引另存 |
| 索引仓/包仓身份不一致 | 生成器校验 + 客户端一致性检查（或明确权威） |

## 14. 请求

### 14.1 请目标组决定

1. 是否受理本修订稿；
2. 是否采用“release dispatch + 定时扫描所有 allowlist tags”作为主/兜底；
3. 是否接受“v1 pin 先行、签名延后”；若签名，采用 signed tag/commit 还是 OIDC keyless；
4. 生成器用 CT 提供的 `ct pkg digest`，还是过渡期 canonical 脚本；
5. 是否替换现有 `ct-pkg/index`，以及首版收录范围。

### 14.2 需要 CT 侧同步评估的接口

- 无 range 时取最新（否则全量索引会默认装最老版）；
- `ct pkg digest <dir>`（只读、无网络）；
- index pin/verify（`ct.lock` 记录 index 身份，`ct install --locked` 校验）；
- yank/advisory 的客户端消费；
- index 行 publisher/version 与 `ct.pkg` 的一致性检查，或明确 `ct.pkg` 是唯一权威。

## 15. 相对 v1 的改动

| v1 | v2 |
| --- | --- |
| “index 仓尚不存在” | 明确现有 `ct-pkg/index` 是五字段 legacy 索引，需替换/退役，不是可用基线 |
| 一行一个版本，未定义无 range 行为 | 多版本 + **无 range 取最新**；否则不上线 |
| “收录所有 semver tag” | 只收满足当前 `ct.pkg` 契约的 tag；pre-identity tag 进 legacy，不回填 |
| “同包同版本原子替换” | 同内容 no-op；digest 变化 hard fail，不替换 |
| “生成器发现歧义即失败” | 跨 publisher 同名两行都收；只对重复 key/身份不一致失败 |
| 签名/提交/pin 三者并列 | v1 pin 先行；签名 v2 条件项；不做无人验的 detached sig |
| digest 复用“脚本或 CT 命令” | 长期契约 `ct pkg digest`；过渡脚本 fail closed + 真实客户端验收 |
| 定时扫描“尚未收录的 repo” | 扫描所有 allowlist tags，与 index 差集 |
| 只写“冻结旧索引” | 旧索引退役/重定向；逐包首个有效 tag；包仓补新 release |
| 未拆责任 | §14.2 明确 CT 侧接口；索引仓只负责生成/allowlist/报告/迁移 |
