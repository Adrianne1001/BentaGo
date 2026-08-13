# Installs what the demo pipeline needs. Idempotent -- safe to re-run, and it
# only fetches what is actually missing.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\setup.ps1
#
# Roughly 1.5 GB the first time, almost all of it the emulator system image.
#
#   ffmpeg   every cut, overlay and mux
#   scrcpy   the screen recorder; adb's own screenrecord caps at 3 minutes
#   edge-tts free neural text-to-speech, including the en-PH voices
#   pillow   draws the title cards, phone bezel and caption type
#   emulator + system image + an AVD pinned to 1080x2400

[CmdletBinding()]
param(
  [string]$SystemImage = 'system-images;android-35;default;x86_64',
  # Recreate the AVD even if one by that name exists.
  [switch]$RecreateAvd
)

$ErrorActionPreference = 'Stop'

function Test-Exe {
  param([string]$Name, [string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $true }
  }
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

$sdk = $env:ANDROID_SDK_ROOT
if (-not $sdk) { $sdk = $env:ANDROID_HOME }
if (-not $sdk) {
  foreach ($guess in 'C:\Android\sdk', "$env:LOCALAPPDATA\Android\Sdk") {
    if (Test-Path -LiteralPath $guess) { $sdk = $guess; break }
  }
}
if (-not $sdk) { throw 'Could not find the Android SDK. Set ANDROID_SDK_ROOT and try again.' }
$env:ANDROID_SDK_ROOT = $sdk
Write-Host "Android SDK: $sdk"

# --- host tools -------------------------------------------------------------

$ffmpegOk = Test-Exe 'ffmpeg' @("$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe")
if ($ffmpegOk) {
  Write-Host 'ffmpeg: already installed'
} else {
  Write-Host 'ffmpeg: installing...'
  winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements --disable-interactivity
}

$scrcpyOk = [bool](Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter 'scrcpy.exe' `
  -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $scrcpyOk) { $scrcpyOk = [bool](Get-Command scrcpy -ErrorAction SilentlyContinue) }
if ($scrcpyOk) {
  Write-Host 'scrcpy: already installed'
} else {
  Write-Host 'scrcpy: installing...'
  winget install --id Genymobile.scrcpy -e --accept-package-agreements --accept-source-agreements --disable-interactivity
}

Write-Host 'python packages: edge-tts, pillow...'
python -m pip install --quiet --upgrade edge-tts pillow
if ($LASTEXITCODE -ne 0) { throw 'pip install failed.' }

# --- emulator ---------------------------------------------------------------

$sdkmanager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdmanager = Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
if (-not (Test-Path -LiteralPath $sdkmanager)) {
  throw "Missing $sdkmanager. Install the Android SDK command-line tools first."
}

$wanted = @()
if (-not (Test-Path -LiteralPath (Join-Path $sdk 'emulator\emulator.exe'))) { $wanted += 'emulator' }
$imagePath = Join-Path $sdk ('system-images\' + ($SystemImage -replace ';', '\'))
if (-not (Test-Path -LiteralPath $imagePath)) { $wanted += $SystemImage }

if ($wanted.Count -gt 0) {
  Write-Host ("Android packages: installing {0}..." -f ($wanted -join ', '))
  # sdkmanager prompts per licence; feed it enough acceptances to get through.
  $yes = ("y`n" * 40)
  $yes | & $sdkmanager --licenses
  $yes | & $sdkmanager @wanted
  if ($LASTEXITCODE -ne 0) { throw 'sdkmanager failed.' }
} else {
  Write-Host 'Android emulator and system image: already installed'
}

# --- the AVD ----------------------------------------------------------------

$avdName = 'bentago_demo'
$avdConfig = "$env:USERPROFILE\.android\avd\$avdName.avd\config.ini"

if ((Test-Path -LiteralPath $avdConfig) -and -not $RecreateAvd) {
  Write-Host "AVD ${avdName}: already exists"
} else {
  Write-Host "AVD ${avdName}: creating..."
  'no' | & $avdmanager create avd -n $avdName -k $SystemImage -d pixel_7 --force
  if ($LASTEXITCODE -ne 0) { throw 'avdmanager failed.' }
}

# A fixed screen is what keeps every take the same size, so this is applied on
# every run rather than only at creation.
$settings = [ordered]@{
  'hw.lcd.width'           = '1080'
  'hw.lcd.height'          = '2400'
  'hw.lcd.density'         = '420'
  'hw.ramSize'             = '3072'
  'hw.keyboard'            = 'yes'
  'disk.dataPartition.size' = '4096M'
  'showDeviceFrame'        = 'no'
  'hw.gpu.enabled'         = 'yes'
  'hw.gpu.mode'            = 'auto'
}

$lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $avdConfig)
foreach ($key in $settings.Keys) {
  $pattern = "^$([regex]::Escape($key))\s*="
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) {
      $lines[$i] = "$key=$($settings[$key])"
      $found = $true
    }
  }
  if (-not $found) { [void]$lines.Add("$key=$($settings[$key])") }
}
($lines -join "`n") | Out-File -LiteralPath $avdConfig -Encoding ascii

Write-Host ''
Write-Host 'Ready. Next:' -ForegroundColor Green
Write-Host '  powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1'
