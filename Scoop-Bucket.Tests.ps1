if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

$targetSchema = "$env:SCOOP_HOME\schema.json"

# scoop core 是 git 工作区：官方 Import-Bucket-Tests.ps1 硬编码校验器读取 $env:SCOOP_HOME\schema.json，
# sync-schema.ps1 写入的注入版若留存会让 `scoop update` 因 "Uncommitted changes" 中止。
$injectedLeftover = if (Test-Path -LiteralPath $targetSchema) { [System.IO.File]::ReadAllText($targetSchema) } else { $null }
if ($injectedLeftover -and $injectedLeftover.Contains('persist_external')) {
    & git -C "$env:SCOOP_HOME" checkout -- schema.json 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host 'schema.json: restored leftover injected schema in scoop core' }
}

$global:MuggleSchemaRestore = [pscustomobject]@{
    Target  = $targetSchema
    Backup  = Join-Path $env:TEMP ("muggle-schema-backup-" + [guid]::NewGuid().ToString('N') + '.json')
    HadFile = (Test-Path -LiteralPath $targetSchema)
    Active  = $true
}
if ($global:MuggleSchemaRestore.HadFile) {
    Copy-Item -LiteralPath $targetSchema -Destination $global:MuggleSchemaRestore.Backup -Force
}

& "$PSScriptRoot\scripts\sync-schema.ps1" -TargetPath $targetSchema

# Import-Bucket-Tests.ps1 在 $env:CI 下用 Get-GitChangedFile 收集“变更的 JSON”做 schema 校验，但该函数
# 的 -Path 只定位 repo root、不做路径过滤，会把根目录的非 manifest JSON（如 .vscode/settings.json）误伤。
# 本仓库根级本就存在非 manifest JSON，故清掉 CI 标志强制全量校验 bucket/*.json（~4s，与本地行为一致）。
Remove-Item Env:\CI -ErrorAction SilentlyContinue

# 点源官方 Import-Bucket-Tests.ps1 包在外层 Describe 里：AfterAll 在块内所有测试（含其自身）结束后执行，
# 此时还原 schema.json 才安全；放在文件顶层会在 Discovery 阶段就执行、Pester Run 前把注入版恢复掉。
Describe 'Scoop-Bucket.Tests (wrapper)' {
    . "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"

    AfterAll {
        $restore = $global:MuggleSchemaRestore
        if (-not $restore -or -not $restore.Active) { return }
        try {
            if ($restore.HadFile) {
                Copy-Item -LiteralPath $restore.Backup -Destination $restore.Target -Force
            } elseif (Test-Path -LiteralPath $restore.Target) {
                Remove-Item -LiteralPath $restore.Target -Force
            }
        } catch {
            Write-Warning "schema.json restore failed: $($_.Exception.Message)"
        } finally {
            if ($restore.HadFile) {
                Remove-Item -LiteralPath $restore.Backup -Force -ErrorAction SilentlyContinue
            }
            $restore.Active = $false
        }
    }
}
