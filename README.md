# BentaGo

Sales tracker for a sari-sari store. One Android phone, one store, no account,
no internet, no monthly fee. All data lives in a single SQLite file on the
device.

Interface is in **English**. Product names stay Filipino, because that is what
is printed on the packet and what a customer asks for.

**No inventory tracking.** A product is a name, a cost and a price. The app
never claims to know what is on the shelf, so nothing can drift out of step with
reality.

**Prices are worked out, not typed.** Adding a product asks for a **name, a cost
per piece and a markup**, in that order, and fills in the selling price. The
pencil beside the price hands control back when a round number is wanted, and
then the markup follows the price instead of driving it.

---

## Install

Ready-to-install files are in [dist/](dist/):

| File | For |
| --- | --- |
| `BentaGo-Setup-1.0.0.exe` | **Windows** — installs for the current user, no admin prompt |
| `BentaGo-1.0.0-arm64.apk` | **Android**, any phone from roughly 2016 on. Smallest. Use this one. |
| `BentaGo-1.0.0-arm32.apk` | Older 32-bit Android phones |
| `BentaGo-1.0.0-universal.apk` | Works on any phone, three times the size. Only if the others refuse to install. |

**Installing the APK:** copy it to the phone, tap it, and allow "install from
unknown sources" when Android asks. That prompt appears once.

Unsure which APK? Install `arm64`. If Android says the package is not
compatible, use `arm32`.

## Status

Builds and runs on Windows and Android. `flutter analyze` is clean and the test
suite passes (**114 tests**, `flutter test`).

Verified working: fresh-install seeding, the v1→v3 schema migrations against a
real database on disk, recording cash and credit sales, cancelling a sale with
the credit reversed, correcting a line quantity with the customer's tab moved to
match, custom categories, period summaries for day/week/month/quarter/year,
Excel and PDF report export read back from the written file, and the automatic
monthly backup firing on first launch.

Toolchain used: Flutter 3.44.9 / Dart 3.12.2 (`C:\src\flutter`), JDK 17,
Android SDK 36 (`C:\Android\sdk`), Visual Studio 2026 with the C++ desktop
workload, Inno Setup 6.7.

---

## Screens

| Tab | File | What it does |
| --- | --- | --- |
| **Sell** | [sell_screen.dart](lib/screens/sell_screen.dart) | Opens here. Tap products, pick Cash / Credit / GCash, `Done`. Confirms and moves on — corrections happen in Records. |
| **Dashboard** | [dashboard_screen.dart](lib/screens/dashboard_screen.dart) | Today's sales / profit / cash, 7-day chart, payment mix, best sellers, credit outstanding, backup age. |
| **Products** | [products_screen.dart](lib/screens/products_screen.dart) | The product register. Toggle top-right switches between a touch list and a table of prices and margins. |
| **Credit** | [credit_screen.dart](lib/screens/credit_screen.dart) | The *listahan*, biggest debt first. Per-customer ledger with payments. |
| **Reports** | [reports_screen.dart](lib/screens/reports_screen.dart) | Day / week / month, arrows to step back. Charts, best and slow movers, categories, expenses. Share icon exports. |
| Records | [sales_table_screen.dart](lib/screens/sales_table_screen.dart) | Every transaction as a filterable, sortable table. Tap a row for its line items, then a line to fix its quantity or take it off; cancel the whole sale from there too. |
| Export | [export_report_screen.dart](lib/screens/export_report_screen.dart) | Pick a range and a file type, see the totals before writing, share the file. |
| Categories | [category_manager.dart](lib/screens/category_manager.dart) | Rename or remove categories. |
| Settings | [settings_screen.dart](lib/screens/settings_screen.dart) | Backup, restore, CSV share. |

## Categories

Categories are **free text on the product row**, not their own table. So:

- a new one is created by typing it — Products → a product → *More details* →
  **New** beside Category;
- it exists the moment a product carries it, and disappears when the last
  product using it is gone;
