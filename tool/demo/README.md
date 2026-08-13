# The demo pipeline

Produces a narrated, framed MP4 walkthrough of the Android app from one command:

```powershell
powershell -ExecutionPolicy Bypass -File tool\demo\setup.ps1      # once, ~1.5 GB
powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1  # ~12 min
```

Output: `dist\BentaGo-Demo-<version>.mp4` — 1920x1080, the phone screen inset in
a bezel on a brand backdrop, with a title card, per-beat captions, an end card
and neural-TTS narration.

Everything intermediate goes to `build\demo\` and can be deleted at will.

## Orientations

```powershell
powershell -File tool\demo\make-demo.ps1 -Orientation both
```

| | Frame | Layout | For |
| --- | --- | --- | --- |
| `landscape` (default) | 1920x1080 | phone right, copy in a left column | laptops, YouTube, a landing page |
| `portrait` | 1080x1920 | phone centred, caption beneath | Stories, Reels, TikTok, viewing on a phone |

Portrait lands at `dist\BentaGo-Demo-<version>-Portrait.mp4`.

**A second orientation costs one re-render, not one re-recording.** Both read the
same `raw.mp4`, `marks.json` and voice clips, so once a take exists:

```powershell
powershell -File tool\demo\edit.ps1 -Orientation portrait   # ~3 min, no emulator
```

The filter graph itself is orientation-agnostic: every coordinate comes from the
`geometry.json` that `render_assets.py` writes, so the layout lives in exactly one
place. A 1080x2400 screen is 9:20 against portrait's 9:16, so the phone is
centred at full height with margins rather than cropped — losing the bottom
navigation bar or the day's takings off the top would cost more than the margins
do.

## How the audio stays in sync

This is the only part worth understanding before changing anything.

Narration is generated **first**, not last. Each clip is measured with `ffprobe`,
and the lengths are handed to the app as
`--dart-define=BENTAGO_BEATS=intro=7412,ringup=9130,...`. The integration test
then holds each beat on screen for exactly that long, spacing its taps evenly
across the time available. So the picture is cut to fit the voice rather than the
other way round.

To place the clips, the editor needs to know where each beat sits in the video
file. Two measurements give it that:

- `marks.json` — the flow stamps `DateTime.now()` at the start and end of every
  beat.
- `capture.json` — `captureStartMs`, stamped the moment scrcpy logs
  `Recording started`. Polled every 50 ms, so it is within a frame or two of the
  real first frame.

  It is deliberately **not** computed as `scrcpyExitMs - videoDuration`, which
  was the first attempt and is subtly wrong: a container's duration is
  `last_pts - first_pts`, and scrcpy can finish with seconds of tail missing. One
  take ran 223 s and produced a 211 s file, which put the computed start 12 s late
  and slid the entire narration out of sync — while still rendering a
  perfectly valid video. Anchoring on the *start* makes a lost tail harmless,
  since the footage after the last beat is unused anyway. `edit.ps1` now also
  refuses to render if the first beat lands before the recording begins, instead
  of clamping it to zero and hiding the problem.

Subtract and you have each beat's offset in seconds. `edit.ps1` places every
clip with `adelay` at that offset. Nothing is aligned by eye and re-running is
idempotent.

If the voice sounds consistently early or late, nudge it — don't re-record:

```powershell
powershell -File tool\demo\edit.ps1 -SyncOffsetMs 320   # positive = later
```

## Stages

| Script | Does | Reads | Writes |
| --- | --- | --- | --- |
| `setup.ps1` | installs ffmpeg, scrcpy, edge-tts, pillow, emulator + AVD | | |
| `narrate.ps1` | edge-tts per beat, then measures each clip | `narration.json` | `beats.json`, `audio\*.mp3` |
| `emulator.ps1` | boots the AVD, pins the status bar via SystemUI demo mode | | `serial.txt` |
| `record.ps1` | builds, installs, drives the app, records with scrcpy | `beats.json` | `video\raw.mp4`, `marks.json`, `capture.json` |
| `render_assets.py` | draws the bezel, backdrop, cards and caption type | `beats.json` | `assets\*.png` |
| `edit.ps1` | composites, mixes, joins | all of the above | `dist\BentaGo-Demo-*.mp4`, `timeline.json` |
| `make-demo.ps1` | runs the four in order | | |
| `contact-sheet.ps1` | one frame per beat, tiled, for checking a take | `timeline.json` | `contact-sheet.png` |

After a run, check it without watching the whole thing:

```powershell
powershell -File tool\demo\contact-sheet.ps1
```

Each tile's caption should describe the screen beside it. If they disagree, a
beat's narration and its actions have drifted apart.

## Changing the demo

- **What is said** — `narration.json`. Clips are cached on the exact wording, so
  editing one beat re-synthesises only that beat.
- **What is shown** — `integration_test\demo_flow.dart`.
- **Beat ids must match between the two.** That pairing is what puts a clip over
  the right moment. A beat in `narration.json` with no counterpart in the flow is
  skipped with a warning; a beat in the flow with no narration falls back to six
  seconds of silence.
- **How it looks** — `render_assets.py`. `SCREEN_X/Y/W/H` there is the single
  source of truth for where the video sits; `edit.ps1` reads it back out of
  `geometry.json` rather than repeating the numbers.

Re-running while iterating:

```powershell
# Re-edit the take already on disk -- no emulator, no rebuild (~2 min)
powershell -File tool\demo\make-demo.ps1 -SkipNarration -SkipRecording

