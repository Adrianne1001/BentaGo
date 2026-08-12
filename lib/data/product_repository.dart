import 'package:sqflite/sqflite.dart';

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

  /// Categories are free text on the product row rather than their own table,
  /// so a custom one exists the moment a product uses it and disappears when
  /// the last product using it is gone. Nothing to manage or clean up.
  Future<List<String>> categoriesInUse() async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT category FROM products
      WHERE archived = 0 AND category IS NOT NULL AND TRIM(category) <> ''
      ORDER BY category COLLATE NOCASE ASC
    ''');
    return rows.map((r) => r['category'] as String).toList();
  }

  /// Category counts, for the manage-categories view.
  Future<Map<String, int>> categoryCounts() async {
    final rows = await _db.rawQuery('''
      SELECT category, COUNT(*) AS c FROM products
      WHERE archived = 0 AND category IS NOT NULL AND TRIM(category) <> ''
      GROUP BY category
      ORDER BY category COLLATE NOCASE ASC
    ''');
    return {
      for (final row in rows) row['category'] as String: (row['c'] as int?) ?? 0,
    };
  }

  /// Renames a category across every product carrying it.
  Future<int> renameCategory(String from, String to) async {
    final target = to.trim();
    if (target.isEmpty) return 0;
    return _db.update(
      'products',
      {'category': target, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'category = ?',
      whereArgs: [from],
    );
  }

  /// Clears a category from every product, leaving the products themselves.
  Future<int> deleteCategory(String category) async {
    return _db.update(
      'products',
      {'category': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  Future<int> insert(Product product) async {
    final row = product.toRow()..remove('id');
    return _db.insert('products', row);
  }

  Future<void> update(Product product) async {
    if (product.id == null) return;
    final row = product.toRow()
      ..remove('id')
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

  Future<int> countActive() async {
    final rows = await _db
        .rawQuery('SELECT COUNT(*) AS c FROM products WHERE archived = 0');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Products with no cost price on file. Profit reporting treats these as pure
  /// margin, so the reports screen uses this to say the figure is an estimate.
  Future<int> countWithoutCost() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE archived = 0 AND cost_centavos <= 0',
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
