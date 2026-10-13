# Run only extracted helpers against disposable fixtures, never the setup script.
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot 'setup-local.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Setup script contains PowerShell syntax errors.' }
foreach ($name in @('Publish-EncryptedProperties', 'New-Secret')) {
    $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (!$functionAst) { throw 'Required setup helper is missing.' }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw $Message }
}
function Assert-NoTemporaryFiles {
    Assert-True (@(Get-ChildItem -LiteralPath $fixtureDir -Filter '*.bak').Count -eq 0) 'Backup file was not cleaned up.'
    Assert-True (![IO.File]::Exists($stagedPath)) 'Staged file was not cleaned up.'
}
$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ('setup-local-test-' + [guid]::NewGuid().ToString('N'))
$destinationPath = Join-Path $fixtureDir 'fixture.yaml'
$stagedPath = Join-Path $fixtureDir 'fixture.tmp'
$utf8 = [Text.UTF8Encoding]::new($false)
$lock = $null
try {
    [IO.Directory]::CreateDirectory($fixtureDir) | Out-Null
    [IO.File]::WriteAllText($destinationPath, 'original fixture', $utf8)
    [IO.File]::WriteAllText($stagedPath, 'replacement fixture', $utf8)
    Publish-EncryptedProperties $stagedPath $destinationPath
    Assert-True ([IO.File]::ReadAllText($destinationPath) -ceq 'replacement fixture') 'Existing-file replacement failed.'
    Assert-NoTemporaryFiles
    Write-Host 'PASS existing-file replacement'

    [IO.File]::Delete($destinationPath)
    [IO.File]::WriteAllText($stagedPath, 'fresh fixture', $utf8)
    Publish-EncryptedProperties $stagedPath $destinationPath
    Assert-True ([IO.File]::ReadAllText($destinationPath) -ceq 'fresh fixture') 'Fresh-file publication failed.'
    Assert-NoTemporaryFiles
    Write-Host 'PASS fresh-file publication'

    # A missing staged file forces failure AFTER the original has moved to backup.
    $originalBytes = [IO.File]::ReadAllBytes($destinationPath)
    $failed = $false
    try { Publish-EncryptedProperties $stagedPath $destinationPath }
    catch { $failed = $_.Exception.Message -eq 'Encrypted properties replacement failed; any original file was preserved.' }
    Assert-True $failed 'Expected replacement failure was not reported.'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($destinationPath)) -ceq [Convert]::ToBase64String($originalBytes)) 'Rollback did not restore original bytes.'
    Assert-NoTemporaryFiles
    Write-Host 'PASS replacement failure and byte-for-byte rollback'

    [IO.File]::WriteAllText($stagedPath, 'blocked replacement fixture', $utf8)
    $lock = [IO.File]::Open($destinationPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $failed = $false
    try { Publish-EncryptedProperties $stagedPath $destinationPath }
    catch { $failed = $_.Exception.Message -eq 'Encrypted properties replacement failed; any original file was preserved.' }
    finally { $lock.Dispose(); $lock = $null }
    Assert-True $failed 'Expected locked-destination failure was not reported.'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($destinationPath)) -ceq [Convert]::ToBase64String($originalBytes)) 'Locked destination was changed.'
    Assert-NoTemporaryFiles
    Write-Host 'PASS locked-destination preservation and staged-file cleanup'

    $ciphertext = 'synthetic fixture'
    $temporaryPath = $stagedPath
    $writeAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Extent.Text.StartsWith('[IO.File]::WriteAllText(') }, $true)
    Assert-True ($null -ne $writeAst) 'UTF-8 write operation is missing.'
    & ([scriptblock]::Create($writeAst.Extent.Text))
    $bytes = [IO.File]::ReadAllBytes($stagedPath)
    Assert-True ($bytes[0] -eq 100 -and $bytes[1] -eq 98 -and $bytes[2] -eq 58) 'YAML must start with db: without a UTF-8 BOM.'
    Assert-True ([IO.File]::ReadAllText($stagedPath) -ceq "db:`n  password: '![synthetic fixture]'`n") 'YAML property format changed.'
    Assert-True ([Convert]::FromBase64String((New-Secret)).Length -eq 24) 'Compatible key generator returned the wrong length.'
    Write-Host 'PASS UTF-8 YAML format and compatible key generator'
    Write-Host ('5 tests passed; PowerShell ' + $PSVersionTable.PSVersion)
} finally {
    if ($lock) { $lock.Dispose() }
    # Nonrecursive cleanup only within this exact, newly created fixture directory.
    if ([IO.Directory]::Exists($fixtureDir)) {
        foreach ($file in [IO.Directory]::GetFiles($fixtureDir)) { [IO.File]::Delete($file) }
        [IO.Directory]::Delete($fixtureDir)
    }
}
