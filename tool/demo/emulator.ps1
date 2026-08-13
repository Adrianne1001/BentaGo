# Stage 2: bring up a clean emulator and dress it for filming.
#
# The status bar matters more than it sounds. Left alone it shows a drifting
# clock, a draining battery and whatever notifications Android feels like, all of
# which change between takes and date the video. SystemUI demo mode pins it.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\emulator.ps1
#   powershell -ExecutionPolicy Bypass -File tool\demo\emulator.ps1 -Fresh

[CmdletBinding()]
param(
  # Wipe the device before booting. Slower, and rarely needed -- the app is
  # reinstalled every run anyway.
  [switch]$Fresh,
  # Boot without the emulator window. Renders through SwiftShader, which is
  # noticeably less smooth, so it is off by default.
  [switch]$Headless,
  # The clock the status bar is frozen at, in 24-hour HHMM.
  [string]$ClockHHMM = '0930'
)

. "$PSScriptRoot\env.ps1"
Initialize-DemoOut

function Get-DemoSerial {
  $lines = & $DemoTools.Adb devices
  foreach ($line in $lines) {
    if ($line -match '^(emulator-\d+)\s+device') { return $Matches[1] }
  }
  return $null
}

function Invoke-Adb {
  # $Rest, not $Args: the latter shadows PowerShell's automatic variable.
  param([string]$Serial, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
  & $DemoTools.Adb -s $Serial @Rest
}

$serial = Get-DemoSerial
if ($serial) {
  Write-Step "Reusing the emulator already running on $serial"
} else {
  Write-Step "Booting the $DemoAvd emulator"

  $emuArgs = @(
    '-avd', $DemoAvd,
    '-no-boot-anim',        # nothing to film during the animation
    '-no-snapshot-save',    # every run starts from the same saved state
    '-gpu', 'host',         # smooth enough to record
    '-no-audio'
  )
  if ($Fresh)    { $emuArgs += '-wipe-data' }
  if ($Headless) { $emuArgs += '-no-window' }

  Start-Process -FilePath $DemoTools.Emulator -ArgumentList $emuArgs -WindowStyle Minimized | Out-Null

  Write-Host '  waiting for the device to appear...'
  $deadline = (Get-Date).AddMinutes(5)
  while (-not $serial) {
    if ((Get-Date) -gt $deadline) { throw 'The emulator did not come up within 5 minutes.' }
    Start-Sleep -Milliseconds 1500
    $serial = Get-DemoSerial
  }

  Write-Host "  $serial attached; waiting for the boot to finish..."
  & $DemoTools.Adb -s $serial wait-for-device
  while ($true) {
    if ((Get-Date) -gt $deadline) { throw 'The emulator attached but never finished booting.' }
    $booted = (Invoke-Adb -Serial $serial shell getprop sys.boot_completed) -join ''
    if ($booted.Trim() -eq '1') { break }
    Start-Sleep -Milliseconds 1500
  }
  # Even after boot_completed, SystemUI needs a moment before it will accept the
  # demo-mode broadcasts below.
  Start-Sleep -Seconds 4
}

Write-Step 'Dressing the device for recording'

# Awake, unlocked, and staying that way.
Invoke-Adb -Serial $serial shell svc power stayon true | Out-Null
Invoke-Adb -Serial $serial shell wm dismiss-keyguard | Out-Null
Invoke-Adb -Serial $serial shell input keyevent 82 | Out-Null

# The app follows the system theme, so pin it rather than inherit whatever the
# image booted with.
Invoke-Adb -Serial $serial shell cmd uimode night no | Out-Null

# Animations at their normal speed: this is a demo, the transitions are the
# point. (Named here so a machine left at 0x by another project's test setup
# does not silently produce a video with no motion in it.)
foreach ($scale in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
  Invoke-Adb -Serial $serial shell settings put global $scale 1 | Out-Null
}

# A fixed, tidy status bar.
Invoke-Adb -Serial $serial shell settings put global sysui_demo_allowed 1 | Out-Null
$demo = @(
  "command enter",
  "command clock -e hhmm $ClockHHMM",
  "command battery -e level 100 -e plugged false",
  "command network -e wifi show -e level 4",
  "command network -e mobile show -e datatype none -e level 4",
  "command notifications -e visible false"
)
foreach ($command in $demo) {
  Invoke-Adb -Serial $serial shell "am broadcast -a com.android.systemui.demo -e $command" | Out-Null
}

# Home screen, so the recording does not open on a settings page.
Invoke-Adb -Serial $serial shell input keyevent KEYCODE_HOME | Out-Null

$size    = (Invoke-Adb -Serial $serial shell wm size) -join ' '
$density = (Invoke-Adb -Serial $serial shell wm density) -join ' '
Write-Host "  $serial  $size  $density"
Write-Host '  status bar pinned via SystemUI demo mode' -ForegroundColor Green

# Handed to record.ps1.
$serial | Out-File -LiteralPath (Join-Path $DemoOut 'serial.txt') -Encoding ascii -NoNewline
Write-Output $serial