# Audition another voice
powershell -File tool\demo\narrate.ps1 -Voice en-PH-JamesNeural -Force
python -m edge_tts --list-voices    # everything available
```

## Demo data

The recording needs a store with history, so `main()` calls
`DemoSeeder.reset()` when built with `--dart-define=BENTAGO_DEMO=true`. It writes
six weeks of sales, four running tabs, monthly utilities and one voided sale from
a fixed seed, so every take shows identical figures — which is what lets the
narration describe them.

`kDemoMode` is `bool.fromEnvironment`, i.e. a compile-time constant, so a normal
`flutter build` drops the branch and tree-shakes the seeder out entirely. Checked
rather than assumed: `Aling Nena` and `Kapitbahay` appear in `libapp.so` of a
profile APK and are absent from a release one.

Being past-dated data it writes rows directly rather than through
`SalesRepository` (which stamps `DateTime.now()`), and keeps the invariants by
hand — centavo integers, `day_key` on every row, price snapshots on
`sale_items`, an appended ledger charge per credit sale, `voided = 1` rather than
a delete. See the class comment.

Two traps that are easy to reintroduce, both covered by the `demo seeder` group
in [test/database_test.dart](../../test/database_test.dart):

- **Settlements must be dated after the charges they clear.** Paying a tab at
  09:00 on the same day that charges ran until 21:00 makes the ledger read as
  negative partway through its own history, and the customer screen prints that
  running balance on every row.
- **Do not book restocking as an expense.** What the stock cost is already on
  every `sale_items` row as `unit_cost_centavos`, and net profit is gross minus
  expenses — so a `Stock` expense subtracts it twice and the demo opens on a
  loss in the danger colour. The seeded Monday expense is the market *fare*,
  which is a real operating cost that COGS does not contain.

`reset()` is reproducible for a given calendar day, not across days: the seed is
fixed, but the weekday pattern and the bill dates move with the calendar and
shift the whole random stream. Hence no peso amounts in `narration.json`.

## Notes and limits

- **edge-tts needs an internet connection.** It is free and needs no API key,
  but it calls Microsoft's endpoint. Offline, use Windows SAPI instead — the
  voices are markedly worse:
  ```powershell
  Add-Type -AssemblyName System.Speech
  $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $s.SelectVoice('Microsoft Zira Desktop'); $s.SetOutputToWaveFile($out); $s.Speak($text)
  ```
- **scrcpy, not `adb shell screenrecord`**: the latter caps at three minutes and
  stutters. scrcpy stops itself via `--time-limit` so the MP4 is always
  finalised; force-killing a recorder leaves an unplayable file.
- **No music bed ships with the repo.** Pass one: `-Music path\to\bed.mp3`
  (mixed at -26 dB, looped, trimmed to length).
- **`-Headless`** boots the emulator without a window. It works, but rendering
  falls back to SwiftShader and the capture is visibly less smooth.
- The emulator runs `-gpu host`; on a machine without a usable GPU, add
  `-gpu swiftshader_indirect` in `emulator.ps1`.
