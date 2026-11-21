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
| IDX-1 | 解除 nightly `refresh-index.sh --all-tags` 的 fail-closed 阻塞：`packages.txt` 中 9 个旧仓的最 `v*` tag 缺 `publisher` / `ns-root`，任务每个夜间在首个此类仓中止 | 自动刷新实质停摆；索引能用的前提是 nightly 绿 | P0 | done | REQ | 2026-11-21 | |
| IDX-2 | README「Published」表去版本化：删硬编码版本与日期，改为"版本以 `index` 为准"+ 包名/仓库静态列表；并明示摘要覆盖面的取舍 | README 仍停在 2026-11-08 的 12 个包，`index` 已是 20 行；8 个包整行缺失，另 3 个版本过期。两条更新路径（夜间自动 / 人工文档）必然漂移 | P1 | done | REQ | 2026-11-21 | 由 `0cdb132` 达成；草案 `draft-readme-single-source` 于同日关闭 |
| IDX-3 | 两个门禁脚本在零输入时不得静默通过：`check-layout.sh` / `check-char-host.sh` 当前在找不到任何包时打印 `ok: 0 …` 并 `exit 0`（layout 实际是 `set -u` 下空数组崩溃） | 独立 clone 本仓运行即为假绿；CI 若克隆失败也会绿，门禁失去意义 | P1 | done | REQ | 2026-11-21 | |
| IDX-4 | `tools/package.sh` 的索引推送补齐与 `refresh-index.sh --push` 同级的保护：推送前 fast-forward 校验、推送后 `git ls-remote` 回读 | 主发布路径（publish / release）目前只做 `git push origin main`，缺回读；两条推送路径的安全等级不一致 | P1 | done | REQ | 2026-11-21 | |
| IDX-5 | 索引格式增加 `min-compiler` 字段、摘要增加 `.digestignore` | 两个都涉及消费端契约：索引字段由 `ct get` 解析，摘要算法在索引仓与 `ct` 侧各有一份实现 | P3 | open | REQ | 2026-11-18 | 归属 CT 仓字段/算法契约；本仓不立项，待 CT 侧给出结论后再评估 |
| IDX-6 | `check-layout.sh` 未读取 `ns-root`：`ns-root = src` 的包（json、fsguard、nexcore 等）其命名空间目录判定会误报，实测完整工作区 101 个单元中 47 个 FAIL | 门禁在真实工作区长期红，失去信号价值；与 `v0-PH-1` 的零输入修复正交 | P1 | done | REQ | 2026-11-21 | |
| IDX-7 | README「Usage」的示例过期：`ct get <publisher>/<name>@<version>   # e.g. std/std@0.3.2`，实际发布方为 `ct`、`std` 最新 0.19.0，索引中也没有 0.3.2 行 | 新用户照抄示例会失败；属于 `IDX-2` 关闭后留下的单行修正 | P2 | done | REQ | 2026-11-21 | |

## 不采纳项

无。意见书 2.1 的"每包仅一行"建议不登记为条目：该限制已于 2026-11-18 解除
（`gen-index.sh` 六字段、`refresh-index.sh --all-tags`、nightly 使用 `--all-tags`），
无需新条目。
