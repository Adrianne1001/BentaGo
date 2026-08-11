import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'app_database.dart';
import 'models.dart';

class CustomerRepository {
  CustomerRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  /// Balances are summed from the ledger on every read rather than kept on the
  /// customer row. Slightly more work per query, but the number is always
  /// consistent with the entries behind it.
  Future<List<Customer>> all({
    bool onlyWithBalance = false,
    String? search,
    bool includeArchived = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    if (!includeArchived) where.add('c.archived = 0');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(c.name LIKE ? OR c.phone LIKE ?)');
      final like = '%${search.trim()}%';
      args
        ..add(like)
        ..add(like);
    }
    // `l.balance` comes from the joined subquery, so it is a real column here
    // and may be filtered on directly.
    if (onlyWithBalance) where.add('COALESCE(l.balance, 0) > 0');

    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await _db.rawQuery('''
      SELECT c.*,
             COALESCE(l.balance, 0) AS balance_centavos,
             l.last_activity        AS last_activity
      FROM customers c
      LEFT JOIN (
        SELECT customer_id,
               SUM(amount_centavos) AS balance,
               MAX(entered_at)      AS last_activity
        FROM ledger_entries
        GROUP BY customer_id
      ) l ON l.customer_id = c.id
      $clause
      ORDER BY COALESCE(l.balance, 0) DESC, c.name COLLATE NOCASE ASC
    ''', args);

    return rows.map(Customer.fromRow).toList();
  }

  Future<Customer?> byId(int id) async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
             COALESCE(SUM(l.amount_centavos), 0) AS balance_centavos,
             MAX(l.entered_at)                   AS last_activity
      FROM customers c
      LEFT JOIN ledger_entries l ON l.customer_id = c.id
      WHERE c.id = ?
      GROUP BY c.id
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return Customer.fromRow(rows.first);
  }

  Future<int> insert(Customer customer) async {
    final row = customer.toRow()..remove('id');
    return _db.insert('customers', row);
  }

  Future<void> update(Customer customer) async {
    if (customer.id == null) return;
    final row = customer.toRow()
      ..remove('id')
      ..remove('created_at');
    await _db.update(
      'customers',
      row,
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> setArchived(int id, bool archived) async {
    await _db.update(
      'customers',
      {'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Blocked while the customer still owes money -- deleting them would take
  /// the debt record with it.
  Future<bool> delete(int id) async {
    final customer = await byId(id);
    if (customer == null) return false;
    if (customer.balanceCentavos != 0) return false;
    await _db.delete('customers', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  Future<List<LedgerEntry>> ledger(int customerId, {int limit = 300}) async {
    final rows = await _db.query(
      'ledger_entries',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'entered_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(LedgerEntry.fromRow).toList();
  }

  /// Records a payment against the running balance. Amount is passed in as a
  /// positive number and stored negative.
  Future<void> recordPayment({
    required int customerId,
    required int amountCentavos,
    String? note,
  }) async {
    if (amountCentavos <= 0) return;
    final now = DateTime.now();
    await _db.insert('ledger_entries', {
      'customer_id': customerId,
      'sale_id': null,
      'amount_centavos': -amountCentavos,
      'entered_at': now.millisecondsSinceEpoch,
      'day_key': Dates.dayKey(now),
      'note': note ?? 'Bayad',
    });
  }

  /// A debt that did not come from a sale in the app -- an old balance carried
  /// over from the notebook, most often.
  Future<void> recordCharge({
    required int customerId,
    required int amountCentavos,
    String? note,
  }) async {
    if (amountCentavos <= 0) return;
    final now = DateTime.now();
    await _db.insert('ledger_entries', {
      'customer_id': customerId,
      'sale_id': null,
      'amount_centavos': amountCentavos,
      'entered_at': now.millisecondsSinceEpoch,
      'day_key': Dates.dayKey(now),
      'note': note ?? 'Utang',
    });
  }

  Future<void> deleteEntry(int entryId) async {
    await _db.delete('ledger_entries', where: 'id = ?', whereArgs: [entryId]);
  }

  Future<int> totalOutstandingCentavos() async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(balance), 0) AS total FROM (
        SELECT SUM(amount_centavos) AS balance
        FROM ledger_entries GROUP BY customer_id
        HAVING SUM(amount_centavos) > 0
      )
    ''');
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> countWithBalance() async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS c FROM (
        SELECT customer_id FROM ledger_entries
        GROUP BY customer_id HAVING SUM(amount_centavos) > 0
      )
    ''');
    return (rows.first['c'] as int?) ?? 0;
  }
}
