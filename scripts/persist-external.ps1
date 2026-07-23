<#
    persist-external.ps1  (v4 — 最终版)
    -------------------------------------
    Scoop `persist_external` 字段的核心实现。

    职责：把安装目录（$dir）之外的数据目录/文件（例如 %AppData%\Code）通过
    Junction / Symlink 链接到 $persist_dir，实现跨 $dir 外数据的实时持久化。
    与原生 `persist` 字段并存、互不覆盖——`persist` 继续由 Scoop 核心处理
    $dir 内部数据，本文件只负责 $dir 之外的部分。

    ===========================================================================
    审查结论汇总（逐项核实，不夸大也不隐瞒）
    ===========================================================================

    [已核实无问题，原样保留的设计]
      · 用 Get-Item -Force（而非 Test-Path）判断路径是否存在——正确处理了
        悬空链接（目标已失效的 Junction/Symlink）的检测盲区。
      · "真实数据" vs "链接残留" 的状态区分——避免把损坏的链接当成真实数据
        去 Move-Item。
      · .Target 属性剥离 \\?\ 前缀的正则：逐字符核对无误；另查阅 NTFS
        reparse point 资料，Junction 的 target 实际上通常是纯路径、不带该
        前缀，因此即使前缀不存在这段代码也不会误伤，是安全的防御性写法。
      · @($sourceItem.Target)[0]：兼容 PowerShell 5.1 下 Target 可能是数组
        的情况。
      · New-Item 用 -Value 而非 -Target：查阅 PowerShell 官方文档，"Target
        is an alias for the Value parameter"，两者完全等价，不是 bug。
      · 删除前清除 ReadOnly 属性：.NET Delete() 遇到只读文件会抛
        UnauthorizedAccessException，这是真实的已知坑，处理正确。
      · 建链接前确保 source 的父目录存在：解决了应用从未运行过、自身配置
        目录尚不存在的场景。
      · 全程使用 -LiteralPath：避免路径中的特殊字符被当成通配符解释。

    [本版修复的真实问题]
      1. 文件/目录占位启发式会把 .gitconfig、.npmrc 等真实是文件的点前缀
         名字，全部误判成目录（原判断把所有点前缀名字都推给了目录分支），
         且没有手动标注机制可以纠正。现恢复三元数组
         [source, target, 'file'/'directory'] 的显式标注；遇到无法从名字
         判断的歧义情况（如 .gitconfig）直接报错，而不是静默创建成错误的
         类型。
      2. 卸载循环里 "已剥离外部链接" 的日志此前是无条件打印的，而实际删除
         函数在发现路径不是链接时会静默跳过，导致"什么都没删成"和"真的
         删除成功"打印同一句话。现在按删除函数的返回值分三种情况处理：
         成功剥离 / 不是链接需要人工核查 / 本来就不存在（不提示）。

    [本版新增的补充校验]
      3. 变量展开后补充 IsPathRooted 校验：如果 manifest 作者漏写了
         $env:/$home/%...% 前缀，之前会被 GetFullPath 悄悄按当前工作目录
         解析成意料之外的路径；现在会直接报出清晰错误。

    [本轮查证：单条目失败会不会拖垮整个安装]
      Invoke-PersistExternalInstall 对每个 persist_external 条目单独
      try/catch，失败时记录日志、跳过该条目，不影响其余条目和整个安装——
      前提是记录日志的方式本身不是终止性的。为此专门查了 Scoop 官方
      lib/core.ps1 源码，确认：

        function abort($msg, [int]$exit_code=1) { write-host $msg -f red; exit $exit_code }
        function error($msg) { write-host "ERROR $msg" -f darkred }
        function warn($msg)  { write-host "WARN $msg" -f darkyellow }

      error/warn 就是纯 Write-Host 包装，与 PowerShell 错误流、
      $ErrorActionPreference 毫无关系，不可能变成终止性错误；真正会终止
      安装的只有 abort（内部直接 exit）。同时确认 Scoop 调用 hook 脚本的
      路径（install_app → Invoke-HookScript → Invoke-Command scriptblock）
      上没有任何地方把 $ErrorActionPreference 设成 'Stop'。
      结论：单条目失败、错误分级、不影响其余条目和整体安装——这个设计是
      成立的，不用担心。

      基于这个查证结果，本版把 Write-Warning/Write-Error 换成了 Scoop 原生
      的 warn/error 函数：这样错误提示天生就不可能被外部
      $ErrorActionPreference 设置影响（不像 Write-Error 理论上仍要依赖
      "调用链上没人把它设成 Stop" 这个假设），同时颜色风格也和 Scoop 原生
      提示保持一致。为了不影响这个文件脱离真实 Scoop 会话单独做 Pester
      测试的能力，若检测到 warn/error 未定义（比如独立测试场景），会自动
      降级为标准的 Write-Warning/Write-Error。

    注意：本文件未在真实 Windows/Scoop 环境中执行测试（当前沙盒为 Linux，
    无 pwsh 可用），以上结论基于逐行静态审查 + 官方源码/文档查证，仍建议
    在真实环境里做一次实测收尾。

    对外入口（供 post_install / pre_uninstall 调用）：
      - Invoke-PersistExternalInstall
      - Invoke-PersistExternalUninstall
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# 0. 兼容层：优先使用 Scoop 原生的 warn/error（lib/core.ps1 里定义的纯
#    Write-Host 包装，永远不会成为终止性错误）；如果这个文件被单独加载
#    （例如脱离真实 Scoop 会话做 Pester 测试），则降级为标准的
#    Write-Warning/Write-Error，保证脚本本身仍然可以独立运行。
# ---------------------------------------------------------------------------
if (-not (Get-Command 'warn' -ErrorAction SilentlyContinue)) {
    function warn($msg) { Write-Warning $msg }
}
if (-not (Get-Command 'error' -ErrorAction SilentlyContinue)) {
    function error($msg) { Write-Error $msg }
}

