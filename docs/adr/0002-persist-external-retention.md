# persist_external 机制保留：不可迁 app 全部使用，维持精简版现状

**Revision 2026-11（架构审查）**：五条修订：
- **链接记录迁入 `$persist_dir`**：`.scoop-persist-external.json` 改由 `scripts/persist-external.ps1` 的 `Invoke-PersistExternalReconcile` 统一读写，位置为 `$persist_dir\.scoop-persist-external.json`；安装版本目录中的旧记录只读回退，persist 记录写入成功后自动删除（全部链接失败时保留，此时它是唯一真相源）。`pre_uninstall` hook 新增 `-PersistDir $persist_dir`，缺省时从版本目录推导（兼容旧 manifest）。
- **记录语义为当前集**：对账后记录等于 manifest 声明的链接集（个别链接失败时为成功应用的子集）；manifest 已不再声明的条目在对账时解除链接，声明集清空时同时删除记录。
- **reset 门卫改读 manifest**：`Invoke-PersistExternalReset` 的门卫从「记录文件存在」改为「manifest 声明 `persist_external`」，记录缺失的 app 不再被静默跳过。
- **链接通道收缩为目录 Junction**（ADR-0004）：file/SymbolicLink、`%VAR%`/`$home` 展开与类型探测分支移除，条目类型只接受 `dir`/`directory`；链接记录由 `{Source,Target,LinkType}` 对象改为源路径字符串数组（读取端仍兼容旧对象）。
- **清单与计数更正**：下表是 2026-08 盘点快照；截至 2026-11 有 21 个 manifest 声明 `persist_external`，新增的 alma、herdr-gpui、hummingbird、hummingbird-nightly、pure-music、rgitui、ropy、sonora、zorite 按 new-manifest 流程加入，未做本 ADR 的源码级审计。
官方 Scoop `persist` 只能持久化 `$dir`（安装目录）内的路径，够不到 `%APPDATA%` / `%LOCALAPPDATA%` 等外部目录。而本仓库部分 app 把用户数据写死在系统路径（Flutter、JVM、.NET、WebView2、商业软件、绿色版均无数据目录重定向机制）。为此本仓库自研 `persist_external`：在 `post_install` 将外部路径通过 Junction（仅目录，ADR-0004 起）链接到 `$persist_dir`，实现实时持久化，配套 `pre_uninstall` 解除链接、`.scoop-persist-external.json` 记录链接状态、`Invoke-PersistExternalReset` 重装系统后恢复。

经 wayfinder #68 决策链（#72 去留 grilling → #75 盘点 → #74/#76 迁移 → #78 验证 → #77 最终处置），现决定：**保留自研精简版 `persist_external`，作为无法迁移 app 的持久化机制；不可迁 manifest 全部继续使用（计数更正见 Revision 2026-11）；脚本不再改造、不引入外部模块**。可迁的 app（cherry-studio、lx-music-desktop、wonderpen）一律迁移到原生 `persist`。

**Status**: accepted

**Considered Options**:
- A. 保留自研精简版 persist_external（现状）：脚本已收敛（install/uninstall/reset 三入口），维护成本 = 每次 manifest 变更的样板 + 卸载链路，无需外部依赖
- B. 引入 Scoop4kariiinUtils（`depends` + `Import-Module` + `Mount-ExternalRuntimeData`）：把维护外包给上游模块，但引入第三方依赖，且违背本仓库「纯 Scoop manifest（不引入外部运行时）」约束（Q2-c）
- C. 混合：能迁的迁原生 persist、不能迁的用 A——已实际执行（cherry/lx/wonderpen 已迁），不可迁档结论为 A
- D. 学习 Extras 放弃持久化（post_uninstall 清理残留）：anx-reader/rclone-ui 在 Extras 已采用，但放弃数据保留，违背「数据不丢」硬约束，未采用

选定 A 而非 B：需求真实但规模收敛（2026-08 盘点 12 个 manifest，多为配置/账户/收藏类数据），自持脚本维护成本可控；不引入外部运行时与 #72 约束一致。选定 A 而非 D：数据不丢是本地硬保障（用户重装即恢复），优于卸载残留 + post_uninstall 清理；为 2 个 Extras 先例 app 引入双策略只会增加维护复杂度，与 Extras 的不一致可接受。

## 不可迁 app 清单（2026-08 盘点：12 个 manifest / 11 个 app）

| Manifest | 技术栈 | 数据路径 |
|---|---|---|
| 163MusicLyrics | C# / .NET WinForms | `%APPDATA%\MusicLyricApp` |
| animeko + animeko-alpha | Kotlin Compose Multiplatform (JVM) | `%APPDATA%`/`%LOCALAPPDATA%\Him188` |
| anx-reader | Flutter/Dart | `%APPDATA%`/`%LOCALAPPDATA%\com.anxcye` |
| DocBox | 绿色版（ghxi） | `%APPDATA%\DocBox` |
| game-cheats-manager | Python + C++ trainers | `%APPDATA%\GCM Trainers` / `GCM Settings` |
| goodsync-10 | 商业原生 | `%LOCALAPPDATA%\GoodSync` |
| manhuagui-downloader | Rust / Tauri v2 | `%APPDATA%\com.lanyeeee.manhuagui-downloader` |
| neat-reader | 绿色版（ghxi） | `%APPDATA%\NeatReader` |
| PicaComic | Flutter/Dart | `%APPDATA%`/`%LOCALAPPDATA%\com.github.pacalini` |
| rclone-ui | TypeScript + WebView2 | `%APPDATA%`/`%LOCALAPPDATA%\com.rclone.ui` |
| venera-next | Flutter/Dart | `%APPDATA%`/`%LOCALAPPDATA%\com.github.cyrilpeng` |

均无 `--user-data-dir` / portable 模式 / 环境变量重定向（详见 `docs/research/2026-08-persist-external-apps-audit.md`；manhuagui-downloader、game-cheats-manager 经 #78 源码级验证）。

上表是 2026-08 盘点快照。此后按 new-manifest 流程新增的 manifest（alma、herdr-gpui、hummingbird、hummingbird-nightly、pure-music、rgitui、ropy、sonora、zorite）未经本 ADR 的源码级审计，其条目形状已完成机械核对（全部为目录）。

## 关联决策

- 官方 schema 根级 `additionalProperties: false`，`persist_external` 必须存在于 schema 中 → 采用测试时动态合并（ADR-0001）
- 可迁 app 一律迁移原生 persist：cherry-studio（官方 portable 机制）、lx-music-desktop（`persist: portable`）、wonderpen（`--wp-user-data-dir`）——均已完成
