import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../core/period.dart';
import 'app_database.dart';
import 'models.dart';

/// Headline numbers for one period. Revenue is recognised when the sale
/// happens, including credit sales, while [cashCollectedCentavos] tracks money that
/// actually reached the drawer -- the two differ in any store that runs a tab,
/// and conflating them is how owners end up thinking they are richer than
/// they are.
class PeriodSummary {
  const PeriodSummary({
    required this.period,
    this.revenueCentavos = 0,
    this.costCentavos = 0,
    this.saleCount = 0,
    this.itemCount = 0,
    this.cashSalesCentavos = 0,
    this.creditSalesCentavos = 0,
    this.gcashSalesCentavos = 0,
    this.creditPaymentsCentavos = 0,
    this.expensesCentavos = 0,
    this.costCoverage = 0,
  });

  final Period period;
  final int revenueCentavos;
  final int costCentavos;
  final int saleCount;
  final int itemCount;
  final int cashSalesCentavos;
  final int creditSalesCentavos;
  final int gcashSalesCentavos;
  final int creditPaymentsCentavos;
  final int expensesCentavos;

  /// Share of revenue whose items had a cost price on file, 0..1. When this is
  /// low the profit figure is optimistic and the UI says so instead of
  /// quietly presenting it as fact.
  final double costCoverage;

  int get grossProfitCentavos => revenueCentavos - costCentavos;
  int get netProfitCentavos => grossProfitCentavos - expensesCentavos;

  /// Money in the drawer: paid-at-the-window sales plus credit settled today.
  int get cashCollectedCentavos =>
      cashSalesCentavos + gcashSalesCentavos + creditPaymentsCentavos;

  double? get marginPercent {
    if (revenueCentavos <= 0) return null;
    return grossProfitCentavos / revenueCentavos * 100;
  }

  int get averageSaleCentavos =>
      saleCount == 0 ? 0 : (revenueCentavos / saleCount).round();

  bool get profitIsEstimate => costCoverage < 0.95;

  bool get isEmpty => saleCount == 0 && expensesCentavos == 0;
}

/// One bar in the daily chart.
class DailyPoint {
  const DailyPoint({
    required this.day,
    this.revenueCentavos = 0,
    this.profitCentavos = 0,
    this.saleCount = 0,
  });

  final DateTime day;
  final int revenueCentavos;
  final int profitCentavos;
  final int saleCount;

  String get dayKey => Dates.dayKey(day);
}

class ProductStat {
  const ProductStat({
    this.productId,
    required this.name,
    required this.qty,
    required this.revenueCentavos,
    required this.profitCentavos,
  });

  final int? productId;
  final String name;
  final int qty;
  final int revenueCentavos;
  final int profitCentavos;
}

class CategoryStat {
  const CategoryStat({
    required this.category,
    required this.qty,
    required this.revenueCentavos,
  });

  final String category;
  final int qty;
  final int revenueCentavos;
}

class HourBucket {
  const HourBucket({
    required this.hour,
    required this.revenueCentavos,
    required this.saleCount,
  });

  final int hour;
  final int revenueCentavos;
  final int saleCount;

  String get label {
    if (hour == 0) return '12am';
    if (hour == 12) return '12nn';
    return hour < 12 ? '${hour}am' : '${hour - 12}pm';
  }
}

