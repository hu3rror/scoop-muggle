# Research: 13 个 persist_external app 的上游能力盘点

> 对应 wayfinder 票「盘点 13 个 persist_external app 的上游能力」（#74）与「manhuagui-downloader / game-cheats-manager 数据目录能力验证」（#78）。
> 结论：**13 个中 1 个确定可迁（wonderpen，已完成迁移）；其余 12 个全部不可迁**（2 个原「需验证」已逐一验证为不可迁）。persist_external 保留用户的实际规模为 12 个 app。

## 方法

对每个 app 查：GitHub 仓库语言/技术栈、README、Extras 现有 manifest 先例（`ScoopInstaller/Extras` 是否收录及如何处理数据目录）。「需验证」档追加源码级验证：直接读上游仓库源码，查是否存在 `PORTABLE_EXECUTABLE_DIR`（Electron portable 特征）、自有 portable 目录、`--user-data-dir`、环境变量或命令行数据目录重定向之一（#78）。

## 分档清单

### 🟢 可迁（确定，Electron）：1 个

| App | 技术栈 | 证据 | 建议 |
|---|---|---|---|
| **wonderpen** | Electron（electron-builder NSIS） | Extras manifest 的 installer.script 解 `$PLUGINSDIR/app.7z`——electron-builder 安装器特征；Electron 内核原生支持 `--user-data-dir` | 迁移到原生 persist：`--user-data-dir="$dir\data"` + `persist: data` + post_install 一次性迁移 `%APPDATA%\WonderPen` |

### 🟡 需验证：2 个 → 已验证均为不可迁（#78，2026-08）

| App | 技术栈 | 验证方法 | 结论 |
|---|---|---|---|
| **manhuagui-downloader** | Rust / **Tauri v2** | 读上游源码（`src-tauri/src/config.rs` / `lib.rs` / `logger.rs` / `tauri.conf.json`）+ 查 Tauri v2 文档 | **不可迁**。数据目录全部硬编码 `app.path().app_data_dir()`（=`%APPDATA%\com.lanyeeee.manhuagui-downloader`）：config.json、日志目录（`app_data_dir\日志`）、默认下载/导出目录（`漫画下载`/`漫画导出`）均在旗下。README 的"免安装版(portable)"仅指绿色 zip 免安装，数据仍落 `%APPDATA%`。Tauri v2 无内建 portable 模式或数据目录环境变量覆盖，需应用自行实现 portable 检测（本应用未实现） |
| **game-cheats-manager** | 主程序 **Python**（PyInstaller/Nuitka 打包），trainers 为 C++/FLTK | 读上游源码（`src/scripts/config.py`） | **不可迁**。GCM Settings 配置目录（settings.json + db）**硬编码** `os.path.join(os.environ["APPDATA"], "GCM Settings")`，无任何重定向机制；无 portable 模式、无环境变量覆盖。trainer 下载目录（"Custom Paths"）仅是 settings.json 内可改的 `downloadPath` 配置键，非机制级重定向，且仍需 settings.json 先落 APPDATA |

### 🔴 不可迁：12 个

| App | 技术栈 | 不可迁原因 |
|---|---|---|
| **manhuagui-downloader** | Rust / Tauri v2 | 见上方 🟡→🔴 验证记录（#78）：数据目录硬编码 `app_data_dir` |
| **game-cheats-manager** | Python + C++ trainers | 见上方 🟡→🔴 验证记录（#78）：GCM Settings 配置目录硬编码 APPDATA |
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
2. **Tauri v2 无内建 portable/数据目录重定向机制**（#78 验证）：`app_data_dir` 由 identifier 派生，需应用自实现 portable 检测（如检测 exe 旁 sentinel 文件）——manhuagui-downloader 未实现，README 的"portable"仅为免安装打包。
3. **cherry-studio 的最佳路径不是 `--user-data-dir`，而是官方 portable 构建**：Extras 用 `Cherry-Studio-*-portable.exe`（上游官方发布）+ `persist: data` + pre_install 迁移——比 setup.exe 解包 + user-data-dir 更干净，已纳入「迁移 cherry-studio 与 lx-music-desktop」票。
4. **对"不可迁"档的三种处理选择**（后续 grilling 决策）：
   - A. 保留 persist_external（现状，10 个 app）
   - B. 学习 Extras：放弃部分 app 的持久化（它们的数据本来就在 %APPDATA%，Scoop 卸载不清理会留残留，但数据不丢）——用 post_uninstall 清理替代 persist
   - C. 混合：保留 persist_external 但只给"数据必须持久化"的 app 用

## 对后续票的输入

- #74（迁移 cherry-studio/lx-music-desktop）：**已完成**。cherry-studio 用官方 portable 机制，lx-music-desktop 用 `persist: portable`
- #76（迁移 wonderpen）：**已完成**（原生 `--wp-user-data-dir` + persist）
- #78（manhuagui-downloader、game-cheats-manager 验证）：**已完成**，两者均 🔴 不可迁 → 移入不可迁档
- 剩余 12 个不可迁 app 的持久化处置：交 #77（grilling）决策
