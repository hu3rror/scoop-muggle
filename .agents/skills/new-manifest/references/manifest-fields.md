# Manifest field reference

Counts are snapshots of `bucket/*.json` usage and exist to tell you what the bucket actually writes; `0` means the field is upstream-valid but this bucket never uses it. Every section links the official wiki page that defines the field.

## Required fields

| Field | Rule |
|---|---|
| `version` | Upstream version as published; keep the tag's form (`8.1.4.0`, `2.1.8`). |
| `description` | One line, no trailing period unless the project uses one. |
| `homepage` | Project page, not the download URL. |
| `license` | SPDX `identifier` when the project declares one. Otherwise a string: `Freeware`, `Proprietary`, `Public Domain`, `Shareware`, `Unknown`. An `url` key is allowed alongside `identifier`; append `,...` when the SPDX expression is incomplete; non-open-source licenses first. Bucket precedents: `{"identifier": "Freeware", "url": "..."}` (goodsync-10). |
| `url` | The download URL. A `#/<name>` fragment renames the download before extraction (`#/dl.7z`, `#/dl.7z_`). Count in bucket: 30 manifests use `#/dl.7z`. |
| `hash` | SHA256 hex by default; prefix `sha512:`, `sha1:`, `md5:` when the source publishes that. cherry-studio uses `sha512:` from `latest.yml`. |

## Download shape

| Field | Usage | Notes |
|---|---|---|
| `architecture` | 123 | Wraps per-arch `url`, `hash`, `bin`, `checkver`, `extract_dir`, `installer`, `pre_install`, `post_install`, `shortcuts`, `uninstaller`. Put arch-specific content here; see repo `AGENTS.md` for the hook merge rule. |
| `url` as array | 30 | Multi-asset installs: parallel `url`/`hash` arrays, one entry per asset (mihomo-shawl-service). |
| `extract_dir` | 23 | The single folder to strip from an archive. Verify the archive's layout before writing it. |
| `extract_to` | 0 | Extract into a subdirectory of the install dir instead of the root. |
| `innosetup` | 1 | `true` when the download is an Inno Setup installer that 7z can unpack. game-cheats-manager precedent. |
| `installer` | 6 | `{file, script, args, keep}` — run an installer from inside the extracted payload; `installer.keep` keeps it after install. Env inside `script`: `$fname`, `$manifest`, `$architecture`, `$dir`. |
| `uninstaller` | 8 | Same shape for uninstall. |

`msi` is deprecated upstream (documents the MSI URL) — treat the MSI as a plain zip instead.

## Binaries, shortcuts, environment

| Field | Usage | Notes |
|---|---|---|
| `bin` | 82 | String or array. An alias triple is `[exe, alias, args]` and must be wrapped in the array: `[["mihomo.exe", "clash"]]`. |
| `shortcuts` | 135 | 4 elements: `[target, "<AppsSubDir>\\<Name>", startParams, iconPath]`; the last two optional. Precedent of a launcher shortcut: cherry-studio. |
| `env_add_path` | 0 | Append a directory to PATH. |
| `env_set` | 1 | `{"VAR": "value"}`; `$dir` available. |
| `notes` | 24 | Array of lines shown after install. |
| `psmodule` | 2 | `{"name": "..."}` — expose a PowerShell module as `$env:PSModulePath` target. posh-git, get-childitemcolor. |
| `depends` | 4 | Install another bucket app first; `suggest` (6) for optional companions (qaac/qaac-qtfiles pair). |

## Install/uninstall hooks

| Field | Usage |
|---|---|
| `pre_install` | 49 |
| `post_install` | 23 |
| `pre_uninstall` | 17 |
| `post_uninstall` | 1 |
| `##` | 3 — array of explanatory strings, the only comment mechanism JSON has here. |

Hook variables (upstream): `$app`, `$architecture`, `$cmd`, `$manifest`, `$version`, `$persist_dir`, `$bucketsdir`, `$original_dir`, `$scoopdir`, `$global`. `$dir` is the current versioned directory, except in `post_install` where it points at the live install. `appdir <name>` resolves another scoop app's dir.

## Persistence

`persist` (52) and the bucket-specific `persist_external` (12) are covered in `persistence.md`.

## Update

`checkver` (150) and `autoupdate` (149) are covered in `checkver-autoupdate.md`.

## Comments and legacy

- `##` — array of comment lines (3 manifests).
- `_comment` — deprecated; do not add.
- `license.identifier` — object form above.
- `extra` — free-form bucket data; no usage here, do not add.

## Wiki pages

- App manifests: https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests
- Persistent data: https://github.com/ScoopInstaller/Scoop/wiki/Persistent-data
- Autoupdate: https://github.com/ScoopInstaller/Scoop/wiki/Autoupdate
