# Persistence

The bucket has two mechanisms. Pick by how the app stores its user data.

## 1. Decide which mechanism

| App behavior | Mechanism |
|---|---|
| Data stays inside the install directory by design (configs, caches, profiles under `$dir`) | Native `persist` |
| App redirects its data to `$dir` via a portable flag (`--portable`, `--user-data-dir`, `PORTABLE_EXECUTABLE_DIR`) | Native `persist`, and add the redirection in `pre_install` (cherry-studio precedent) |
| App writes to `%APPDATA%` / `%LOCALAPPDATA%` (or elsewhere outside `$dir`) with no way to redirect | `persist_external` (bucket-specific extension) |

The default when unsure is native `persist`. Only choose `persist_external` when a data path outside `$dir` is observed in the app's docs, source, or a repo precedent — record that evidence, otherwise mark `[NEED-VERIFY]`.

## 2. Native `persist`

Upstream behavior (unchanged by this bucket):

- `"persist": "config"` or `["config", "conf"]` — the second element renames the data dir in `~/scoop/persist/<app>/`; existing `$dir` data migrates on first install.
- **When persisting a file, create it in `pre_install`, never `post_install`** — the persistence runner defaults to a directory when the target does not exist. musicplayer2 precedent.
- `scoop uninstall -p` purges the persisted data; plain uninstall keeps it.

## 3. `persist_external` (repo extension)

Custom key, documented in `docs/adr/0002-persist-external-retention.md` and implemented by `scripts/persist-external.ps1`. ADR-0002 resolved to keep it (option A) over third-party runtime helpers or dropping persistence.

Manifest shape — an array of items, each either:

- a plain external path string: `["$env:AppData\\NeatReader"]`, or
- a tuple `[source, targetName]` or `[source, targetName, kind]`, where `kind` is `"directory"` (alias `"dir"`); `"file"` is rejected:

```json
"persist_external": [
    ["$env:AppData\\com.github.pacalini", "data", "directory"],
    ["$env:LocalAppData\\com.github.pacalini", "cache", "directory"]
]
```

(PicaComic precedent.) Without a tuple, the external path's leaf becomes the stored name and the entry is linked as a directory (junctions only; ADR-0004).

Hook wiring — dot-source the helper and call the install/uninstall functions bare; they read `$dir`, `$persist_dir` and `$manifest` from the hook scope (ADR-0005):

```json
"post_install": [
    ". \"$(Find-BucketDirectory -Root -Name (coalesce $bucket 'muggle'))/scripts/persist-external.ps1\"",
    "Invoke-PersistExternalInstall"
],
"pre_uninstall": [
    ". \"$(Find-BucketDirectory -Root -Name (coalesce $bucket 'muggle'))/scripts/persist-external.ps1\"",
    "Invoke-PersistExternalUninstall"
]
```

Exception — when the install itself runs the real installer under admin (Inno/Silent), the link must exist before the installer runs, and services must be stopped before uninstall; then put the Install call in `pre_install` and keep service control around it. goodsync-10 precedent: `pre_install` = admin guard + dot-source + `Invoke-PersistExternalInstall` + run setup `/S` + stop `gs-server` process; `pre_uninstall` = admin guard + stop process + `gs-runner.exe /stop-remove-services` + dot-source + `Invoke-PersistExternalUninstall`.

A silent-setup frame may need the link created before setup writes `%LOCALAPPDATA%`.
Every hook string is a contract: `scripts/persist-external-hooks.Tests.ps1` parses each `bucket/*.json` and fails CI on a call with any argument, a renamed function, or a `persist_external` manifest missing the uninstall hook.

Manifests saved by older installs still pass `-Manifest`/`-Dir`/`-PersistDir`; the script keeps those aliases so their uninstall keeps working. Hooks you write never pass arguments.

Behavior notes:

- The helper keeps its own link record (`.scoop-persist-external.json`) inside `$persist_dir` per app, so uninstall can remove exactly the links this bucket created — it never touches real user data.
- `scoop update` re-runs the outgoing manifest's `pre_install`/`post_install` and, on the reinstall run, its `pre_uninstall`/`post_uninstall` (`libexec/scoop-update.ps1:351,377`); the functions are idempotent (link present → skip).
- Reconcile treats the record as the manifest's declared set: an entry removed from the manifest is unlinked on the next install/reset (persist data itself stays in place), an empty declared set deletes the record, and a partially-failed run records only the links it applied. If every link fails, the stale record is removed rather than kept while a legacy version-dir record, the only one left, stays in place.
- `scoop persist-external-reset` (alias registered on install) re-links everything after a failed move.

When neither is verifiable from docs or source, write native `persist` only if something in `$dir` is worth keeping; otherwise write no persist key and mark `[NEED-VERIFY]`.

## Precedents in the bucket

- Native `persist` — e.g. mihomo-shawl-service (config, ui, proxies, rules, cache.db, logs), cherry-studio (data after a `.cmd` launcher redirects via `PORTABLE_EXECUTABLE_DIR`).
- `persist_external` (ADR-0002 list) — apps writing to `%APPDATA%`/`%LOCALAPPDATA%` with no portable switch. cherry-studio, lx-music-desktop, wonderpen were migrated from `persist_external` to native when upstream gained redirection.
