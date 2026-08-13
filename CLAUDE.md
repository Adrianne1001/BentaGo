# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

BentaGo is a Flutter sales tracker for a single sari-sari store: one phone, one
store, offline, no account. SQLite is the entire backend. [README.md](README.md)
is unusually complete — read it for product decisions, build traps, backup
layout and the reasoning behind what was left out. This file covers the working
rules and the shape of the code.

## Commands

```powershell
flutter pub get
flutter analyze                       # must be clean; the release script gates on it
flutter test                          # 114 tests, real SQLite on disk
flutter run -d windows                # fastest dev loop; desktop uses the FFI factory
flutter run -d <android-device-id>

# one file / one group / one test
flutter test test/core_test.dart
flutter test test/database_test.dart --plain-name "correcting a sale"
flutter test test/core_test.dart --plain-name "reads decimals"

dart run tool/inspect_db.dart                   # schema + row counts of the live DB
dart run tool/inspect_db.dart path\to\backup.db # or of a backup, read-only

# Rebuild every installable in dist/ (~5 min, gates on analyze + test)
powershell -ExecutionPolicy Bypass -File tool\release.ps1
powershell -ExecutionPolicy Bypass -File tool\release.ps1 -BumpBuild

# Narrated demo video, end to end: emulator -> driven app -> TTS -> MP4
powershell -ExecutionPolicy Bypass -File tool\demo\setup.ps1       # once, ~1.5 GB
powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1   # ~7 min
powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1 -Orientation both
powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1 -SkipNarration -SkipRecording

# Re-cut an existing take -- no emulator, no rebuild, no re-recording
powershell -ExecutionPolicy Bypass -File tool\demo\edit.ps1 -Orientation portrait
powershell -ExecutionPolicy Bypass -File tool\demo\contact-sheet.ps1   # one frame per beat, to check a take
```

The demo pipeline lives in [tool/demo/](tool/demo/) and is documented in
[tool/demo/README.md](tool/demo/README.md) — read that before touching it, in
particular the note on why narration is generated *before* the recording and why
the capture start is anchored on scrcpy's log line rather than the video's
duration. Its one hook into the app is `DemoSeeder.reset()` in
[lib/demo/demo_seed.dart](lib/demo/demo_seed.dart), called from `main()` behind
`kDemoMode` (a `bool.fromEnvironment` constant, so it tree-shakes out of every
normal build) and deliberately *after* the monthly backup, because it deletes
every sale, tab and expense in the database. Beat ids must stay in step between
[tool/demo/narration.json](tool/demo/narration.json) and
[integration_test/demo_flow.dart](integration_test/demo_flow.dart).

The seeder writes rows directly rather than through the repositories (it needs
past dates, and a repository stamps `now`), so it upholds the invariants above by
hand and the `demo seeder` group in
[test/database_test.dart](test/database_test.dart) is what holds it to them —
notably that no tab ever reads as negative and that every window shows a profit.
Without those, a regression only surfaces as something wrong in a 12-minute
video.

**Any code change that lands on `main` must be followed by `tool\release.ps1`.**
The CI workflow ([.github/workflows/release.yml](.github/workflows/release.yml))
does not build — it publishes whatever is already committed in [dist/](dist/) and
fails if `dist/` does not carry the `pubspec.yaml` version. Artifacts are built
locally because the release keystore only exists on the dev machine.

Two traps when running that script non-interactively: do **not** pipe it through
`2>&1` (PowerShell turns the harmless `share_plus` KGP warning into a
`NativeCommandError` and `$ErrorActionPreference = 'Stop'` aborts the Android
build), and keep `pubspec.yaml` **ASCII-only** (`-BumpBuild` rewrites the file
and mangles non-ASCII bytes).

## Architecture

```
main.dart      opens the DB and runs the monthly backup *before* the first frame,
               then overrides databaseProvider — no screen ever renders a
               "database not ready" state
core/          Money + Dates (format.dart), Period (period.dart), theme
data/          AppDatabase (schema + migrations), models, one repository per
               area, BackupService, ExportService
state/         Riverpod providers (providers.dart), sell-screen cart
widgets/       SectionCard, StatTile, AsyncBlock, hand-painted charts
screens/       one file per screen; HomeShell holds the five bottom-nav tabs
```

Data flows one way: screens read `FutureProvider`s → providers call a repository
→ repository runs SQL. Screens never touch `AppDatabase` directly and repositories
never import Flutter.

### Invariants — breaking any of these is a correctness bug, not a style choice

- **Money is an `int` of centavos.** Never a `double`, never in a model, a row,
  or a provider. `Money.format` / `Money.parse` in
  [core/format.dart](lib/core/format.dart) are the only conversion points.
- **Every sale, ledger entry and expense stores `day_key`** (local `yyyy-MM-dd`).
  All day/week/month grouping is `day_key BETWEEN ? AND ?` — string comparison,
  never timezone arithmetic. `Period.startKey` / `endKey` produce those bounds.
  The one exception is `ReportRepository.byHour`, which must divide `sold_at` to
  seconds and ask `strftime` for `localtime`.