- renaming updates every product carrying it at once;
- removing a category clears the field and **keeps the products**.

Nothing to manage, migrate, or clean up. The seeded products ship with English
categories (Food, Snacks, Drinks, Coffee, Milk, Candy, Toiletries, Laundry,
Fresh, Other).

## Code map

```
lib/
  core/       theme (light + dark), peso and date formatting, Period
  data/       SQLite schema, models, one repository per area,
              backup service, report export (xlsx + pdf)
  state/      Riverpod providers, sell-screen cart
  widgets/    stat tiles, hand-painted charts, shared form pieces
  screens/    one file per screen
tool/         inspect_db.dart — dump a database's schema and row counts
```

Four decisions the rest of the code leans on:

- **Money is always an `int` of centavos.** Never a `double`. `Money.format`
  and `Money.parse` in [core/format.dart](lib/core/format.dart) are the only
  places that convert.
- **Every sale stores `day_key`** (local `yyyy-MM-dd`). Day / week / month
  grouping is a string comparison, so no report can be thrown off by a UTC
  offset.
- **`sale_items` snapshots unit price *and* unit cost.** Reports never join
  back to the live product price — otherwise raising a price would silently
  rewrite last month's profit. Correcting a past sale's quantity re-totals it
  from that snapshot too, so a price change today cannot reach backwards.
- **The ledger is append-only.** Cancelling a sale or correcting its quantity
  writes an adjusting entry rather than editing or deleting the original, so a
  customer's tab always reads as a list of things that happened.

## Reports vocabulary

Two numbers that are easy to conflate, kept deliberately separate:

- **Sales / revenue** — recognised when the sale happens, including credit.
- **Cash received** — cash and GCash sales, plus credit payments collected.

They differ in any store that runs a tab. **Profit** is revenue minus the cost
of what was sold; **Net profit** subtracts expenses too. Where products have no
cost price on file, the app labels the profit figure as an estimate rather than
presenting it as fact.

**Markup and margin are not the same number**, and the app never uses one word
for both:

- **Markup** — profit over the **cost**. What the product form asks for, because
  it is how buying works: paid ₱14, add 20%, sell at ₱16.80.
- **Margin** — profit over the **price**. What every report shows, because it is
  the figure that composes with revenue: 20% margin on ₱1,000 of sales is ₱200.

The same product is a 21.4% markup and a 17.6% margin at ₱14 cost / ₱17 price.
The product form prints both under the price so the two can never be read as one.

---

## Reports out of the app

Reports → the share icon. Two choices and a button:

1. **What to cover** — `Day`, `Month`, `Quarter`, `Year` or `Start–end`, then the
   arrows step through them. Picking the size first and stepping second means any
   month or quarter is two taps and no date picker; `Start–end` opens one for an
   arbitrary span.
2. **File type** — **Excel** (`.xlsx`) or **PDF**.

Before anything is written the screen shows the gross sales, profit, line count
and transaction count for the chosen range, so an empty month is obvious *before*
the file is opened rather than after.

The report is a **flat table of every line sold** — one row per product per sale,
not one row per transaction — with gross sales and profit per line, under the
period and the two totals. Cancelled sales and lines taken off a sale are absent
entirely. Files land in `BentaGo/Reports/` next to the backups and the share
sheet opens on them.

In the Excel file, money is written as **numbers rather than text**, so the sheet
can be re-totalled, sorted and pivoted. That is the whole reason it exists
alongside the CSV the backup already writes.

Two constraints worth knowing, both from the PDF writer having only the 14
standard PDF fonts:

- Figures carry **no peso sign** — U+20B1 has no glyph in WinAnsi — so the money
  columns are plain numbers under a `PHP` heading.
- Text is folded to ASCII on the way in (`pdfSafe` in
  [export_service.dart](lib/data/export_service.dart)): an en dash becomes a
  hyphen, curly quotes straighten, and anything past Latin-1 in a product name
  becomes `?`. Without it the writer drops the character silently. Embedding a
  Unicode font is the alternative, at roughly half a megabyte of APK for a
  handful of characters that have fine stand-ins.

