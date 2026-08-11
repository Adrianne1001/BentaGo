import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../core/period.dart';
import 'app_database.dart';
import 'models.dart';

/// One line of the sell screen's running basket.
class CartLine {
  const CartLine({required this.product, required this.qty});

  final Product product;
  final int qty;

  int get lineTotalCentavos => product.priceCentavos * qty;
  int get lineCostCentavos => product.costCentavos * qty;

  CartLine withQty(int next) => CartLine(product: product, qty: next);
}

class SalesRepository {
  SalesRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  /// Records a sale, decrements stock for every tracked line, and -- when the
  /// sale is on credit -- adds the matching charge to the customer's ledger.
  /// All of it in one transaction, so a half-written sale is impossible.
  Future<int> recordSale({
    required List<CartLine> lines,
    required PaymentType paymentType,
    int? customerId,
    String? note,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Cannot record a sale with no items.');
    }
    if (paymentType == PaymentType.utang && customerId == null) {
      throw ArgumentError('An utang sale needs a customer.');
    }

    final now = DateTime.now();
    final total =
        lines.fold<int>(0, (sum, line) => sum + line.lineTotalCentavos);
    final cost =
        lines.fold<int>(0, (sum, line) => sum + line.lineCostCentavos);

    return _db.transaction((txn) async {
      final saleId = await txn.insert('sales', {
        'sold_at': now.millisecondsSinceEpoch,
        'day_key': Dates.dayKey(now),
        'total_centavos': total,
        'cost_centavos': cost,
        'payment_type': paymentType.code,
        'customer_id': customerId,
        'note': note,
        'voided': 0,
      });

      for (final line in lines) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': line.product.id,
          'product_name': line.product.name,
          'qty': line.qty,
          'unit_price_centavos': line.product.priceCentavos,
          'unit_cost_centavos': line.product.costCentavos,
          'line_total_centavos': line.lineTotalCentavos,
        });

        if (line.product.trackStock && line.product.id != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ?, updated_at = ? WHERE id = ?',
            [line.qty, now.millisecondsSinceEpoch, line.product.id],
          );
          await txn.insert('stock_movements', {
            'product_id': line.product.id,
            'delta': -line.qty,
            'reason': StockReason.sale.code,
            'cost_centavos': line.lineCostCentavos,
            'moved_at': now.millisecondsSinceEpoch,
            'day_key': Dates.dayKey(now),
            'note': 'Benta #$saleId',
          });
        }
      }

      if (paymentType == PaymentType.utang && customerId != null) {
        await txn.insert('ledger_entries', {
          'customer_id': customerId,
          'sale_id': saleId,
          'amount_centavos': total,
          'entered_at': now.millisecondsSinceEpoch,
          'day_key': Dates.dayKey(now),
          'note': 'Benta #$saleId',
        });
      }

      return saleId;
    });
  }

  /// Reverses a sale: puts the stock back, cancels any utang charge, and marks
  /// the row voided rather than deleting it, so the day's history stays honest.
  Future<void> voidSale(int saleId) async {
    final now = DateTime.now();

    await _db.transaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        where: 'id = ? AND voided = 0',
        whereArgs: [saleId],
        limit: 1,
      );
      if (saleRows.isEmpty) return;
      final sale = saleRows.first;

      final items = await txn
          .query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);

      for (final item in items) {
        final productId = item['product_id'] as int?;
        final qty = (item['qty'] as int?) ?? 0;
        if (productId == null || qty == 0) continue;

        final productRows = await txn.query(
          'products',
          columns: ['track_stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) continue;
        if (((productRows.first['track_stock'] as int?) ?? 1) != 1) continue;

        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
          [qty, now.millisecondsSinceEpoch, productId],
        );
        await txn.insert('stock_movements', {
          'product_id': productId,
          'delta': qty,
          'reason': StockReason.correction.code,
          'cost_centavos': 0,
          'moved_at': now.millisecondsSinceEpoch,
          'day_key': Dates.dayKey(now),
          'note': 'Binawi ang benta #$saleId',
        });
      }

      final customerId = sale['customer_id'] as int?;
      final wasUtang = (sale['payment_type'] as String?) == 'utang';
      if (wasUtang && customerId != null) {
        // Reversing entry, not a delete -- the ledger is append-only.
        await txn.insert('ledger_entries', {
          'customer_id': customerId,
          'sale_id': saleId,
          'amount_centavos': -((sale['total_centavos'] as int?) ?? 0),
          'entered_at': now.millisecondsSinceEpoch,
          'day_key': Dates.dayKey(now),
          'note': 'Binawi ang benta #$saleId',
        });
      }

      await txn.update(
        'sales',
        {'voided': 1},
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  Future<Sale?> byId(int id) async {
    final rows = await _db.rawQuery('''
      SELECT s.*, c.name AS customer_name,
             (SELECT COALESCE(SUM(qty), 0) FROM sale_items WHERE sale_id = s.id)
               AS item_count
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;

    final itemRows = await _db
        .query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id');
    return Sale.fromRow(
      rows.first,
      items: itemRows.map(SaleItem.fromRow).toList(),
    );
  }

  /// Backing query for the sales data table. Filters compose, and the caller
  /// pages through with [limit] / [offset].
  Future<List<Sale>> list({
    Period? period,
    PaymentType? paymentType,
    int? customerId,
    String? search,
    bool includeVoided = false,
    String orderBy = 'sold_at DESC',
    int limit = 100,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    if (!includeVoided) where.add('s.voided = 0');
    if (period != null) {
      where.add('s.day_key BETWEEN ? AND ?');
      args
        ..add(period.startKey)
        ..add(period.endKey);
    }
    if (paymentType != null) {
      where.add('s.payment_type = ?');
      args.add(paymentType.code);
    }
    if (customerId != null) {
      where.add('s.customer_id = ?');
      args.add(customerId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('''(
        c.name LIKE ?
        OR s.note LIKE ?
        OR CAST(s.id AS TEXT) = ?
        OR EXISTS (
          SELECT 1 FROM sale_items i
          WHERE i.sale_id = s.id AND i.product_name LIKE ?
        )
      )''');
      final like = '%${search.trim()}%';
      args
        ..add(like)
        ..add(like)
        ..add(search.trim())
        ..add(like);
    }

    final rows = await _db.rawQuery('''
      SELECT s.*, c.name AS customer_name,
             (SELECT COALESCE(SUM(qty), 0) FROM sale_items WHERE sale_id = s.id)
               AS item_count
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.$orderBy
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);

    return rows.map((r) => Sale.fromRow(r)).toList();
  }

  Future<int> count({Period? period, bool includeVoided = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeVoided) where.add('voided = 0');
    if (period != null) {
      where.add('day_key BETWEEN ? AND ?');
      args
        ..add(period.startKey)
        ..add(period.endKey);
    }
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}',
      args,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<SaleItem>> itemsFor(int saleId) async {
    final rows = await _db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id',
    );
    return rows.map(SaleItem.fromRow).toList();
  }

  /// The most recent non-voided sale, for the undo affordance.
  Future<Sale?> lastSale() async {
    final rows = await _db.query(
      'sales',
      where: 'voided = 0',
      orderBy: 'sold_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Sale.fromRow(rows.first);
  }

  // --- expenses -----------------------------------------------------------

  Future<int> addExpense({
    required int amountCentavos,
    required String category,
    String? note,
    DateTime? spentAt,
  }) async {
    final when = spentAt ?? DateTime.now();
    return _db.insert('expenses', {
      'amount_centavos': amountCentavos,
      'category': category,
      'spent_at': when.millisecondsSinceEpoch,
      'day_key': Dates.dayKey(when),
      'note': note,
    });
  }

  Future<void> deleteExpense(int id) async {
    await _db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> expenses({Period? period, int limit = 200}) async {
    final rows = await _db.query(
      'expenses',
      where: period == null ? null : 'day_key BETWEEN ? AND ?',
      whereArgs: period == null ? null : [period.startKey, period.endKey],
      orderBy: 'spent_at DESC',
      limit: limit,
    );
    return rows.map(Expense.fromRow).toList();
  }
}