class ReportRepository {
  ReportRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  Future<PeriodSummary> summary(Period period) async {
    final args = [period.startKey, period.endKey];

    final saleRows = await _db.rawQuery('''
      SELECT
        COALESCE(SUM(total_centavos), 0) AS revenue,
        COALESCE(SUM(cost_centavos), 0)  AS cost,
        COUNT(*)                         AS sale_count,
        COALESCE(SUM(CASE WHEN payment_type = 'cash'
                     THEN total_centavos ELSE 0 END), 0) AS cash_sales,
        -- 'utang' is the code credit sales were stored under before the
        -- interface moved to English. Matching both keeps old rows counted.
        COALESCE(SUM(CASE WHEN payment_type IN ('credit', 'utang')
                     THEN total_centavos ELSE 0 END), 0) AS credit_sales,
        COALESCE(SUM(CASE WHEN payment_type = 'gcash'
                     THEN total_centavos ELSE 0 END), 0) AS gcash_sales
      FROM sales
      WHERE voided = 0 AND day_key BETWEEN ? AND ?
    ''', args);
    final sales = saleRows.first;

    final itemRows = await _db.rawQuery('''
      SELECT
        COALESCE(SUM(i.qty), 0) AS item_count,
        COALESCE(SUM(CASE WHEN i.unit_cost_centavos > 0
                     THEN i.line_total_centavos ELSE 0 END), 0) AS costed_revenue
      FROM sale_items i
      JOIN sales s ON s.id = i.sale_id
      WHERE s.voided = 0 AND s.day_key BETWEEN ? AND ?
    ''', args);
    final items = itemRows.first;

    // Payments recorded against credit inside this period. Stored negative,
    // so flip the sign to report money received.
    final paymentRows = await _db.rawQuery('''
      SELECT COALESCE(SUM(-amount_centavos), 0) AS paid
      FROM ledger_entries
      WHERE amount_centavos < 0 AND day_key BETWEEN ? AND ?
    ''', args);

    final expenseRows = await _db.rawQuery('''
      SELECT COALESCE(SUM(amount_centavos), 0) AS spent
      FROM expenses WHERE day_key BETWEEN ? AND ?
    ''', args);

    final revenue = (sales['revenue'] as int?) ?? 0;
    final costedRevenue = (items['costed_revenue'] as int?) ?? 0;

    return PeriodSummary(
      period: period,
      revenueCentavos: revenue,
      costCentavos: (sales['cost'] as int?) ?? 0,
      saleCount: (sales['sale_count'] as int?) ?? 0,
      itemCount: (items['item_count'] as int?) ?? 0,
      cashSalesCentavos: (sales['cash_sales'] as int?) ?? 0,
      creditSalesCentavos: (sales['credit_sales'] as int?) ?? 0,
      gcashSalesCentavos: (sales['gcash_sales'] as int?) ?? 0,
      creditPaymentsCentavos: (paymentRows.first['paid'] as int?) ?? 0,
      expensesCentavos: (expenseRows.first['spent'] as int?) ?? 0,
      costCoverage: revenue == 0 ? 1 : costedRevenue / revenue,
    );
  }

  /// Daily totals across the period, with zero-filled gaps so a quiet day
  /// shows as an empty bar instead of collapsing the chart's spacing.
  Future<List<DailyPoint>> dailySeries(Period period) async {
    final rows = await _db.rawQuery('''
      SELECT day_key,
             COALESCE(SUM(total_centavos), 0) AS revenue,
             COALESCE(SUM(total_centavos - cost_centavos), 0) AS profit,
             COUNT(*) AS sale_count
      FROM sales
      WHERE voided = 0 AND day_key BETWEEN ? AND ?
      GROUP BY day_key
    ''', [period.startKey, period.endKey]);

    final byKey = {
      for (final row in rows) row['day_key'] as String: row,
    };

    return period.days.map((day) {
      final row = byKey[Dates.dayKey(day)];
      return DailyPoint(
        day: day,
        revenueCentavos: (row?['revenue'] as int?) ?? 0,
        profitCentavos: (row?['profit'] as int?) ?? 0,
        saleCount: (row?['sale_count'] as int?) ?? 0,
      );
    }).toList();
  }

  /// The last [count] days ending today. Drives the dashboard's week strip.
  Future<List<DailyPoint>> recentDays(int count) async {
    final end = Dates.endOfDay(DateTime.now());
    final start = Dates.startOfDay(
      DateTime.now().subtract(Duration(days: count - 1)),
    );
    return dailySeries(
      Period(kind: PeriodKind.day, start: start, end: end),
    );
  }

