# Scoop Muggle Bucket [![Build status](https://ci.appveyor.com/api/projects/status/eiyp2qhs11n83jo0/branch/main?svg=true)](https://ci.appveyor.com/project/hu3rror/scoop-muggle/branch/master)

A [Scoop](https://scoop.sh/) bucket of Windows applications not commonly found in other buckets: reading/document tools, media players, network utilities, AI clients, and system utilities.

[简体中文](README.zh-cn.md)

## Installation

```pwsh
scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
scoop install muggle/<app_name>
```

Example:

```pwsh
scoop install muggle/keepassxc
```

Update all installed apps:

```pwsh
scoop update *
```

## Categories

### Reading & Documents
- [goldendict-ng](https://github.com/xiaoyifang/goldendict-ng) — dictionary lookup
- [anx-reader](https://github.com/Anxcye/anx-reader) — e-book reader with AI features
- [pdfpatcher](bucket/pdfpatcher.json) / [k2pdfopt](bucket/k2pdfopt.json) / [briss](bucket/briss.json) — PDF editing and layout optimization
- [zlibrary](bucket/zlibrary.json) — Z-Library desktop client

### Manga & Comics
- [yomikiru](https://github.com/mienaiyami/yomikiru)
- [mangadex-dl](https://mangadex-dl.mansuf.link/)
- [manhuagui-downloader](bucket/manhuagui-downloader.json)
- [PicaComic](bucket/PicaComic.json)
- [neeview](bucket/neeview.json)

### Music & Audio
- [musicplayer2](https://github.com/zhongyang219/MusicPlayer2) — playback, playlists, lyrics, format conversion
- [nora](https://github.com/Sandakan/Nora)
- [dopamine-legacy](bucket/dopamine-legacy.json) / [dopamine-preview](bucket/dopamine-preview.json)
- [lx-music-desktop](bucket/lx-music-desktop.json)
- [163MusicLyrics](bucket/163MusicLyrics.json) (and lite/pro variants)
- [mp3tag](bucket/mp3tag.json) — tag editor
- [qaac](bucket/qaac.json) / [m4acut](bucket/m4acut.json) — AAC/ALAC encoding and lossless cutting
- [vitomu](bucket/vitomu.json) / [deemix-portable](bucket/deemix-portable.json) / [qbldx-mod](bucket/qbldx-mod.json) — audio downloaders

### Network & Proxy
- [mihomo-shawl-service](bucket/mihomo-shawl-service.json) — mihomo bundled with a Windows service wrapper
- [sparkle](bucket/sparkle.json) / [clash-nyanpasu-nightly](bucket/clash-nyanpasu-nightly.json) / [goclashz](bucket/goclashz.json) — Mihomo/Clash GUIs
- [mosdns](bucket/mosdns.json) / [mosdns-cn](bucket/mosdns-cn.json) — DNS forwarder
- [q](bucket/q.json) — DNS client (UDP/TCP/DoT/DoH/DoQ/ODoH)
- [opentrace](bucket/opentrace.json) / [NatTypeTester](bucket/NatTypeTester.json) / [cdnlookup](bucket/cdnlookup.json) — network diagnostics
- [gopeed](bucket/gopeed.json) / [pget](bucket/pget.json) — parallel-connection downloaders

### AI Tools
- [cherry-studio](https://cherry-ai.com) — multi-LLM desktop client
- [chatall](http://chatall.ai) — query multiple chat models concurrently
- [witsy](bucket/witsy.json) — desktop AI assistant / MCP client
- [ainiee](https://github.com/NEKOparapa/AiNiee) — AI translation for games, novels, subtitles
- [pot-desktop](https://pot.pylogmon.com/) — cross-platform translation
- [geminicommit-cli](bucket/geminicommit-cli.json) — commit message generation via Gemini

### System & Productivity
- [keepassxc](https://keepassxc.org) — password manager
- [locale-remulator](https://github.com/InWILL/Locale_Remulator) — per-app region/language simulation
- [context-menu-manager](bucket/context-menu-manager.json) / [win11-classic-context-menu](bucket/win11-classic-context-menu.json)
- [notepad3](bucket/notepad3.json) / [heynote](bucket/heynote.json) — text editors
- [run-hidden](bucket/run-hidden.json) / [run-hidden-console](bucket/run-hidden-console.json) — run console apps without a visible window
- [posh-git](bucket/posh-git.json) / [get-childitemcolor](bucket/get-childitemcolor.json) — PowerShell modules
- [eza](bucket/eza.json) — `ls` replacement

### Image Processing
- [caesium](bucket/caesium.json) / [rimage](bucket/rimage.json) — image compression
- [jpegview-fork](https://github.com/sylikc/jpegview) — lightweight image viewer/editor
- [picgo](bucket/picgo.json) — image uploader
- [icns](bucket/icns.json) — `.icns` file creation

### Gaming
- [cheat-engine](bucket/cheat-engine.json)
- [game-cheats-manager](https://github.com/dyang886/Game-Cheats-Manager)
- [bg3-mod-manager](bucket/bg3-mod-manager.json)
- [nhse](bucket/nhse.json) / [ACNH-design-pattern-editor](bucket/ACNH-design-pattern-editor.json) — Animal Crossing tools
- [betterjoy-lts](bucket/betterjoy-lts.json) — Switch controller remapping
- [RyuSAK](bucket/RyuSAK.json) — Ryujinx save/mod manager
- [NsEmuTools](bucket/NsEmuTools.json) — Switch emulator installer

Full manifest list: [bucket/](bucket)

## Manifests worth reading

A few manifests use less common Scoop features and are useful as reference. All pull directly from the upstream project's own release channel.

| Manifest | Notable technique |
|---|---|
| [163MusicLyrics](bucket/163MusicLyrics.json) / [PicaComic](bucket/PicaComic.json) | Persists data outside the install directory (`$dir`), such as `%APPDATA%`, via the custom `persist_external` field paired with `scripts/persist-external.ps1` helper script. |
| [mihomo-shawl-service](bucket/mihomo-shawl-service.json) | Bundles two upstream release URLs, wraps the binary as a Windows service through an external helper script, coordinates `pre_install`/`post_install`/`pre_uninstall`/`persist`. |
| [goldendict-ng](bucket/goldendict-ng.json) | `checkver` pulls the version out of a Qt-tagged asset name using `jsonpath` + `regex` + `replace`, kept consistent with `autoupdate`. |
| [musicplayer2](bucket/musicplayer2.json) | Creates placeholder files in `pre_install` so `persist` has valid targets on first run. |
| [qaac](bucket/qaac.json) + [qaac-qtfiles](bucket/qaac-qtfiles.json) | Two manifests coordinated through `depends`/`suggest`; the second links itself into the first's install directory via `installer.script`. |
| [vcredist-aio](bucket/vcredist-aio.json) | `hash` is scraped from an HTML release-notes page with a multiline regex instead of a checksum file. |

## Contributing

Report outdated manifests or broken URLs via [issues](https://github.com/hu3rror/scoop-muggle/issues), or submit a PR directly.
