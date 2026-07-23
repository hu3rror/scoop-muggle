<#
    persist-external.ps1  (v2)
    ---------------------------
    Scoop `persist_external` 字段的核心实现草稿。
    职责：把安装目录($dir)之外的数据目录/文件（如 %AppData%\Code）
    通过 Junction/Symlink 链接到 $persist_dir，实现跨 $dir 外的实时持久化。

    与原生 `persist` 字段并存、互不覆盖：`persist` 继续由 Scoop 核心处理
    $dir 内部数据，本文件只处理 $dir 之外的部分。

    v2 相对 v1 的变化：
      1. 安装时把实际创建的 (Source, Target, LinkType) 记录落盘到
         "$dir\.scoop-persist-external.json"；卸载时优先读这个记录文件，
         而不是重新解析 manifest 的 persist_external 字段——避免版本升级
         导致字段路径变化时，卸载逻辑对不上当初真实创建的链接。
      2. 明确"断链接"与"覆盖疑似真实数据"两种删除场景的边界：
         - 断链接（已用 LinkType 确认是链接）→ Remove-Item -Force 即可，
           删的只是 reparse point，不影响 persist_dir 里的真实数据。
         - 安装时发现外域路径有未迁移的真实数据 → 改名备份而不是直接删除
           或丢回收站，效果等价但不依赖 COM/Shell.Application。

    注意：本文件未在真实 Windows/Scoop 环境中执行测试（当前沙盒为 Linux，
    无 pwsh 可用），仅完成逻辑设计与静态审查，供讨论与后续在真实环境验证。

    对外入口（供 post_install / pre_uninstall 调用）：
      - Invoke-PersistExternalInstall
      - Invoke-PersistExternalUninstall
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# 1. 路径解析：只允许受控的变量形式，避免任意代码执行风险
# ---------------------------------------------------------------------------
function Convert-ExternalPath {
    <#
        将 manifest 中写的路径字符串展开为绝对路径。
        支持: $env:VAR、%VAR%、$home、~
        刻意不使用 Invoke-Expression / ExpandString，避免 manifest 里
        被注入任意表达式（区别于 abyss 的 A-Resolve-SpecialPath，那边
        因为 manifest 本身已是受信任的 pre_install/post_install 执行环境，
        所以直接用 ExpandString 是合理的；这里作为独立字段单独保守处理，
        具体取哪种策略可以再讨论）。
    #>
    param(
        [Parameter(Mandatory)][string]$RawPath
    )

    $p = $RawPath.Trim()

    # $home / ~
    $p = $p -replace '^\$home', [regex]::Escape($HOME) -replace '^~', [regex]::Escape($HOME)

    # $env:VAR 形式
    $p = [regex]::Replace($p, '\$env:(\w+)', {
        param($m)
        $val = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
        if ($null -eq $val) {
            throw "persist_external: 未知环境变量 `$env:$($m.Groups[1].Value)`（来源路径: $RawPath）"
        }
        $val
    })

    # %VAR% 形式
    $p = [regex]::Replace($p, '%(\w+)%', {
        param($m)
        $val = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
        if ($null -eq $val) {
            throw "persist_external: 未知环境变量 %$($m.Groups[1].Value)%（来源路径: $RawPath）"
        }
        $val
    })

    return [System.IO.Path]::GetFullPath($p)
}

