# Manifest field reference

Rules; a precedent names a manifest in `bucket/`. Wiki pages at the end.

## Required fields

| Field | Rule |
| --- | --- |
| `version` | Upstream version as published; keep the tag's form (`8.1.4.0`, `2.1.8`). |
| `description` | One line, no trailing period unless the project uses one. |
| `homepage` | Project page, not the download URL. |
| `license` | SPDX `identifier` when the project declares one. Otherwise a string: `Freeware`, `Proprietary`, `Public Domain`, `Shareware`, `Unknown`. An `url` key is allowed alongside `identifier`; append `,...` when the SPDX expression is incomplete; non-open-source licenses first. Bucket precedents: `{"identifier": "Freeware", "url": "..."}` (goodsync-10). |
| `url` | The download URL. A `#/<name>` fragment renames the download before extraction (`#/dl.7z`, `#/dl.7z_`). |
| `hash` | SHA256 hex by default; prefix `sha512:`, `sha1:`, `md5:` when the source publishes that. cherry-studio uses `sha512:` from `latest.yml`. |

### Hash sources

Three sources, in order; take the first the project offers and say which one you used:

1. GitHub release API — each asset carries `assets[].digest` as `sha256:<hex>`: `gh api repos/<owner>/<repo>/releases/latest --jq '.assets[] | {name, digest}'`.
2. An upstream hash file — `latest.yml`, `SHA256SUMS`, `*.sha256`, `checksums.txt`.
3. The downloaded file itself — the slowest and the last resort here; hashing it needs the `Get-FileHash` shim from `AGENTS.md`.

Cross-check against a second source when one exists: a lone digest that contradicts the asset's bytes only surfaces as a failed install. `autoupdate.hash` reads the same source as the manifest (`checkver-autoupdate.md`).

## Download shape

| Field | Notes |
| --- | --- |
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
| --- | --- |
| `bin` | String or array. An alias triple is `[exe, alias, args]` and must be wrapped in the array: `[["mihomo.exe", "clash"]]`. |
| `shortcuts` | 4 elements: `[target, "<AppsSubDir>\\<Name>", startParams, iconPath]`; the last two optional. Precedent of a launcher shortcut: cherry-studio. |
| `env_add_path` | Append a directory to PATH. |
| `env_set` | `{"VAR": "value"}`; `$dir` available. |
| `notes` | Array of lines shown after install. One line per command or fact; no prose paragraphs. |
| `psmodule` | `{"name": "..."}` — expose a PowerShell module as `$env:PSModulePath` target. posh-git, get-childitemcolor. |
| `depends` | Install another bucket app first; `suggest` for optional companions (qaac/qaac-qtfiles pair). |

## Install/uninstall hooks

Hook fields: `pre_install`, `post_install`, `pre_uninstall`, `post_uninstall`.
`##` — array of explanatory strings, the only comment mechanism JSON has here.
Hook variables (upstream): `$app`, `$architecture`, `$manifest`, `$version`, `$persist_dir`, `$bucketsdir`, `$original_dir`, `$scoopdir`, `$global`, `$dir` — there is no `$cmd`, and no flag says whether the hook runs for install or update: an undefined `$cmd` guard under `Set-StrictMode -Off` is false forever (`bucket/notepad3.json:34` is such a dead guard; don't copy it). `$dir` is the versioned install directory, except in `post_install` where it is the `current` junction (`apps\<app>\current`). `appdir <name>` resolves another scoop app's dir.

`scoop update` also runs the outgoing manifest's `pre_uninstall`/`post_uninstall` before reinstalling (`libexec/scoop-update.ps1:351,354,377`) — an uninstall hook must not assume the app is going away (see `persistence.md`).

Verify hook semantics against the installed scoop sources (`$SCOOP/apps/scoop/current` is a git checkout) rather than trusting this list: `lib/install.ps1` drives install, `libexec/scoop-update.ps1` drives update, and `Invoke-HookScript` executes a hook.

### Explorer integration

Optional registration of a context-menu entry or a URL scheme. The two templates live in `scripts/<app>/` — `install-context.reg` and `uninstall-context.reg` — and write the install path as `{{dir}}`. `post_install` resolves both under `$bucketsdir` and expands them into `$dir`, then stops: importing and removing the keys is the user's manual step (`GLOSSARY.md`, Explorer integration). `bucket/wu.json` and `bucket/zed.json` carry the live shape.

Three rules ride on that shape. A missing template warns and skips, so the install survives an install path that lacks the bucket's `scripts/`. The keys are HKCU only, so the import needs no admin. `notes` gives both commands, the removal one marked "run before uninstalling", because `scoop uninstall` deletes `$dir` together with its copy of the templates.

## Persistence and update

`persist` / `persist_external`: `persistence.md`. `checkver` / `autoupdate`: `checkver-autoupdate.md`.

## Comments and legacy

- `_comment` — deprecated; do not add.
- `extra` — free-form bucket data; unused here, do not add.

## Wiki pages

- App manifests: <https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests>
- Persistent data: <https://github.com/ScoopInstaller/Scoop/wiki/Persistent-data>
- Autoupdate: <https://github.com/ScoopInstaller/Scoop/wiki/Autoupdate>
