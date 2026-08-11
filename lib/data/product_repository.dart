import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'app_database.dart';
import 'models.dart';

class ProductRepository {
  ProductRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  Future<List<Product>> all({
    bool includeArchived = false,
    String? search,
    String? category,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    if (!includeArchived) where.add('archived = 0');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR barcode = ? OR category LIKE ?)');
      final like = '%${search.trim()}%';
      args
        ..add(like)
        ..add(search.trim())
        ..add(like);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }

    final rows = await _db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Product.fromRow).toList();
  }

  Future<Product?> byId(int id) async {
    final rows =
        await _db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Product.fromRow(rows.first);
  }

  Future<Product?> byBarcode(String barcode) async {
    final rows = await _db.query(
      'products',
      where: 'barcode = ? AND archived = 0',
      whereArgs: [barcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromRow(rows.first);
  }

  Future<List<String>> categoriesInUse() async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT category FROM products
      WHERE archived = 0 AND category IS NOT NULL AND TRIM(category) <> ''
      ORDER BY category COLLATE NOCASE ASC
    ''');
    return rows.map((r) => r['category'] as String).toList();
  }

  /// Returns the new row id. Opening stock, when given, is also written as a
  /// stock movement so the ledger of where stock came from stays complete.
  Future<int> insert(Product product, {int openingStock = 0}) async {
    return _db.transaction((txn) async {
      final row = product.toRow()..remove('id');
      row['stock'] = openingStock;
      final id = await txn.insert('products', row);

      if (openingStock != 0) {
        final now = DateTime.now();
        await txn.insert('stock_movements', {
          'product_id': id,
          'delta': openingStock,
          'reason': StockReason.restock.code,
          'cost_centavos': product.costCentavos * openingStock,
          'moved_at': now.millisecondsSinceEpoch,
          'day_key': Dates.dayKey(now),
          'note': 'Simulang stock',
        });
      }
      return id;
    });
  }

  /// Updates the profile fields only. Stock is never edited here -- it moves
  /// through [adjustStock] so every change has a reason attached to it.
  Future<void> update(Product product) async {
    if (product.id == null) return;
    final row = product.toRow()
      ..remove('id')
      ..remove('stock')
      ..remove('created_at');
    await _db.update(
      'products',
      row,
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> setArchived(int id, bool archived) async {
    await _db.update(
      'products',
      {
        'archived': archived ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard delete. Sale history survives because `sale_items` snapshots the
  /// product name and prices and its foreign key is ON DELETE SET NULL.
  Future<void> delete(int id) async {
    await _db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock({
    required int productId,
    required int delta,
    required StockReason reason,
    int costCentavos = 0,
    String? note,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? _db;
    final now = DateTime.now();

    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
      [delta, now.millisecondsSinceEpoch, productId],
    );
    await db.insert('stock_movements', {
      'product_id': productId,
      'delta': delta,
      'reason': reason.code,
      'cost_centavos': costCentavos,
      'moved_at': now.millisecondsSinceEpoch,
      'day_key': Dates.dayKey(now),
      'note': note,
    });
  }

  /// A delivery: adds stock and, when a new unit cost is supplied, updates the
  /// product's cost basis so margin reporting follows the supplier's price.
  Future<void> receiveDelivery({
    required int productId,
    required int qty,
    int? newUnitCostCentavos,
    String? note,
  }) async {
    await _db.transaction((txn) async {
      if (newUnitCostCentavos != null && newUnitCostCentavos > 0) {
        await txn.update(
          'products',
          {
            'cost_centavos': newUnitCostCentavos,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
      await adjustStock(
        productId: productId,
        delta: qty,
        reason: StockReason.restock,
        costCentavos: (newUnitCostCentavos ?? 0) * qty,
        note: note,
        executor: txn,
      );
    });
  }

  Future<List<Product>> lowStock() async {
    final rows = await _db.rawQuery('''
      SELECT * FROM products
      WHERE archived = 0 AND track_stock = 1
        AND reorder_level > 0 AND stock <= reorder_level
      ORDER BY (stock - reorder_level) ASC, name COLLATE NOCASE ASC
    ''');
    return rows.map(Product.fromRow).toList();
  }

  Future<List<StockMovement>> movements({int? productId, int limit = 200}) async {
    final rows = await _db.rawQuery('''
      SELECT m.*, p.name AS product_name
      FROM stock_movements m
      LEFT JOIN products p ON p.id = m.product_id
      ${productId != null ? 'WHERE m.product_id = ?' : ''}
      ORDER BY m.moved_at DESC
      LIMIT ?
    ''', [if (productId != null) productId, limit]);
    return rows.map(StockMovement.fromRow).toList();
  }

  /// Total peso value of everything on the shelf, at cost.
  Future<int> inventoryValueCentavos() async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(stock * cost_centavos), 0) AS value
      FROM products WHERE archived = 0 AND track_stock = 1 AND stock > 0
    ''');
    return (rows.first['value'] as int?) ?? 0;
  }

  Future<int> countActive() async {
    final rows = await _db
        .rawQuery('SELECT COUNT(*) AS c FROM products WHERE archived = 0');
    return (rows.first['c'] as int?) ?? 0;
  }
}
