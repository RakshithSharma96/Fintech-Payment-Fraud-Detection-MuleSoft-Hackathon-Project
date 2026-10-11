param([Parameter(ValueFromRemainingArguments=$true)][string[]]$MavenArgs)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$jdkDir = if ($env:FRAUD_JAVA_HOME) { $env:FRAUD_JAVA_HOME } else { 'C:\AnypointStudio\plugins\org.mule.tooling.jdk.win32.x86_64_1.4.1' }
$mavenCmd = if ($env:FRAUD_MAVEN_CMD) { $env:FRAUD_MAVEN_CMD } else { 'C:\Users\raksh\Desktop\Mulesoft-Payment Fraud Detection\tools\apache-maven-3.9.9\bin\mvn.cmd' }
if (!(Test-Path -LiteralPath "$jdkDir\bin\java.exe")) { throw 'Set FRAUD_JAVA_HOME to your Java 17 JDK.' }
if (!(Test-Path -LiteralPath $mavenCmd)) { throw 'Set FRAUD_MAVEN_CMD to mvn.cmd.' }
$env:JAVA_HOME = $jdkDir
$env:PATH = "$jdkDir\bin;" + $env:PATH
if (Test-Path -LiteralPath "$projectRoot\.local\secure.key") {
    $env:FRAUD_SECURE_KEY = (Get-Content -LiteralPath "$projectRoot\.local\secure.key" -Raw).Trim()
}
Push-Location $projectRoot
try { & $mavenCmd @MavenArgs; $result = $LASTEXITCODE } finally { Pop-Location }
exit $result

