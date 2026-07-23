<#
    persist-external.ps1
    --------------------
    Scoop 'persist_external' core implementation.
    Links external paths (outside $dir, e.g. %AppData%\Code) to $persist_dir
    via Junction/Symlink for real-time persistence.

    Public entry points:
      - Invoke-PersistExternalInstall
      - Invoke-PersistExternalUninstall
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# 0. Compatibility layer: prefer Scoop native warn/error functions;
#    fallback to Write-Warning/Error if running standalone.
# ---------------------------------------------------------------------------
if (-not (Get-Command 'warn' -ErrorAction SilentlyContinue)) {
    function warn($msg) { Write-Warning $msg }
}
if (-not (Get-Command 'error' -ErrorAction SilentlyContinue)) {
    function error($msg) { Write-Error $msg }
}

# Normalize path trailing separators (preserve root paths like "C:\")
function ConvertTo-TrimmedPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path.Length -gt 3) { return $Path.TrimEnd('\', '/') }
    return $Path
}

# ---------------------------------------------------------------------------
# 1. Path resolution: expand $env:VAR / %VAR% / $home / ~
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

    # Expand $env:VAR format
    $p = [regex]::Replace($p, '\$env:(?<name>[\w()]+)', {
            param($m)
            $varName = $m.Groups['name'].Value
            $val = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($val)) {
                throw "persist_external: Unknown environment variable `$env:$($varName) (Source path: $RawPath)"
            }
            $val
        }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # Expand %VAR% format
    $p = [regex]::Replace($p, '%(?<name>[\w()]+)%', {
            param($m)
            $varName = $m.Groups['name'].Value
            $val = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($val)) {
                throw "persist_external: Unknown environment variable %$varName% (Source path: $RawPath)"
            }
            $val
        }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # Verify absolute path
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        throw "persist_external: Path '$RawPath' expanded to non-absolute path '$p'. Please use `$env:, `$home, or %VAR% prefix."
    }

    return [System.IO.Path]::GetFullPath($p)
}

# ---------------------------------------------------------------------------
# 2. Parse Manifest definitions
#    Supports [source, target] or [source, target, 'file'|'directory']
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
                    default { throw "persist_external: Unknown type hint '$($item[2])', must be 'file' or 'directory'" }
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

# Resolve item type when creating placeholders
function Resolve-ExternalItemType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [string]$TypeHint
    )

    if ($TypeHint) { return $TypeHint }

    $leaf = Split-Path $Source -Leaf
    $ext = [System.IO.Path]::GetExtension($leaf)

    if ($leaf.StartsWith('.') -and $leaf -eq $ext) {
        throw "persist_external: Cannot infer item type for '$leaf'. Please specify explicit type hint in manifest, e.g. ['$Source', '$leaf', 'file']"
    }

    if ($ext) { return 'File' }
    return 'Directory'
}

# Check symlink privilege
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
# 3. Persistence record (.scoop-persist-external.json)
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
        warn "persist_external: Failed to read link record '$path', falling back to manifest parsing: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 4. Safe link removal
# ---------------------------------------------------------------------------
function Remove-ReparsePointSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $CleanPath = ConvertTo-TrimmedPath -Path $Path
    $item = Get-Item -LiteralPath $CleanPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }

    if (-not $item.LinkType) { return $false }

    if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
        $item.Attributes = $item.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
    }

    if ($item.PSIsContainer) {
        [System.IO.Directory]::Delete($CleanPath)
    } else {
        [System.IO.File]::Delete($CleanPath)
    }
    return $true
}

# ---------------------------------------------------------------------------
# 5. Core linking logic
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

    # 1. Idempotency check
    if ($sourceIsLink) {
        $currentTarget = @($sourceItem.Target)[0]
        if ($currentTarget) {
            $normCurrent = [System.IO.Path]::GetFullPath(($currentTarget -replace '^\\\\\?\\', ''))
            $normPersist = [System.IO.Path]::GetFullPath($PersistTarget)
            if ($normCurrent -eq $normPersist -and ($null -ne $targetItem)) {
                Write-Verbose "persist_external: '$Source' is already linked to '$PersistTarget'"
                return $sourceItem.LinkType
            }
        }
    }

    # 2. Target does not exist
    if ($null -eq $targetItem) {
        $targetParent = Split-Path $PersistTarget -Parent
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }

        if ($sourceIsRealData) {
            Move-Item -LiteralPath $Source -Destination $PersistTarget -Force
            $sourceItem = $null
            $sourceIsRealData = $false
        } else {
            if ($sourceIsLink) {
                Remove-ReparsePointSafe -Path $Source | Out-Null
                $sourceItem = $null
                $sourceIsLink = $false
            }
            $itemType = Resolve-ExternalItemType -Source $Source -TypeHint $TypeHint
            if ($itemType -eq 'File') {
                New-Item -ItemType File -Path $PersistTarget -Force | Out-Null
            } else {
                New-Item -ItemType Directory -Path $PersistTarget -Force | Out-Null
            }
        }
        $targetItem = Get-Item -LiteralPath $PersistTarget -Force -ErrorAction Stop
    }

    # 3. Handle conflict
    if ($sourceIsRealData) {
        $backup = "$Source.pre-persist-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        warn "persist_external: '$Source' conflicts with existing persist data, backed up to '$backup'"
        Move-Item -LiteralPath $Source -Destination $backup -Force
        $sourceItem = $null
        $sourceIsRealData = $false
    }

    # 4. Clean dangling/old links
    if ($null -ne (Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue)) {
        Remove-ReparsePointSafe -Path $Source | Out-Null
    }

    # 5. Ensure parent directory exists
    $sourceParent = Split-Path $Source -Parent
    if (-not (Test-Path -LiteralPath $sourceParent)) {
        New-Item -ItemType Directory -Path $sourceParent -Force | Out-Null
    }

    # 6. Create link
    $isDirTarget = $targetItem.PSIsContainer
    $linkType = if ($isDirTarget) { 'Junction' } else { 'SymbolicLink' }

    if ($isDirTarget) {
        New-Item -ItemType Junction -Path $Source -Target $PersistTarget -Force | Out-Null
    } else {
        if (-not (Test-CanCreateSymlink)) {
            throw "persist_external: Symlink creation requires Administrator privilege or Developer Mode (Target: $Source)"
        }
        New-Item -ItemType SymbolicLink -Path $Source -Target $PersistTarget -Force | Out-Null
    }

    return $linkType
}

# ---------------------------------------------------------------------------
# 6. Public entry points
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
            error "persist_external: Failed to process '$($d.Source)': $_"
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
        warn "persist_external: Link record not found, falling back to manifest parsing"
        $defs = Get-PersistExternalDefinition -Manifest $Manifest
        $records = $defs | ForEach-Object { @{ Source = $_.Source } }
    }

    foreach ($r in $records) {
        $removed = Remove-ReparsePointSafe -Path $r.Source
        if ($removed) {
            Write-Verbose "persist_external: Removed external link '$($r.Source)'"
        } elseif ($null -ne (Get-Item -LiteralPath $r.Source -Force -ErrorAction SilentlyContinue)) {
            warn "persist_external: '$($r.Source)' is not expected link, skipped to protect real data"
        }
    }
}
