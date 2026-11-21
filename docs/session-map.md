# 会话映射 — ct-pkg/index

> 主规范 §9.3 / G0 `g0-landing` 的产物。本仓按 `deviation:
> split-planning-and-implementation`（`AGENTS.md` 0.3）分工：规划会话承担
> REQ + EDITOR，实现由执笔人（DEV）承担，VERIFY 暂由执笔人复核留痕。
>
> 草案 phase 不登记在本文件（6.7.1 PN-14）；只有定稿后的 phase 才追加行。

| 任务 | 对话 | 角色 | phase |
| --- | --- | --- | --- |
| 解除 nightly 索引刷新阻塞 | 规划会话 + 执笔人 | EDITOR / DEV | `v0-PH-0` |
| 门禁零输入不得静默通过 | 规划会话 | REQ + EDITOR + DEV（实现已落地，VERIFY 待复核） | `v0-PH-1` |
| 索引推送补齐同级保护 | 待派工（执笔人） | DEV | `v0-PH-2` |

`v0-PH-1` 的四个实现提交（`1286f05`、`41ea365`、`9580405`、`ae2fe05`）在分工
裁定之前由规划会话完成；按 0.3 的收敛项，需由 VERIFY 复核后才进入收口。

未定稿的草案不在此表（PN-14），见 `docs/planning/roadmap.md`。
