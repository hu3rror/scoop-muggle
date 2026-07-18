# Scoop Muggle Bucket [![Build status](https://ci.appveyor.com/api/projects/status/eiyp2qhs11n83jo0/branch/main?svg=true)](https://ci.appveyor.com/project/hu3rror/scoop-muggle/branch/master)

面向 [Scoop](https://scoop.sh/) 的软件仓库，收录其他 bucket 中较少见的 Windows 应用：阅读/文档工具、媒体播放器、网络工具、AI 客户端及系统工具。

[English](README.md)

## 安装

```pwsh
scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
scoop install muggle/<软件名>
```

示例：

```pwsh
scoop install muggle/keepassxc
```

更新所有已安装软件：

```pwsh
scoop update *
```

## 分类

### 阅读 / 文档
- [goldendict-ng](https://github.com/xiaoyifang/goldendict-ng) — 词典查询程序
- [anx-reader](https://github.com/Anxcye/anx-reader) — 带 AI 功能的电子书阅读器
- [pdfpatcher](bucket/pdfpatcher.json) / [k2pdfopt](bucket/k2pdfopt.json) / [briss](bucket/briss.json) — PDF 编辑与排版优化
- [zlibrary](bucket/zlibrary.json) — Z-Library 官方客户端

### 漫画
- [yomikiru](https://github.com/mienaiyami/yomikiru)
- [mangadex-dl](https://mangadex-dl.mansuf.link/)
- [manhuagui-downloader](bucket/manhuagui-downloader.json)
- [PicaComic](bucket/PicaComic.json)
- [neeview](bucket/neeview.json)

### 音乐 / 音频
- [musicplayer2](https://github.com/zhongyang219/MusicPlayer2) — 播放、歌单、歌词、格式转换
- [nora](https://github.com/Sandakan/Nora)
- [dopamine-legacy](bucket/dopamine-legacy.json) / [dopamine-preview](bucket/dopamine-preview.json)
- [lx-music-desktop](bucket/lx-music-desktop.json)
- [163MusicLyrics](bucket/163MusicLyrics.json)（含 lite/pro 版本）
- [mp3tag](bucket/mp3tag.json) — 标签编辑器
- [qaac](bucket/qaac.json) / [m4acut](bucket/m4acut.json) — AAC/ALAC 编码与无损切割
- [vitomu](bucket/vitomu.json) / [deemix-portable](bucket/deemix-portable.json) / [qbldx-mod](bucket/qbldx-mod.json) — 音频下载工具

### 网络 / 代理
- [mihomo-shawl-service](bucket/mihomo-shawl-service.json) — mihomo 内置 Windows 服务封装
- [sparkle](bucket/sparkle.json) / [clash-nyanpasu-nightly](bucket/clash-nyanpasu-nightly.json) / [goclashz](bucket/goclashz.json) — Mihomo/Clash 图形客户端
- [mosdns](bucket/mosdns.json) / [mosdns-cn](bucket/mosdns-cn.json) — DNS 转发器
- [q](bucket/q.json) — 支持 UDP/TCP/DoT/DoH/DoQ/ODoH 的 DNS 客户端
- [opentrace](bucket/opentrace.json) / [NatTypeTester](bucket/NatTypeTester.json) / [cdnlookup](bucket/cdnlookup.json) — 网络诊断工具
- [gopeed](bucket/gopeed.json) / [pget](bucket/pget.json) — 多线程下载器

### AI 工具
- [cherry-studio](https://cherry-ai.com) — 多 LLM 桌面客户端
- [chatall](http://chatall.ai) — 同时向多个模型提问
- [witsy](bucket/witsy.json) — 桌面 AI 助手 / MCP 客户端
- [ainiee](https://github.com/NEKOparapa/AiNiee) — 游戏/小说/字幕的 AI 翻译工具
- [pot-desktop](https://pot.pylogmon.com/) — 跨平台划词翻译
- [geminicommit-cli](bucket/geminicommit-cli.json) — 基于 Gemini 的 commit message 生成

### 系统 / 效率
- [keepassxc](https://keepassxc.org) — 密码管理器
- [locale-remulator](https://github.com/InWILL/Locale_Remulator) — 按应用调整区域和语言设置
- [context-menu-manager](bucket/context-menu-manager.json) / [win11-classic-context-menu](bucket/win11-classic-context-menu.json)
- [notepad3](bucket/notepad3.json) / [heynote](bucket/heynote.json) — 文本编辑器
- [run-hidden](bucket/run-hidden.json) / [run-hidden-console](bucket/run-hidden-console.json) — 隐藏控制台窗口运行程序
- [posh-git](bucket/posh-git.json) / [get-childitemcolor](bucket/get-childitemcolor.json) — PowerShell 模块
- [eza](bucket/eza.json) — `ls` 的现代替代品

### 图像处理
- [caesium](bucket/caesium.json) / [rimage](bucket/rimage.json) — 图片压缩
- [jpegview-fork](https://github.com/sylikc/jpegview) — 轻量图片查看/编辑器
- [picgo](bucket/picgo.json) — 图床上传工具
- [icns](bucket/icns.json) — `.icns` 图标文件生成

### 游戏
- [cheat-engine](bucket/cheat-engine.json)
- [game-cheats-manager](https://github.com/dyang886/Game-Cheats-Manager)
- [bg3-mod-manager](bucket/bg3-mod-manager.json)
- [nhse](bucket/nhse.json) / [ACNH-design-pattern-editor](bucket/ACNH-design-pattern-editor.json) — 集合啦工具
- [betterjoy-lts](bucket/betterjoy-lts.json) — Switch 手柄重映射
- [RyuSAK](bucket/RyuSAK.json) — Ryujinx 存档/Mod 管理
- [NsEmuTools](bucket/NsEmuTools.json) — Switch 模拟器安装工具

完整清单：[bucket/](bucket)

## 值得参考的 Manifest

以下几个 manifest 使用了不常见的 Scoop 特性，可作为编写参考，来源均直接指向上游项目自身的发布渠道。

| Manifest | 技术要点 |
|---|---|
| [mihomo-shawl-service](bucket/mihomo-shawl-service.json) | 同时打包两个上游发行包，通过外部辅助脚本将程序注册为 Windows 服务，`pre_install`/`post_install`/`pre_uninstall`/`persist` 协同工作 |
| [goldendict-ng](bucket/goldendict-ng.json) | `checkver` 用 `jsonpath` + `regex` + `replace` 从带 Qt 版本号的资源文件名中提取版本号，与 `autoupdate` 保持一致 |
| [musicplayer2](bucket/musicplayer2.json) | `pre_install` 中预先创建占位文件，使 `persist` 在首次安装时即有可链接的目标 |
| [qaac](bucket/qaac.json) + [qaac-qtfiles](bucket/qaac-qtfiles.json) | 两个 manifest 通过 `depends`/`suggest` 关联，后者在 `installer.script` 中将自身链接进前者的安装目录 |
| [spotx](bucket/spotx.json) | `checkver` 用完整 PowerShell 脚本组合 GitHub release 标签、commit 日期与短 SHA，而非单一正则 |
| [vcredist-aio](bucket/vcredist-aio.json) | `hash` 通过多行正则从 HTML 发行说明页面中抓取，而非校验和文件 |

## 反馈

发现失效链接或过时 manifest，请提交 [issue](https://github.com/hu3rror/scoop-muggle/issues) 或直接提 PR。
