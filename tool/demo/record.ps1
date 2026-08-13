# Stage 3: run the demo on the device and capture it.
#
# Ordering, and why:
#
#   1. `flutter drive` is started first, in the background. It builds, installs
#      and launches -- minutes of work that must not end up in the recording.
#   2. The app window is polled for focus. That is the first frame.
#   3. Only then does scrcpy start capturing. The flow's opening hold covers the
#      second or so it takes to attach.
#   4. scrcpy stops itself via --time-limit, so the MP4 is always finalised
#      properly. Killing a recorder mid-write leaves an unplayable file.
#
# The recording's start on the host clock is taken from scrcpy's own
# "Recording started" log line, stamped the moment it appears. Beat marks are
# stamped by the app on the same clock, so the two subtract cleanly.
#
# It is deliberately NOT derived as (exit time - video duration), which was the
# first attempt: the container's duration is last_pts - first_pts, and scrcpy can
# finish with several seconds of tail missing. On one take a 223-second session
# produced a 211-second file, which put the computed start 12 seconds late and
# silently slid the whole narration out of sync. Anchoring on the start makes a
# lost tail harmless -- it only shortens the unused footage after the last beat.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\record.ps1

[CmdletBinding()]
param(
  [string]$Serial,
  # Recorded on top of the narration total, to cover install, launch and the
  # tail after the last beat. scrcpy stops at this point no matter what.
  [int]$TailSeconds = 35,
  [int]$BitRateMbps = 16
)

. "$PSScriptRoot\env.ps1"
Initialize-DemoOut

$beatsPath = Join-Path $DemoOut 'beats.json'
if (-not (Test-Path -LiteralPath $beatsPath)) {
  throw "Missing $beatsPath -- run tool\demo\narrate.ps1 first."
}
$manifest = Get-Content -LiteralPath $beatsPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $Serial) {
  $serialFile = Join-Path $DemoOut 'serial.txt'
  if (Test-Path -LiteralPath $serialFile) {
    $Serial = (Get-Content -LiteralPath $serialFile -Raw).Trim()
  }
}
if (-not $Serial) { throw 'No device serial. Run tool\demo\emulator.ps1 first.' }

# --- hand the beat lengths to the app ---------------------------------------

# The flow holds each beat for exactly as long as its narration clip runs.
$beatSpec = ($manifest.beats | ForEach-Object { "$($_.id)=$($_.holdMs)" }) -join ','

$videoPath = Join-Path $DemoOut 'video\raw.mp4'
$marksPath = Join-Path $DemoOut 'marks.json'
foreach ($stale in $videoPath, $marksPath) {
  if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
}

Write-Step 'Reinstalling the app so the demo data is built from scratch'
# Ignore the failure when it was never installed.
try { & $DemoTools.Adb -s $Serial uninstall $DemoAppId | Out-Null } catch { }

Write-Step 'Starting the driven demo (builds, installs, launches)'

$driveArgs = @(
  'drive',
  '--driver=test_driver/demo_driver.dart',
  '--target=integration_test/demo_flow.dart',
  '--profile',                       # release-smooth, but still drivable
  '-d', $Serial,
  '--dart-define=BENTAGO_DEMO=true',
  "--dart-define=BENTAGO_BEATS=$beatSpec"
)

$driveLog = Join-Path $DemoOut 'flutter-drive.log'
$drive = Start-Process -FilePath $DemoTools.Flutter -ArgumentList $driveArgs `
  -WorkingDirectory $DemoRepo -PassThru -NoNewWindow `
  -RedirectStandardOutput $driveLog -RedirectStandardError "$driveLog.err"

# Touching .Handle caches the process handle. Without it, .NET releases the
# handle when the process ends and .ExitCode reads back as $null after
# WaitForExit -- which looks exactly like a failure and is not one.
$null = $drive.Handle

Write-Host "  flutter drive pid $($drive.Id), logging to $driveLog"
Write-Host '  waiting for the app to take the screen...'

$focusDeadline = (Get-Date).AddMinutes(12)
$onScreen = $false
while (-not $onScreen) {
  if ($drive.HasExited) {
    throw "flutter drive exited early (code $($drive.ExitCode)). See $driveLog"
  }
  if ((Get-Date) -gt $focusDeadline) {
    throw "The app never appeared within 12 minutes. See $driveLog"
  }
  $focus = (& $DemoTools.Adb -s $Serial shell dumpsys window) -join "`n"
  if ($focus -match [regex]::Escape($DemoAppId)) { $onScreen = $true; break }
  Start-Sleep -Milliseconds 400
}

Write-Host '  app is up' -ForegroundColor Green

# --- capture ----------------------------------------------------------------

$limitSeconds = [int][Math]::Ceiling($manifest.totalMs / 1000.0) + $TailSeconds
Write-Step ("Recording for up to {0}s" -f $limitSeconds)

