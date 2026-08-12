# BentaGo

Sales tracker for a sari-sari store. One Android phone, one store, no account,
no internet, no monthly fee. All data lives in a single SQLite file on the
device.

Interface is in **English**. Product names stay Filipino, because that is what
is printed on the packet and what a customer asks for.

**No inventory tracking.** A product is a name, a price and optionally a cost.
The app never claims to know what is on the shelf, so nothing can drift out of
step with reality. Adding a product needs a **name and a price**; everything
else is optional.

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
suite passes (**61 tests**, `flutter test`).

Verified working: fresh-install seeding, the v1→v3 schema migrations against a
real database on disk, recording cash and credit sales, cancelling a sale with
the credit reversed, custom categories, period summaries for day/week/month, and
the automatic monthly backup firing on first launch.

Toolchain used: Flutter 3.44.9 / Dart 3.12.2 (`C:\src\flutter`), JDK 17,
Android SDK 36 (`C:\Android\sdk`), Visual Studio 2026 with the C++ desktop
workload, Inno Setup 6.7.

---

## Screens

| Tab | File | What it does |
| --- | --- | --- |
| **Sell** | [sell_screen.dart](lib/screens/sell_screen.dart) | Opens here. Tap products, pick Cash / Credit / GCash, `Done`. Undo via snackbar for 8 seconds. |
| **Dashboard** | [dashboard_screen.dart](lib/screens/dashboard_screen.dart) | Today's sales / profit / cash, 7-day chart, payment mix, best sellers, credit outstanding, backup age. |
| **Products** | [products_screen.dart](lib/screens/products_screen.dart) | The product register. Toggle top-right switches between a touch list and a table of prices and margins. |
| **Credit** | [credit_screen.dart](lib/screens/credit_screen.dart) | The *listahan*, biggest debt first. Per-customer ledger with payments. |
| **Reports** | [reports_screen.dart](lib/screens/reports_screen.dart) | Day / week / month, arrows to step back. Charts, best and slow movers, categories, expenses. |
| Records | [sales_table_screen.dart](lib/screens/sales_table_screen.dart) | Every transaction as a filterable, sortable table. Tap a row for its line items; cancel from there. |
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
  data/       SQLite schema, models, one repository per area, backup service
  state/      Riverpod providers, sell-screen cart
  widgets/    stat tiles, hand-painted charts, shared form pieces
  screens/    one file per screen
tool/         inspect_db.dart — dump a database's schema and row counts
```

Three decisions the rest of the code leans on:

- **Money is always an `int` of centavos.** Never a `double`. `Money.format`
  and `Money.parse` in [core/format.dart](lib/core/format.dart) are the only
  places that convert.
- **Every sale stores `day_key`** (local `yyyy-MM-dd`). Day / week / month
  grouping is a string comparison, so no report can be thrown off by a UTC
  offset.
- **`sale_items` snapshots unit price *and* unit cost.** Reports never join
  back to the live product price — otherwise raising a price would silently
  rewrite last month's profit.

## Reports vocabulary

Two numbers that are easy to conflate, kept deliberately separate:

- **Sales / revenue** — recognised when the sale happens, including credit.
- **Cash received** — cash and GCash sales, plus credit payments collected.

They differ in any store that runs a tab. **Profit** is revenue minus the cost
of what was sold; **Net profit** subtracts expenses too. Where products have no
cost price on file, the app labels the profit figure as an estimate rather than
presenting it as fact.

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

On Windows the same tree sits under `Documents\BentaGo\Backups\`.

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

## Things deliberately left out

- **Inventory / stock counts** — removed on request. No stock column, no
  reorder alerts, no stock-movement ledger. Cost prices stay, because they feed
  profit rather than stock.
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
