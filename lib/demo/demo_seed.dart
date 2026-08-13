import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/app_database.dart';
import '../data/models.dart';

/// Compile-time gate for the recorded demo. `false` in every normal build, so
/// the whole of [DemoSeeder] is tree-shaken out of the APK that ships.
///
/// Turned on only by the demo pipeline:
///     flutter build apk --profile --dart-define=BENTAGO_DEMO=true
const bool kDemoMode = bool.fromEnvironment('BENTAGO_DEMO');

/// Fills a fresh install with six weeks of plausible trading so the demo
/// recording has something to show.
///
/// **This deletes every sale, tab, customer and expense in the database.** It is
/// only ever reached behind [kDemoMode], and the pipeline only ever points at an
/// emulator, but running a demo build on a phone that holds a real store's
/// records would wipe them. There is no undo.
///
/// Reproducible *for a given calendar day*: the same seed replayed against the
/// same dates writes the same rows, so re-recording a take on the same day shows
/// identical figures. It does not hold across days -- the weekday pattern, the
/// payday bonus and the two utility-bill dates all move with the calendar, and
/// any of them shifts the whole random stream. So never write a peso amount into
/// `narration.json`; describe what the screen does, not what it says.
///
/// Written as direct inserts rather than through `SalesRepository` because a
/// repository stamps `DateTime.now()` on everything it writes, and this needs
/// rows dated into the past. The invariants that matter are kept by hand:
///
///   * money is only ever an `int` of centavos;
///   * every sale, ledger entry and expense carries its local `day_key`;
///   * `sale_items` snapshots the unit price and unit cost it sold at;
///   * a credit sale's ledger charge is appended in the same transaction, and
///     nothing in the ledger is ever edited or deleted afterwards;
///   * the one reversed sale is marked `voided`, not removed.
abstract class DemoSeeder {
  /// Six weeks of history plus a partly-finished today.
  static const int _daysOfHistory = 41;

  /// Any constant would do; this one just has to never change, or two takes made
  /// on the same day stop matching each other.
  static const int _seed = 20260814;

  /// Once a tab passes this, the customer settles most of it the next morning.
  /// Keeps closing balances in the hundreds, which is what a real tab looks
  /// like -- an unbroken six weeks of charges would read as a debt spiral.
  static const int _settleAboveCentavos = 45000;

  /// How far back the one reversed sale sits.
  static const int _voidDaysBack = 14;

  static const List<_DemoCustomer> _customers = [
    _DemoCustomer('Aling Nena', '0917 555 0142', 'Kapitbahay, bayad tuwing Sabado'),
    _DemoCustomer('Mang Tonyo', '0918 555 0177', 'Tricycle driver'),
    _DemoCustomer('Ate Rosa', '0906 555 0163', null),
    _DemoCustomer('Kuya Ben', '0995 555 0119', 'Construction, bayad kada kinsenas'),
    _DemoCustomer('Baby Lyn', null, null),
    _DemoCustomer('Tita Cora', '0927 555 0188', null),
    _DemoCustomer('Jun-jun', null, 'Anak ni Aling Nena'),
    _DemoCustomer('Marites', '0939 555 0154', null),
  ];

  /// The four who actually run a tab. The rest are cash customers who happen to
  /// be saved, which is the normal shape of the list.
  static const List<int> _creditCustomerIndexes = [0, 1, 3, 5];

  /// How many customers a seeded database holds. Exposed for the tests.
  static int get customerCount => _customers.length;

  /// Trading is heaviest at breakfast and again after work. Weighted by
  /// repetition rather than a distribution, because it only has to look right.
  static const List<int> _hours = [
    6, 6, 7, 7, 7, 8, 8, 8, 9, 9,
    10, 11, 11, 12, 12, 13, 14, 15,
    16, 16, 17, 17, 17, 18, 18, 18, 19, 19, 19, 20, 20, 21,
  ];

  /// Sales per day by weekday (Mon = 1). Sunday is busiest, Wednesday quietest.
  static const Map<int, int> _salesByWeekday = {
    DateTime.monday: 17,
    DateTime.tuesday: 16,
    DateTime.wednesday: 15,
    DateTime.thursday: 18,
    DateTime.friday: 23,
    DateTime.saturday: 27,
    DateTime.sunday: 25,
  };

