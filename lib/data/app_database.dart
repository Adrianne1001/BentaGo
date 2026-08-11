import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'seed_products.dart';

/// Everything lives in one SQLite file. There is no server, no sync and no
/// account -- one phone, one store, one database.
///
/// Two rules the schema depends on:
///   * money is always an INTEGER number of centavos, never a REAL;
///   * every sale stores `day_key` (local `yyyy-MM-dd`) so day / week / month
///     grouping is a plain string comparison instead of timezone arithmetic.
class AppDatabase {
  AppDatabase._(this.db, this.file);

  final Database db;
  final File file;

  static const String fileName = 'bentago.db';
  static const int schemaVersion = 1;

  static Future<Directory> dataDirectory() async {
    return getApplicationDocumentsDirectory();
  }

  static Future<String> resolvePath() async {
    final dir = await dataDirectory();
    return p.join(dir.path, fileName);
  }

  static Future<AppDatabase> open({bool seedIfEmpty = true}) async {
    // sqflite ships a native implementation on Android/iOS only. Registering
    // the FFI factory lets `flutter run -d windows` work for quick testing.
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await resolvePath();
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
      onUpgrade: (db, from, to) async {
        // Reserved for future migrations. Each step must be additive so an
        // existing store never loses records on update.
      },
    );

    return AppDatabase._(database, File(path));
  }

  Future<void> close() => db.close();

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    // Products. Only `name` and `price_centavos` are required -- everything
    // else may be left blank when adding a product in a hurry.
    // Sold by the piece only: one product, one unit, no pack conversion.
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
        stock          INTEGER NOT NULL DEFAULT 0,
        reorder_level  INTEGER NOT NULL DEFAULT 0,
        track_stock    INTEGER NOT NULL DEFAULT 1,
        archived       INTEGER NOT NULL DEFAULT 0,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_products_name ON products(name)');
    batch.execute(
      'CREATE INDEX idx_products_archived ON products(archived, name)',
    );

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
      CREATE TABLE stock_movements (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id    INTEGER NOT NULL
                        REFERENCES products(id) ON DELETE CASCADE,
        delta         INTEGER NOT NULL,
        reason        TEXT    NOT NULL,
        cost_centavos INTEGER NOT NULL DEFAULT 0,
        moved_at      INTEGER NOT NULL,
        day_key       TEXT    NOT NULL,
        note          TEXT
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_movements_product ON stock_movements(product_id, moved_at DESC)',
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
        'stock': 0,
        'reorder_level': 5,
        'track_stock': 1,
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
