if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

# Paths for the schema file and its backup copy
$targetSchema = "$env:SCOOP_HOME\schema.json"
$backupSchema = "$env:SCOOP_HOME\schema.json.bak"

# Backup the existing schema if it exists
if (Test-Path $targetSchema) {
    Copy-Item $targetSchema $backupSchema -Force
}

try {
    # Install the local schema for bucket tests and run them
    Copy-Item "$PSScriptRoot\schema.json" $targetSchema -Force
    . "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
} finally {
    # Restore the original schema after tests complete
    if (Test-Path $backupSchema) {
        Copy-Item $backupSchema $targetSchema -Force
        Remove-Item $backupSchema -Force
    }
}
