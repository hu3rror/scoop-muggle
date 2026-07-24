if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

# 1. Locate the custom schema.json in the repository
$sourceSchema = if (Test-Path "$PSScriptRoot\schema.json") {
    "$PSScriptRoot\schema.json"
} else {
    "$PSScriptRoot\..\schema.json"
}

if (-not (Test-Path $sourceSchema)) {
    throw "Custom schema.json not found at '$sourceSchema'!"
}

# 2. Target path inside Scoop Core where Scoop.Validator loads schema.json
$targetSchema = "$env:SCOOP_HOME\schema.json"

# Replace Scoop Core schema.json so it remains updated during Pester 5 execution phase
Copy-Item $sourceSchema $targetSchema -Force

# Dot-source official test runner
. "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
