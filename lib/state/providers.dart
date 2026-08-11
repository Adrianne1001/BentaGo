import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/period.dart';
import '../data/app_database.dart';
import '../data/backup_service.dart';
import '../data/customer_repository.dart';
import '../data/models.dart';
import '../data/product_repository.dart';
import '../data/report_repository.dart';
import '../data/sales_repository.dart';

/// Overridden in `main()` once the database has been opened, so no screen has
/// to deal with an "is the database ready yet" state.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final productRepositoryProvider =
    Provider((ref) => ProductRepository(ref.watch(databaseProvider)));
final salesRepositoryProvider =
    Provider((ref) => SalesRepository(ref.watch(databaseProvider)));
final customerRepositoryProvider =
    Provider((ref) => CustomerRepository(ref.watch(databaseProvider)));
final reportRepositoryProvider =
    Provider((ref) => ReportRepository(ref.watch(databaseProvider)));
final backupServiceProvider =
    Provider((ref) => BackupService(ref.watch(databaseProvider)));

/// Bumped after every write. Read queries watch it, so recording a sale
/// refreshes the dashboard, the stock list and the reports at once without
/// each screen having to know what the others need.
final dataVersionProvider = StateProvider<int>((ref) => 0);

extension DataRefresh on WidgetRef {
  void refreshData() =>
      read(dataVersionProvider.notifier).update((value) => value + 1);
}

extension DataRefreshRef on Ref {
  void refreshData() =>
      read(dataVersionProvider.notifier).update((value) => value + 1);
}

// --- products -------------------------------------------------------------

final productSearchProvider = StateProvider<String>((ref) => '');
final productCategoryFilterProvider = StateProvider<String?>((ref) => null);

final productListProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(productRepositoryProvider).all(
        search: ref.watch(productSearchProvider),
        category: ref.watch(productCategoryFilterProvider),
      );
});

/// Unfiltered, for pickers and dropdowns.
final allProductsProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(productRepositoryProvider).all();
});

final productCategoriesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(productRepositoryProvider).categoriesInUse();
});

final lowStockProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(productRepositoryProvider).lowStock();
});

final inventoryValueProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(productRepositoryProvider).inventoryValueCentavos();
});

final stockMovementsProvider =
    FutureProvider.family<List<StockMovement>, int?>((ref, productId) async {
  ref.watch(dataVersionProvider);
  return ref.watch(productRepositoryProvider).movements(productId: productId);
});

// --- customers ------------------------------------------------------------

final customerSearchProvider = StateProvider<String>((ref) => '');

final customerListProvider = FutureProvider<List<Customer>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(customerRepositoryProvider).all(
        search: ref.watch(customerSearchProvider),
      );
});

final customerProvider =
    FutureProvider.family<Customer?, int>((ref, id) async {
  ref.watch(dataVersionProvider);
  return ref.watch(customerRepositoryProvider).byId(id);
});

final customerLedgerProvider =
    FutureProvider.family<List<LedgerEntry>, int>((ref, id) async {
  ref.watch(dataVersionProvider);
  return ref.watch(customerRepositoryProvider).ledger(id);
});

final totalOutstandingProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(customerRepositoryProvider).totalOutstandingCentavos();
});

final debtorCountProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(customerRepositoryProvider).countWithBalance();
});

// --- reporting ------------------------------------------------------------

/// The period the Ulat screen is looking at. Starts on today.
final selectedPeriodProvider =
    StateProvider<Period>((ref) => Period.today());

final periodSummaryProvider =
    FutureProvider.family<PeriodSummary, Period>((ref, period) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).summary(period);
});

final dailySeriesProvider =
    FutureProvider.family<List<DailyPoint>, Period>((ref, period) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).dailySeries(period);
});

final recentDaysProvider =
    FutureProvider.family<List<DailyPoint>, int>((ref, count) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).recentDays(count);
});

final monthlySeriesProvider =
    FutureProvider.family<List<DailyPoint>, int>((ref, count) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).monthlySeries(count);
});

final topProductsProvider =
    FutureProvider.family<List<ProductStat>, Period>((ref, period) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).topProducts(period);
});

