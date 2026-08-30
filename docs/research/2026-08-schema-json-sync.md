# Research: 官方 schema.json 的演进与同步机制

> 对应 wayfinder 票「官方 schema.json 的演进与同步机制」（#70）。
> 问题：本仓库本地维护一份在官方基础上扩展了 `persist_external` 的 `schema.json`（688 行改动），如何避免官方 schema 演进时本地副本过时？

## 结论速览

1. **官方 schema 会演进，且近期变动真实存在**：`persist` 显式类型（#6367）、formatjson 根键排序（#6494）、schema 更严格化（#5093）都是近一年内的合并。无独立 changelog，跟随主项目 CHANGELOG。
2. **校验链路的关键事实**：CI 里 `test/Import-Bucket-Tests.ps1` 用 `Scoop.Validator.dll` 加载 **`$env:SCOOP_HOME/schema.json`**（即 Scoop 核心 clone 的 schema），不是直接读 bucket 自带 schema。本仓库 `Scoop-Bucket.Tests.ps1` 把本地 schema **复制覆盖**进 `$env:SCOOP_HOME`，所以本地版本才生效——一旦官方 schema 新增字段而本地未同步，校验就会漏掉这些字段的规则。
3. **官方 schema 根级 `additionalProperties: false`**：顶层不允许未声明字段。`persist_external` 必须存在 schema 里，否则官方 `Scoop.Validator` 直接报错。这决定了本仓库无法用"manifest 端规避"，必须维持某种 schema 扩展。
4. **更现代的维护方式是"官方为基 + 增量补丁"**：不再持有 688 行静态拷贝，而是测试/CI 时动态拉取官方 schema 并注入 `persist_external` 增量，或用一个小的本地补丁文件做合并。

## 一手来源

### 1. 校验链路（决定"谁在消费 schema"）

- [test/Import-Bucket-Tests.ps1](https://github.com/ScoopInstaller/Scoop/blob/master/test/Import-Bucket-Tests.ps1) — `Describe 'Manifest validates against the schema'`：
  - `Add-Type ... Scoop.Validator.dll`
  - `New-Object Scoop.Validator("$PSScriptRoot/../schema.json", $true)` — **加载路径是 `$env:SCOOP_HOME/schema.json`**（`$PSScriptRoot` 是 SCOOP_HOME 下的 `test/`，其上一级即 SCOOP_HOME）。
  - 逐文件 `$validator.Validate($file)`，断言 `Errors.Count -eq 0`。
- 本仓库 [Scoop-Bucket.Tests.ps1](../../Scoop-Bucket.Tests.ps1) — 在 Import 之前 `Copy-Item` 本地 `schema.json` → `$env:SCOOP_HOME\schema.json`。这就是"本地 schema 覆盖"生效的原理。

### 2. 官方 schema 演进事实

- [官方 schema.json（master）](https://raw.githubusercontent.com/ScoopInstaller/Scoop/master/schema.json) — 根级 `additionalProperties: false`；`persist` 目前是 `stringOrArrayOfStringsOrAnArrayOfArrayOfStrings`（未含 #6367 的 file/directory 对象，说明该 PR 可能尚未合入 master，需以 master 为准）。
- [CHANGELOG.md](https://github.com/ScoopInstaller/Scoop/blob/master/CHANGELOG.md) — schema 变更随主项目 changelog，无独立记录。
- [PR #6494: formatjson 按 schema 排序 manifest 根键](https://github.com/ScoopInstaller/Scoop/pull/6494) — schema 参与工具链的近期例子。
- [PR #5093: schema 更严格化](https://github.com/ScoopInstaller/Scoop/pull/5093) — `additionalProperties: false` 强化。

### 3. 扩展 schema 的社区做法

- [PR #4623: 添加 $schema 属性](https://github.com/ScoopInstaller/Scoop/pull/4623) — manifest 可声明 `$schema` 指向官方 schema，供编辑器校验/补全。
- [Issue #6394 + PR #6395](https://github.com/ScoopInstaller/Scoop/issues/6394) — CI 曾对所有 changed JSON（含非 manifest）跑校验，官方已修复 include 模式。提示：CI 校验范围是 `bucket/**/*.json`。
- 结论：官方本身不提供"bucket 侧扩展 schema"的机制；自定义字段必须由 bucket 自己以某种方式注入校验链路。

## 对决策票的输入（#73）

- 方案候选：
  - A. **保留静态拷贝 + 手动同步**（现状）：简单，但会过时，且校验链路上"官方新增字段"会漏。
  - B. **官方为基 + 本地增量补丁**：`Scoop-Bucket.Tests.ps1` 启动时拉取/读取官方 schema（或仓库内维护一份官方 schema 快照 + 一个小 patch 脚本注入 `persist_external`），再复制进 SCOOP_HOME。官方 schema 更新只需更新快照/重新拉取，`persist_external` 增量独立维护。
  - C. **测试时动态拉取官方 schema**：CI/本地测试联网抓 `raw.githubusercontent.com` 官方 schema + 注入增量。零本地拷贝，但依赖网络可用性。
  - D. **放弃自定义字段，迁移到官方 `persist` 能力**：若去留决策（#72）走向"弃用 persist_external"，则本地 schema 可直接删除，回到纯官方 schema——这是最省维护的路径。
- 事实提示：`additionalProperties: false` 意味着只要 manifest 里还有 `persist_external`，就必须保留某种 schema 扩展；**若 #72 决定弃用该字段，schema 问题自动消失**。