- **`sale_items` snapshots `unit_price_centavos` and `unit_cost_centavos`.**
  Reports and corrections re-total from the snapshot; never join back to the live
  `products` row, or changing a price rewrites last month's profit.
- **The credit ledger is append-only.** Cancelling a sale or correcting a
  quantity inserts an adjusting `ledger_entries` row; it never edits or deletes
  the original. Customer balances are always summed from the ledger, never stored
  on the customer row.
- **Sales are voided, never deleted** (`voided = 1`), and every read filters
  `voided = 0` unless it explicitly asks otherwise.
- **`payment_type` reads through `PaymentTypeX.fromCode`,** which maps the legacy
  `'utang'` code to `PaymentType.credit`. Filtering credit in SQL needs
  `IN ('credit', 'utang')` — see `SalesRepository.list`.
- **Markup ≠ margin.** Markup is over cost (what the product form asks for),
  margin is over price (what every report shows). Never use one word for the
  other; the same product is 21.4% markup and 17.6% margin at ₱14/₱17.
- **Multi-table writes run in one `_db.transaction`.** A sale plus its lines plus
  its ledger charge is atomic — a half-written sale with an uncharged tab must be
  impossible.

### Riverpod conventions

- `databaseProvider` throws by default and is overridden in `main()`.
- Every read provider starts with `ref.watch(dataVersionProvider)`. After any
  write, call `ref.refreshData()` (extension in
  [state/providers.dart](lib/state/providers.dart)) — that single bump refreshes
  the dashboard, product list, reports and credit screen at once. There is no
  per-screen invalidation.
- Parameterised reads are `FutureProvider.family` keyed on `Period` or an int id,
  so anything used as a family key needs `==`/`hashCode` (see `SalesQuery`).
- Render async state with `AsyncBlock<T>` rather than repeating
  `value.when(...)`.

### UI conventions

- Colours come from `context.colors` (the `AppColors` `ThemeExtension` in
  [core/theme.dart](lib/core/theme.dart)), never from literals — both light and
  dark must stay legible.
- Build from the shared widgets in [widgets/common.dart](lib/widgets/common.dart)
  (`SectionCard`, `StatTile`, `PillTag`, `EmptyState`, `QtyStepper`,
  `AppSearchField`) and the hand-painted charts in
  [widgets/charts.dart](lib/widgets/charts.dart). No chart package.
- Interface text is English; product names stay Filipino. `PaymentType` carries
  both `label` and `localLabel` (`Credit` / `Utang`) for where the local word is
  what the store says.
- `analysis_options.yaml` enforces single quotes and bans `print`.

### Schema changes

Bump `AppDatabase.schemaVersion`, add a `from < N` block to `_upgrade`, and add a
migration test to the `migration` group in
[test/database_test.dart](test/database_test.dart) that builds the old schema on
disk and reopens it. Migrations must be lossless for anything still in use — an
existing store must never lose sales, products or credit. `DROP COLUMN` needs
SQLite 3.35+, which Android 12 and below do not have, so tolerate its failure
(the v3 step does).

### Dependency rule

Prefer pure-Dart packages. `file_picker` was removed and `excel`/`pdf` were
chosen because a plugin shipping its own Kotlin Gradle plugin is a build failure
waiting for the next AGP. Restore reads the app's own backup folder instead of
opening a system file browser. Before adding any dependency with a platform
channel, check it against the four build settings documented in README.md.

### Testing

Tests run against real SQLite in a temp directory — no mocks. `database_test.dart`
calls `AppDatabase.registerDesktopFactory()` once, then each test gets a fresh
`openAt(tempDir)`. Services that write files take a directory override as their
test seam (`appOwnedDirectory`'s `override`, `BackupService`'s root override).
`core_test.dart` covers the pure logic: centavo parsing, period boundaries,
markup/margin, `pdfSafe`, CSV escaping.

### Out of scope

Inventory/stock, undo on the sell screen, re-pricing a past sale, per-pack
pricing, product photos, barcode scanning, e-load, PIN lock. These are decisions,
not gaps — README.md explains each. Don't add them back without being asked.

## Agents

Talk to **[bentago-lead](.claude/agents/bentago-lead.md)** — it owns the request,
decides which specialists apply, and can run several on the same task (e.g. a
change touching a repository and a screen goes to `bentago-data` and
`bentago-ui` in parallel, then `bentago-invariants` reviews the result).

| Agent | Owns |
| --- | --- |
| `bentago-lead` | Entry point. Plans, delegates, fans out, reconciles the results. |
| `bentago-data` | Schema, migrations, repositories, models, transactions, centavo arithmetic. |
| `bentago-ui` | Screens, widgets, theme, navigation, Riverpod wiring in the UI. |
| `bentago-reports` | Report queries, `Period` math, Excel/PDF export, backup and restore. |
| `bentago-tests` | Writes and runs `flutter analyze` / `flutter test`, diagnoses failures. |
| `bentago-release` | `tool\release.ps1`, Windows/Android build traps, `dist/`, Inno Setup, CI. |
| `bentago-invariants` | Read-only review against the invariants above and the out-of-scope list. |
