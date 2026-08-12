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

  /// Records a sale and, when it is on credit, adds the matching charge to the
  /// customer's ledger. Both in one transaction, so a half-written sale with an
  /// uncharged tab is impossible.
  Future<int> recordSale({
    required List<CartLine> lines,
    required PaymentType paymentType,
    int? customerId,
    String? note,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Cannot record a sale with no items.');
    }
    if (paymentType == PaymentType.credit && customerId == null) {
      throw ArgumentError('A credit sale needs a customer.');
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
      }

      if (paymentType == PaymentType.credit && customerId != null) {
        await txn.insert('ledger_entries', {
          'customer_id': customerId,
          'sale_id': saleId,
          'amount_centavos': total,
          'entered_at': now.millisecondsSinceEpoch,
          'day_key': Dates.dayKey(now),
          'note': 'Sale #$saleId',
        });
      }

      return saleId;
    });
  }

  /// Reverses a sale: cancels any credit charge and marks the row voided rather
  /// than deleting it, so the day's history stays honest.
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

      final customerId = sale['customer_id'] as int?;
      final wasCredit = PaymentTypeX.fromCode(
            sale['payment_type'] as String?,
          ) ==
          PaymentType.credit;

      if (wasCredit && customerId != null) {
        // Reversing entry, not a delete -- the ledger is append-only.
        await txn.insert('ledger_entries', {
          'customer_id': customerId,
          'sale_id': saleId,
          'amount_centavos': -((sale['total_centavos'] as int?) ?? 0),
          'entered_at': now.millisecondsSinceEpoch,
          'day_key': Dates.dayKey(now),
          'note': 'Sale #$saleId cancelled',
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

    final itemRows = await _db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [id],
      orderBy: 'id',
    );
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
      if (paymentType == PaymentType.credit) {
        // 'utang' is the legacy code for the same thing.
        where.add("s.payment_type IN ('credit', 'utang')");
      } else {
        where.add('s.payment_type = ?');
        args.add(paymentType.code);
      }
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

  // --- corrections --------------------------------------------------------

  /// Changes one line's quantity and re-totals the sale around it.
  ///
  /// The line keeps the unit price and unit cost it was sold at. A product whose
  /// price changed since is irrelevant here -- the recorded sale is what
  /// happened, and re-pricing it from today's product row would rewrite last
  /// month's profit.
  ///
  /// Setting the quantity to zero removes the line, and removing the last line
  /// voids the whole sale rather than leaving a sale worth nothing.
  Future<void> setSaleItemQty({
    required int saleId,
    required int itemId,
    required int qty,
  }) async {
    if (qty < 0) throw ArgumentError('Quantity cannot be negative.');

    final removingLast = await _db.transaction((txn) async {
      final itemRows = await txn.query(
        'sale_items',
        where: 'id = ? AND sale_id = ?',
        whereArgs: [itemId, saleId],
        limit: 1,
      );
      if (itemRows.isEmpty) return false;
      final item = SaleItem.fromRow(itemRows.first);
      if (item.qty == qty) return false;

      final siblings = await txn.query(
        'sale_items',
        where: 'sale_id = ? AND id != ?',
        whereArgs: [saleId, itemId],
      );
      if (qty == 0 && siblings.isEmpty) return true;

      if (qty == 0) {
        await txn.delete('sale_items', where: 'id = ?', whereArgs: [itemId]);
      } else {
        await txn.update(
          'sale_items',
          {
            'qty': qty,
            'line_total_centavos': item.unitPriceCentavos * qty,
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }

      await _retotal(
        txn,
        saleId,
        note: qty == 0
            ? 'removed ${item.productName}'
            : '${item.productName} ${item.qty}→$qty',
      );
      return false;
    });

    // Outside the transaction: voidSale opens its own.
    if (removingLast) await voidSale(saleId);
  }

  /// Recomputes a sale's total and cost from the lines it still has, moves any
  /// credit balance by the difference, and stamps what changed on the row.
  ///
  /// The ledger is never rewritten -- a correction appends an adjusting entry the
  /// same way a cancellation does, so a customer's tab can always be read as a
  /// list of things that happened.
  Future<void> _retotal(
    DatabaseExecutor txn,
    int saleId, {
    required String note,
  }) async {
    final saleRows = await txn.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (saleRows.isEmpty) return;
    final sale = saleRows.first;
    final previousTotal = (sale['total_centavos'] as int?) ?? 0;

    final totals = await txn.rawQuery('''
      SELECT COALESCE(SUM(unit_price_centavos * qty), 0) AS total,
             COALESCE(SUM(unit_cost_centavos * qty), 0)  AS cost
      FROM sale_items WHERE sale_id = ?
    ''', [saleId]);
    final total = (totals.first['total'] as int?) ?? 0;
    final cost = (totals.first['cost'] as int?) ?? 0;

    final now = DateTime.now();
    final stamp = 'edited ${Dates.shortDay(now)}: $note';
    final existing = (sale['note'] as String?)?.trim();

    await txn.update(
      'sales',
      {
        'total_centavos': total,
        'cost_centavos': cost,
        'note': existing == null || existing.isEmpty
            ? stamp
            : '$existing; $stamp',
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    final customerId = sale['customer_id'] as int?;
    final wasCredit =
        PaymentTypeX.fromCode(sale['payment_type'] as String?) ==
            PaymentType.credit;
    final delta = total - previousTotal;
    if (wasCredit && customerId != null && delta != 0) {
      await txn.insert('ledger_entries', {
        'customer_id': customerId,
        'sale_id': saleId,
        'amount_centavos': delta,
        'entered_at': now.millisecondsSinceEpoch,
        'day_key': Dates.dayKey(now),
        'note': 'Sale #$saleId corrected',
      });
    }
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
