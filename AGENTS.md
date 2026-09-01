# AGENTS.md

Scoop bucket repository: manifests for Windows applications, maintained under `bucket/`, `deprecated/`, `scripts/`, plus the custom `persist_external` mechanism.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues, operated via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use the default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md` + `docs/adr/`（无则跳过，随 domain-modeling 惰性创建）。See `docs/agents/domain.md`.

## 环境实战（PS 5.1 / gh / git / scoop）

本仓库工作流在 PowerShell 5.1 下交互，照下面写法规避固定坑：

- `gh` 的 `--jq` 表达式含空格 / 管道 / `\(...)` 会被 PowerShell 拆成多个参数；**存变量也救不了含 `| join(...)` 的格式化表达式**（实测仍拆参）。无空格紧凑表达式（`--jq '.[].number'`）可直接用；其余（`gh issue list` / `gh run list` / `gh run view` 的格式化输出）改用 `ConvertFrom-Json` + PowerShell 侧格式化最稳。
- `--add-assignee @me` 的 `@me` 会被解释成 splatting，必须写 `--add-assignee "@me"`。
- 多行 `--body` 一律用 `--body-file <file>` 传文件，不要用 here-string 内联（会变成多个参数）。
- `gh issue close --comment` 的 `✓ Closed` 输出走 stderr、显示为红字，不是失败——以 `gh issue view` 的实际 state 为准。
- `git push` 的进度输出（`To https://...`）走 stderr 显示为 NativeCommandError 红字，也不是失败——以 `git log` / `git status` / 远端核对实际结果。
- 循环里 `ConvertFrom-Json` 解析失败会残留上一个对象的引用，导致字段被误判到相邻 manifest：失败时 `continue` 或清空变量。
- 读含中文的文件（manifest JSON、ps1 脚本头部）在 PS 5.1 可能乱码/解析报错（如 `Get-Content` 读 .ps1 报 ParserError），用 .NET `[IO.File]::ReadAllText` 读取。
- 更新 map/issue body（`gh issue edit <n> --body-file`）时，PowerShell 双引号字符串里的 markdown 反引号（如 `` `app_data_dir()` ``）会被当作转义符吞掉（反引号+a 变 `^G`）。用单引号字符串拼接，或先写临时文件再 `--body-file`。

### gh api 与源码获取

- `gh api` 的 `--jq` 只写紧凑表达式，含函数链（`test()`/`contains()`）会报 "function not defined"；复杂过滤改用 `ConvertFrom-Json` + PowerShell 侧过滤。
- 下载 release 资产（octet-stream，如 `latest.yml`）用 `curl.exe -sL <url>`，`gh api` 不适用。
- 读上游仓库源码用 `gh api <repo>/contents/<path> --jq '.content'`（base64 解码：`[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))`）；`fetch_content` mode=answer 受 quota 限制报 429 时改用这个。
- 判断远端文件/app 是否存在（如某 manifest 是否在 Extras/Main 收录）：`gh api ... --jq '.name'` 在 404 时返回非空错误文本，会被误判为存在。用 `curl.exe -sL -o NUL -w "%{http_code}" <raw url>` 以状态码判定（200/404）。
- 并行 `gh issue create` 返回的编号可能与创建顺序相反：创建后立即用 `gh issue view` 核对编号-标题对应。

### git 与换行

- PS 5.1 无 `&&`/`||`：复合命令用 `;` 分隔或分行执行。
- 仓库 `.gitattributes` 为 `* text=auto eol=crlf`，测试强制物理 CRLF 且文件以换行结尾；写/编辑工具产出 LF。改完文本文件用 .NET `ReadAllText` 读，先归一为 LF 再转 CRLF，补末尾换行，UTF8 无 BOM（测试禁 BOM）后 `WriteAllText`。
- `core.autocrlf=false` 时 `git status` 会把已按 eol=crlf 正确检出的文件误报为 modified（`git diff` 无内容差异）。鉴别：`git ls-files --eol` 显示 `i/lf w/crlf` + `attr/text=auto eol=crlf` 即规范状态；此时 `git add <文件>` 重新规范化，blob 不变则不产生多余 diff。

### scoop manifest 与安装

- `arch_specific` 对 hook（pre_install/post_install 等）取「架构级优先、有则忽略顶层」：manifest 顶层与 `architecture.<arch>` 同时写时**只有架构版本执行**。架构相关内容（解包、launcher）放架构级；跨架构逻辑（数据迁移）放顶层 `post_install`（在 persist 链接之后执行，可安全操作 `$persist_dir`）。
- 版本不变时 `scoop update <app>` 不会重装；manifest 变更测试用 `scoop update <app> --force`。
- 本环境无 `Get-FileHash` cmdlet：自己算 hash 用 .NET `[System.Security.Cryptography.SHA256]::Create()` + `ComputeHash()`；跑 `scoop update/install` 前必须注入兼容函数（scoop 两处调用 `-Path $file -Algorithm $alg` 与 `-InputStream $urlStream`，需返回含 `.Hash` 大写 hex 的对象），否则下载后 hash 校验假失败（报 Hash check failed 且 Actual 为空）。

### checkver 与 autoupdate

- `bin/checkver.ps1` wrapper 已内置 `-Dir bucket`，勿再传 `-Dir`（报 "parameter specified multiple times"）。官方参数：`-App <name>` 单查、`-Update`/`-ForceUpdate` 自动改 manifest、`-SkipUpdated` 只看有更新的；`-u` 不是有效参数。
- 自动更新要下载算 hash → 同样先注入 Get-FileHash 兼容函数（同 `scoop install`）。
- 全量 checkver 时部分 app 报「Windows PowerShell 处于非交互模式。朗读和提示功能不可用」（Invoke-WebRequest 在非交互会话的报错），属环境噪音、非 manifest 问题，可忽略。
- autoupdate 报 404 = 上游 URL 结构变了（案例：sf6-cm-tray-mod 新增 `/releases/<ver>/<sha256>/` 层级）。对策：抓上游 `latest.json` 看真实结构；checkver 改 regex 同时捕获 `version`+`sha256`（`(?<version>...)` / `(?<sha256>...)`，后者以 `$matchSha256` 注入 URL）；hash 用 `autoupdate.hash.jsonpath` 从 json 提取（如 `$.artifacts['windows-amd64'].sha256`）。改前用 `curl.exe -w "%{http_code}"` 验证新 URL 可达、用 Python 验证 jsonpath。

### deprecated 目录

- `lib/manifest.ps1`：deprecated/ 是 `scoop update/uninstall` 的 manifest 兜底来源（bucket/ 找不到时回退查 deprecated/）→ **删除 deprecated manifest 后，已安装该 app 的用户无法再 scoop update**。官方 ScoopInstaller/Main 也保留 deprecated/，归档弃用是生态惯例。
- deprecated/ 不参与测试与 excavator 更新（失控存档），上游 URL 可能已过期。
- 清理原则：只删「上游 URL 失效 + 无替代 + 无引用（README / 其他 manifest）」三条件均满足的死条目；`git rm` + 本地测试 + CI 验证。
- 判定 URL 失效：`curl.exe -sL -o NUL -w "%{http_code}"`，404=失效、000=瞬时超时需复测完整 URL、451=法律封禁（GitHub DMCA）。

### 跑测试

- `bin\test.ps1` 需要 Pester 5.2.0 + BuildHelpers 2.0.1（预装于 `Documents\WindowsPowerShell\Modules`，默认 PSModulePath 找不到）：先 `$env:PSModulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules;$env:PSModulePath"` 再跑。