# ---------------------------------------------------------------------------
# 0.1 小工具：路径尾部分隔符归一化。persist_external 的来源路径实际不可能
#     是盘符根目录，这里只是防御性兜底——避免把 "C:\" 这种裸盘符根目录
#     裁剪成语义完全不同的 "C:"（相对路径）。
# ---------------------------------------------------------------------------
function ConvertTo-TrimmedPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path.Length -gt 3) { return $Path.TrimEnd('\', '/') }
    return $Path
}

# ---------------------------------------------------------------------------
# 1. 路径解析：展开 $env:VAR / %VAR% / $home / ~，支持带括号的环境变量
#    （如 ProgramFiles(x86)）。
# ---------------------------------------------------------------------------
function Convert-ExternalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawPath)

    $p = $RawPath.Trim()

    if ($p -eq '$home' -or $p -eq '~') {
        $p = $HOME
    } elseif ($p -match '^(\$home|~)[/\\](?<rest>.*)$') {
        $p = Join-Path $HOME $Matches['rest']
    }

    # $env:VAR 形式
    $p = [regex]::Replace($p, '\$env:(?<name>[\w()]+)', {
            param($m)
            $varName = $m.Groups['name'].Value
            $val = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($val)) {
                throw "persist_external: 未知环境变量 `$env:$varName（来源路径: $RawPath）"
            }
            $val
        }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # %VAR% 形式
    $p = [regex]::Replace($p, '%(?<name>[\w()]+)%', {
            param($m)
            $varName = $m.Groups['name'].Value
            $val = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($val)) {
                throw "persist_external: 未知环境变量 %$varName%（来源路径: $RawPath）"
            }
            $val
        }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # 变量展开完必须是绝对路径。如果 manifest 作者漏写了 $env:/$home/%...%
    # 前缀，不做这个校验的话，GetFullPath 会悄悄按当前工作目录把它解析成
    # 一个谁也没预料到的路径，而不是在这里就报错。
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        throw "persist_external: 路径 '$RawPath' 展开后不是绝对路径（结果: '$p'），请检查是否漏写了 `$env:/`$home/%...% 前缀"
    }

    return [System.IO.Path]::GetFullPath($p)
}

