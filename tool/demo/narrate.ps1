# Stage 1 of the demo pipeline: turn narration.json into voice clips, measure
# them, and write build\demo\beats.json.
#
# This runs *before* anything is recorded, and that ordering is the whole trick.
# Once each clip's length is known, the app can be told to hold each beat for
# exactly that long, which is what makes the finished video line up without
# anyone dragging clips around in an editor.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\narrate.ps1
#   powershell -ExecutionPolicy Bypass -File tool\demo\narrate.ps1 -Force

[CmdletBinding()]
param(
  # Re-synthesise every clip even if the wording has not changed.
  [switch]$Force,
  # Overrides narration.json's voice, for auditioning another one.
  [string]$Voice,
  # Silence held after each clip, so one beat does not run into the next.
  [int]$TailPadMs = 700
)

. "$PSScriptRoot\env.ps1"
Initialize-DemoOut

$narration = Get-Narration
$voiceName = if ($Voice) { $Voice } else { $narration.voice }
$audioDir  = Join-Path $DemoOut 'audio'

Write-Step "Narrating $($narration.beats.Count) beats as $voiceName"

$beats = New-Object System.Collections.ArrayList
$index = 0

foreach ($beat in $narration.beats) {
  $index++
  $stem = '{0:d2}-{1}' -f $index, $beat.id
  $txt  = Join-Path $audioDir "$stem.txt"
  $mp3  = Join-Path $audioDir "$stem.mp3"

  # Cache on the exact wording: the .txt beside each clip is what it was spoken
  # from, so an unchanged script costs no network round trip.
  $needsVoice = $true
  if (-not $Force -and (Test-Path -LiteralPath $mp3) -and (Test-Path -LiteralPath $txt)) {
    $previous = [System.IO.File]::ReadAllText($txt)
    if ($previous -eq $beat.text) { $needsVoice = $false }
  }

  if ($needsVoice) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($txt, $beat.text, $utf8NoBom)

    Write-Host ("  [{0}] {1}" -f $stem, $beat.caption)
    & $DemoTools.Python -m edge_tts `
      --file $txt `
      --voice $voiceName `
      "--rate=$($narration.rate)" `
      "--pitch=$($narration.pitch)" `
      --write-media $mp3
    if ($LASTEXITCODE -ne 0) {
      throw "edge-tts failed on beat '$($beat.id)'. It needs an internet connection; for an offline run see the note in tool\demo\README.md."
    }
  } else {
    Write-Host ("  [{0}] {1} (cached)" -f $stem, $beat.caption)
  }

  $raw = & $DemoTools.Ffprobe -v error -show_entries format=duration -of csv=p=0 $mp3
  $seconds = [double]::Parse(($raw | Select-Object -First 1).Trim(), [Globalization.CultureInfo]::InvariantCulture)
  if ($seconds -le 0) { throw "Could not read a duration from $mp3" }

  $voiceMs = [int][Math]::Round($seconds * 1000)

  [void]$beats.Add([ordered]@{
    id       = $beat.id
    caption  = $beat.caption
    text     = $beat.text
    audio    = $mp3
    voiceMs  = $voiceMs
    # What the app is told to hold for: the voice plus a breath afterwards.
    holdMs   = $voiceMs + $TailPadMs
  })
}

# Summed by hand: Measure-Object reads properties off objects, and these are
# ordered dictionaries.
$totalMs = 0
foreach ($beat in $beats) { $totalMs += $beat.holdMs }

$manifest = [ordered]@{
  voice     = $voiceName
  tailPadMs = $TailPadMs
  totalMs   = $totalMs
  title     = $narration.title
  end       = $narration.end
  beats     = $beats
}

$beatsPath = Join-Path $DemoOut 'beats.json'
$manifest | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $beatsPath -Encoding utf8

Write-Host ''
Write-Host ("Narration total: {0:mm\:ss} across {1} beats" -f ([TimeSpan]::FromMilliseconds($totalMs)), $beats.Count) -ForegroundColor Green
Write-Host "Wrote $beatsPath"
