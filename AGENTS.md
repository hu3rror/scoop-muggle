# AGENTS.md

Scoop bucket repository: manifests for Windows applications, maintained under `bucket/`, `deprecated/`, `scripts/`, plus the custom `persist_external` mechanism.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues, operated via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use the default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.

## PowerShell + gh 实战

本仓库工作流高度依赖 `gh` CLI，在 PowerShell 5.1 下传参有几个固定坑，照下面写法规避：

- `gh` 的 `--jq` 表达式含空格 / 管道 / 内层引号会被 PowerShell 拆成多个参数。把表达式存入变量再传（`$expr = '...'; gh ... --jq $expr`），或用无空格的紧凑表达式（如 `--jq '.[].number'`）。
- `--add-assignee @me` 的 `@me` 会被解释成 splatting，必须写 `--add-assignee "@me"`。
- 多行 `--body` 一律用 `--body-file <file>` 传文件，不要用 here-string 内联（会变成多个参数）。
- `gh issue close --comment` 的 `✓ Closed` 输出走 stderr、显示为红字，不是失败——以 `gh issue view` 的实际 state 为准。
- 本环境无 `Get-FileHash` cmdlet；用 .NET `[System.Security.Cryptography.SHA256]::Create()` + `ComputeHash()` 算哈希。
- 循环里 `ConvertFrom-Json` 解析失败会残留上一个对象的引用，导致字段被误判到相邻 manifest：失败时 `continue` 或清空变量。
- 读含中文的 JSON（如 manifest 的 shortcuts 中文名）在 PS 5.1 可能乱码/解析失败，确认编码为 UTF-8 BOM 或换 .NET 读取。
