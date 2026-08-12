import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
// Narrowed to the two desktop-only symbols. The ffi package re-exports all of
// sqflite, and importing it wholesale would make the sqflite import above look
// redundant -- then deleting the ffi dependency (see README) would break this
// file rather than just the one block that uses it.
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import 'seed_products.dart';

/// Everything lives in one SQLite file. There is no server, no sync and no
/// account -- one phone, one store, one database.
///
/// Two rules the schema depends on:
///   * money is always an INTEGER number of centavos, never a REAL;
///   * every sale stores `day_key` (local `yyyy-MM-dd`) so day / week / month
///     grouping is a plain string comparison instead of timezone arithmetic.
///
/// Inventory is deliberately not modelled. A product is a name, a price and
/// optionally a cost -- there are no stock counts, so nothing can drift out of
/// step with the shelf.
class AppDatabase {
  AppDatabase._(this.db, this.file);

  final Database db;
  final File file;

  static const String fileName = 'bentago.db';

  /// 2 added `products.ever_stocked`.
  /// 3 removed inventory tracking altogether: the four stock columns and the
  ///   `stock_movements` table.
  static const int schemaVersion = 3;

  static Future<Directory> dataDirectory() async {
    return getApplicationDocumentsDirectory();
  }

  static Future<String> resolvePath() async {
    final dir = await dataDirectory();
    return p.join(dir.path, fileName);
  }

  /// Registers the FFI factory on desktop. sqflite ships a native
  /// implementation for Android and iOS only, so this is what lets
  /// `flutter run -d windows` and `flutter test` touch a real database.
  static void registerDesktopFactory() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<AppDatabase> open({bool seedIfEmpty = true}) async {
    registerDesktopFactory();
    return openAt(await resolvePath(), seedIfEmpty: seedIfEmpty);
  }

  /// Opens the database at an explicit path. Separated from [open] so tests can
  /// work against a temp directory without needing path_provider's platform
  /// bindings.
  static Future<AppDatabase> openAt(
    String path, {
    bool seedIfEmpty = true,
  }) async {
    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        if (seedIfEmpty) await _seed(db);
      },
      onUpgrade: _upgrade,
    );

    return AppDatabase._(database, File(path));
  }

  Future<void> close() => db.close();

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    // Products. Only `name` and `price_centavos` are required -- everything
    // else may be left blank when adding a product in a hurry.
    // Sold by the piece only: one product, one unit, no pack conversion.
    // `category` is free text, so a new one can be typed at any time.
    batch.execute('''
      CREATE TABLE products (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        name           TEXT    NOT NULL,
        price_centavos INTEGER NOT NULL,
        cost_centavos  INTEGER NOT NULL DEFAULT 0,
        description    TEXT,
        category       TEXT,
        emoji          TEXT,
        barcode        TEXT,
        unit_label     TEXT    NOT NULL DEFAULT 'pc',
        archived       INTEGER NOT NULL DEFAULT 0,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_products_name ON products(name)');
    batch.execute(
      'CREATE INDEX idx_products_archived ON products(archived, name)',
    );
    batch.execute('CREATE INDEX idx_products_category ON products(category)');

    batch.execute('''
      CREATE TABLE customers (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL,
        phone      TEXT,
        note       TEXT,
        archived   INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE sales (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        sold_at        INTEGER NOT NULL,
        day_key        TEXT    NOT NULL,
        total_centavos INTEGER NOT NULL,
        cost_centavos  INTEGER NOT NULL DEFAULT 0,
        payment_type   TEXT    NOT NULL,
        customer_id    INTEGER REFERENCES customers(id) ON DELETE SET NULL,
        note           TEXT,
        voided         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('CREATE INDEX idx_sales_day ON sales(day_key, voided)');
    batch.execute('CREATE INDEX idx_sales_time ON sales(sold_at DESC)');
    batch.execute('CREATE INDEX idx_sales_customer ON sales(customer_id)');

    // Unit price and cost are snapshotted here. Reports must never join back
    // to the live product price, or changing a price silently rewrites history.
    batch.execute('''
      CREATE TABLE sale_items (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id             INTEGER NOT NULL
                              REFERENCES sales(id) ON DELETE CASCADE,
        product_id          INTEGER REFERENCES products(id) ON DELETE SET NULL,
        product_name        TEXT    NOT NULL,
        qty                 INTEGER NOT NULL,
        unit_price_centavos INTEGER NOT NULL,
        unit_cost_centavos  INTEGER NOT NULL DEFAULT 0,
        line_total_centavos INTEGER NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_items_sale ON sale_items(sale_id)');
    batch.execute('CREATE INDEX idx_items_product ON sale_items(product_id)');

    // Append-only. A correction is a new reversing row, never an edit.
    batch.execute('''
      CREATE TABLE ledger_entries (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id     INTEGER NOT NULL
                          REFERENCES customers(id) ON DELETE CASCADE,
        sale_id         INTEGER REFERENCES sales(id) ON DELETE SET NULL,
        amount_centavos INTEGER NOT NULL,
        entered_at      INTEGER NOT NULL,
        day_key         TEXT    NOT NULL,
        note            TEXT
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_ledger_customer ON ledger_entries(customer_id, entered_at DESC)',
    );

    batch.execute('''
      CREATE TABLE expenses (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        amount_centavos INTEGER NOT NULL,
        category        TEXT    NOT NULL,
        spent_at        INTEGER NOT NULL,
        day_key         TEXT    NOT NULL,
        note            TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_expenses_day ON expenses(day_key)');

    batch.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
  }

  /// Each step is additive or subtractive-but-lossless for anything the app
  /// still uses, so an existing store never loses sales, products or credit.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN ever_stocked INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (from < 3) {
      // Inventory tracking removed. DROP COLUMN keeps the table's identity, so
      // sale_items' foreign key to products(id) is untouched -- rebuilding the
      // table instead would fire ON DELETE SET NULL and orphan every line item.
      //
      // DROP COLUMN needs SQLite 3.35+. Android's bundled SQLite is older than
      // that on Android 12 and below, so a failure here is tolerated: the
      // columns simply stay behind, unread and harmless. A fresh install never
      // takes this path at all.
      for (final column in const [
        'stock',
        'reorder_level',
        'track_stock',
        'ever_stocked',
      ]) {
        try {
          await db.execute('ALTER TABLE products DROP COLUMN $column');
        } on Object {
          // Column absent, indexed, or unsupported on this SQLite build.
        }
      }
      await db.execute('DROP TABLE IF EXISTS stock_movements');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_category '
        'ON products(category)',
      );
    }
  }

  static Future<void> _seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final item in seedProducts) {
      batch.insert('products', {
        'name': item.name,
        'price_centavos': item.priceCentavos,
        'cost_centavos': item.costCentavos,
        'category': item.category,
        'emoji': item.emoji,
        'unit_label': 'pc',
        'archived': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  // --- settings key/value -------------------------------------------------

  Future<String?> getSetting(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