final categoryStatsProvider =
    FutureProvider.family<List<CategoryStat>, Period>((ref, period) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).byCategory(period);
});

final hourlyStatsProvider =
    FutureProvider.family<List<HourBucket>, Period>((ref, period) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).byHour(period);
});

final expenseBreakdownProvider =
    FutureProvider.family<List<Expense>, Period>((ref, period) async {
  ref.watch(dataVersionProvider);
  return ref.watch(reportRepositoryProvider).expenseBreakdown(period);
});

/// Today's numbers, used by the dashboard regardless of what the Ulat screen
/// is currently showing.
final todaySummaryProvider = FutureProvider<PeriodSummary>((ref) async {
  ref.watch(dataVersionProvider);
  return ref
      .watch(reportRepositoryProvider)
      .summary(Period.of(PeriodKind.day, DateTime.now()));
});

final thisWeekSummaryProvider = FutureProvider<PeriodSummary>((ref) async {
  ref.watch(dataVersionProvider);
  return ref
      .watch(reportRepositoryProvider)
      .summary(Period.of(PeriodKind.week, DateTime.now()));
});

final thisMonthSummaryProvider = FutureProvider<PeriodSummary>((ref) async {
  ref.watch(dataVersionProvider);
  return ref
      .watch(reportRepositoryProvider)
      .summary(Period.of(PeriodKind.month, DateTime.now()));
});

// --- sales table ----------------------------------------------------------

class SalesQuery {
  const SalesQuery({
    this.period,
    this.paymentType,
    this.search = '',
    this.includeVoided = false,
    this.orderBy = 'sold_at DESC',
    this.limit = 200,
  });

  final Period? period;
  final PaymentType? paymentType;
  final String search;
  final bool includeVoided;
  final String orderBy;
  final int limit;

  SalesQuery copyWith({
    Period? period,
    bool clearPeriod = false,
    PaymentType? paymentType,
    bool clearPaymentType = false,
    String? search,
    bool? includeVoided,
    String? orderBy,
    int? limit,
  }) {
    return SalesQuery(
      period: clearPeriod ? null : (period ?? this.period),
      paymentType:
          clearPaymentType ? null : (paymentType ?? this.paymentType),
      search: search ?? this.search,
      includeVoided: includeVoided ?? this.includeVoided,
      orderBy: orderBy ?? this.orderBy,
      limit: limit ?? this.limit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SalesQuery &&
      other.period == period &&
      other.paymentType == paymentType &&
      other.search == search &&
      other.includeVoided == includeVoided &&
      other.orderBy == orderBy &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(period, paymentType, search, includeVoided, orderBy, limit);
}

final salesQueryProvider = StateProvider<SalesQuery>(
  (ref) => SalesQuery(period: Period.of(PeriodKind.month, DateTime.now())),
);

final salesTableProvider = FutureProvider<List<Sale>>((ref) async {
  ref.watch(dataVersionProvider);
  final query = ref.watch(salesQueryProvider);
  return ref.watch(salesRepositoryProvider).list(
        period: query.period,
        paymentType: query.paymentType,
        search: query.search,
        includeVoided: query.includeVoided,
        orderBy: query.orderBy,
        limit: query.limit,
      );
});

final saleDetailProvider =
    FutureProvider.family<Sale?, int>((ref, id) async {
  ref.watch(dataVersionProvider);
  return ref.watch(salesRepositoryProvider).byId(id);
});

final recentSalesProvider =
    FutureProvider.family<List<Sale>, int>((ref, limit) async {
  ref.watch(dataVersionProvider);
  return ref.watch(salesRepositoryProvider).list(limit: limit);
});

// --- backups --------------------------------------------------------------

final backupListProvider = FutureProvider<List<BackupFile>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(backupServiceProvider).listAll();
});

final backupPathProvider = FutureProvider<String>((ref) async {
  return ref.watch(backupServiceProvider).displayPath();
});

final lastBackupProvider = FutureProvider<DateTime?>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(backupServiceProvider).lastBackupAt();
});
