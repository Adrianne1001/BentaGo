# Rebuilds every installable in dist\ from the current source.
#
#   powershell -ExecutionPolicy Bypass -File tool\release.ps1
#   ... -BumpBuild       increment the +N build number in pubspec.yaml first
#   ... -SkipTests       skip analyze and tests (not recommended)
#
# Produces:
#   dist\BentaGo-Setup-<version>.exe     Windows installer
#   dist\BentaGo-<version>-arm64.apk     Android, most phones
#   dist\BentaGo-<version>-arm32.apk     Android, older 32-bit phones
#   dist\BentaGo-<version>-universal.apk Android, works anywhere
#
# Refuses to ship if analyze or the tests fail -- a broken build in dist\ that
# looks current is worse than an obviously stale one.

param(
    [switch]$BumpBuild,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# --- toolchain ---------------------------------------------------------------
$flutterBin = 'C:\src\flutter\bin'
$jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'jdk-17*' } | Sort-Object Name -Descending | Select-Object -First 1
if (-not $jdk) { throw 'JDK 17 not found under C:\Program Files\Microsoft' }

$env:JAVA_HOME = $jdk.FullName
$env:ANDROID_HOME = 'C:\Android\sdk'
$env:Path = "$env:JAVA_HOME\bin;$env:Path;$flutterBin"

$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { throw "Inno Setup compiler not found at $iscc" }

function Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }

# --- version -----------------------------------------------------------------
$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw

if ($BumpBuild) {
    $pubspec = [regex]::Replace(
        $pubspec,
        '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
        { param($m) "version: $($m.Groups[1].Value)+$([int]$m.Groups[2].Value + 1)" }
    )
    Set-Content $pubspecPath -Value $pubspec -Encoding utf8 -NoNewline
}

if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'Could not read version from pubspec.yaml'
}
$version = $Matches[1]
$build = $Matches[2]
Write-Host "BentaGo $version (build $build)" -ForegroundColor Green

# --- gate --------------------------------------------------------------------
if (-not $SkipTests) {
    Step 'analyze'
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed - nothing built' }

    Step 'test'
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'tests failed - nothing built' }
}

# Clear old artifacts before anything is built, not after. Inno Setup writes
# straight into dist\, so clearing later deletes the installer just produced.
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
Get-ChildItem $dist -Filter 'BentaGo-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force

# Windows and Android are built one after the other on purpose: they share the
# build\ root, and running them together corrupted the Kotlin incremental cache.
Step 'windows'
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'windows build failed' }

Step 'installer'
& $iscc "/DMyAppVersion=$version" 'windows\installer\bentago.iss' | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { throw 'installer build failed' }

Step 'android'
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw 'split apk build failed' }
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'universal apk build failed' }

# --- stage -------------------------------------------------------------------
Step 'dist'
$apk = Join-Path $root 'build\app\outputs\flutter-apk'
Copy-Item "$apk\app-arm64-v8a-release.apk"   "$dist\BentaGo-$version-arm64.apk"     -Force
Copy-Item "$apk\app-armeabi-v7a-release.apk" "$dist\BentaGo-$version-arm32.apk"     -Force
Copy-Item "$apk\app-release.apk"             "$dist\BentaGo-$version-universal.apk" -Force

if (-not (Test-Path "$dist\BentaGo-Setup-$version.exe")) {
    throw "installer missing from dist - expected BentaGo-Setup-$version.exe"
}

# --- verify ------------------------------------------------------------------
Step 'signature'
$buildTools = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Directory |
    Sort-Object Name -Descending | Select-Object -First 1
& "$($buildTools.FullName)\apksigner.bat" verify --print-certs "$dist\BentaGo-$version-arm64.apk" 2>&1 |
    Select-String 'certificate DN' | ForEach-Object { $_.Line.Trim() }

Step 'done'
Get-ChildItem $dist -File | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize
Write-Host "Built from version $version+$build at $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Green