  /// Wipes the trading history and writes it again from scratch.
  ///
  /// Products are left alone: a fresh install already seeds the price list, and
  /// the pipeline uninstalls the app before each run so that list is known.
  static Future<void> reset(AppDatabase app) async {
    final db = app.db;
    final products = await _activeProducts(db);
    if (products.isEmpty) return;

    final now = DateTime.now();
    final rng = _Rng(_seed);

    await db.transaction((txn) async {
      // Children first: sale_items and ledger_entries both point at sales.
      await txn.delete('sale_items');
      await txn.delete('ledger_entries');
      await txn.delete('sales');
      await txn.delete('expenses');
      await txn.delete('customers');

      final customerIds = <int>[];
      for (final customer in _customers) {
        customerIds.add(
          await txn.insert('customers', {
            'name': customer.name,
            'phone': customer.phone,
            'note': customer.note,
            'archived': 0,
            'created_at': DateTime(now.year, now.month, now.day)
                .subtract(const Duration(days: _daysOfHistory + 3))
                .millisecondsSinceEpoch,
          }),
        );
      }

      // Running tab per customer, in centavos, so a settlement can be written
      // the moment one gets uncomfortably large.
      final balances = <int, int>{for (final id in customerIds) id: 0};
      var reversedOne = false;

      for (var back = _daysOfHistory; back >= 0; back--) {
        final day = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: back));
        final dayKey = Dates.dayKey(day);
        final isToday = back == 0;

        // The day's first sale that went on a tab, kept so one of them can be
        // reversed further down -- a cancelled cash sale would leave the ledger
        // untouched, and the adjusting entry is the interesting part.
        _CreditSale? firstCreditSale;

        var count = _salesByWeekday[day.weekday] ?? 18;
        count += rng.range(-3, 4);

        // Payday weekends move more goods.
        if ((day.day == 15 || day.day == 30) && day.weekday >= DateTime.friday) {
          count += 6;
        }

        for (var i = 0; i < count; i++) {
          final hour = rng.pick(_hours);
          final soldAt = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            rng.range(0, 59),
            rng.range(0, 59),
          );
          // Today is only part-way through, so nothing may be stamped ahead of
          // the clock -- a sale in the future reads as a bug on the dashboard.
          if (isToday && soldAt.isAfter(now)) continue;

          final lines = _basket(rng, products);
          var total = 0;
          var cost = 0;
          for (final line in lines) {
            total += line.unitPriceCentavos * line.qty;
            cost += line.unitCostCentavos * line.qty;
          }

          // Cash dominates; a tab is the exception, and GCash is still rare.
          final roll = rng.range(1, 100);
          var paymentType = PaymentType.cash;
          int? customerId;
          if (roll > 82 && roll <= 95) {
            paymentType = PaymentType.credit;
            customerId = customerIds[rng.pick(_creditCustomerIndexes)];
          } else if (roll > 95) {
            paymentType = PaymentType.gcash;
          }

          final saleId = await txn.insert('sales', {
            'sold_at': soldAt.millisecondsSinceEpoch,
            'day_key': dayKey,
            'total_centavos': total,
            'cost_centavos': cost,
            'payment_type': paymentType.code,
            'customer_id': customerId,
            'note': null,
            'voided': 0,
          });

          for (final line in lines) {
            await txn.insert('sale_items', {
              'sale_id': saleId,
              'product_id': line.productId,
              'product_name': line.productName,
              'qty': line.qty,
              // Snapshot, not a join: re-pricing a product must never rewrite
              // what last month earned.
              'unit_price_centavos': line.unitPriceCentavos,
              'unit_cost_centavos': line.unitCostCentavos,
              'line_total_centavos': line.unitPriceCentavos * line.qty,
            });
          }

          if (paymentType == PaymentType.credit && customerId != null) {
            await txn.insert('ledger_entries', {
              'customer_id': customerId,
              'sale_id': saleId,
              'amount_centavos': total,
              'entered_at': soldAt.millisecondsSinceEpoch,
              'day_key': dayKey,
              'note': 'Sale #$saleId',
            });
            balances[customerId] = (balances[customerId] ?? 0) + total;

            firstCreditSale ??= _CreditSale(
              saleId: saleId,
              customerId: customerId,
              totalCentavos: total,
              soldAt: soldAt,
            );
          }
        }

        // Reverse one credit sale, the way the app does it: an adjusting ledger
        // entry rather than an edit, and `voided = 1` rather than a delete.
        //
        // Done here, inside the day, so `balances` is corrected before the
        // settlement pass below reads it -- settling against a balance that
        // still counted a cancelled sale would over-pay and push the tab
        // negative.
        if (!reversedOne && back <= _voidDaysBack && firstCreditSale != null) {
          await _reverseSale(txn, firstCreditSale);
          balances[firstCreditSale.customerId] =
              (balances[firstCreditSale.customerId] ?? 0) -
                  firstCreditSale.totalCentavos;
          reversedOne = true;
        }

        // Settle the tabs that ran up too far, the *next* morning -- a payment
        // stamped 9am today cannot be settling charges made at 6pm today, and
        // the customer's ledger would read as going negative before it was paid.
        for (final id in customerIds) {
          final owed = balances[id] ?? 0;
          if (owed <= _settleAboveCentavos || isToday) continue;
          // Round down to a whole peso -- nobody hands over centavos.
          final paying = (owed * rng.range(70, 90) ~/ 100 ~/ 100) * 100;
          if (paying <= 0) continue;

          final paidAt = day.add(
            Duration(days: 1, hours: 9, minutes: rng.range(0, 50)),
          );
          await txn.insert('ledger_entries', {
            'customer_id': id,
            'sale_id': null,
            'amount_centavos': -paying,
            'entered_at': paidAt.millisecondsSinceEpoch,
            'day_key': Dates.dayKey(paidAt),
            'note': 'Payment',
          });
          balances[id] = owed - paying;
        }

        // The fare to the market, not the goods: what the stock cost is already
        // on every `sale_items` row as `unit_cost_centavos`, and the reports
        // subtract expenses from a gross profit that has taken it off once
        // already. Booking the restocking spend here as well would count it
        // twice and show the store running at a loss every week.
        if (day.weekday == DateTime.monday) {
          await _expense(
            txn,
            day.add(const Duration(hours: 7)),
            rng.range(8000, 15000),
            'Transport',
            'Palengke fare',
          );
        }
        if (day.day == 5) {
          await _expense(
            txn,
            day.add(const Duration(hours: 10)),
            rng.range(68000, 94000),
            'Electricity',
            'Meralco',
          );
        }
        if (day.day == 12) {
          await _expense(
            txn,
            day.add(const Duration(hours: 10)),
            rng.range(24000, 38000),
            'Water',
            null,
          );
        }
      }
    });
  }

  static Future<void> _expense(
    DatabaseExecutor txn,
    DateTime when,
    int amountCentavos,
    String category,
    String? note,
  ) async {
    await txn.insert('expenses', {
      'amount_centavos': amountCentavos,
      'category': category,
      'spent_at': when.millisecondsSinceEpoch,
      'day_key': Dates.dayKey(when),
      'note': note,
    });
  }

  /// Cancels [sale] the way `SalesRepository.voidSale` does: append the
  /// reversing ledger entry, then mark the row voided.
  static Future<void> _reverseSale(
    DatabaseExecutor txn,
    _CreditSale sale,
  ) async {
    // Twenty minutes later, and every hour in [_hours] is 21:00 or earlier, so
    // this cannot cross midnight into a day_key that disagrees with itself.
    final voidedAt = sale.soldAt.add(const Duration(minutes: 20));

    await txn.insert('ledger_entries', {
      'customer_id': sale.customerId,
      'sale_id': sale.saleId,
      'amount_centavos': -sale.totalCentavos,
      'entered_at': voidedAt.millisecondsSinceEpoch,
      'day_key': Dates.dayKey(voidedAt),
      'note': 'Sale #${sale.saleId} cancelled',
    });

    await txn.update(
      'sales',
      {'voided': 1},
      where: 'id = ?',
      whereArgs: [sale.saleId],
    );
  }

  /// One to four distinct products, with the cheap fast-movers bought in
  /// handfuls and the expensive tins one at a time.
  static List<_DemoLine> _basket(_Rng rng, List<Product> products) {
    final lineCount = switch (rng.range(1, 100)) {
      <= 34 => 1,
      <= 68 => 2,
      <= 90 => 3,
      _ => 4,
    };

    final chosen = <int, Product>{};
    var attempts = 0;
    while (chosen.length < lineCount && attempts < 20) {
      attempts++;
      final product = rng.pick(products);
      final id = product.id;
      if (id == null) continue;
      chosen[id] = product;
    }

    return [
      for (final product in chosen.values)
        _DemoLine(
          productId: product.id,
          productName: product.name,
          qty: product.priceCentavos <= 500
              ? rng.range(2, 6)
              : product.priceCentavos <= 1500
                  ? rng.range(1, 3)
                  : 1,
          unitPriceCentavos: product.priceCentavos,
          unitCostCentavos: product.costCentavos,
        ),
    ];
  }

  static Future<List<Product>> _activeProducts(Database db) async {
    final rows = await db.query(
      'products',
      where: 'archived = 0',
      orderBy: 'id',
    );
    return rows.map(Product.fromRow).toList();
  }
}

class _DemoCustomer {
  const _DemoCustomer(this.name, this.phone, this.note);

  final String name;
  final String? phone;
  final String? note;
}

/// Just enough about a credit sale to reverse it later.
class _CreditSale {
  const _CreditSale({
    required this.saleId,
    required this.customerId,
    required this.totalCentavos,
    required this.soldAt,
  });

  final int saleId;
  final int customerId;
  final int totalCentavos;
  final DateTime soldAt;
}

class _DemoLine {
  const _DemoLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPriceCentavos,
    required this.unitCostCentavos,
  });

  final int? productId;
  final String productName;
  final int qty;
  final int unitPriceCentavos;
  final int unitCostCentavos;
}

/// A linear congruential generator, so two takes made on the same day produce
/// byte-identical data. `dart:math`'s Random is seedable too, but its exact
/// sequence is not contractual across SDK versions and this one is.
class _Rng {
  _Rng(this._state);

  int _state;

  int _next() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state;
  }

  int range(int minInclusive, int maxInclusive) =>
      minInclusive + _next() % (maxInclusive - minInclusive + 1);

  T pick<T>(List<T> items) => items[_next() % items.length];
}
