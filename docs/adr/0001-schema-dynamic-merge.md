# schema.json 采用「官方 master 为基 + persist_external 增量」的测试时动态合并

官方 Scoop schema 根级 `additionalProperties: false`，而本仓库 manifest 使用自研 `persist_external` 字段（见 persist_external 相关决策），该字段必须存在于 schema 中，否则校验报错。此前仓库在根目录维护一份静态扩展拷贝（约 1 行根级属性注入），官方 schema 演进即会过时。现决定：删除仓库内静态 `schema.json`，改为测试/CI 启动时由 `scripts/sync-schema.ps1` 拉取官方 master schema、注入 `persist_external` 后写入 `$env:SCOOP_HOME\schema.json`；`.vscode/settings.json` 的 IntelliSense 改指向官方 raw URL。

**Status**: accepted

**Considered Options**:
- A. 保留静态拷贝 + 手动同步（原状）：简单但必然过时，官方演进（如 persist 对象形式 #6367、schema 收紧 #5093）会静默漏校验
- B. 仓库内官方快照 + 注入脚本：校验结果可控，但快照落后是常态，维护动作与 A 相近
- D. 回归官方 schema（停用 persist_external）：仅在「10 个不可迁 app 全部放弃持久化」后成立，属另一决策票，未采用

选定 C（动态拉取）而非 B 的理由：字段规则跟随官方最新定义、零仓库拷贝；代价（官方收紧导致历史 manifest 校验波动、本地测试依赖网络）由「缓存上次注入版 schema」兜底吸收——拉取失败时复用已写入 `$env:SCOOP_HOME\schema.json` 的注入版并告警，无缓存则显式失败。
