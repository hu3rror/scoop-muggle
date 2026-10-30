# checkver and autoupdate

`checkver` finds the latest version; `autoupdate` rewrites the manifest when that version changes. Both run in maintenance/CI, never during install.

## 1. Choose the form from the source

Work down this list; stop at the first form the source actually supports.

| Source shape | checkver | autoupdate |
|---|---|---|
| GitHub releases with `/releases` page | `"checkver": "github"` (74 manifests) or `{"github": "<repo url>"}` (25) | `url` with `$version` |
| A JSON endpoint (GitHub API, `latest.json`, `update.json`) | `{"url": "<json>", "jsonpath": "$.<path>"}` (17) — add `regex`/`replace` when the tag is not clean | `url` with `$version`, `hash` from the same JSON |
| HTML page, version appears in plain text | `{"url": "<page>", "regex": "<pattern>"}`; add `"reverse": true` when newest is last | `url` with `$version` |
| XML/RSS feed | `{"url": "...", "xpath": "..."}` | `url` with `$version` |
| Hashing from RDF/metalink/fosshub/sourceforge endpoints | plain `url` + hash mode (fosshub/sourceforge auto-detect) | `hash` with the matching `mode` |
| Multi-hop version (several pages, token required) | `{"script": [...]}` — last resort, flag in the report | only when the script also yields a stable URL |

Extra `checkver` properties: `url`, `regex`/`re`, `jsonpath`/`jp`, `xpath`, `reverse`, `replace`, `useragent`, `script`. `replace` (13 manifests) reshapes the captured value into the version, e.g. stripping a `v` prefix or a suffix.

No version API (ghxi green page, plain direct URL): write neither `checkver` nor `autoupdate`, note it in the report.

## 2. Captured and version variables

- `checkver.replace`: `${1}`, `${name}` (1-based capture names).
- `autoupdate.url`/`hash`: `$match1`, `$matchName`.
- Versions: `$version`, `$underscoreVersion`, `$dashVersion`, `$cleanVersion`, `$majorVersion`, `$minorVersion`, `$patchVersion`, `$buildVersion`, `$matchHead`, `$matchTail`, `$preReleaseVersion`.
- URL: `$url`, `$baseurl`, `$basename`.
- Hash: `$md5`, `$sha1`, `$sha256`, `$sha512`, `$checksum`, `$base64` (base64 form of the hash — cherry-studio uses `$base64` with `sha512:` in a `latest.yml` regex).

## 3. autoupdate.hash

Available keys: `url`, `mode`, `jsonpath`, `jp`, `xpath`, `regex`, `replace`, `algorithm`, `extract` (an embedded-manifest field), `useragent`.

Mode chain, first success wins: `extract` (default) → `json` → `xpath` → `rdf` → `metalink` → `fosshub`/`sourceforge` (auto when the URL matches) → `download` (download and hash the file itself).

`extract` built-in regexes, useful when no checksum file exists:

- bare hash: `^([a-fA-F0-9]+)$`
- `hash filename` pairs: `([a-fA-F0-9]{32,128})[\x20\t]+.*$basename(?:[\x20\t]+\d+)?`

## 4. Verify before reporting

1. `bin/checkver.ps1 -App <name>` — the reported version must equal the manifest's `version`. (The wrapper already passes `-Dir bucket`; never pass `-Dir` yourself, and `-u` is not an accepted parameter here.)
2. With autoupdate: `bin/checkver.ps1 -App <name> -ForceUpdate`, then diff. The rewritten `url`, `hash`, and `extract_dir` must equal the values already in the manifest. A mismatch means the URL template or hash rule is wrong.
3. `scoop config debug $true` before a checkver run when the form misbehaves; capture the regex/JSON match in the output.
4. The manual round-trip also works: lower `version`, run `-ForceUpdate`, confirm the bump, restore if needed.

Unverifiable at build time (e.g. a source that publishes only a rolling URL): keep the manifest installable, write no autoupdate, and mark `[NEED-VERIFY]`.

## 5. Bucket precedents

- `checkver: "github"` — 74 manifests.
- `checkver: {"github": "<repo>"}` — 25.
- `jsonpath` — 17, e.g. goldendict-ng (`jsonpath` + `regex` + `replace` over a Qt-tagged asset name).
- `regex` on HTML — e.g. vcredist-aio (multiline regex over a release-notes page).
- `script` — 2: hitomi-downloader (multi-page `Invoke-WebRequest` + `[regex]::Match`), spotx (try/catch + `Get-GitHubToken` + commit-date version).
- `latest.yml` hash source — 8, e.g. cherry-studio (`$baseurl/latest.yml` + regex with `$base64`).
- `reverse`, `xpath`, `rdf`, `metalink` — 0 in this bucket; valid upstream, use when the source demands it.

Wiki: https://github.com/ScoopInstaller/Scoop/wiki/Autoupdate
