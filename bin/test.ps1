#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'BuildHelpers'; ModuleVersion = '2.0.1' }
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

$pesterConfig = New-PesterConfiguration -Hashtable @{
    Run    = @{
        Path     = "$PSScriptRoot/.."
        PassThru = $true
    }
    Output = @{
        Verbosity = 'Detailed'
    }
}

if ($pesterConfig.Run.PSObject.Properties['FailOnNullOrEmptyForEach']) {
    $pesterConfig.Run.FailOnNullOrEmptyForEach = $false
}

$result = Invoke-Pester -Configuration $pesterConfig
exit $result.FailedCount