# ---------------------------------------------------------------------------
# 2. 解析 manifest 的 persist_external 字段，归一化为 [Source, TargetName] 对
# ---------------------------------------------------------------------------
function Get-PersistExternalDefinition {
    <#
        输入 manifest.persist_external（可能是字符串/数组/二元数组混合），
        输出统一的对象数组： @{ Source = <展开后的绝对路径>; TargetName = <persist_dir 下子目录名> }
    #>
    param(
        [Parameter(Mandatory)]$Manifest
    )

    $raw = $Manifest.persist_external
    if (-not $raw) { return @() }
    if ($raw -isnot [array]) { $raw = @($raw) }

    $result = @()
    foreach ($item in $raw) {
        if ($item -is [array]) {
            # ["$env:LocalAppData\Code-Logs", "custom-logs-dir"]
            $sourceRaw = $item[0]
            $targetName = $item[1]
        } else {
            $sourceRaw = $item
            $targetName = $null
        }

        $source = Convert-ExternalPath -RawPath $sourceRaw
        if (-not $targetName) {
            # 默认用来源路径的叶子名。不同 app 各自的 persist_dir 天然隔离，
            # 同一个 app 内部若有多个来源叶子名重复，建议手动指定 TargetName。
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
# 3. 能力检测：是否可以创建 Symlink（文件级链接需要）
# ---------------------------------------------------------------------------
function Test-CanCreateSymlink {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) { return $true }

    # Win10 1703+ 开发者模式开启后，非管理员也可以创建 symlink
    try {
        $devMode = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
            -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop
        return ($devMode -eq 1)
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# 4. 安装记录文件：落盘实际创建的链接，供卸载时精确回溯
# ---------------------------------------------------------------------------
function Get-ExternalLinkRecordPath {
    param([Parameter(Mandatory)][string]$Dir)
    Join-Path $Dir '.scoop-persist-external.json'
}

function Save-ExternalLinkRecord {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][array]$Records  # @(@{Source=...; Target=...; LinkType=...}, ...)
    )
    $path = Get-ExternalLinkRecordPath -Dir $Dir
    $Records | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Force -Encoding utf8
}

function Read-ExternalLinkRecord {
    param([Parameter(Mandatory)][string]$Dir)
    $path = Get-ExternalLinkRecordPath -Dir $Dir
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $content = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($content -isnot [array]) { $content = @($content) }
        return $content
    } catch {
        Write-Warning "persist_external: 读取链接记录 '$path' 失败，将回退到重新解析 manifest：$_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 5. 建立单个链接：含旧数据迁移与冲突处理
# ---------------------------------------------------------------------------
function New-ExternalPersistLink {
    param(
        [Parameter(Mandatory)][string]$Source,       # 外域原始路径，如 %AppData%\Code
        [Parameter(Mandatory)][string]$PersistTarget  # $persist_dir\TargetName
    )

    $sourceExists = Test-Path $Source
    $targetExists = Test-Path $PersistTarget

    # 情况 A：source 已经是指向 target 的链接 —— 幂等，直接跳过
    if ($sourceExists) {
        $item = Get-Item $Source -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -and $item.Target -eq $PersistTarget) {
            Write-Verbose "persist_external: '$Source' 已链接到 '$PersistTarget'，跳过"
            return (Get-Item $Source -Force).LinkType
        }
    }

    # 情况 B：persist_dir 里没有数据
    if (-not $targetExists) {
        $targetParent = Split-Path $PersistTarget -Parent
        if (-not (Test-Path $targetParent)) { New-Item -ItemType Directory -Path $targetParent -Force | Out-Null }

        if ($sourceExists) {
            # 外域有数据 —— 迁移进 persist_dir
            Move-Item -Path $Source -Destination $PersistTarget -Force
        } else {
            # 两边都没有 —— 新建空目录占位
            New-Item -ItemType Directory -Path $PersistTarget -Force | Out-Null
        }
    }
    # 情况 C：persist_dir 已有数据，且外域也有未迁移的真实数据（非链接）—— 冲突
    elseif ($sourceExists -and -not (Get-Item $Source -Force).LinkType) {
        # 不做自动合并（高风险），改名备份，不直接删除、也不需要回收站：
        # rename 是原子操作，不依赖 Shell.Application COM，在非交互式会话
        # （例如 CI、计划任务）下同样可靠。
        $backup = "$Source.pre-persist-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warning "persist_external: '$Source' 与已存在的持久化数据冲突，原数据已备份到 '$backup'，未自动合并，请手动检查"
        Move-Item -Path $Source -Destination $backup -Force
    }

    # 清理 source 位置（此时应已不存在真实数据，只可能残留一个失效链接）
    if (Test-Path $Source) {
        $item = Get-Item $Source -Force
        if ($item.LinkType) {
            # 确认是链接才删除：删的是 reparse point 本身，不触碰 persist_dir 里的真实数据，
            # 因此直接 Remove-Item -Force 即可，无需回收站兜底。
            Remove-Item $Source -Force
        }
    }

    # 建立链接：目录用 Junction（免权限），文件用 SymbolicLink（需权限/开发者模式）
    $isDirTarget = (Get-Item $PersistTarget -Force).PSIsContainer
    $linkType = if ($isDirTarget) { 'Junction' } else { 'SymbolicLink' }

    if ($isDirTarget) {
        New-Item -ItemType Junction -Path $Source -Target $PersistTarget -Force | Out-Null
    } else {
        if (-not (Test-CanCreateSymlink)) {
            throw "persist_external: 创建文件级符号链接需要管理员权限或已开启开发者模式（目标: $Source）"
        }
        New-Item -ItemType SymbolicLink -Path $Source -Target $PersistTarget -Force | Out-Null
    }

    return $linkType
}

# ---------------------------------------------------------------------------
# 6. 安全断开链接（卸载用）：仅删除确认是链接的 source，绝不误删真实数据
# ---------------------------------------------------------------------------
function Remove-ExternalPersistLink {
    param(
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path $Source)) { return }

    $item = Get-Item $Source -Force
    if ($item.LinkType) {
        # 已确认是 Junction/SymbolicLink，删的是 reparse point 本身，
        # persist_dir 里的真实数据不受影响，直接 Force 删除即可。
        Remove-Item $Source -Force
        Write-Verbose "persist_external: 已断开链接 '$Source'（持久化数据仍保留在 persist_dir 中）"
    } else {
        # 不是链接：可能是链接损坏后用户手动放回的真实数据，绝不删除，只警告。
        Write-Warning "persist_external: '$Source' 不是预期的链接，跳过删除以避免误删真实数据，请手动检查"
    }
}

# ---------------------------------------------------------------------------
# 对外入口
# ---------------------------------------------------------------------------
function Invoke-PersistExternalInstall {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$PersistDir,
        [Parameter(Mandatory)][string]$Dir  # 当前版本安装目录，用于落盘链接记录
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
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Dir
    )

    # 优先使用安装时落盘的记录，避免因 manifest 版本间字段变化导致
    # 卸载逻辑和实际创建的链接对不上。
    $records = Read-ExternalLinkRecord -Dir $Dir

    if ($null -eq $records) {
        # 记录文件不存在（例如该功能在某次更新后才引入，旧版本没有记录）
        # 或读取失败 —— 回退到重新解析 manifest，尽力而为。
        Write-Warning "persist_external: 未找到安装时链接记录，回退为重新解析 manifest.persist_external"
        $defs = Get-PersistExternalDefinition -Manifest $Manifest
        $records = $defs | ForEach-Object { @{ Source = $_.Source } }
    }

    foreach ($r in $records) {
        Remove-ExternalPersistLink -Source $r.Source
    }
}
