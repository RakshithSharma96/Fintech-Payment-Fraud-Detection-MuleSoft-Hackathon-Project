param([string]$SecureToolJar = 'C:\Users\raksh\Desktop\Mulesoft-Payment Fraud Detection\tools\secure-properties-tool.jar', [switch]$UpdateDatabasePassword)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$jdkDir = if ($env:FRAUD_JAVA_HOME) { $env:FRAUD_JAVA_HOME } else { 'C:\AnypointStudio\plugins\org.mule.tooling.jdk.win32.x86_64_1.4.1' }
if (!(Test-Path -LiteralPath $SecureToolJar)) { throw 'Pass -SecureToolJar with the official MuleSoft Secure Properties Tool JAR.' }
$localDir = Join-Path $projectRoot '.local'
if ($UpdateDatabasePassword -and !(Test-Path -LiteralPath "$localDir\secure.key" -PathType Leaf)) { throw 'Existing local key is required to update the database password.' }
if ((Test-Path -LiteralPath "$localDir\secure.key") -and !$UpdateDatabasePassword) { throw 'Local secrets already exist. Use -UpdateDatabasePassword to preserve the existing key.' }
function New-Secret {
    $bytes = New-Object byte[] 24
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    return [Convert]::ToBase64String($bytes)
}
function Publish-EncryptedProperties {
    param([string]$TemporaryPath, [string]$DestinationPath)
    $backupPath = "$DestinationPath.$([guid]::NewGuid().ToString('N')).bak"
    $backedUp = $false
    $published = $false
    try {
        if ([IO.File]::Exists($DestinationPath)) {
            [IO.File]::Move($DestinationPath, $backupPath)
            $backedUp = $true
        }
        [IO.File]::Move($TemporaryPath, $DestinationPath)
        $published = $true
    } catch {
        if ($backedUp) {
            try { [IO.File]::Move($backupPath, $DestinationPath) }
            catch { throw 'Encrypted properties rollback failed. Preserve the adjacent .bak file for recovery.' }
        }
        throw 'Encrypted properties replacement failed; any original file was preserved.'
    } finally {
        # Retain the backup if rollback fails; never overwrite a concurrent destination.
        if ([IO.File]::Exists($TemporaryPath)) { [IO.File]::Delete($TemporaryPath) }
        if ($published -and $backedUp) { [IO.File]::Delete($backupPath) }
    }
}
$key = if ($UpdateDatabasePassword) { [IO.File]::ReadAllText("$localDir\secure.key").Trim() } else { New-Secret }
if ([string]::IsNullOrWhiteSpace($key)) { throw 'Local encryption key must not be empty.' }
$dbSecret = Read-Host 'Password of the native Windows MySQL fraud_app user' -AsSecureString
$dbPassword = [System.Net.NetworkCredential]::new('', $dbSecret).Password
if ([string]::IsNullOrEmpty($dbPassword)) { throw 'Database password must not be empty.' }
$encryptedPath = Join-Path $projectRoot 'src\main\resources\secure-dev.yaml'
$temporaryPath = "$encryptedPath.$([guid]::NewGuid().ToString('N')).tmp"
$keyTemporaryPath = $null
try {
    try {
        $encryptedValue = & "$jdkDir\bin\java.exe" -cp $SecureToolJar com.mulesoft.tools.SecurePropertiesTool string encrypt AES CBC $key $dbPassword 2>&1
    } catch { throw 'Secure Properties encryption failed.' }
    if ($LASTEXITCODE -ne 0) { throw 'Secure Properties encryption failed.' }
    $outputLines = @($encryptedValue | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($outputLines.Count -ne 1) { throw 'Secure Properties encryption returned unexpected output.' }
    $ciphertext = $outputLines[0]
    try { $cipherBytes = [Convert]::FromBase64String($ciphertext) }
    catch { throw 'Secure Properties encryption returned invalid ciphertext.' }
    if ($cipherBytes.Length -lt 16 -or $cipherBytes.Length % 16 -ne 0 -or [Convert]::ToBase64String($cipherBytes) -cne $ciphertext) {
        throw 'Secure Properties encryption returned invalid ciphertext.'
    }
    [IO.File]::WriteAllText($temporaryPath, "db:`n  password: '![${ciphertext}]'`n", [Text.UTF8Encoding]::new($false))
    if (!$UpdateDatabasePassword) {
        New-Item -ItemType Directory -Force -Path $localDir | Out-Null
        $keyTemporaryPath = "$localDir\secure.key.$([guid]::NewGuid().ToString('N')).tmp"
        $key | Set-Content -LiteralPath $keyTemporaryPath -Encoding ascii
        # Publish the complete key first; Move refuses to overwrite a concurrent key.
        [IO.File]::Move($keyTemporaryPath, "$localDir\secure.key")
    }
    Publish-EncryptedProperties -TemporaryPath $temporaryPath -DestinationPath $encryptedPath
} finally {
    $dbPassword = $null
    $key = $null
    $ciphertext = $null
    $cleanupFailed = $false
    foreach ($path in @($temporaryPath, $keyTemporaryPath)) {
        if ($path) {
            try {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
            }
            catch { $cleanupFailed = $true }
        }
    }
    if ($cleanupFailed) { throw 'Temporary setup file cleanup failed. Remove the setup .tmp files before retrying.' }
}
Write-Host 'Updated encrypted native MySQL properties. No secrets were printed or environment files created.'

