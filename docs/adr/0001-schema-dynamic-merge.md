# schema.json 采用「官方 master 为基 + persist_external 增量」的测试时动态合并

官方 Scoop schema 根级 `additionalProperties: false`，而本仓库 manifest 使用自研 `persist_external` 字段（见 persist_external 相关决策），该字段必须存在于 schema 中，否则校验报错。此前仓库在根目录维护一份静态扩展拷贝（约 1 行根级属性注入），官方 schema 演进即会过时。现决定：删除仓库内静态 `schema.json`，改为测试/CI 启动时由 `scripts/sync-schema.ps1` 拉取官方 master schema、注入 `persist_external` 后写入 `$env:SCOOP_HOME\schema.json`；`.vscode/settings.json` 的 IntelliSense 改指向官方 raw URL。

**Status**: accepted

**Considered Options**:
- A. 保留静态拷贝 + 手动同步（原状）：简单但必然过时，官方演进（如 persist 对象形式 #6367、schema 收紧 #5093）会静默漏校验
- B. 仓库内官方快照 + 注入脚本：校验结果可控，但快照落后是常态，维护动作与 A 相近
- D. 回归官方 schema（停用 persist_external）：仅在不可迁 app 全部放弃持久化后成立，属另一决策票，未采用

选定 C（动态拉取）而非 B 的理由：字段规则跟随官方最新定义、零仓库拷贝；代价（官方收紧导致历史 manifest 校验波动、本地测试依赖网络）由「缓存上次注入版 schema」兜底吸收——拉取失败时复用注入版缓存并告警，无缓存则显式失败。

**Revision 2026-10**：注入版写入 `$env:SCOOP_HOME\schema.json`（scoop core 是 git 工作区）会让 `scoop update` 因 Uncommitted changes 中止。修订：
- 缓存移出 git 工作区，存 `%LOCALAPPDATA%\muggle-scoop\schema.injected.json`（非 Windows 退回系统临时目录）。
- `Scoop-Bucket.Tests.ps1` 测试开始前自愈上次残留（若 schema.json 含 `persist_external`，`git checkout -- schema.json` 还原官方版），测试结束由外层 `Describe` 的 `AfterAll` 把原始内容字节级还原（备份在 TEMP，跑后即删）。
- 受制于官方 `Import-Bucket-Tests.ps1` 硬编码 `$PSScriptRoot/../schema.json`，注入版仍须短暂落在 scoop core；但不再留存，已验证跑完 `bin\test.ps1` 后 scoop core `git status` 干净。

**Revision 2026-11**：注入的 `persist_external` 规则从弱约束（`type: array`，元素不限）收紧为可读、可校的形状定义：
- 新增 `definitions.persistExternalEntry`：条目要么是字符串，要么是长度 2–3 的数组 `[来源, 目标名]` / `[来源, 目标名, 类型]`，类型枚举 `file` / `dir` / `directory`（`dir` 为 `directory` 的别名），多余元素拒绝。
- 外层用 `anyOf`（字符串条目本身也是数组，`oneOf` 会把嵌套数组判为重叠而整条拒绝），内层条目用 `oneOf`。
- 属性带 `$type: array` 与 `description`，读 schema 的工具/AI 能直接看出形状；校验消息仍以 `anyOf` 分支为主。
- 判定依据（Scoop.Validator 实测）：仓库 188 个 manifest 全部通过；单字符串、纯字符串数组、2/3 元组、`dir` 别名、`file` 类型均通过；4 元组、未知类型、非字符串、空数组均被拒。

