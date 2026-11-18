# 需求池 — ct-pkg/index

> 字段按主规范 6.1 P-3：`id`、`what`、`why`、`priority`、`status`、`owner`、
> `last-touched`、`block`。前七项非空；`block` 为空即"未阻塞"。
> `status` 只允许 `open` / `planned` / `in-phase` / `dormant` / `rejected` / `done`。
>
> 本池条目来自 2026-11-18 对《ct-pkg/index 项目意见书》的评估。评估结论：
> 意见书第一部分（文档漂移）成立且被低估；第二部分 2.1 已被同日改动超越；
> 2.3 / 2.4 成立，其中 2.4 应升级为缺陷。评估还发现意见书未覆盖的 nightly 阻塞。

| id | what | why | priority | status | owner | last-touched | block |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IDX-1 | 解除 nightly `refresh-index.sh --all-tags` 的 fail-closed 阻塞：`packages.txt` 中 9 个旧仓的最 `v*` tag 缺 `publisher` / `ns-root`，任务每个夜间在首个此类仓中止 | 自动刷新实质停摆；索引能用的前提是 nightly 绿 | P0 | open | REQ | 2026-11-18 | 待用户在 A（各仓补包定义并重发版）与 B（`packages.txt` 拆主/legacy 两文件）之间裁定 |
| IDX-2 | README「Published」表去版本化：删硬编码版本与日期，改为"版本以 `index` 为准"+ 包名/仓库静态列表；并明示摘要覆盖面的取舍 | README 仍停在 2026-11-08 的 12 个包，`index` 已是 20 行；8 个包整行缺失，另 3 个版本过期。两条更新路径（夜间自动 / 人工文档）必然漂移 | P1 | planned | REQ | 2026-11-18 | |
| IDX-3 | 两个门禁脚本在零输入时不得静默通过：`check-layout.sh` / `check-char-host.sh` 当前在找不到任何包时打印 `ok: 0 …` 并 `exit 0` | 独立 clone 本仓运行即为假绿；CI 若克隆失败也会绿，门禁失去意义 | P1 | planned | REQ | 2026-11-18 | |
| IDX-4 | `tools/package.sh` 的索引推送补齐与 `refresh-index.sh --push` 同级的保护：推送前 fast-forward 校验、推送后 `git ls-remote` 回读 | 主发布路径（publish / release）目前只做 `git push origin main`，缺回读；两条推送路径的安全等级不一致 | P1 | planned | REQ | 2026-11-18 | |
| IDX-5 | 索引格式增加 `min-compiler` 字段、摘要增加 `.digestignore` | 两个都涉及消费端契约：索引字段由 `ct get` 解析，摘要算法在索引仓与 `ct` 侧各有一份实现 | P3 | open | REQ | 2026-11-18 | 归属 CT 仓字段/算法契约；本仓不立项，待 CT 侧给出结论后再评估 |

## 不采纳项

无。意见书 2.1 的"每包仅一行"建议不登记为条目：该限制已于 2026-11-18 解除
（`gen-index.sh` 六字段、`refresh-index.sh --all-tags`、nightly 使用 `--all-tags`），
无需新条目。
