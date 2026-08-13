# Locates the external tools the demo pipeline drives. Dot-sourced by the other
# scripts in this folder; not meant to be run on its own.
#
# Everything is resolved to an absolute path rather than trusted to be on PATH:
# winget's shims and the Android SDK both land in per-user directories that a
# freshly started shell has not picked up yet.

$ErrorActionPreference = 'Stop'

function Find-FirstPath {
  param([string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  return $null
}

function Find-Tool {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string[]]$Candidates = @(),
    [switch]$Optional
  )

  $found = Find-FirstPath -Candidates $Candidates
  if (-not $found) {
    $onPath = Get-Command $Name -ErrorAction SilentlyContinue
    if ($onPath) { $found = $onPath.Source }
  }
  if (-not $found -and -not $Optional) {
    throw "Could not find $Name. Run: powershell -File tool\demo\setup.ps1"
  }
  return $found
}

# --- Android SDK ------------------------------------------------------------

$script:AndroidSdk = Find-FirstPath -Candidates @(
  $env:ANDROID_SDK_ROOT,
  $env:ANDROID_HOME,
  'C:\Android\sdk',
  "$env:LOCALAPPDATA\Android\Sdk"
)
if (-not $script:AndroidSdk) { throw 'Could not find the Android SDK.' }

$DemoTools = [ordered]@{
  Sdk        = $script:AndroidSdk
  Adb        = Find-Tool -Name 'adb' -Candidates @("$script:AndroidSdk\platform-tools\adb.exe")
  Emulator   = Find-Tool -Name 'emulator' -Candidates @("$script:AndroidSdk\emulator\emulator.exe")
  AvdManager = Find-Tool -Name 'avdmanager' -Candidates @("$script:AndroidSdk\cmdline-tools\latest\bin\avdmanager.bat")
  SdkManager = Find-Tool -Name 'sdkmanager' -Candidates @("$script:AndroidSdk\cmdline-tools\latest\bin\sdkmanager.bat")

  Ffmpeg     = Find-Tool -Name 'ffmpeg'  -Candidates @("$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe")
  Ffprobe    = Find-Tool -Name 'ffprobe' -Candidates @("$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffprobe.exe")

  # winget unpacks scrcpy into a versioned folder, so this one has to be hunted.
  Scrcpy     = Find-Tool -Name 'scrcpy' -Candidates @(
                 (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
                    -Filter 'scrcpy.exe' -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending |
                    Select-Object -First 1 -ExpandProperty FullName)
               )

  Flutter    = Find-Tool -Name 'flutter' -Candidates @('C:\src\flutter\bin\flutter.bat')
  Python     = Find-Tool -Name 'python'
}

# scrcpy shells out to adb; point it at the same one this script found so a
# second adb on PATH cannot start a competing server.
$env:ADB = $DemoTools.Adb
$env:ANDROID_SDK_ROOT = $DemoTools.Sdk

# --- Paths ------------------------------------------------------------------

$DemoRepo   = (Resolve-Path -LiteralPath "$PSScriptRoot\..\..").Path
$DemoOut    = Join-Path $DemoRepo 'build\demo'
$DemoAvd    = 'bentago_demo'
$DemoAppId  = 'ph.bentago.bentago'

function Initialize-DemoOut {
  foreach ($sub in @('', 'audio', 'assets', 'video')) {
    $path = if ($sub) { Join-Path $DemoOut $sub } else { $DemoOut }
    if (-not (Test-Path -LiteralPath $path)) {
      New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
  }
}

function Write-Step {
  param([string]$Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-Narration {
  $path = Join-Path $PSScriptRoot 'narration.json'
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing $path" }
  return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}
