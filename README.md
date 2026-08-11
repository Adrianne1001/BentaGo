# BentaGo

Sales tracker for a sari-sari store. One Android phone, one store, no account,
no internet, no monthly fee. All data lives in a single SQLite file on the
device.

Sold **by the piece only** — one product, one unit, no pack conversion.
Adding a product needs a **name and a price**; everything else is optional.

---

## Status: not yet compiled

Flutter is not installed on this machine, so this code has **never been run
through `dart analyze` or a build**. Treat the first `flutter analyze` as part
of setup — expect a handful of small fixes (a missing `const`, an import
ordering lint, possibly a package API that moved in a newer major version).
The schema, the queries and the screen logic are the parts worth reviewing
carefully; the compiler will find the rest.

Platform folders (`android/`, etc.) also don't exist yet — step 2 below
generates them.

---

## Setup

**1. Install Flutter** (3.29 or newer — the theme code uses `CardThemeData` and
`Color.withValues`, which are 3.29 / 3.27 APIs).

Easiest on Windows:

```powershell
winget install --id Google.Flutter
```

Then restart the terminal and confirm:

```powershell
flutter --version
flutter doctor
```

`flutter doctor` will tell you what's missing for Android builds — usually
Android Studio plus the command-line tools and an accepted licence
(`flutter doctor --android-licenses`).

**2. Generate the platform folders.** Run this *in this directory*. It creates
`android/` and leaves the existing `lib/` and `pubspec.yaml` alone:

```powershell
cd d:\Documents\Clients\Personal\BentaGo
git init
git add -A
git commit -m "BentaGo source before flutter create"
flutter create --project-name bentago --org ph.bentago --platforms=android,windows .
```

The `git init` first is worth the ten seconds — if `flutter create` overwrites
anything unexpected, `git diff` shows you exactly what and `git checkout` puts
it back.

**3. Fetch packages and check it compiles:**

```powershell
flutter pub get
flutter analyze
```

**4. Run it.** On a phone (USB debugging on) or an emulator:

```powershell
flutter devices
flutter run
```

Or on Windows desktop for fast iteration without a phone — this is what
`sqflite_common_ffi` is in the dependency list for:

```powershell
flutter run -d windows
```

---

## Release APK

```powershell
# One-time: create a signing key and KEEP IT SAFE.
keytool -genkey -v -keystore $env:USERPROFILE\bentago-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bentago
```

Create `android/key.properties` (already gitignored):

```properties
storePassword=<your password>
keyPassword=<your password>
keyAlias=bentago
storeFile=C:/Users/<you>/bentago-key.jks
```

Wire it into `android/app/build.gradle.kts` per the
[Flutter signing docs](https://docs.flutter.dev/deployment/android#signing-the-app),
then:

```powershell
flutter build apk --release
```

Output lands in `build\app\outputs\flutter-apk\app-release.apk`. Copy it to the
phone and open it (Android will ask permission to install from an unknown
source, once).

**Back up the keystore file and its passwords somewhere off this machine.** If
you lose it you cannot ever update the installed app — only uninstall and
reinstall, which deletes her data along with it.

---

## Screens

| Tab | File | What it does |
| --- | --- | --- |
| **Benta** | [sell_screen.dart](lib/screens/sell_screen.dart) | Opens here. Tap products, pick Cash / Utang / GCash, `Tapos`. Undo via snackbar for 8 seconds. |
| **Dashboard** | [dashboard_screen.dart](lib/screens/dashboard_screen.dart) | Today's benta / kita / cash, 7-day chart, payment mix, top sellers, low stock, backup age. |
| **Paninda** | [stock_screen.dart](lib/screens/stock_screen.dart) | Product register. Toggle top-right switches between a touch list and a full data table of prices and margins. |
| **Utang** | [utang_screen.dart](lib/screens/utang_screen.dart) | The listahan, biggest debt first. Per-customer ledger with payments. |
| **Ulat** | [reports_screen.dart](lib/screens/reports_screen.dart) | Day / week / month, arrows to step back. Charts, top and slow movers, categories, expenses. |
| Talaan | [sales_table_screen.dart](lib/screens/sales_table_screen.dart) | Every transaction as a filterable, sortable table. Tap a row for its line items; void from there. |
| Settings | [settings_screen.dart](lib/screens/settings_screen.dart) | Backup, restore, CSV share. |

## Code map

```
lib/
  core/       theme (light + dark), peso and date formatting, Period
  data/       SQLite schema, models, one repository per area, backup service
  state/      Riverpod providers, sell-screen cart
  widgets/    stat tiles, hand-painted charts, shared form pieces
  screens/    one file per screen
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

- **Benta / revenue** — recognised when the sale happens, including utang.
- **Cash na natanggap** — cash and GCash sales, plus utang payments collected.

They differ in any store that runs a tab. **Kita** is revenue minus the cost of
what was sold; **Natirang kita** subtracts expenses too. Where products have no
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
    bago-i-restore/   safety copy taken before each restore (keeps 3)
```

**Automatic** — one backup per calendar month, written on the first app launch
in that month. Deliberately not a background job: budget Android phones kill
scheduled work aggressively, and the app gets opened most days anyway.

**Each backup is two files** — the SQLite database (for restoring) and a CSV of
every sale line (for opening in Excel).

**The caveat, stated plainly:** Android deletes this folder when the app is
uninstalled, and it goes with the phone if the phone does. On-device backups
protect against a corrupted database or a bad restore — *not* against a lost
handset. The `I-share` button on each backup exists for that: once a month,
send it to herself on Messenger or Drive. The Settings screen says this in
Tagalog, and the dashboard turns the backup tile amber past seven days.

**Restore** validates the file is a BentaGo database, copies the current one
aside first, then replaces it. The app must be fully closed and reopened
afterwards — the in-memory handle still points at the replaced file.

---

## Things deliberately left out

- **Per-pack pricing** — removed as requested. `unit_label` is free text
  (`pc`, `sachet`, `bote`) but there is only ever one unit per product.
- **Product photos** — the emoji picker plus a colour-tinted initial covers
  recognition without an image dependency, storage growth, or camera
  permissions. Add `image_picker` later if she wants real photos.
- **Barcode scanning** — the `barcode` column and its lookup query exist, so
  adding `mobile_scanner` is a screen, not a migration.
- **E-load and GCash cash-in** — GCash exists as a *payment type*, but load
  sales have their own float-and-margin arithmetic and are not modelled.
- **PIN lock** — one phone, one person. Add it when a helper starts covering
  the window.

## First run

The database seeds ~30 common sari-sari products at zero stock, so the sell
screen works in the first minute instead of demanding an hour of data entry.
Edit or delete any of them in Paninda; the list is in
[data/seed_products.dart](lib/data/seed_products.dart).

Two things worth doing with your sister rather than for her: photograph the
shelf and enter her real stock together in one sitting, and watch her use it at
the window for an hour. Entering 80 products alone is the most common reason an
app like this gets abandoned in week two.

## Removing the desktop dependency

`sqflite_common_ffi` exists only so `flutter run -d windows` works. For the
production APK you can drop it:

1. Remove the line from `pubspec.yaml`.
2. In [data/app_database.dart](lib/data/app_database.dart), delete the
   `sqfliteFfiInit()` block in `open()` and its import.
