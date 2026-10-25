param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$privateAssetDir = Join-Path $PSScriptRoot 'assets\private'
$historyAsset = Join-Path $privateAssetDir 'techem_heating_history.json'
$settingsAsset = Join-Path $privateAssetDir 'snuggletemp_settings.json'
$historySource = Join-Path $root 'techem_heating_history.json'
$settingsSource = Join-Path $root 'snuggletemp_settings.local.json'
$copiedHistory = $false
$copiedSettings = $false
New-Item -ItemType Directory -Force $privateAssetDir | Out-Null
try {
  if (Test-Path $historySource) {
    Copy-Item $historySource $historyAsset -Force
    $copiedHistory = $true
  }
  if (Test-Path $settingsSource) {
    Copy-Item $settingsSource $settingsAsset -Force
    $copiedSettings = $true
  }
  Push-Location $PSScriptRoot
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
  flutter build apk --debug --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
} finally {
  Pop-Location
  if ($copiedHistory) { Remove-Item $historyAsset -Force -ErrorAction SilentlyContinue }
  if ($copiedSettings) { Remove-Item $settingsAsset -Force -ErrorAction SilentlyContinue }
}
Write-Host "APK: $PSScriptRoot\build\app\outputs\flutter-apk\app-debug.apk"