# ---------------------------------------------------------------------------
# 2. 解析 manifest 的 persist_external 字段
#    支持二元 [source, target] 和三元 [source, target, type] 形式，第三个
#    元素可选 'file' / 'directory'，用于消解无法从名字猜出类型的歧义情况
#    （例如 .gitconfig 是文件、.vscode 是目录，光看名字规律猜不出来）。
# ---------------------------------------------------------------------------
function Get-PersistExternalDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Manifest)

    $raw = $Manifest.persist_external
    if (-not $raw) { return @() }
    if ($raw -isnot [array]) { $raw = @($raw) }

    $result = @()
    foreach ($item in $raw) {
        $typeHint = $null
        if ($item -is [array]) {
            $sourceRaw = $item[0]
            $targetName = $item[1]
            if ($item.Count -ge 3 -and $item[2]) {
                $typeHint = switch -Regex ($item[2]) {
                    '^(file)$' { 'File'; break }
                    '^(dir|directory)$' { 'Directory'; break }
                    default { throw "persist_external: 未知类型标注 '$($item[2])'，只能是 'file' 或 'directory'" }
                }
            }
        } else {
            $sourceRaw = $item
            $targetName = $null
        }

        $source = Convert-ExternalPath -RawPath $sourceRaw
        if (-not $targetName) {
            $targetName = Split-Path $source -Leaf
        }

        $result += [PSCustomObject]@{
            Source     = $source
            TargetName = $targetName
            TypeHint   = $typeHint
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# 2.1 判断"source 和 persist_dir 目标两边都不存在"时应该占位成文件还是目录
# ---------------------------------------------------------------------------
function Resolve-ExternalItemType {
    <#
        仅在需要新建占位（source 和 persist_dir 目标都不存在）时调用。
        优先使用 manifest 里的显式标注；没有标注时才用启发式猜测，且遇到
        猜不准的情况——点前缀且无二级扩展名，如 .gitconfig（文件）、
        .vscode（目录）——直接报错，而不是把所有点前缀名字都当成目录，
        导致真实是文件的场景被误建成空文件夹。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [string]$TypeHint
    )

    if ($TypeHint) { return $TypeHint }

    $leaf = Split-Path $Source -Leaf
    $ext = [System.IO.Path]::GetExtension($leaf)

    if ($leaf.StartsWith('.') -and $leaf -eq $ext) {
        throw "persist_external: 无法从名字 '$leaf' 判断应创建为文件还是目录（source 和 persist_dir 目标均不存在），请在 persist_external 里用三元数组显式标注类型，例如 [`"$Source`", `"$leaf`", `"file`"]"
    }

    if ($ext) { return 'File' }
    return 'Directory'
}

# ---------------------------------------------------------------------------
# 2.2 能力检测：是否可以创建 Symlink（文件级链接需要，Junction 不需要）
# ---------------------------------------------------------------------------
function Test-CanCreateSymlink {
    [CmdletBinding()]
    param()

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) { return $true }

    try {
        $devMode = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
            -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop
        return ($devMode -eq 1)
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# 3. 安装记录文件读写（$dir\.scoop-persist-external.json）
#    安装时把实际创建的链接落盘，卸载时优先读这份记录而不是重新解析
#    manifest——避免版本升级时字段路径变化导致卸载逻辑和实际创建的链接
#    对不上。
# ---------------------------------------------------------------------------
function Get-ExternalLinkRecordPath {
    param([Parameter(Mandatory)][string]$Dir)
    Join-Path $Dir '.scoop-persist-external.json'
}

function Save-ExternalLinkRecord {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][array]$Records
    )
    $path = Get-ExternalLinkRecordPath -Dir $Dir
    $Records | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Force -Encoding utf8
}

