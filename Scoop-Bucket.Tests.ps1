if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

$targetSchema = "$env:SCOOP_HOME\schema.json"
& "$PSScriptRoot\scripts\sync-schema.ps1" -TargetPath "$targetSchema"

# Import-Bucket-Tests.ps1 在 $env:CI 下用 Get-GitChangedFile 收集“变更的 JSON”做 schema 校验，但该函数
# 的 -Path 只定位 repo root、不做路径过滤，会把根目录的非 manifest JSON（如 .vscode/settings.json）误伤。
# 本仓库根级本就存在非 manifest JSON，故清掉 CI 标志强制全量校验 bucket/*.json（~4s，与本地行为一致）。
Remove-Item Env:\CI -ErrorAction SilentlyContinue

. "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
