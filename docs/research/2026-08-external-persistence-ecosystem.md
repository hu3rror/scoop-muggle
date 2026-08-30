# Research: 生态中外部路径持久化的现代实践

> 对应 wayfinder 票「生态中外部路径持久化的现代实践」（#69）。
> 问题：Scoop 生态中如何处理"写死 `%APPDATA%`/`%LOCALAPPDATA%`/`$home` 路径、不认 portable 模式"的应用？`persist_external` 是否独有？

## 结论速览

1. **需求是真实的**：官方 `persist` 只能持久化 `$dir`（安装目录）内的路径，够不到 `%APPDATA%` 等外部路径。这正是 `persist_external` 存在的理由，不是空想。
2. **生态已有现成先例，且维护方式更现代**：`Scoop4kariiinUtils`（Scoop4kariiin bucket 的配套模块）提供了与 `persist_external` 同构的功能（`Mount-ExternalRuntimeData`），但以**独立 Scoop 应用**形式维护，manifest 通过 `depends` 依赖它，而非每个 bucket 自持一套脚本。
3. **社区标准做法分三档**：首选 app 原生 portable / user-data-dir；次选 manifest 内脚本建 junction；最重的场景才用外部模块工具。

## 一手来源

### 1. 官方 `persist` 的能力边界

- [Scoop Wiki: Persistent data](https://github.com/ScoopInstaller/Scoop/wiki/Persistent-data) — 数据存于 `~/scoop/persist/<app>/`，manifest 用 `persist` 声明（相对 `$dir` 的路径），安装时复制进 `$persist_dir` 并以 **junction（目录）/ hard link（文件）** 链接回 `$dir`。
- [lib/install.ps1](https://github.com/lukesampson/scoop/blob/master/lib/install.ps1) — `persist_data` 实现：链接只发生在 `$dir` ↔ `$persist_dir` 之间。
- 结论：官方 `persist` **不**支持把 `%APPDATA%\AppName` 这类路径声明为持久化项——`persist` 中的路径语义是"`$dir` 下的子路径"。

### 2. 官方 persist 的近期演进（schema 层面）

- [PR #6367: Allow explicit declaration of persistent item types](https://github.com/ScoopInstaller/Scoop/pull/6367) — 官方 schema 的 `persist` 现支持 `{"file": [...], "directory": [...]}` 显式对象格式，解决"文件/目录歧义"。**官方自己也在解决类型推断问题**（`persist_external` 的 `Resolve-ExternalItemType` 是同问题的自研解法）。
- [Issue #6179: Improve manifest "persist"](https://github.com/ScoopInstaller/Scoop/issues/6179) — 官方讨论 persist 增强的背景。

### 3. 生态现成先例：Scoop4kariiinUtils

[AkariiinMKII/Scoop4kariiinUtils](https://github.com/AkariiinMKII/Scoop4kariiin)（module 本体），配套 [Scoop4kariiin bucket](https://github.com/AkariiinMKII/Scoop4kariiin)：

- **`Mount-ExternalRuntimeData`**：把 `$persist_dir` 下的目录 mount 到 `$env:APPDATA` / `$env:LOCALAPPDATA`（junction）——与 `persist_external` 的链接逻辑同构。
- **`Dismount-ExternalRuntimeData`**：卸载对应链接。
- **`Import-PersistItem` / `New-PersistItem` / `Backup-PersistItem` / `Restore-PersistItem`**：从其他 app 导入、建占位、备份、恢复 persist 项。
- **维护模式差异（关键）**：manifest 通过 `"depends": "Scoop4kariiin/Scoop4kariiinUtils"` 依赖这个**已发布为独立 Scoop 应用的模块**，然后在 `installer.script` 里 `Import-Module` + 一行函数调用即可。模块本身由另一个 bucket 独立维护、可随 `scoop update` 升级——bucket 自身不再持有脚本。

### 4. 社区对非 portable app 的三档标准做法

| 档位 | 做法 | 适用 |
|---|---|---|
| 1（首选） | app 支持 `--user-data-dir` / portable 模式 → 用**原生 `persist`** | cherry-studio、VSCode 类、多数 Electron app |
| 2（次选） | `post_install` 脚本手动建 junction：`%APPDATA%\X` → `$persist_dir\X` | 少量路径、app 固定 |
| 3（最重） | 外部模块工具（如 `Scoop4kariiinUtils`）统一管理 mount | 多路径、需要导入/迁移/备份能力 |

- [Discussion #5389: portability and post-uninstall cleanup](https://github.com/ScoopInstaller/Scoop/discussions/5389) — 社区对非 portable app 的持久化讨论。
- [Extras Discussion #10651: Chromium/Electron 的 portable 设置目录](https://github.com/ScoopInstaller/Extras/discussions/10651) — 对 `%AppData%` 写死路径应用的社区讨论。

## 对决策票的输入（#72）

- `persist_external` 的需求成立，但**自持脚本不是唯一路径**。
- 候选方向：
  - A. **精简自研**：保留脚本但大幅收敛（减少样板、修复 DocBox 类错误），自持维护。
  - B. **引入 Scoop4kariiinUtils**：manifest 改为 `depends` + `Import-Module` + `Mount-ExternalRuntimeData`，删除本地脚本——把维护成本外包给上游模块，但引入第三方依赖。
  - C. **混合（按 app 分档）**：有 user-data-dir 的迁移到原生 `persist`，其余视数量决定用 A 或 B。
- 事实提示：15 个 manifest 里，cherry-studio 明确有 user-data-dir 类能力（anx-reader 等 Electron 应用多数也支持），这些可先迁移，数量可能显著少于 15。