function Read-ExternalLinkRecord {
    param([Parameter(Mandatory)][string]$Dir)
    $path = Get-ExternalLinkRecordPath -Dir $Dir
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($content -isnot [array]) { $content = @($content) }
        return $content
    } catch {
        warn "persist_external: 读取链接记录 '$path' 失败，将回退到重新解析 manifest：$_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 4. 安全断链：用 .NET API 避免穿透误删 + 清除 ReadOnly 属性
#    返回 $true/$false 表示"是否真的删除了东西"，供调用方准确区分
#    "成功剥离" / "不是链接、跳过" / "本来就不存在" 三种情况。
# ---------------------------------------------------------------------------
function Remove-ReparsePointSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $CleanPath = ConvertTo-TrimmedPath -Path $Path
    $item = Get-Item -LiteralPath $CleanPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }        # 什么都没有，无需处理

    if (-not $item.LinkType) { return $false }     # 存在但不是链接，绝不误删

    if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
        $item.Attributes = $item.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
    }

    if ($item.PSIsContainer) {
        # .NET Directory.Delete 作用于 Junction/目录 Symlink 时，只删除
        # 联接点本身，绝不会递归触碰 Target 目录内容
        [System.IO.Directory]::Delete($CleanPath)
    } else {
        [System.IO.File]::Delete($CleanPath)
    }
    return $true
}

# ---------------------------------------------------------------------------
# 5. 核心逻辑：建立单个外部持久化链接
# ---------------------------------------------------------------------------
function New-ExternalPersistLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$PersistTarget,
        [string]$TypeHint
    )

    $Source = ConvertTo-TrimmedPath -Path $Source
    $PersistTarget = ConvertTo-TrimmedPath -Path $PersistTarget

    $sourceItem = Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue
    $targetItem = Get-Item -LiteralPath $PersistTarget -Force -ErrorAction SilentlyContinue

    $sourceIsLink = ($null -ne $sourceItem) -and [bool]$sourceItem.LinkType
    $sourceIsRealData = ($null -ne $sourceItem) -and (-not $sourceItem.LinkType)

    # 1. 幂等性检查：Source 已经是指向 PersistTarget 的有效链接 -> 直接跳过
    if ($sourceIsLink) {
        $currentTarget = @($sourceItem.Target)[0]
        if ($currentTarget) {
            $normCurrent = [System.IO.Path]::GetFullPath(($currentTarget -replace '^\\\\\?\\', ''))
            $normPersist = [System.IO.Path]::GetFullPath($PersistTarget)
            if ($normCurrent -eq $normPersist -and ($null -ne $targetItem)) {
                Write-Verbose "persist_external: '$Source' 已有效链接至 '$PersistTarget'，跳过"
                return $sourceItem.LinkType
            }
        }
    }

    # 2. 处理 PersistTarget 不存在的情况
    if ($null -eq $targetItem) {
        $targetParent = Split-Path $PersistTarget -Parent
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }

        if ($sourceIsRealData) {
            # 只有在 Source 是【真实数据】时才执行迁移
            Move-Item -LiteralPath $Source -Destination $PersistTarget -Force
            $sourceItem = $null
            $sourceIsRealData = $false
        } else {
            # Source 是【残留/悬空链接】，直接剥离清理，禁止当真实数据 Move-Item
            if ($sourceIsLink) {
                Remove-ReparsePointSafe -Path $Source | Out-Null
                $sourceItem = $null
                $sourceIsLink = $false
            }
            # 按显式标注或启发式判断创建文件还是目录占位，歧义情况（如
            # .gitconfig）直接报错而不是猜错
            $itemType = Resolve-ExternalItemType -Source $Source -TypeHint $TypeHint
            if ($itemType -eq 'File') {
                New-Item -ItemType File -Path $PersistTarget -Force | Out-Null
            } else {
                New-Item -ItemType Directory -Path $PersistTarget -Force | Out-Null
            }
        }
        $targetItem = Get-Item -LiteralPath $PersistTarget -Force -ErrorAction Stop
    }

    # 3. 处理冲突情况（PersistTarget 已有数据，且 Source 也是冲突的真实数据）
    if ($sourceIsRealData) {
        $backup = "$Source.pre-persist-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        warn "persist_external: '$Source' 与已有持久化数据冲突，原数据已自动备份至 '$backup'"
        Move-Item -LiteralPath $Source -Destination $backup -Force
        $sourceItem = $null
        $sourceIsRealData = $false
    }

    # 4. 彻底清理 Source 位置可能残留的失效/坏链接，确保创建新链接的前置
    #    路径完全空置
    if ($null -ne (Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue)) {
        Remove-ReparsePointSafe -Path $Source | Out-Null
    }

    # 5. 确保外域父级目录存在（首次安装、应用自身配置目录还没建出来的场景）
    $sourceParent = Split-Path $Source -Parent
    if (-not (Test-Path -LiteralPath $sourceParent)) {
        New-Item -ItemType Directory -Path $sourceParent -Force | Out-Null
    }

    # 6. 建立链接：目录用 Junction（免权限），文件用 SymbolicLink（需权限/
    #    开发者模式）
    $isDirTarget = $targetItem.PSIsContainer
    $linkType = if ($isDirTarget) { 'Junction' } else { 'SymbolicLink' }

    if ($isDirTarget) {
        New-Item -ItemType Junction -Path $Source -Target $PersistTarget -Force | Out-Null
    } else {
        # 文件级 Symlink 需要管理员权限或开发者模式，建之前先检查，给出
        # 清晰的报错原因，而不是让 New-Item 抛出难懂的系统级异常
        if (-not (Test-CanCreateSymlink)) {
            throw "persist_external: 创建文件级符号链接需要管理员权限或已开启开发者模式（目标: $Source）"
        }
        New-Item -ItemType SymbolicLink -Path $Source -Target $PersistTarget -Force | Out-Null
    }

    return $linkType
}

