# Pulls one frame per beat out of the finished video and tiles them into a single
# PNG, so a take can be checked at a glance instead of watched end to end.
#
# What to look for: the caption on the left should describe the screen on the
# right. If they disagree, a beat's taps and its narration have drifted apart --
# usually because demo_flow.dart and narration.json no longer list the same ids.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\contact-sheet.ps1

[CmdletBinding()]
param(
  # How far into each beat to grab the frame. A little way in, so the caption has
  # finished fading up and the beat's first tap has landed.
  [double]$IntoBeat = 2.5,
  [int]$Columns = 3,
  [ValidateSet('landscape', 'portrait')]
  [string]$Orientation = 'landscape',
  [string]$OutFile
)

. "$PSScriptRoot\env.ps1"
Initialize-DemoOut

if ($Orientation -eq 'portrait') {
  $timelinePath = Join-Path $DemoOut 'timeline-portrait.json'
} else {
  $timelinePath = Join-Path $DemoOut 'timeline.json'
}
if (-not (Test-Path -LiteralPath $timelinePath)) {
  throw "Missing $timelinePath -- run tool\demo\edit.ps1 first."
}
$timeline = Get-Content -LiteralPath $timelinePath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not (Test-Path -LiteralPath $timeline.outFile)) {
  throw "Missing $($timeline.outFile) -- run tool\demo\edit.ps1 first."
}
if (-not $OutFile) { $OutFile = Join-Path $DemoOut "contact-sheet-$Orientation.png" }

$framesDir = Join-Path $DemoOut "frames-$Orientation"
if (Test-Path -LiteralPath $framesDir) { Remove-Item -LiteralPath $framesDir -Recurse -Force }
New-Item -ItemType Directory -Path $framesDir -Force | Out-Null

Write-Step "Pulling $($timeline.beats.Count) frames from $(Split-Path -Leaf $timeline.outFile)"

foreach ($beat in $timeline.beats) {
  # Clamped so a beat shorter than -IntoBeat still lands inside itself.
  $at = [Math]::Min([double]$beat.finalStart + $IntoBeat, [double]$beat.finalEnd - 0.3)
  $stamp = $at.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
  $out = Join-Path $framesDir ('{0:d2}-{1}.png' -f $beat.number, $beat.id)

  # -ss before -i seeks by keyframe, which is fast and plenty accurate here.
  & $DemoTools.Ffmpeg -y -hide_banner -loglevel error `
    -ss $stamp -i $timeline.outFile -frames:v 1 -vf 'scale=640:-1' $out
  if ($LASTEXITCODE -ne 0) { throw "ffmpeg could not read a frame at ${stamp}s" }
  Write-Host ("  {0,6}s  {1}" -f $stamp, $beat.id)
}

# The frames keep readable names, but ffmpeg's image2 demuxer needs a numbered
# sequence to read them as one stream -- `-pattern_type glob` is a POSIX-only
# feature and the Windows builds report "globbing is not supported". Copying a
# dozen small PNGs is cheaper than assembling a twelve-input xstack.
$seqDir = Join-Path $framesDir 'seq'
New-Item -ItemType Directory -Path $seqDir -Force | Out-Null
$ordered = Get-ChildItem -LiteralPath $framesDir -Filter '*.png' | Sort-Object Name
$n = 0
foreach ($frame in $ordered) {
  $n++
  Copy-Item -LiteralPath $frame.FullName -Destination (Join-Path $seqDir ('{0:d3}.png' -f $n))
}

$rows = [Math]::Ceiling($n / [double]$Columns)
& $DemoTools.Ffmpeg -y -hide_banner -loglevel error `
  -start_number 1 -i (Join-Path $seqDir '%03d.png') `
  -filter_complex "tile=$($Columns)x$($rows):margin=8:padding=8:color=0x0D161D" `
  -frames:v 1 $OutFile
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg could not tile the frames.' }
Remove-Item -LiteralPath $seqDir -Recurse -Force

Write-Host ''
Write-Host "Wrote $OutFile" -ForegroundColor Green
Write-Host "  individual frames in $framesDir"
