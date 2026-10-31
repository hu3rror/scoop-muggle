# Manifest field reference

Rules; a precedent names a manifest in `bucket/`. Wiki pages at the end.

## Required fields

| Field | Rule |
|---|---|
| `version` | Upstream version as published; keep the tag's form (`8.1.4.0`, `2.1.8`). |
| `description` | One line, no trailing period unless the project uses one. |
| `homepage` | Project page, not the download URL. |
| `license` | SPDX `identifier` when the project declares one. Otherwise a string: `Freeware`, `Proprietary`, `Public Domain`, `Shareware`, `Unknown`. An `url` key is allowed alongside `identifier`; append `,...` when the SPDX expression is incomplete; non-open-source licenses first. Bucket precedents: `{"identifier": "Freeware", "url": "..."}` (goodsync-10). |
| `url` | The download URL. A `#/<name>` fragment renames the download before extraction (`#/dl.7z`, `#/dl.7z_`). |
| `hash` | SHA256 hex by default; prefix `sha512:`, `sha1:`, `md5:` when the source publishes that. cherry-studio uses `sha512:` from `latest.yml`. |

## Download shape

| Field | Usage | Notes |
| Field | Notes |
|---|---|
| `architecture` | Wraps per-arch `url`, `hash`, `bin`, `checkver`, `extract_dir`, `installer`, `pre_install`, `post_install`, `shortcuts`, `uninstaller`. Put arch-specific content here; see repo `AGENTS.md` for the hook merge rule. |
| `url` as array | Multi-asset installs: parallel `url`/`hash` arrays, one entry per asset (mihomo-shawl-service). |
| `extract_dir` | Folder to strip from an archive. |
| `extract_to` | Extract into a subdirectory of the install dir instead of the root. |
| `innosetup` | `true` when the download is an Inno Setup installer that 7z can unpack. game-cheats-manager precedent. |
| `installer` | `{file, script, args, keep}` — run an installer from inside the extracted payload; `installer.keep` keeps it after install. Env inside `script`: `$fname`, `$manifest`, `$architecture`, `$dir`. |
| `uninstaller` | Same shape for uninstall. |

`msi` is deprecated upstream (documents the MSI URL) — treat the MSI as a plain zip instead.

## Binaries, shortcuts, environment

| Field | Notes |
|---|---|
| `bin` | String or array. An alias triple is `[exe, alias, args]` and must be wrapped in the array: `[["mihomo.exe", "clash"]]`. |
| `shortcuts` | 4 elements: `[target, "<AppsSubDir>\\<Name>", startParams, iconPath]`; the last two optional. Precedent of a launcher shortcut: cherry-studio. |
| `env_add_path` | Append a directory to PATH. |
| `env_set` | `{"VAR": "value"}`; `$dir` available. |
| `notes` | Array of lines shown after install. |
| `psmodule` | `{"name": "..."}` — expose a PowerShell module as `$env:PSModulePath` target. posh-git, get-childitemcolor. |
| `depends` | Install another bucket app first; `suggest` for optional companions (qaac/qaac-qtfiles pair). |

## Install/uninstall hooks

Hook fields: `pre_install`, `post_install`, `pre_uninstall`, `post_uninstall`.
`##` — array of explanatory strings, the only comment mechanism JSON has here.
Hook variables (upstream): `$app`, `$architecture`, `$cmd`, `$manifest`, `$version`, `$persist_dir`, `$bucketsdir`, `$original_dir`, `$scoopdir`, `$global`. `$dir` is the current versioned directory, except in `post_install` where it points at the live install. `appdir <name>` resolves another scoop app's dir.

## Persistence and update

`persist` / `persist_external`: `persistence.md`. `checkver` / `autoupdate`: `checkver-autoupdate.md`.

## Comments and legacy

- `_comment` — deprecated; do not add.
- `extra` — free-form bucket data; unused here, do not add.

## Wiki pages

- App manifests: https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests
- Persistent data: https://github.com/ScoopInstaller/Scoop/wiki/Persistent-data
- Autoupdate: https://github.com/ScoopInstaller/Scoop/wiki/Autoupdate