# ---------------------------------------------------------------------------
# 6. 对外入口
# ---------------------------------------------------------------------------
function Invoke-PersistExternalInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$PersistDir,
        [Parameter(Mandatory)][string]$Dir
    )

    $defs = Get-PersistExternalDefinition -Manifest $Manifest
    if (-not $defs) { return }

    $records = @()
    foreach ($d in $defs) {
        $target = Join-Path $PersistDir $d.TargetName
        try {
            $linkType = New-ExternalPersistLink -Source $d.Source -PersistTarget $target -TypeHint $d.TypeHint
            $records += @{ Source = $d.Source; Target = $target; LinkType = $linkType }
        } catch {
            # 单条目失败只记录、跳过，不影响其余条目和整体安装——error 是
            # 纯 Write-Host 包装，不会被 $ErrorActionPreference 影响、也
            # 不会中断这个 foreach 循环（已查证 Scoop 官方 lib/core.ps1）
            error "persist_external: 处理 '$($d.Source)' 失败: $_"
        }
    }

    if ($records) {
        Save-ExternalLinkRecord -Dir $Dir -Records $records
    }
}

function Invoke-PersistExternalUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Dir
    )

    $records = Read-ExternalLinkRecord -Dir $Dir

    if ($null -eq $records) {
        warn "persist_external: 未找到安装时链接记录，回退为重新解析 manifest.persist_external"
        $defs = Get-PersistExternalDefinition -Manifest $Manifest
        $records = $defs | ForEach-Object { @{ Source = $_.Source } }
    }

    foreach ($r in $records) {
        $removed = Remove-ReparsePointSafe -Path $r.Source
        if ($removed) {
            Write-Verbose "persist_external: 已剥离外部链接 '$($r.Source)'"
        } elseif ($null -ne (Get-Item -LiteralPath $r.Source -Force -ErrorAction SilentlyContinue)) {
            # 存在但不是链接：可能是链接损坏后用户手动放回了真实数据，
            # 绝不删除，只警告
            warn "persist_external: '$($r.Source)' 不是预期的链接，跳过删除以避免误删真实数据，请手动检查"
        }
        # 两者都不成立（本来就不存在）：无需任何提示
    }
}
