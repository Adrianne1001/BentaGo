# The one command. Narrate, boot, record, edit.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1
#
# Everything intermediate lands in build\demo\ and is safe to delete; the
# finished video goes to dist\BentaGo-Demo-<version>.mp4.
#
# Useful while iterating -- each stage can be re-run on its own, and the ones
# before it are skipped:
#
#   -SkipNarration   reuse the voice clips (they are cached on wording anyway)
#   -SkipRecording   re-edit the take that is already in build\demo\video\raw.mp4
#
# To change what is said, edit tool\demo\narration.json. To change what is
# *shown*, edit integration_test\demo_flow.dart -- and keep the beat ids in the
# two files in step, because that is what pairs a clip with a moment.

[CmdletBinding()]
param(
  [switch]$SkipNarration,
  [switch]$SkipRecording,
  # Re-synthesise every voice clip even if the wording is unchanged.
  [switch]$ForceNarration,
  [string]$Voice,
  [string]$Music,
  [switch]$Fresh,
  [switch]$Headless,
  # 'both' renders the 1920x1080 and the 1080x1920 cut from the same take. The
  # second orientation is only a re-render -- one recording feeds both.
  [ValidateSet('landscape', 'portrait', 'both')]
  [string]$Orientation = 'landscape',
  [string]$OutFile
)

. "$PSScriptRoot\env.ps1"
Initialize-DemoOut

$started = Get-Date

Write-Host ''
Write-Host 'BentaGo demo pipeline' -ForegroundColor White
Write-Host '---------------------'

if (-not $SkipNarration) {
  $narrateArgs = @{}
  if ($ForceNarration) { $narrateArgs['Force'] = $true }
  if ($Voice)          { $narrateArgs['Voice'] = $Voice }
  & "$PSScriptRoot\narrate.ps1" @narrateArgs
  if ($LASTEXITCODE -ne 0) { throw 'Narration stage failed.' }
} else {
  Write-Step 'Skipping narration (reusing build\demo\beats.json)'
  if (-not (Test-Path -LiteralPath (Join-Path $DemoOut 'beats.json'))) {
    throw 'There is no beats.json to reuse. Run without -SkipNarration.'
  }
}

if (-not $SkipRecording) {
  $emuArgs = @{}
  if ($Fresh)    { $emuArgs['Fresh'] = $true }
  if ($Headless) { $emuArgs['Headless'] = $true }
  $serial = & "$PSScriptRoot\emulator.ps1" @emuArgs | Select-Object -Last 1

  & "$PSScriptRoot\record.ps1" -Serial $serial
  if ($LASTEXITCODE -ne 0) { throw 'Recording stage failed.' }
} else {
  Write-Step 'Skipping recording (reusing build\demo\video\raw.mp4)'
  foreach ($needed in 'capture.json', 'marks.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $DemoOut $needed))) {
      throw "There is no $needed to reuse. Run without -SkipRecording."
    }
  }
}

if ($Orientation -eq 'both') {
  $orientations = @('landscape', 'portrait')
} else {
  $orientations = @($Orientation)
}
if ($OutFile -and $orientations.Count -gt 1) {
  throw '-OutFile names a single file, so it cannot be combined with -Orientation both.'
}

foreach ($shape in $orientations) {
  $editArgs = @{ Orientation = $shape }
  if ($Music)   { $editArgs['Music'] = $Music }
  if ($OutFile) { $editArgs['OutFile'] = $OutFile }
  & "$PSScriptRoot\edit.ps1" @editArgs
  if ($LASTEXITCODE -ne 0) { throw "Edit stage failed for $shape." }
}

Write-Host ''
Write-Host ("Done in {0:mm\:ss}." -f ((Get-Date) - $started)) -ForegroundColor Green
