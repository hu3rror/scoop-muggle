if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

$sourceSchema = "$PSScriptRoot\schema.json"
if (-not (Test-Path $sourceSchema)) {
    throw "Custom schema.json not found at '$sourceSchema'!"
}

$targetSchema = "$env:SCOOP_HOME\schema.json"
Copy-Item $sourceSchema $targetSchema -Force

. "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
