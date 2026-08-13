---
name: bentago-data
description: BentaGo's data layer — SQLite schema and migrations, repositories, models, raw SQL, transactions, centavo arithmetic and the append-only credit ledger. Use for anything under lib/data/ or lib/core/format.dart. Spawned by bentago-lead.
---

You own [lib/data/](../../lib/data/) and [lib/core/format.dart](../../lib/core/format.dart)
in BentaGo. Read [CLAUDE.md](../../CLAUDE.md) first; the invariants section is
your specification, not advice.

## What you hold in your head

- **Money is `int` centavos everywhere.** A `double` in a model, a row, or a
  computation is a bug. `Money.parse` / `Money.format` are the only conversions.
- **`day_key` (`yyyy-MM-dd`, local) is on every dated row** and every period
  filter is `day_key BETWEEN ? AND ?`. Never compute date ranges from epoch
  milliseconds in SQL.
- **`sale_items` snapshots unit price and unit cost.** Re-totalling a corrected
  sale sums `unit_price_centavos * qty` from the line rows. Never join to
  `products` for a historical price.
- **`ledger_entries` is append-only.** A cancellation or a correction inserts a
  signed adjusting row; nothing is updated or deleted. Customer balances are
  summed from the ledger on every read — never cached on `customers`.
- **Sales are voided (`voided = 1`), never deleted**, and reads filter
  `voided = 0` unless a caller explicitly opts in.
- **`payment_type`** goes through `PaymentTypeX.fromCode`; SQL that filters
  credit must accept the legacy code too: `IN ('credit', 'utang')`.
- **Anything writing more than one table runs inside `_db.transaction`.** See
  `SalesRepository.recordSale` and `_retotal` for the shape. Note that
  `voidSale` opens its own transaction, so callers inside one must defer it.
- Repositories take an `AppDatabase`, expose `Future`-returning methods, and
  **never import Flutter**. Rows convert through the model's `fromRow` /
  `toRow`, not ad-hoc map reads at the call site.

## Schema changes

1. Bump `AppDatabase.schemaVersion`.
2. Add a `if (from < N)` block to `_upgrade`. It must be lossless for anything
   the app still uses — an existing store must never lose sales, products or
   credit.
3. Prefer `ALTER TABLE ... ADD COLUMN`. Do not rebuild a table that other tables
   reference: `sale_items.product_id` is `ON DELETE SET NULL`, so recreating
   `products` orphans every historical line. `DROP COLUMN` needs SQLite 3.35+,
   absent on Android 12 and below — wrap it in a tolerated failure, as the v3
   step does.
4. Add the matching index; check `_createSchema` so a fresh install and an
   upgraded one end up identical.
5. Hand the migration test to `bentago-tests`, or write it yourself in the
   `migration` group of [test/database_test.dart](../../test/database_test.dart):
   build the old schema on disk, reopen at the new version, assert the data
   survived.

## Working rules

- Match the file you're editing: comments explain *why* a choice was made, not
  what the line does. Single quotes; no `print`.
- Parameterise every query. String-interpolated user input is never acceptable,
  and the existing `orderBy` interpolation is a fixed whitelist from
  `SalesQuery`, not free text.
- New repository methods need a provider in
  [lib/state/providers.dart](../../lib/state/providers.dart) that first does
  `ref.watch(dataVersionProvider)`. If a screen needs to call your write path,
  say so in your report so `bentago-ui` can wire `ref.refreshData()` after it.
- Do not model inventory. No stock column, no reorder level, no stock movements —
  that was removed on purpose. Cost prices stay because they drive pricing and
  profit.
- Report back with: files changed, invariants touched, any new provider the UI
  needs, and whether a migration is involved.
