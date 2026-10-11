param([string]$SecureToolJar = 'C:\Users\raksh\Desktop\Mulesoft-Payment Fraud Detection\tools\secure-properties-tool.jar')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$jdkDir = if ($env:FRAUD_JAVA_HOME) { $env:FRAUD_JAVA_HOME } else { 'C:\AnypointStudio\plugins\org.mule.tooling.jdk.win32.x86_64_1.4.1' }
if (!(Test-Path -LiteralPath $SecureToolJar)) { throw 'Pass -SecureToolJar with the official MuleSoft Secure Properties Tool JAR.' }
$localDir = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
if (Test-Path -LiteralPath "$localDir\secure.key") { throw 'Local secrets already exist. Preserve them, or move them aside to rotate.' }
function New-Secret {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes)
}
$key = New-Secret
$dbPassword = New-Secret
$rootPassword = New-Secret
$encryptedPath = Join-Path $projectRoot 'src\main\resources\secure-dev.yaml'
$encryptedValue = & "$jdkDir\bin\java.exe" -cp $SecureToolJar com.mulesoft.tools.SecurePropertiesTool string encrypt AES CBC $key $dbPassword
    if ($LASTEXITCODE -ne 0) { throw 'Secure Properties encryption failed.' }
    $ciphertext = ($encryptedValue | Select-Object -Last 1).Trim()
    "db:`n  password: '![${ciphertext}]'" | Set-Content -LiteralPath $encryptedPath -Encoding utf8NoBOM
    $key | Set-Content -LiteralPath "$localDir\secure.key" -Encoding ascii
    "MYSQL_ROOT_PASSWORD=$rootPassword`nMYSQL_PASSWORD=$dbPassword" | Set-Content -LiteralPath "$projectRoot\.env" -Encoding ascii
Write-Host 'Created ignored local key, encrypted properties and Docker environment. No secrets were printed.'