$scrcpyArgs = @(
  "--serial=$Serial",
  "--record=$videoPath",
  '--no-audio',
  '--no-window',                     # capture only; nothing to look at
  '--no-playback',
  "--video-bit-rate=${BitRateMbps}M",
  '--max-fps=30',
  "--time-limit=$limitSeconds"
)
$scrcpyLog = Join-Path $DemoOut 'scrcpy.log'
$scrcpy = Start-Process -FilePath $DemoTools.Scrcpy -ArgumentList $scrcpyArgs `
  -PassThru -NoNewWindow `
  -RedirectStandardOutput $scrcpyLog -RedirectStandardError "$scrcpyLog.err"
$null = $scrcpy.Handle

Write-Host "  scrcpy pid $($scrcpy.Id) -> $videoPath"

# The sync anchor. Polled tightly, because every millisecond between the real
# first frame and this stamp is a millisecond the narration will sit late.
$captureStartMs = 0
$anchorDeadline = (Get-Date).AddSeconds(45)
while ($true) {
  if ((Get-Date) -gt $anchorDeadline) {
    throw "scrcpy never reported that recording had started. See $scrcpyLog"
  }
  if ($scrcpy.HasExited) { throw "scrcpy exited before recording began. See $scrcpyLog" }
  if (Test-Path -LiteralPath $scrcpyLog) {
    $log = Get-Content -LiteralPath $scrcpyLog -Raw -ErrorAction SilentlyContinue
    if ($log -and $log -match 'Recording started') {
      $captureStartMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      break
    }
  }
  Start-Sleep -Milliseconds 50
}
Write-Host '  capture anchored' -ForegroundColor Green

# --- wait for the flow, then for the recorder -------------------------------

$drive.WaitForExit()
$driveExit = $drive.ExitCode
Write-Host ''
Write-Host "  flutter drive finished (exit $driveExit)"

if ($driveExit -ne 0) {
  Write-Host '--- flutter drive output (tail) ---' -ForegroundColor Yellow
  if (Test-Path -LiteralPath $driveLog) { Get-Content -LiteralPath $driveLog -Tail 40 }
  if (Test-Path -LiteralPath "$driveLog.err") { Get-Content -LiteralPath "$driveLog.err" -Tail 40 }
}

# Left to stop on its own so the container is written out cleanly. This is the
# only wasted wall-clock in the pipeline, bounded by -TailSeconds.
Write-Host '  letting scrcpy finalise the recording...'
$scrcpy.WaitForExit()
$exitMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

if (-not (Test-Path -LiteralPath $videoPath)) {
  Write-Host '--- scrcpy output ---' -ForegroundColor Yellow
  if (Test-Path -LiteralPath $scrcpyLog) { Get-Content -LiteralPath $scrcpyLog -Tail 30 }
  if (Test-Path -LiteralPath "$scrcpyLog.err") { Get-Content -LiteralPath "$scrcpyLog.err" -Tail 30 }
  throw 'scrcpy produced no video.'
}

if ($driveExit -ne 0) {
  throw "The demo flow failed (flutter drive exit $driveExit). The raw recording is at $videoPath; see $driveLog for which step could not be found."
}
if (-not (Test-Path -LiteralPath $marksPath)) {
  throw "The flow finished but reported no beat marks. Expected $marksPath; see $driveLog."
}

# --- report ------------------------------------------------------------------

$durationRaw = & $DemoTools.Ffprobe -v error -show_entries format=duration -of csv=p=0 $videoPath
$videoSeconds = [double]::Parse(($durationRaw | Select-Object -First 1).Trim(), [Globalization.CultureInfo]::InvariantCulture)

# How much of the session never made it into the file. Harmless in itself -- the
# tail after the last beat is unused -- but a large figure means the encoder was
# struggling, so it is worth seeing.
$sessionSeconds = ($exitMs - $captureStartMs) / 1000.0
$lostTail = $sessionSeconds - $videoSeconds
if ($lostTail -gt 3.0) {
  Write-Host ("  note: {0:n1}s of the session is missing from the file (encoder dropped the tail)" -f $lostTail) -ForegroundColor Yellow
}

$capture = [ordered]@{
  video          = $videoPath
  videoSeconds   = $videoSeconds
  scrcpyExitMs   = $exitMs
  # Stamped when scrcpy said it had started, not inferred from the duration.
  # See the note at the top of this file.
  captureStartMs = $captureStartMs
  lostTailSeconds = [Math]::Round($lostTail, 3)
  serial         = $Serial
}
$capturePath = Join-Path $DemoOut 'capture.json'
$capture | ConvertTo-Json | Out-File -LiteralPath $capturePath -Encoding utf8

Write-Host ''
Write-Host ("Recorded {0:mm\:ss} to {1}" -f ([TimeSpan]::FromSeconds($videoSeconds)), $videoPath) -ForegroundColor Green
Write-Host "Wrote $capturePath and $marksPath"
