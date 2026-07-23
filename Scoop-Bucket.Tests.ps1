if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Resolve-Path (scoop prefix scoop) }

# Paths for the schema file and its backup copies
$targetSchema = "$env:SCOOP_HOME\schema.json"
$backupSchema = "$env:SCOOP_HOME\schema.json.bak"

$rootSchema = "$PSScriptRoot\..\schema.json"
$rootBackupSchema = "$PSScriptRoot\..\schema.json.bak"

# Backup existing schemas if they exist
if (Test-Path $targetSchema) {
    Copy-Item $targetSchema $backupSchema -Force
}
if (Test-Path $rootSchema) {
    Copy-Item $rootSchema $rootBackupSchema -Force
}

try {
    # Install local schema for bucket tests at both potential lookup locations
    Copy-Item "$PSScriptRoot\schema.json" $targetSchema -Force
    Copy-Item "$PSScriptRoot\schema.json" $rootSchema -Force

    # Use call operator (&) instead of dot-sourcing (.) to ensure script scopes match
    & "$env:SCOOP_HOME\test\Import-Bucket-Tests.ps1"
} finally {
    # Restore original schemas after tests complete
    if (Test-Path $backupSchema) {
        Copy-Item $backupSchema $targetSchema -Force
        Remove-Item $backupSchema -Force
    }
    if (Test-Path $rootBackupSchema) {
        Copy-Item $rootBackupSchema $rootSchema -Force
        Remove-Item $rootBackupSchema -Force
    } else {
        Remove-Item $rootSchema -Force -ErrorAction SilentlyContinue
    }
}
