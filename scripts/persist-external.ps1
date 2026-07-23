Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# 1. 路径解析：支持带括号的环境变量（如 ProgramFiles(x86)）
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

    return [System.IO.Path]::GetFullPath($p)
}

# ---------------------------------------------------------------------------
# 2. 解析 Manifest 字段定义
# ---------------------------------------------------------------------------
function Get-PersistExternalDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Manifest)

    $raw = $Manifest.persist_external
    if (-not $raw) { return @() }
    if ($raw -isnot [array]) { $raw = @($raw) }

    $result = @()
    foreach ($item in $raw) {
        if ($item -is [array]) {
            $sourceRaw = $item[0]
            $targetName = $item[1]
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
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# 3. 记录文件读写 ($dir\.scoop-persist-external.json)
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
        Write-Warning "persist_external: 读取链接记录 '$path' 失败，将回退到重新解析 manifest：$_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 4. 安全断链辅助函数 (修复了 ReadOnly 属性阻碍删除的隐患)
# ---------------------------------------------------------------------------
function Remove-ReparsePointSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $CleanPath = $Path.TrimEnd('\', '/')
    # 严格使用 Get-Item -LiteralPath -Force 获取物理节点（忽略悬空状态）
    $item = Get-Item -LiteralPath $CleanPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }

    # 安全防御：如果不是链接（是真实数据），绝不误删！
    if (-not $item.LinkType) { return }

    # 【隐患修复 2】：先移除只读属性，防止 .NET Delete() 抛出 UnauthorizedAccessException
    if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
        $item.Attributes = $item.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
    }

    if ($item.PSIsContainer) {
        # .NET Directory.Delete 作用于 Junction/DirectorySymlink 时，只删除联接点本身，绝不递归触碰 Target 内容
        [System.IO.Directory]::Delete($CleanPath)
    } else {
        # 文件软链
        [System.IO.File]::Delete($CleanPath)
    }
}

# ---------------------------------------------------------------------------
# 5. 核心逻辑：建立链接 (修复了 PS 5.1 下 Target 属性为数组引发的异常)
# ---------------------------------------------------------------------------
function New-ExternalPersistLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$PersistTarget
    )

    $Source = $Source.TrimEnd('\', '/')
    $PersistTarget = $PersistTarget.TrimEnd('\', '/')

    # 获取物理节点（不随悬空链接解析）
    $sourceItem = Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue
    $targetItem = Get-Item -LiteralPath $PersistTarget -Force -ErrorAction SilentlyContinue

    # 精准判定节点状态
    $sourceIsLink = ($null -ne $sourceItem) -and [bool]$sourceItem.LinkType
    $sourceIsRealData = ($null -ne $sourceItem) -and (-not $sourceItem.LinkType)

    # 1. 检查幂等性：如果 Source 已经是指向 PersistTarget 的有效链接 -> 直接跳过
    if ($sourceIsLink) {
        # 【隐患修复 1】：显式提取首个字符串元素，兼容 PS 5.1 中 Target 返回 List[string] 的情况
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
            # 如果 Source 是【残留/悬空链接】，直接剥离清理，禁止当作真实数据 Move-Item
            if ($sourceIsLink) {
                Remove-ReparsePointSafe -Path $Source
                $sourceItem = $null
                $sourceIsLink = $false
            }
            # 智能判定初始化空文件还是空目录
            $leaf = Split-Path $Source -Leaf
            if ($leaf -match '\.[a-zA-Z0-9_-]+$' -and $leaf -notmatch '^\.') {
                New-Item -ItemType File -Path $PersistTarget -Force | Out-Null
            } else {
                New-Item -ItemType Directory -Path $PersistTarget -Force | Out-Null
            }
        }
        # 刷新存储区节点状态
        $targetItem = Get-Item -LiteralPath $PersistTarget -Force -ErrorAction Stop
    }

    # 3. 处理冲突情况 (PersistTarget 已有数据，且 Source 也是冲突的真实数据)
    if ($sourceIsRealData) {
        $backup = "$Source.pre-persist-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warning "persist_external: '$Source' 与已有持久化数据冲突，原数据已自动备份至 '$backup'"
        Move-Item -LiteralPath $Source -Destination $backup -Force
        $sourceItem = $null
        $sourceIsRealData = $false
    }

    # 4. 彻底清理 Source 位置可能残留的失效/坏链接，确保创建新链接的前置路径完全空置
    if ($null -ne (Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue)) {
        Remove-ReparsePointSafe -Path $Source
    }

    # 5. 确保外域父级目录存在
    $sourceParent = Split-Path $Source -Parent
    if (-not (Test-Path -LiteralPath $sourceParent)) {
        New-Item -ItemType Directory -Path $sourceParent -Force | Out-Null
    }

    # 6. 建立链接 (按照 Scoop 官方规范使用 -Value 参数)
    $isDirTarget = $targetItem.PSIsContainer
    $linkType = if ($isDirTarget) { 'Junction' } else { 'SymbolicLink' }

    if ($isDirTarget) {
        New-Item -ItemType Junction -Path $Source -Value $PersistTarget -Force | Out-Null
    } else {
        New-Item -ItemType SymbolicLink -Path $Source -Value $PersistTarget -Force | Out-Null
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
            $linkType = New-ExternalPersistLink -Source $d.Source -PersistTarget $target
            $records += @{ Source = $d.Source; Target = $target; LinkType = $linkType }
        } catch {
            Write-Error "persist_external: 处理 '$($d.Source)' 失败: $_"
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
        $defs = Get-PersistExternalDefinition -Manifest $Manifest
        $records = $defs | ForEach-Object { @{ Source = $_.Source } }
    }

    foreach ($r in $records) {
        Remove-ReparsePointSafe -Path $r.Source
        Write-Verbose "persist_external: 已剥离外部链接 '$($r.Source)'"
    }
}
