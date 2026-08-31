if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

$targetSchema = "$env:SCOOP_HOME\schema.json"
& "$PSScriptRoot\scripts\sync-schema.ps1" -TargetPath "$targetSchema"

. "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
