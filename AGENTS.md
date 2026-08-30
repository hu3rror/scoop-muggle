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

本仓库工作流高度依赖 `gh` CLI，在 PowerShell 5.1 下交互有几个固定坑，照下面写法规避：

- `gh` 的 `--jq` 表达式含空格 / 管道 / 内层引号会被 PowerShell 拆成多个参数。把表达式存入变量再传（`$expr = '...'; gh ... --jq $expr`），或用无空格的紧凑表达式（如 `--jq '.[].number'`）。
- `--add-assignee @me` 的 `@me` 会被解释成 splatting，必须写 `--add-assignee "@me"`。
- 多行 `--body` 一律用 `--body-file <file>` 传文件，不要用 here-string 内联（会变成多个参数）。
- `gh issue close --comment` 的 `✓ Closed` 输出走 stderr、显示为红字，不是失败——以 `gh issue view` 的实际 state 为准。
- 本环境无 `Get-FileHash` cmdlet；用 .NET `[System.Security.Cryptography.SHA256]::Create()` + `ComputeHash()` 算哈希。
- 循环里 `ConvertFrom-Json` 解析失败会残留上一个对象的引用，导致字段被误判到相邻 manifest：失败时 `continue` 或清空变量。
- 读含中文的文件（manifest JSON、ps1 脚本头部）在 PS 5.1 可能乱码/解析报错（如 `Get-Content` 读 .ps1 报 ParserError），用 .NET `[IO.File]::ReadAllText` 读取。

### gh api 与源码获取

- `gh api` 的 `--jq` 只写紧凑表达式，含函数链（`test()`/`contains()`）会报 "function not defined"；复杂过滤改用 `ConvertFrom-Json` + PowerShell 侧过滤。
- 下载 release 资产（octet-stream，如 `latest.yml`）用 `curl.exe -sL <url>`，`gh api` 不适用。
- 读上游仓库源码用 `gh api <repo>/contents/<path> --jq '.content'`（base64 解码：`[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))`），避开 `fetch_content` mode=answer 的 429 quota。
- 并行 `gh issue create` 返回的编号可能与创建顺序相反：创建后立即用 `gh issue view` 核对编号-标题对应。

### git 与换行

- PS 5.1 无 `&&`/`||`：复合命令用 `;` 分隔或分行执行。
- 仓库 `.gitattributes` 为 `* text=auto eol=crlf`，测试强制物理 CRLF 且文件以换行结尾。写/编辑工具产出 LF，改完文本文件后用 .NET 转 CRLF 并补末尾换行：`[IO.File]::ReadAllText` → `-replace "`r`n","`n" -replace "`n","`r`n"` → 补 `"`r`n"` → `WriteAllText`（UTF8 无 BOM，测试禁 BOM）。
- `core.autocrlf=false` 时 `git status` 会把已按 eol=crlf 正确检出的文件误报为 modified（`git diff` 无内容差异）。鉴别：`git ls-files --eol` 显示 `i/lf w/crlf` + `attr/text=auto eol=crlf` 即规范状态；此时 `git add <文件>` 重新规范化，blob 不变则不产生多余 diff。

### 模块安装

- 本机 `Install-Module`（PowerShellGet）不可用（PackageManagement 加载失败），用 PSResourceGet：`Install-PSResource <mod> -Version x.y.z -Scope CurrentUser -TrustRepository`（非交互模式必须显式 trust）。
- `Install-PSResource` 装完落在 `Documents\WindowsPowerShell\Modules`，而 PSModulePath 第一位是 `Documents\PowerShell\Modules`，`#Requires` 会找不到：先手动拼前缀 `$env:PSModulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules;$env:PSModulePath"`，再 `Import-Module -RequiredVersion`。
