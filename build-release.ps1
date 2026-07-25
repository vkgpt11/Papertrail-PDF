param(
    [ValidateSet("apk", "aab", "both")]
    [string]$Format = "apk"
)

$ErrorActionPreference = "Stop"
$projectDirectory = $PSScriptRoot
Set-Location -LiteralPath $projectDirectory

$defaultJavaHome = "C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot"
if (-not $env:JAVA_HOME -and (Test-Path -LiteralPath $defaultJavaHome)) {
    $env:JAVA_HOME = $defaultJavaHome
}

$versionLine = Select-String -LiteralPath "pubspec.yaml" -Pattern '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
if (-not $versionLine) {
    throw "Could not read version from pubspec.yaml. Expected: version: 1.2.3+4"
}

$versionName = $versionLine.Matches[0].Groups[1].Value
$buildNumber = $versionLine.Matches[0].Groups[2].Value
$releaseDirectory = Join-Path $projectDirectory "release"
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

flutter clean
if ($LASTEXITCODE -ne 0) { throw "flutter clean failed." }

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

if ($Format -in @("apk", "both")) {
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "APK build failed." }
    $apkName = "Papertrail-PDF-v$versionName-build$buildNumber.apk"
    $apkDestination = Join-Path $releaseDirectory $apkName
    Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-release.apk" -Destination $apkDestination -Force
    Write-Host "APK created: $apkDestination" -ForegroundColor Green
}

if ($Format -in @("aab", "both")) {
    flutter build appbundle --release
    if ($LASTEXITCODE -ne 0) { throw "App Bundle build failed." }
    $aabName = "Papertrail-PDF-v$versionName-build$buildNumber.aab"
    $aabDestination = Join-Path $releaseDirectory $aabName
    Copy-Item -LiteralPath "build\app\outputs\bundle\release\app-release.aab" -Destination $aabDestination -Force
    Write-Host "App Bundle created: $aabDestination" -ForegroundColor Green
}
