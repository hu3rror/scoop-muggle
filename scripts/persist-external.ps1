<#
    persist-external.ps1
    --------------------
    Scoop `persist_external` 字段核心实现。
    用于将安装目录（$dir）之外的数据/配置（如 %AppData%\Code）通过 Junction/Symlink
    链接至 $persist_dir，实现跨安装目录的实时持久化。与原生 `persist` 字段并行不冲突。

    对外入口：
      - Invoke-PersistExternalInstall
      - Invoke-PersistExternalUninstall
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# 0. 兼容层：优先使用 Scoop 原生 warn/error（纯 Write-Host，不会抛出终止性异常）；
#    若脱离 Scoop 会话独立运行（如 Pester 测试），则自动降级为 Write-Warning/Error。
# ---------------------------------------------------------------------------
if (-not (Get-Command 'warn' -ErrorAction SilentlyContinue)) {
    function warn($msg) { Write-Warning $msg }
}
if (-not (Get-Command 'error' -ErrorAction SilentlyContinue)) {
    function error($msg) { Write-Error $msg }
}

# 路径尾部分隔符归一化（保留盘符根目录如 "C:\"）
function ConvertTo-TrimmedPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path.Length -gt 3) { return $Path.TrimEnd('\', '/') }
    return $Path
}

# ---------------------------------------------------------------------------
# 1. 路径解析：展开 $env:VAR / %VAR% / $home / ~，支持 ProgramFiles(x86) 等带括号变量
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

    # 展开 $env:VAR 形式
    $p = [regex]::Replace($p, '\$env:(?<name>[\w()]+)', {
            param($m)
            $varName = $m.Groups['name'].Value
            $val = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($val)) {
                throw "persist_external: 未知环境变量 `$env:$varName (来源路径: $RawPath)"
            }
            $val
        }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # 展开 %VAR% 形式
    $p = [regex]::Replace($p, '%(?<name>[\w()]+)%', {
            param($m)
            $varName = $m.Groups['name'].Value
            $val = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($val)) {
                throw "persist_external: 未知环境变量 %$varName% (来源路径: $RawPath)"
            }
            $val
        }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # 校验是否为绝对路径，拦截因前缀漏写导致的当前工作目录误拼接
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        throw "persist_external: 路径 '$RawPath' 展开后不是绝对路径 (结果: '$p')，请检查是否漏写 `$env: / `$home / %...% 前缀 "
    }

    return [System.IO.Path]::GetFullPath($p)
}

# ---------------------------------------------------------------------------
# 2. 解析 Manifest 定义
#    支持二元 [source, target] 与三元 [source, target, 'file'|'directory'] 格式
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

# 当 source 与 target 均不存在时，确定新新建占位符类型（解决如 .gitconfig 与 .vscode 的命名歧义）
function Resolve-ExternalItemType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [string]$TypeHint
    )

    if ($TypeHint) { return $TypeHint }

    $leaf = Split-Path $Source -Leaf
    $ext = [System.IO.Path]::GetExtension($leaf)

    # 点前缀且无二级扩展名时无法自动推断，强制要求三元组显式标注
    if ($leaf.StartsWith('.') -and $leaf -eq $ext) {
        throw "persist_external: 无法从名字 '$leaf' 推断占位类型（文件/目录），请在 manifest 中使用三元数组显式指定，例如 ['$Source', '$leaf', 'file']"
    }

    if ($ext) { return 'File' }
    return 'Directory'
}

# 检测权限：文件级 SymbolicLink 需要管理员权限或开启 Windows 开发者模式
function Test-CanCreateSymlink {
    [CmdletBinding()]
    param()

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
# 3. 链接状态持久化（落盘至 $dir\.scoop-persist-external.json）
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
        warn "persist_external: 读取链接记录 '$path' 失败，将回退为重新解析 manifest：$_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 4. 安全剥离链接
#    清除 ReadOnly 属性，并调用 .NET API 避开 Remove-Item 可能存在的递归穿透风险
# ---------------------------------------------------------------------------
function Remove-ReparsePointSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $CleanPath = ConvertTo-TrimmedPath -Path $Path
    # 使用 Get-Item -Force 获取物理节点，防止 Test-Path 因悬空链接返回 $false
    $item = Get-Item -LiteralPath $CleanPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }

    # 保护机制：非链接实体绝不误删
    if (-not $item.LinkType) { return $false }

    # 清除 ReadOnly 属性，防止 .NET Delete() 报 UnauthorizedAccessException
    if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
        $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }

    if ($item.PSIsContainer) {
        # .NET Directory.Delete 作用于 Junction 时仅删除联接点本身，不会递归触碰目标目录
        [System.IO.Directory]::Delete($CleanPath)
    } else {
        [System.IO.File]::Delete($CleanPath)
    }
    return $true
}

