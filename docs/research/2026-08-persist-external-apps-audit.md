# Research: 13 个 persist_external app 的上游能力盘点

> 对应 wayfinder 票「盘点 13 个 persist_external app 的上游能力」（#74）。
> 结论：**13 个中 1 个确定可迁（wonderpen）、2 个需验证、10 个不可迁**。persist_external 保留用户的实际规模为 10 个 app。

## 方法

对每个 app 查：GitHub 仓库语言/技术栈、README、Extras 现有 manifest 先例（`ScoopInstaller/Extras` 是否收录及如何处理数据目录）。

## 分档清单

### 🟢 可迁（确定，Electron）：1 个

| App | 技术栈 | 证据 | 建议 |
|---|---|---|---|
| **wonderpen** | Electron（electron-builder NSIS） | Extras manifest 的 installer.script 解 `$PLUGINSDIR/app.7z`——electron-builder 安装器特征；Electron 内核原生支持 `--user-data-dir` | 迁移到原生 persist：`--user-data-dir="$dir\data"` + `persist: data` + post_install 一次性迁移 `%APPDATA%\WonderPen` |

### 🟡 需验证：2 个

| App | 技术栈 | 现状 | 待验证点 |
|---|---|---|---|
| **manhuagui-downloader** | Rust / **Tauri v2** | README 明确"免安装版(portable)解压后可以直接运行" | Tauri v2 的数据目录默认在 `%APPDATA%\com.lanyeeee...`，需查应用是否支持数据目录重定向（Tauri 的 `app-config` / 环境变量） |
| **game-cheats-manager** | C++ | README 有 "Custom Paths: Change where your trainers are saved"（trainer 库目录可自定义） | trainer 下载目录可迁到 `$dir`，但 "GCM Settings" 配置目录是否也可自定义需验证 |

### 🔴 不可迁：10 个

| App | 技术栈 | 不可迁原因 |
|---|---|---|
| **anx-reader** | Flutter/Dart | **Extras 已收录且放弃持久化**（无 persist、无 user-data-dir，仅 post_uninstall 清除 `%APPDATA%\com.anxcye\anx_reader`）——Flutter 无数据目录重定向机制 |
| **PicaComic** | Flutter/Dart | 同上，README 无 portable 信息 |
| **venera-next** | Flutter/Dart | 同上 |
| **animeko (+alpha)** | Kotlin Compose Multiplatform (JVM) | JVM 数据目录硬编码 APPDATA/LOCALAPPDATA，无 portable 模式 |
| **rclone-ui** | TypeScript + WebView2 | **Extras 已收录且放弃持久化**（仅 suggest WebView2，无 persist） |
| **163MusicLyrics** | C# / .NET WinForms | 无 portable 机制 |
| **goodsync-10** | 商业原生 | 商业软件，无 portable 版 |
| **neat-reader** | 绿色版（ghxi） | 无上游 repo，未知数据目录机制，默认 APPDATA |
| **DocBox** | 绿色版（ghxi） | 同上 |

## 关键观察

1. **Extras 的处理策略比预想更务实**：对 Flutter 类（anx-reader）和 WebView2 类（rclone-ui），Extras **干脆不做持久化**，只保证卸载时清理数据。这为"不可迁"档提供了一种新选项（见下方建议）。
2. **cherry-studio 的最佳路径不是 `--user-data-dir`，而是官方 portable 构建**：Extras 用 `Cherry-Studio-*-portable.exe`（上游官方发布）+ `persist: data` + pre_install 迁移——比 setup.exe 解包 + user-data-dir 更干净，已纳入「迁移 cherry-studio 与 lx-music-desktop」票。
3. **对"不可迁"档的三种处理选择**（后续 grilling 决策）：
   - A. 保留 persist_external（现状，10 个 app）
   - B. 学习 Extras：放弃部分 app 的持久化（它们的数据本来就在 %APPDATA%，Scoop 卸载不清理会留残留，但数据不丢）——用 post_uninstall 清理替代 persist
   - C. 混合：保留 persist_external 但只给"数据必须持久化"的 app 用

## 对后续票的输入

- #75（迁移 cherry-studio/lx-music-desktop）：cherry-studio 用官方 portable.exe（Extras 已验证模式），lx-music-desktop 用 `--user-data-dir`（Electron 绿色版）
- 新开票：wonderpen 迁移（可迁-确定）
- 新开票（或并入手盘点）：manhuagui-downloader、game-cheats-manager 的验证
