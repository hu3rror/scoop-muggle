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

# 2. Target path inside Scoop Core (where Scoop.Validator loads schema.json)
$targetSchema = "$env:SCOOP_HOME\schema.json"
$backupSchema = "$env:SCOOP_HOME\schema.json.bak"

# Backup existing Scoop Core schema.json
if (Test-Path $targetSchema) {
    Copy-Item $targetSchema $backupSchema -Force
}

try {
    # Copy custom schema.json to Scoop Core
    Copy-Item $sourceSchema $targetSchema -Force

    # Dot-source official test runner as per official Scoop specification
    . "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
} finally {
    # Restore original Scoop Core schema.json
    if (Test-Path $backupSchema) {
        Copy-Item $backupSchema $targetSchema -Force
        Remove-Item $backupSchema -Force
    }
}
