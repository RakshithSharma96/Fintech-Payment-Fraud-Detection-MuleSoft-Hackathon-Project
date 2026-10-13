# Separate regression groups, then full suite. Run from PowerShell 7.
param([ValidateSet('m1','m2','m3','combined')][string]$StartAt = 'm1')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $orderedGroups = @('m1','m2','m3','combined')
    foreach ($group in ($orderedGroups | Select-Object -Skip ([array]::IndexOf($orderedGroups,$StartAt)))) {
        $arguments = @('test')
        if ($group -ne 'combined') {
            $arguments += "-Dtest.milestone=$group"
        }
        $logPath = if ($group -eq 'combined') { '.local/m3-final-test.log' } else { ".local/m3-group-$group.log" }
        & ./scripts/maven.ps1 @arguments *> $logPath
        if ($LASTEXITCODE -ne 0) { throw "$group tests failed; inspect $logPath" }
        python ./scripts/capture-m3-group.py $group $logPath
        if ($LASTEXITCODE -ne 0) { throw "$group evidence validation failed" }
        Write-Host "$group results captured."
    }
    python ./scripts/export-test-evidence.py --milestone 3
    if ($LASTEXITCODE -ne 0) { throw 'Final evidence export failed' }
} finally { Pop-Location }