# ---------------------------------------------------------------------------
# 5. 核心链接逻辑（处理迁移、冲突与悬空链接）
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

    # 1. 幂等性检查：若已成功链接至目标则跳过
    if ($sourceIsLink) {
        # 取 @()[0] 兼容 PS 5.1 下 Junction Target 返回 List[string] 的情况
        $currentTarget = @($sourceItem.Target)[0]
        if ($currentTarget) {
            $normCurrent = [System.IO.Path]::GetFullPath(($currentTarget -replace '^\\\\\?\\', ''))
            $normPersist = [System.IO.Path]::GetFullPath($PersistTarget)
            if ($normCurrent -eq $normPersist -and ($null -ne $targetItem)) {
                Write-Verbose "persist_external: '$Source' 已有效链接至 '$PersistTarget' "
                return $sourceItem.LinkType
            }
        }
    }

    # 2. 处理持久化存储区目标不存在的情况
    if ($null -eq $targetItem) {
        $targetParent = Split-Path $PersistTarget -Parent
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }

        if ($sourceIsRealData) {
            # 仅迁移真实数据，禁止对悬空/坏链接执行 Move-Item
            Move-Item -LiteralPath $Source -Destination $PersistTarget -Force
            $sourceItem = $null
            $sourceIsRealData = $false
        } else {
            if ($sourceIsLink) {
                Remove-ReparsePointSafe -Path $Source | Out-Null
                $sourceItem = $null
                $sourceIsLink = $false
            }
            # 创建空文件/空目录占位
            $itemType = Resolve-ExternalItemType -Source $Source -TypeHint $TypeHint
            if ($itemType -eq 'File') {
                New-Item -ItemType File -Path $PersistTarget -Force | Out-Null
            } else {
                New-Item -ItemType Directory -Path $PersistTarget -Force | Out-Null
            }
        }
        $targetItem = Get-Item -LiteralPath $PersistTarget -Force -ErrorAction Stop
    }

    # 3. 处理冲突：持久化存储区与外域同时存在真实数据，备份外域旧数据
    if ($sourceIsRealData) {
        $backup = "$Source.pre-persist-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        warn "persist_external: '$Source' 与已有持久化数据冲突，原数据已自动备份至 '$backup' "
        Move-Item -LiteralPath $Source -Destination $backup -Force
        $sourceItem = $null
        $sourceIsRealData = $false
    }

    # 4. 清理外域残留的旧/坏链接
    if ($null -ne (Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue)) {
        Remove-ReparsePointSafe -Path $Source | Out-Null
    }

    # 5. 确保外域父级目录存在
    $sourceParent = Split-Path $Source -Parent
    if (-not (Test-Path -LiteralPath $sourceParent)) {
        New-Item -ItemType Directory -Path $sourceParent -Force | Out-Null
    }

    # 6. 建立链接（目录使用 Junction，文件使用 SymbolicLink）
    $isDirTarget = $targetItem.PSIsContainer
    $linkType = if ($isDirTarget) { 'Junction' } else { 'SymbolicLink' }

    if ($isDirTarget) {
        New-Item -ItemType Junction -Path $Source -Target $PersistTarget -Force | Out-Null
    } else {
        if (-not (Test-CanCreateSymlink)) {
            throw "persist_external: 创建文件符号链接需要管理员权限或启用开发者模式 (目标: $Source)"
        }
        New-Item -ItemType SymbolicLink -Path $Source -Target $PersistTarget -Force | Out-Null
    }

    return $linkType
}

# ---------------------------------------------------------------------------
# 6. 对外主入口
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
            # 单项失败打印错误并继续处理后续项，不终止整体安装
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

    # 优先使用落盘记录进行解链，确保精准回溯
    $records = Read-ExternalLinkRecord -Dir $Dir

    if ($null -eq $records) {
        warn "persist_external: 未找到安装记录文件，回退为重新解析 manifest.persist_external"
        $defs = Get-PersistExternalDefinition -Manifest $Manifest
        $records = $defs | ForEach-Object { @{ Source = $_.Source } }
    }

    foreach ($r in $records) {
        $removed = Remove-ReparsePointSafe -Path $r.Source
        if ($removed) {
            Write-Verbose "persist_external: 已剥离外部链接 '$($r.Source)'"
        } elseif ($null -ne (Get-Item -LiteralPath $r.Source -Force -ErrorAction SilentlyContinue)) {
            warn "persist_external: '$($r.Source)' 不是预期链接，跳过删除以保护真实数据，请手动检查 "
        }
    }
}
