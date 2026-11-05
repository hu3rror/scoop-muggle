# Facts are resolved at discovery time and handed to each It as plain values:
# Pester 5 does not expose file-scope variables inside It bodies.
#
# References that depend on the installing bucket ($app, $_, the $bucketsdir
# glob) are skipped: their target is not in this repo.

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptsRoot = Join-Path $repoRoot 'scripts'
$hookKeys = 'pre_install', 'post_install', 'pre_uninstall', 'post_uninstall'
$scriptKeys = 'installer', 'uninstaller'

$manifestFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'bucket') -Filter '*.json')
$referenceCases = @()
$seen = [System.Collections.Generic.HashSet[string]]::new()

foreach ($file in $manifestFiles) {
    $manifest = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
    $texts = @()
    foreach ($key in $hookKeys) {
        $texts += @($manifest.$key | Where-Object { $_ -is [string] })
    }
    foreach ($key in $scriptKeys) {
        $texts += @($manifest.$key.script | Where-Object { $_ -is [string] })
    }

    foreach ($text in $texts) {
        foreach ($match in [regex]::Matches($text, 'scripts[\\/]+(?<name>[A-Za-z0-9._-]+)')) {
            $reference = "scripts/" + $match.Groups['name'].Value
            if (-not $seen.Add("$($file.Name)|$reference")) { continue }
            $referenceCases += @{
                Name      = $file.Name
                Reference = $reference
                Exists    = Test-Path -LiteralPath (Join-Path $scriptsRoot $match.Groups['name'].Value)
            }
        }
    }
}

$coverageCases = @(@{ Manifests = $manifestFiles.Count; References = $referenceCases.Count })

Describe 'manifest script references' {

    It 'finds literal script references to check (<Manifests> manifests, <References> references)' -TestCases $coverageCases {
        param($Manifests, $References)
        $Manifests | Should -BeGreaterThan 0
        $References | Should -BeGreaterThan 0
    }

    It '<Name>: <Reference> exists in this bucket' -TestCases $referenceCases {
        param($Name, $Reference, $Exists)
        $Exists | Should -BeTrue
    }
}
