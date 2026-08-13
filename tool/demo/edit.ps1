# Stage 4: cut the recording, lay the narration over it, and render the MP4.
#
# Nothing here is aligned by eye. Three files decide the timeline:
#
#   capture.json  when the first captured frame happened, on the host clock
#   marks.json    when each beat started and ended, on the same clock
#   beats.json    which voice clip belongs to which beat
#
# Subtracting the first from the second gives each beat's exact position in the
# video file, so every clip is placed arithmetically.
#
#   powershell -ExecutionPolicy Bypass -File tool\demo\edit.ps1
#   powershell -ExecutionPolicy Bypass -File tool\demo\edit.ps1 -Music path\to\bed.mp3

[CmdletBinding()]
param(
  # Optional music bed. Ducked well under the narration; off by default because
  # there is no music in the repo to default to.
  [string]$Music,
  [int]$MusicGainDb = -26,
  # Seconds of video kept before the first beat and after the last.
  [double]$PreRoll = 1.0,
  [double]$PostRoll = 1.4,
  [double]$TitleSeconds = 4.0,
  [double]$EndSeconds = 5.0,
  # Nudge for the narration against the picture, in milliseconds. Positive moves
  # the voice later. The default compensates for scrcpy finishing its file a
  # moment after it stops capturing.
  [int]$SyncOffsetMs = 200,
  # landscape = 1920x1080, phone framed beside the copy. portrait = 1080x1920,
  # phone centred with the caption beneath it, for Stories and Reels.
  #
  # Both read the same recording, marks and voice clips, so a second orientation
  # costs one re-render -- no emulator and no re-recording.
  [ValidateSet('landscape', 'portrait')]
  [string]$Orientation = 'landscape',
  [string]$OutFile
)

. "$PSScriptRoot\env.ps1"
Initialize-DemoOut

$isPortrait = $Orientation -eq 'portrait'

# Kept apart so rendering one orientation never clobbers the other's layers.
if ($isPortrait) {
  $assets = Join-Path $DemoOut 'assets-portrait'
} else {
  $assets = Join-Path $DemoOut 'assets'
}