---

## Backups

**Location** — inside the app's own storage, reachable from any file manager,
no permission prompt:

```
Android/data/ph.bentago.bentago/files/BentaGo/Backups/
    monthly/          bentago-2026-08.db  + .csv     (keeps 12)
    manual/           bentago-manual-20260811-143022.db  + .csv  (keeps 10)
    before-restore/   safety copy taken before each restore (keeps 3)
```

On Windows the same tree sits under `Documents\BentaGo\Backups\`. Exported
reports go to `BentaGo/Reports/` beside it, and are not pruned — they are
generated on demand, not on a schedule.

**Automatic** — one backup per calendar month, written on the first app launch
in that month. Deliberately not a background job: budget Android phones kill
scheduled work aggressively, and the app gets opened most days anyway.

**Each backup is two files** — the SQLite database (for restoring) and a CSV of
every sale line (for opening in Excel).

**The caveat, stated plainly:** Android deletes this folder when the app is
uninstalled, and it goes with the phone if the phone does. On-device backups
protect against a corrupted database or a bad restore — *not* against a lost
handset. The `Share` button on each backup exists for that: once a month, send
it to herself on Messenger or Drive. The Settings screen says so, and the
dashboard turns the backup tile amber past seven days.

**Restore** offers a list of the backups it finds on the device rather than a
system file browser — friendlier for a non-technical user, and it removes a
dependency that breaks under AGP 9 (see below). To restore a backup from
somewhere else, copy its `.db` into the folder Settings displays and it appears
in the list. Restore validates the file is a BentaGo database, copies the
current one aside first, then replaces it. The app must be fully closed and
reopened afterwards — the in-memory handle still points at the replaced file.

---

## Building

**After any code change, refresh the shipped files with one command:**

```powershell
powershell -ExecutionPolicy Bypass -File tool\release.ps1
```

That gates on `flutter analyze` and `flutter test` and **refuses to build if
either fails** — a broken build sitting in `dist/` looking current is worse than
an obviously stale one. Then it clears the old artifacts, builds Windows and
Android (sequentially: they share `build/`, and running them together corrupts
the Kotlin incremental cache), compiles the installer, stages everything into
`dist/`, and verifies the APK signature. Roughly five minutes.

Two traps when running that script from somewhere other than an interactive
prompt:

- **Do not pipe it through `2>&1`.** Windows PowerShell wraps a native command's
  stderr in error records, so the harmless `share_plus` KGP warning below becomes
  a `NativeCommandError`, and `$ErrorActionPreference = 'Stop'` kills the script
  in the middle of the Android build. Nothing has actually failed.
- **Keep `pubspec.yaml` ASCII-only.** `-BumpBuild` rewrites the whole file, and
  the read/write round trip mangles non-ASCII bytes — a `₱` in a comment comes
  back as `â‚±`.

Add `-BumpBuild` to increment the `+N` build number in `pubspec.yaml` first.
Android needs an increasing build number only to *publish* an update; installing
a rebuilt APK with the same number over an existing install works fine.

The individual steps, if ever needed by hand:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.0.0 windows\installer\bentago.iss
flutter build apk --release --split-per-abi
flutter build apk --release
```

Windows desktop needs Visual Studio with the **Desktop development with C++**
workload, and **Developer Mode** on (Settings → System → For developers) —
Flutter creates symlinks in the plugin build directories and Windows only allows
that for admins or with Developer Mode enabled.

### Release signing

`android/key.properties` (gitignored) points at the keystore. When it is absent
the release build falls back to the debug key instead of failing, so a fresh
clone still builds.

**Back up the keystore file and its password somewhere off this machine.**
Losing either means you can never update the installed app — only uninstall and
reinstall, which deletes the store's data along with it.

### Four build settings that are not decoration

Each of these was a build failure, not a preference:

- **`kotlin.incremental=false`** in `android/gradle.properties` — Kotlin's
  incremental compiler could not close its own cache files on this machine and
  failed `:share_plus:compileReleaseKotlin` every time. Release builds are full
  rebuilds anyway.
- **The `compileSdk = 36` override** in `android/build.gradle.kts` — plugins pin
  their own compileSdk and some lag behind what their transitive dependencies
  require ("is currently compiled against android-34"). It is registered
  *before* the `evaluationDependsOn(":app")` block, because `afterEvaluate` on
  an already-evaluated project is an error.
- **`-dontwarn com.google.android.play.core.**`** in
  [proguard-rules.pro](android/app/proguard-rules.pro) — the Flutter engine
  references Play Core for deferred components, which this single-APK app never
  uses, so R8 was failing on legitimately absent classes.
- **No `file_picker` dependency.** From AGP 9 it stops applying the Kotlin
  Gradle plugin and relies on AGP's built-in Kotlin, which the Flutter template
  disables — so its Kotlin never compiled and the build died at
  `GeneratedPluginRegistrant`. Restore reads the app's own backup folder
  instead, which is better UX regardless.

### Known future issue

`flutter build apk` warns that `share_plus` applies the Kotlin Gradle plugin and
that a future Flutter will refuse to build such plugins. Nothing to do today;
when that lands, upgrade share_plus to a built-in-Kotlin version.

---

## The demo video

A narrated walkthrough of the Android app builds itself from one command:

```powershell
powershell -ExecutionPolicy Bypass -File tool\demo\setup.ps1      # once, ~1.5 GB
powershell -ExecutionPolicy Bypass -File tool\demo\make-demo.ps1  # ~12 min
```

That boots an emulator, drives the app through twelve scripted beats, records it,
speaks the narration, and renders `dist\BentaGo-Demo-<version>.mp4` — 1920x1080,
the phone screen inset in a bezel with captions and a title card. No video editor
and no manual alignment: the narration is synthesised *first*, and the app is
told to hold each beat for exactly as long as its voice clip runs.

Nothing about it ships in the app. Its one hook is `DemoSeeder.reset()`, which
writes six weeks of fixed demo trading and is guarded by a
`bool.fromEnvironment` constant, so a normal build tree-shakes it away.

Edit the words in [tool/demo/narration.json](tool/demo/narration.json), the
actions in [integration_test/demo_flow.dart](integration_test/demo_flow.dart),
and see [tool/demo/README.md](tool/demo/README.md) for how the two stay in sync.

---

## Things deliberately left out

- **Inventory / stock counts** — removed on request. No stock column, no
  reorder alerts, no stock-movement ledger. Cost prices stay, and are now
  required, because they feed pricing and profit rather than stock.
- **Undo on the sell screen** — removed on request. A snackbar action sitting
  over the product grid is one mis-tap away from silently reversing a sale that
  was correct, and the window closes before anyone notices. Corrections live in
  Records, where the sale can be read back before it is changed.
- **Editing what a past sale charged** — a line's quantity can be fixed and a
  line can be taken off, but the price it sold at is fixed. A sale that can be
  re-priced after the fact is a sale whose history cannot be trusted.
- **Per-pack pricing** — `unit_label` is free text (`pc`, `sachet`, `bote`) but
  there is only ever one unit per product.
- **Product photos** — the emoji picker plus a colour-tinted initial covers
  recognition without an image dependency, storage growth, or camera
  permissions.
- **Barcode scanning** — the `barcode` column and its lookup query exist, so
  adding a scanner is a screen, not a migration.
- **E-load and GCash cash-in** — GCash exists as a *payment type*, but load
  sales have their own float-and-margin arithmetic and are not modelled.
- **PIN lock** — one phone, one person.

## First run

The database seeds ~32 common sari-sari products, so the sell screen works in
the first minute instead of demanding an hour of data entry. Edit or delete any
of them in Products; the list is in
[data/seed_products.dart](lib/data/seed_products.dart).

An existing database keeps whatever categories it already had — the seed only
applies to a fresh install. Rename them under Products → the tag icon.