  /// Monthly totals for the trailing [count] months, oldest first.
  Future<List<DailyPoint>> monthlySeries(int count) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - (count - 1));
    final rows = await _db.rawQuery('''
      SELECT SUBSTR(day_key, 1, 7) AS month_key,
             COALESCE(SUM(total_centavos), 0) AS revenue,
             COALESCE(SUM(total_centavos - cost_centavos), 0) AS profit,
             COUNT(*) AS sale_count
      FROM sales
      WHERE voided = 0 AND day_key >= ?
      GROUP BY month_key
    ''', [Dates.dayKey(start)]);

    final byKey = {for (final row in rows) row['month_key'] as String: row};

    return List.generate(count, (i) {
      final month = DateTime(start.year, start.month + i);
      final row = byKey[Dates.monthKey(month)];
      return DailyPoint(
        day: month,
        revenueCentavos: (row?['revenue'] as int?) ?? 0,
        profitCentavos: (row?['profit'] as int?) ?? 0,
        saleCount: (row?['sale_count'] as int?) ?? 0,
      );
    });
  }

  Future<List<ProductStat>> topProducts(
    Period period, {
    int limit = 8,
    bool worst = false,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT i.product_id,
             i.product_name AS name,
             COALESCE(SUM(i.qty), 0) AS qty,
             COALESCE(SUM(i.line_total_centavos), 0) AS revenue,
             COALESCE(SUM(i.line_total_centavos
                          - (i.unit_cost_centavos * i.qty)), 0) AS profit
      FROM sale_items i
      JOIN sales s ON s.id = i.sale_id
      WHERE s.voided = 0 AND s.day_key BETWEEN ? AND ?
      GROUP BY i.product_name
      ORDER BY revenue ${worst ? 'ASC' : 'DESC'}
      LIMIT ?
    ''', [period.startKey, period.endKey, limit]);

    return rows
        .map(
          (r) => ProductStat(
            productId: r['product_id'] as int?,
            name: r['name'] as String? ?? '',
            qty: (r['qty'] as int?) ?? 0,
            revenueCentavos: (r['revenue'] as int?) ?? 0,
            profitCentavos: (r['profit'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  Future<List<CategoryStat>> byCategory(Period period) async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(p.category), ''), 'No category')
               AS category,
             COALESCE(SUM(i.qty), 0) AS qty,
             COALESCE(SUM(i.line_total_centavos), 0) AS revenue
      FROM sale_items i
      JOIN sales s ON s.id = i.sale_id
      LEFT JOIN products p ON p.id = i.product_id
      WHERE s.voided = 0 AND s.day_key BETWEEN ? AND ?
      GROUP BY category
      ORDER BY revenue DESC
    ''', [period.startKey, period.endKey]);

    return rows
        .map(
          (r) => CategoryStat(
            category: r['category'] as String? ?? 'No category',
            qty: (r['qty'] as int?) ?? 0,
            revenueCentavos: (r['revenue'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// Sales by hour of day, for spotting the rush. `sold_at` is epoch
  /// milliseconds, so divide to seconds before handing it to strftime and ask
  /// for localtime -- otherwise every bar lands 8 hours off in PH time.
  Future<List<HourBucket>> byHour(Period period) async {
    final rows = await _db.rawQuery('''
      SELECT CAST(strftime('%H', sold_at / 1000, 'unixepoch', 'localtime')
                  AS INTEGER) AS hour,
             COALESCE(SUM(total_centavos), 0) AS revenue,
             COUNT(*) AS sale_count
      FROM sales
      WHERE voided = 0 AND day_key BETWEEN ? AND ?
      GROUP BY hour
      ORDER BY hour
    ''', [period.startKey, period.endKey]);

    final byHour = {
      for (final row in rows) (row['hour'] as int?) ?? 0: row,
    };

    return List.generate(24, (hour) {
      final row = byHour[hour];
      return HourBucket(
        hour: hour,
        revenueCentavos: (row?['revenue'] as int?) ?? 0,
        saleCount: (row?['sale_count'] as int?) ?? 0,
      );
    });
  }

  Future<List<Expense>> expenseBreakdown(Period period) async {
    final rows = await _db.rawQuery('''
      SELECT category,
             COALESCE(SUM(amount_centavos), 0) AS amount_centavos,
             MAX(spent_at) AS spent_at
      FROM expenses
      WHERE day_key BETWEEN ? AND ?
      GROUP BY category
      ORDER BY amount_centavos DESC
    ''', [period.startKey, period.endKey]);
    return rows.map(Expense.fromRow).toList();
  }

  /// The date of the very first recorded sale, used to bound date pickers.
  Future<DateTime?> firstSaleDate() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(sold_at) AS first FROM sales WHERE voided = 0',
    );
    final value = rows.first['first'] as int?;
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