function Read-JsonFile {
  param([string]$Path, [string]$Hint)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Missing $Path -- $Hint" }
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Every number handed to ffmpeg goes through this.
#
# PowerShell's -f operator formats for the current culture: '{0:n3}' produces
# "12,5" where the decimal separator is a comma, and inserts thousands
# separators past 1000. ffmpeg parses neither, and would either error or -- worse
# -- silently read a different number.
function Fmt {
  param([double]$Value)
  return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

$manifest = Read-JsonFile (Join-Path $DemoOut 'beats.json')   'run tool\demo\narrate.ps1'
$capture  = Read-JsonFile (Join-Path $DemoOut 'capture.json') 'run tool\demo\record.ps1'
$marks    = Read-JsonFile (Join-Path $DemoOut 'marks.json')   'run tool\demo\record.ps1'

if (-not $OutFile) {
  $version = (Select-String -Path (Join-Path $DemoRepo 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
  if ($isPortrait) {
    $OutFile = Join-Path $DemoRepo "dist\BentaGo-Demo-$version-Portrait.mp4"
  } else {
    $OutFile = Join-Path $DemoRepo "dist\BentaGo-Demo-$version.mp4"
  }
}
$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# --- still layers -----------------------------------------------------------

Write-Step "Rendering the $Orientation title, bezel and caption layers"
& $DemoTools.Python (Join-Path $PSScriptRoot 'render_assets.py') `
  (Join-Path $DemoOut 'beats.json') $assets --orientation $Orientation
if ($LASTEXITCODE -ne 0) { throw 'render_assets.py failed.' }

$geometry = Read-JsonFile (Join-Path $assets 'geometry.json') 'render_assets.py should have written it'

# --- timeline ---------------------------------------------------------------

$captureStart = [double]$capture.captureStartMs

# marks.json is in flow order; index them by id so beats.json drives the order.
$markById = @{}
foreach ($mark in $marks) { $markById[$mark.id] = $mark }

$timeline = New-Object System.Collections.ArrayList
$index = 0
foreach ($beat in $manifest.beats) {
  $index++
  $mark = $markById[$beat.id]
  if (-not $mark) {
    Write-Host "  ! beat '$($beat.id)' was never reached on the device; skipping it" -ForegroundColor Yellow
    continue
  }
  [void]$timeline.Add([ordered]@{
    # `number` names the caption PNG, which render_assets.py numbered from the
    # full beat list. `slot` is the position in *this* list, and is what the
    # ffmpeg input indexes are counted from -- the two diverge as soon as a beat
    # is skipped above, and mixing them up pairs clips with the wrong beats.
    number   = $index
    slot     = $timeline.Count
    id       = $beat.id
    audio    = $beat.audio
    caption  = Join-Path $assets ('caption-{0:d2}-{1}.png' -f $index, $beat.id)
    absStart = (([double]$mark.startedAtMs - $captureStart) / 1000.0)
    absEnd   = (([double]$mark.endedAtMs   - $captureStart) / 1000.0)
  })
}
if ($timeline.Count -eq 0) { throw 'No beats survived; nothing to edit.' }

$first = $timeline[0]
$last  = $timeline[$timeline.Count - 1]

# Loud rather than clamped. A negative offset means capture.json's start time
# disagrees with the beat marks, and silently pinning it to zero produces a video
# that renders perfectly and is out of sync from the first word -- which is
# exactly how this went wrong once already.
if ($first.absStart -lt -0.5) {
  throw ("The first beat is timed {0:n2}s BEFORE the recording starts, which cannot be. " -f $first.absStart) +
        'capture.json and marks.json disagree; re-run tool\demo\record.ps1 rather than trusting this take.'
}
if ($first.absStart -gt 180) {
  throw ("The first beat is timed {0:n2}s into the recording, which is implausibly late. " -f $first.absStart) +
        'Check capture.json against marks.json.'
}

$trimStart = [Math]::Max(0.0, $first.absStart - $PreRoll)
$bodyEnd   = [Math]::Min([double]$capture.videoSeconds, $last.absEnd + $PostRoll)
$bodyDur   = $bodyEnd - $trimStart
if ($bodyDur -le 1.0) { throw "Worked out a body length of ${bodyDur}s, which cannot be right. Check capture.json against marks.json." }

Write-Host ("  body: {0:n2}s .. {1:n2}s ({2:n2}s of the {3:n2}s recording)" -f `
  $trimStart, $bodyEnd, $bodyDur, [double]$capture.videoSeconds)

# --- body: filter graph -----------------------------------------------------
#
# Inputs, in order:
#   0            the recording
#   1            bg.png
#   2            frame.png
#   3..2+N       one caption PNG per beat
#   3+N..        one voice clip per beat

$inputs = New-Object System.Collections.ArrayList
[void]$inputs.AddRange(@('-ss', (Fmt $trimStart), '-t', (Fmt $bodyDur), '-i', $capture.video))
[void]$inputs.AddRange(@('-loop', '1', '-i', (Join-Path $assets 'bg.png')))
[void]$inputs.AddRange(@('-loop', '1', '-i', (Join-Path $assets 'frame.png')))
foreach ($beat in $timeline) {
  [void]$inputs.AddRange(@('-loop', '1', '-i', $beat.caption))
}
foreach ($beat in $timeline) {
  [void]$inputs.AddRange(@('-i', $beat.audio))
}
if ($Music) { [void]$inputs.AddRange(@('-stream_loop', '-1', '-i', $Music)) }

$n = $timeline.Count
$captionBase = 3
$audioBase = 3 + $n
$musicIndex = $audioBase + $n

$filters = New-Object System.Collections.ArrayList

# The phone screen: the recording, scaled to the hole in the bezel.
[void]$filters.Add(
  "[0:v]setpts=PTS-STARTPTS,fps=30,scale=$($geometry.screenW):$($geometry.screenH):flags=lanczos[screen]"
)
# The backdrop, held for exactly the body's length.
$bodyDurText = Fmt $bodyDur
[void]$filters.Add("[1:v]scale=$($geometry.width):$($geometry.height),trim=duration=$bodyDurText,setpts=PTS-STARTPTS[bg]")
[void]$filters.Add("[bg][screen]overlay=$($geometry.screenX):$($geometry.screenY):shortest=0[withscreen]")
# The bezel goes on top, so its rounded hole clips the video's corners.
[void]$filters.Add("[2:v]trim=duration=$bodyDurText,setpts=PTS-STARTPTS[bezel]")
[void]$filters.Add('[withscreen][bezel]overlay=0:0[framed]')

# Captions, fading in and out around their beat.
$stage = 'framed'
$fade = 0.35
foreach ($beat in $timeline) {
  $i = $captionBase + $beat.slot
  $start = $beat.absStart - $trimStart
  $end = [Math]::Min($bodyDur, $beat.absEnd - $trimStart)
  # Held a touch past the beat's start and pulled in before its end, so the
  # caption changes read as deliberate rather than as a flicker on the cut.
  $inAt = [Math]::Max(0.0, $start + 0.12)
  $outAt = [Math]::Max($inAt + $fade + 0.4, $end - 0.25)
  $label = "cap$($beat.slot)"
  $next = "stage$($beat.slot)"

  [void]$filters.Add(
    "[$($i):v]trim=duration=$bodyDurText,setpts=PTS-STARTPTS,format=rgba," +
    "fade=t=in:st=$(Fmt $inAt):d=$(Fmt $fade):alpha=1," +
    "fade=t=out:st=$(Fmt $outAt):d=$(Fmt $fade):alpha=1[$label]"
  )
  [void]$filters.Add(
    "[$stage][$label]overlay=0:0:enable='between(t,$(Fmt $inAt),$(Fmt ($outAt + $fade + 0.05)))'[$next]"
  )
  $stage = $next
}

# Ease in and out of the body; the concat with the cards happens after this.
[void]$filters.Add("[$stage]fade=t=in:st=0:d=0.5,fade=t=out:st=$(Fmt ($bodyDur - 0.6)):d=0.6,format=yuv420p[vout]")

# Narration: every clip normalised to one format, delayed to its beat, summed.
$mixLabels = New-Object System.Collections.ArrayList
foreach ($beat in $timeline) {
  $i = $audioBase + $beat.slot
  $delayMs = [int][Math]::Round((($beat.absStart - $trimStart) * 1000.0) + $SyncOffsetMs)
  if ($delayMs -lt 0) { $delayMs = 0 }
  $label = "v$($beat.slot)"
  # $() around every value that is followed by a colon: PowerShell would
  # otherwise read "$i:a" as a scoped variable reference and expand it to
  # nothing at all.
  [void]$filters.Add(
    "[$($i):a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo," +
    "adelay=delays=$($delayMs):all=1[$label]"
  )
  [void]$mixLabels.Add("[$label]")
}

if ($Music) {
  [void]$filters.Add(
    "[$($musicIndex):a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo," +
    "volume=$($MusicGainDb)dB,atrim=duration=$bodyDurText,asetpts=PTS-STARTPTS[bed]"
  )
  [void]$mixLabels.Add('[bed]')
}

# normalize=0: amix otherwise divides every input by the input count, so a
# twelve-clip narration would come out inaudibly quiet.
[void]$filters.Add(
  ($mixLabels -join '') +
  "amix=inputs=$($mixLabels.Count):normalize=0:dropout_transition=0," +
  "apad,atrim=duration=$bodyDurText,alimiter=limit=0.95[aout]"
)

$graphPath = Join-Path $DemoOut "body-$Orientation.filter"
($filters -join ";`n") | Out-File -LiteralPath $graphPath -Encoding ascii

# The graph is passed as a file rather than on the command line: it is several
# kilobytes of colons, brackets and quotes, and Windows' argument handling
# mangles it.
#
# ffmpeg 7 replaced -filter_complex_script with a generic "read this option's
# value from a file" prefix, and 9 removed the old spelling entirely.
$versionLine = (& $DemoTools.Ffmpeg -hide_banner -version | Select-Object -First 1)
$ffmpegMajor = 0
if ($versionLine -match 'ffmpeg version n?(\d+)') { $ffmpegMajor = [int]$Matches[1] }
if ($ffmpegMajor -ge 7) {
  $graphFlag = '-/filter_complex'
} else {
  $graphFlag = '-filter_complex_script'
}

$bodyPath = Join-Path $DemoOut "video\body-$Orientation.mp4"
Write-Step "Compositing the $Orientation body"

$encode = @(
  '-map', '[vout]', '-map', '[aout]',
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '19',
  '-pix_fmt', 'yuv420p', '-r', '30',
  '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
  '-movflags', '+faststart'
)

& $DemoTools.Ffmpeg -y -hide_banner -loglevel warning -stats @inputs `
  $graphFlag $graphPath @encode $bodyPath
if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed compositing the body. The filter graph is at $graphPath" }

# --- cards ------------------------------------------------------------------

function New-Card {
  param([string]$Image, [double]$Seconds, [string]$Out)

  $vf = "scale=$($geometry.width):$($geometry.height),fps=30," +
        "fade=t=in:st=0:d=0.6,fade=t=out:st=$(Fmt ($Seconds - 0.7)):d=0.7,format=yuv420p"

  & $DemoTools.Ffmpeg -y -hide_banner -loglevel error `
    -loop 1 -t (Fmt $Seconds) -i $Image `
    -f lavfi -t (Fmt $Seconds) -i 'anullsrc=r=48000:cl=stereo' `
    -vf $vf `
    -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p -r 30 `
    -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest -movflags +faststart $Out
  if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed rendering $Out" }
}

Write-Step 'Rendering the opening and closing cards'
$titlePath = Join-Path $DemoOut "video\title-$Orientation.mp4"
$endPath   = Join-Path $DemoOut "video\end-$Orientation.mp4"
New-Card -Image (Join-Path $assets 'title.png') -Seconds $TitleSeconds -Out $titlePath
New-Card -Image (Join-Path $assets 'end.png')   -Seconds $EndSeconds   -Out $endPath

# --- join -------------------------------------------------------------------

Write-Step 'Joining'
$listPath = Join-Path $DemoOut "concat-$Orientation.txt"
@(
  "file '$($titlePath -replace '\\', '/')'"
  "file '$($bodyPath  -replace '\\', '/')'"
  "file '$($endPath   -replace '\\', '/')'"
) | Out-File -LiteralPath $listPath -Encoding ascii

# All three were encoded with identical settings, so this is a stream copy.
& $DemoTools.Ffmpeg -y -hide_banner -loglevel error `
  -f concat -safe 0 -i $listPath -c copy -movflags +faststart $OutFile
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg failed joining the parts.' }

# Where each beat ended up in the finished file, so contact-sheet.ps1 can pull a
# frame per beat without recomputing any of the arithmetic above.
$timelineOut = New-Object System.Collections.ArrayList
foreach ($beat in $timeline) {
  [void]$timelineOut.Add([ordered]@{
    number      = $beat.number
    id          = $beat.id
    caption     = (Split-Path -Leaf $beat.caption)
    finalStart  = [Math]::Round($TitleSeconds + ($beat.absStart - $trimStart), 3)
    finalEnd    = [Math]::Round($TitleSeconds + ($beat.absEnd - $trimStart), 3)
  })
}
if ($isPortrait) {
  $timelinePath = Join-Path $DemoOut 'timeline-portrait.json'
} else {
  $timelinePath = Join-Path $DemoOut 'timeline.json'
}
@{
  outFile       = $OutFile
  orientation   = $Orientation
  titleSeconds  = $TitleSeconds
  bodySeconds   = [Math]::Round($bodyDur, 3)
  endSeconds    = $EndSeconds
  syncOffsetMs  = $SyncOffsetMs
  beats         = $timelineOut
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $timelinePath -Encoding utf8

$finalRaw = & $DemoTools.Ffprobe -v error -show_entries format=duration -of csv=p=0 $OutFile
$finalSeconds = [double]::Parse(($finalRaw | Select-Object -First 1).Trim(), [Globalization.CultureInfo]::InvariantCulture)
$sizeMb = [Math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 1)

Write-Host ''
Write-Host ("Wrote {0}" -f $OutFile) -ForegroundColor Green
# ASCII only: PowerShell 5.1 reads this file as ANSI, so a middle dot here comes
# out of the console as mojibake.
Write-Host ("  {0:mm\:ss}  |  {1} MB  |  {2}x{3}  |  {4} narrated beats" -f `
  ([TimeSpan]::FromSeconds($finalSeconds)), $sizeMb, $geometry.width, $geometry.height, $timeline.Count)
