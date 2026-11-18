---
phase-id: draft-index-refresh-unblock
status: draft
---

# 草案：解除 nightly 索引刷新的阻塞

> 未定稿。不占正式编号、不排期、不派工、不开工（主规范 6.7.1 PN-12 / PN-14）。
> 追溯：`IDX-1`（分析：`docs/planning/analysis/AN-IDX-1.md`）

## 目标

让 nightly `refresh-index.sh --all-tags` 重新退出 0，同时不删除 `index` 中任何
仍可解析的旧行。

## 范围

**做什么**

- 按用户裁定执行 A 或 B：
  - A：9 个旧仓（`hal`、`hal-posix`、`zlib`、`png`、`net-posix`、`sqlite`、
    `sql`、`hashmap`、`dict`）补 `publisher` / `ns-root` 并重发版本，随后
    `--all-tags` 回填；
  - B：`packages.txt` 只留已迁移的 10 个仓，旧仓移入 `packages.txt.legacy`，
    并记录旧仓的人工刷新方式。
- 两种方案都要同步 `.github/workflows/gates.yml` 的克隆源（它读 `packages.txt`）。

**不做什么**

- 不改 `refresh-index.sh` 的 fail-closed 语义。
- 不改 `ct` 仓，不为旧 tag 补键（tag 不可变）。
- 不改 `index` 的行格式与既有行内容。

## 依赖

- 用户对 A / B 的裁定（主编不得自选）。
- 若选 A：9 个仓各自的新版本与 tag。

## 已知风险

- 选 B 后旧仓发版不会被自动收录；触发信号：旧仓发 tag 后 `index` 行不变。
- 选 A 时若某仓 `publisher` 与既有行不同，会触发漂移保护并跳过旧版本；触发信号：
  刷新输出出现 `publisher … differs`。
- 阻塞期间 nightly 的失败发生在首个坏仓，可能掩盖后续仓的真实新版本。
