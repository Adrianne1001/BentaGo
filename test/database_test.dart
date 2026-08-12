import 'dart:io';

import 'package:bentago/core/period.dart';
import 'package:bentago/data/app_database.dart';
import 'package:bentago/data/backup_service.dart';
import 'package:bentago/data/customer_repository.dart';
import 'package:bentago/data/models.dart';
import 'package:bentago/data/product_repository.dart';
import 'package:bentago/data/report_repository.dart';
import 'package:bentago/data/sales_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Drives the real SQLite layer end to end: selling, credit, reports and
/// backups. Runs against a temp database on disk rather than a mock, so the
/// actual SQL is what gets exercised.
void main() {
  AppDatabase.registerDesktopFactory();

  late Directory tempDir;
  late AppDatabase db;
  late ProductRepository products;
  late SalesRepository sales;
  late CustomerRepository customers;
  late ReportRepository reports;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bentago_test_');
    db = await AppDatabase.openAt(p.join(tempDir.path, 'test.db'));
    products = ProductRepository(db);
    sales = SalesRepository(db);
    customers = CustomerRepository(db);
    reports = ReportRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('seeding', () {
    test('a fresh database opens with a usable price list', () async {
      final all = await products.all();
      expect(all.length, greaterThan(20));
      expect(all.every((pr) => pr.priceCentavos > 0), isTrue);
      expect(all.every((pr) => pr.unitLabel == 'pc'), isTrue);
    });

    test('seeded products carry categories the form can offer', () async {
      final categories = await products.categoriesInUse();
      expect(categories, contains('Snacks'));
      expect(categories, contains('Drinks'));
      // Sorted, no blanks.
      expect(categories.every((c) => c.trim().isNotEmpty), isTrue);
    });

    test('there is no inventory concept anywhere in the schema', () async {
      final columns = await db.db.rawQuery('PRAGMA table_info(products)');
      final names = columns.map((c) => c['name'] as String).toSet();
      expect(names, contains('price_centavos'));
      expect(names.contains('stock'), isFalse);
      expect(names.contains('track_stock'), isFalse);
      expect(names.contains('reorder_level'), isFalse);
      expect(names.contains('ever_stocked'), isFalse);

      final tables = await db.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();
      expect(tableNames.contains('stock_movements'), isFalse);
    });
  });

  group('products', () {
    test('name and price alone make a valid product', () async {
      final id = await products.insert(
        const Product(name: 'Tinapay', priceCentavos: 500),
      );
      final saved = await products.byId(id);
      expect(saved!.name, 'Tinapay');
      expect(saved.priceCentavos, 500);
      expect(saved.description, isNull);
      expect(saved.category, isNull);
      expect(saved.hasCost, isFalse);
      expect(saved.marginPercent, isNull);
    });

    test('cost drives the margin figures', () async {
      final id = await products.insert(
        const Product(name: 'Kape', priceCentavos: 1000, costCentavos: 800),
      );
      final saved = await products.byId(id);
      expect(saved!.marginCentavos, 200);
      expect(saved.marginPercent, 20);
      expect(saved.hasCost, isTrue);
    });

    test('editing keeps the id and drops nothing', () async {
      final id = await products.insert(
        const Product(name: 'Asin', priceCentavos: 800, category: 'Food'),
      );
      await products.update(
        Product(
          id: id,
          name: 'Asin (dagat)',
          priceCentavos: 900,
          category: 'Fresh',
        ),
      );

      final saved = await products.byId(id);
      expect(saved!.name, 'Asin (dagat)');
      expect(saved.priceCentavos, 900);
      expect(saved.category, 'Fresh');
    });

    test('deleting a product keeps its sales history readable', () async {
      final id = await products.insert(
        const Product(name: 'Paalisin', priceCentavos: 1500),
      );
      final product = (await products.byId(id))!;
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );

      await products.delete(id);

      final sale = await sales.byId(saleId);
      expect(sale!.totalCentavos, 3000);
      expect(sale.items.single.productName, 'Paalisin');
      expect(sale.items.single.productId, isNull);
    });
  });

  group('custom categories', () {
    test('a category exists as soon as a product carries it', () async {
      expect(await products.categoriesInUse(), isNot(contains('Frozen')));

      await products.insert(
        const Product(
          name: 'Ice cream',
          priceCentavos: 3000,
          category: 'Frozen',
        ),
      );

      expect(await products.categoriesInUse(), contains('Frozen'));
      expect((await products.categoryCounts())['Frozen'], 1);
    });

    test('filtering by a custom category returns only its products', () async {
      await products.insert(
        const Product(name: 'A', priceCentavos: 100, category: 'School'),
      );
      await products.insert(
        const Product(name: 'B', priceCentavos: 200, category: 'School'),
      );

      final filtered = await products.all(category: 'School');
      expect(filtered.length, 2);
      expect(filtered.every((pr) => pr.category == 'School'), isTrue);
    });

    test('renaming moves every product at once', () async {
      await products.insert(
        const Product(name: 'A', priceCentavos: 100, category: 'Softdrinks'),
      );
      await products.insert(
        const Product(name: 'B', priceCentavos: 200, category: 'Softdrinks'),
      );

      final moved = await products.renameCategory('Softdrinks', 'Sodas');
      expect(moved, 2);
      expect(await products.categoriesInUse(), contains('Sodas'));
      expect(await products.categoriesInUse(), isNot(contains('Softdrinks')));
    });

    test('removing a category keeps the products', () async {
      final id = await products.insert(
        const Product(name: 'Keeper', priceCentavos: 100, category: 'Temp'),
      );

      await products.deleteCategory('Temp');

      final saved = await products.byId(id);
      expect(saved, isNotNull, reason: 'the product must survive');
      expect(saved!.category, isNull);
      expect(await products.categoriesInUse(), isNot(contains('Temp')));
    });

    test('renaming to a blank name changes nothing', () async {
      final id = await products.insert(
        const Product(name: 'Safe', priceCentavos: 100, category: 'Keep'),
      );

      expect(await products.renameCategory('Keep', '   '), 0);
      expect((await products.byId(id))!.category, 'Keep');
    });

    test('renaming onto an existing category merges the two', () async {
      await products.insert(
        const Product(name: 'A', priceCentavos: 100, category: 'Soda'),
      );
      await products.insert(
        const Product(name: 'B', priceCentavos: 100, category: 'Softdrinks'),
      );

      // The form blocks this case, but the repository merging rather than
      // erroring is the behaviour the manager screen relies on.
      await products.renameCategory('Softdrinks', 'Soda');

      expect((await products.categoryCounts())['Soda'], 2);
      expect(await products.categoriesInUse(), isNot(contains('Softdrinks')));
    });

    test('deleting one category leaves the others alone', () async {
      await products.insert(
        const Product(name: 'A', priceCentavos: 100, category: 'Gone'),
      );
      final keeperId = await products.insert(
        const Product(name: 'B', priceCentavos: 100, category: 'Stays'),
      );

      await products.deleteCategory('Gone');

      expect(await products.categoriesInUse(), isNot(contains('Gone')));
      expect(await products.categoriesInUse(), contains('Stays'));
      expect((await products.byId(keeperId))!.category, 'Stays');
    });

    test('a category disappears when its last product is gone', () async {
      final id = await products.insert(
        const Product(name: 'Only one', priceCentavos: 100, category: 'Solo'),
      );
      expect(await products.categoriesInUse(), contains('Solo'));

      await products.delete(id);
      expect(await products.categoriesInUse(), isNot(contains('Solo')));
    });
  });

  group('selling', () {
    Future<Product> item({
      String name = 'Test item',
      int price = 1000,
      int cost = 700,
    }) async {
      final id = await products.insert(
        Product(name: name, priceCentavos: price, costCentavos: cost),
      );
      return (await products.byId(id))!;
    }

    test('a cash sale records totals and profit', () async {
      final product = await item();
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );

      final sale = await sales.byId(saleId);
      expect(sale!.totalCentavos, 3000);
      expect(sale.costCentavos, 2100);
      expect(sale.profitCentavos, 900);
      expect(sale.paymentType, PaymentType.cash);
    });

    test('unit price is snapshotted, so later price changes do not '
        'rewrite history', () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );

      await products.update(product.copyWith(priceCentavos: 5000));

      final sale = await sales.byId(saleId);
      expect(sale!.items.single.unitPriceCentavos, 1000);
      expect(sale.totalCentavos, 1000);
    });

    test('a credit sale needs a customer', () async {
      final product = await item();
      expect(
        () => sales.recordSale(
          lines: [CartLine(product: product, qty: 1)],
          paymentType: PaymentType.credit,
        ),
        throwsArgumentError,
      );
    });

    test('an empty basket cannot be recorded', () async {
      expect(
        () => sales.recordSale(lines: [], paymentType: PaymentType.cash),
        throwsArgumentError,
      );
    });

    test('a credit sale charges the customer ledger', () async {
      final product = await item(price: 2500);
      final customerId =
          await customers.insert(const Customer(name: 'Aling Beth'));

      await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );

      final customer = await customers.byId(customerId);
      expect(customer!.balanceCentavos, 5000);
      expect(customer.owes, isTrue);
      expect(await customers.totalOutstandingCentavos(), 5000);
      expect(await customers.countWithBalance(), 1);
    });

    test('cancelling a sale reverses the credit', () async {
      final product = await item();
      final customerId =
          await customers.insert(const Customer(name: 'Mang T'));

      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 5)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );
      expect((await customers.byId(customerId))!.balanceCentavos, 5000);

      await sales.voidSale(saleId);

      expect((await customers.byId(customerId))!.balanceCentavos, 0);

      // The row survives, marked voided -- the ledger is append-only.
      final sale = await sales.byId(saleId);
      expect(sale!.voided, isTrue);
      expect((await customers.ledger(customerId)).length, 2);
    });

    test('cancelling twice does not double-refund', () async {
      final product = await item();
      final customerId = await customers.insert(const Customer(name: 'X'));
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 4)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );

      await sales.voidSale(saleId);
      await sales.voidSale(saleId);

      expect((await customers.byId(customerId))!.balanceCentavos, 0);
    });
  });

  group('credit ledger', () {
    test('a payment reduces the balance', () async {
      final customerId = await customers.insert(const Customer(name: 'Suki'));
      await customers.recordCharge(
        customerId: customerId,
        amountCentavos: 10000,
        note: 'Old balance',
      );
      expect((await customers.byId(customerId))!.balanceCentavos, 10000);

      await customers.recordPayment(
        customerId: customerId,
        amountCentavos: 4000,
      );
      expect((await customers.byId(customerId))!.balanceCentavos, 6000);

      final ledger = await customers.ledger(customerId);
      expect(ledger.first.isPayment, isTrue);
      expect(ledger.first.amountCentavos, -4000);
    });

    test('a customer who still owes cannot be deleted', () async {
      final customerId = await customers.insert(const Customer(name: 'Ower'));
      await customers.recordCharge(
        customerId: customerId,
        amountCentavos: 5000,
      );

      expect(await customers.delete(customerId), isFalse);
      expect(await customers.byId(customerId), isNotNull);

      await customers.recordPayment(
        customerId: customerId,
        amountCentavos: 5000,
      );
      expect(await customers.delete(customerId), isTrue);
    });

    test('onlyWithBalance filters to actual debtors', () async {
      final owing = await customers.insert(const Customer(name: 'Owes'));
      await customers.insert(const Customer(name: 'Clear'));
      await customers.recordCharge(customerId: owing, amountCentavos: 100);

      final debtors = await customers.all(onlyWithBalance: true);
      expect(debtors.single.name, 'Owes');
      expect((await customers.all()).length, 2);
    });
  });

  group('reports', () {
    Future<Product> item(int price, int cost) async {
      final id = await products.insert(
        Product(name: 'Item $price', priceCentavos: price, costCentavos: cost),
      );
      return (await products.byId(id))!;
    }

    test('revenue and cash collected diverge when credit is involved',
        () async {
      final product = await item(1000, 600);
      final customerId = await customers.insert(const Customer(name: 'L'));

      await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );

      final summary = await reports.summary(Period.today());
      expect(summary.revenueCentavos, 5000);
      expect(summary.cashSalesCentavos, 2000);
      expect(summary.creditSalesCentavos, 3000);
      // Nothing has been paid on the tab yet.
      expect(summary.cashCollectedCentavos, 2000);
      expect(summary.grossProfitCentavos, 2000);
      expect(summary.saleCount, 2);
      expect(summary.itemCount, 5);
    });

    test('a credit payment shows up as cash collected', () async {
      final product = await item(1000, 600);
      final customerId = await customers.insert(const Customer(name: 'P'));
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );
      await customers.recordPayment(
        customerId: customerId,
        amountCentavos: 1500,
      );

      final summary = await reports.summary(Period.today());
      expect(summary.revenueCentavos, 2000);
      expect(summary.cashSalesCentavos, 0);
      expect(summary.cashCollectedCentavos, 1500);
    });

    test('sales stored under the legacy utang code still count as credit',
        () async {
      final product = await item(1000, 600);
      final customerId = await customers.insert(const Customer(name: 'Old'));
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );
      // Rewrite the row the way an older build would have stored it.
      await db.db.update(
        'sales',
        {'payment_type': 'utang'},
        where: 'id = ?',
        whereArgs: [saleId],
      );

      final summary = await reports.summary(Period.today());
      expect(summary.creditSalesCentavos, 2000);
      expect(summary.cashCollectedCentavos, 0);

      final filtered = await sales.list(paymentType: PaymentType.credit);
      expect(filtered.single.id, saleId);
      expect(filtered.single.paymentType, PaymentType.credit);
    });

    test('expenses reduce net but not gross profit', () async {
      final product = await item(1000, 600);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 5)],
        paymentType: PaymentType.cash,
      );
      await sales.addExpense(amountCentavos: 800, category: 'Electricity');

      final summary = await reports.summary(Period.today());
      expect(summary.grossProfitCentavos, 2000);
      expect(summary.expensesCentavos, 800);
      expect(summary.netProfitCentavos, 1200);
    });

    test('profit is flagged as an estimate when cost is missing', () async {
      final withCost = await item(1000, 600);
      final noCostId = await products.insert(
        const Product(name: 'No cost', priceCentavos: 1000),
      );
      final noCost = (await products.byId(noCostId))!;

      await sales.recordSale(
        lines: [CartLine(product: withCost, qty: 1)],
        paymentType: PaymentType.cash,
      );
      var summary = await reports.summary(Period.today());
      expect(summary.profitIsEstimate, isFalse);

      await sales.recordSale(
        lines: [CartLine(product: noCost, qty: 1)],
        paymentType: PaymentType.cash,
      );
      summary = await reports.summary(Period.today());
      expect(summary.profitIsEstimate, isTrue);
      expect(summary.costCoverage, closeTo(0.5, 0.01));
    });

    test('cancelled sales are excluded from every total', () async {
      final product = await item(1000, 600);
      final keep = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );
      final drop = await sales.recordSale(
        lines: [CartLine(product: product, qty: 9)],
        paymentType: PaymentType.cash,
      );
      await sales.voidSale(drop);

      final summary = await reports.summary(Period.today());
      expect(summary.revenueCentavos, 1000);
      expect(summary.saleCount, 1);

      expect((await sales.list()).map((s) => s.id), [keep]);
      expect((await sales.list(includeVoided: true)).length, 2);
    });

    test('the daily series zero-fills every day in the period', () async {
      final product = await item(1000, 600);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );

      final week = Period.of(PeriodKind.week, DateTime.now());
      final series = await reports.dailySeries(week);
      expect(series.length, 7);
      expect(series.fold<int>(0, (s, d) => s + d.revenueCentavos), 2000);
      expect(series.where((d) => d.saleCount > 0).length, 1);
    });

    test('day, week and month all see the same sale', () async {
      final product = await item(1000, 600);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 4)],
        paymentType: PaymentType.cash,
      );

      for (final kind in PeriodKind.values) {
        final summary = await reports.summary(Period.of(kind, DateTime.now()));
        expect(summary.revenueCentavos, 4000, reason: 'failed for ${kind.name}');
      }
    });

    test('top products ranks by revenue and carries quantity', () async {
      final cheap = await item(500, 300);
      final dear = await item(4000, 3000);
      await sales.recordSale(
        lines: [
          CartLine(product: cheap, qty: 10),
          CartLine(product: dear, qty: 3),
        ],
        paymentType: PaymentType.cash,
      );

      final top = await reports.topProducts(Period.today());
      expect(top.first.name, dear.name);
      expect(top.first.revenueCentavos, 12000);
      expect(top.first.qty, 3);
      expect(top.last.revenueCentavos, 5000);
    });

    test('category totals follow the product category', () async {
      final id = await products.insert(
        const Product(
          name: 'Grouped',
          priceCentavos: 1000,
          costCentavos: 500,
          category: 'Frozen',
        ),
      );
      await sales.recordSale(
        lines: [CartLine(product: (await products.byId(id))!, qty: 3)],
        paymentType: PaymentType.cash,
      );

      final byCategory = await reports.byCategory(Period.today());
      expect(byCategory.single.category, 'Frozen');
      expect(byCategory.single.revenueCentavos, 3000);
      expect(byCategory.single.qty, 3);
    });

    test('hourly buckets cover all 24 hours', () async {
      final product = await item(1000, 600);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );

      final hours = await reports.byHour(Period.today());
      expect(hours.length, 24);
      expect(hours.fold<int>(0, (s, h) => s + h.revenueCentavos), 1000);
      // The bucket must match local time, not UTC.
      expect(hours[DateTime.now().hour].revenueCentavos, 1000);
    });

    test('an empty period reports zero rather than throwing', () async {
      final lastYear = Period.of(
        PeriodKind.month,
        DateTime(DateTime.now().year - 1),
      );
      final summary = await reports.summary(lastYear);
      expect(summary.isEmpty, isTrue);
      expect(summary.revenueCentavos, 0);
      expect(summary.marginPercent, isNull);
      expect(summary.averageSaleCentavos, 0);
    });
  });

  group('backups', () {
    test('a manual backup writes a database and a CSV', () async {
      final id = await products.insert(
        const Product(name: 'Backup me', priceCentavos: 1234),
      );
      await sales.recordSale(
        lines: [CartLine(product: (await products.byId(id))!, qty: 2)],
        paymentType: PaymentType.cash,
      );

      final service = BackupService(
        db,
        rootOverride: Directory(p.join(tempDir.path, 'backups')),
      );
      final result = await service.createManualBackup();

      expect(result.ok, isTrue, reason: result.message);
      expect(await result.file!.database.exists(), isTrue);
      expect(await result.file!.csv!.exists(), isTrue);

      final csv = await result.file!.csv!.readAsString();
      expect(csv, contains('Backup me'));
      expect(csv, contains('sale_id'));
      // 1234 centavos is P12.34 a piece, so two of them is P24.68.
      expect(csv, contains('12.34'));
      expect(csv, contains('24.68'));
    });

    test('the monthly backup runs once per month, not once per launch',
        () async {
      final service = BackupService(
        db,
        rootOverride: Directory(p.join(tempDir.path, 'backups')),
      );

      final first = await service.runMonthlyBackupIfDue();
      expect(first, isNotNull);
      expect(first!.ok, isTrue);

      // Simulates reopening the app the same month.
      expect(await service.runMonthlyBackupIfDue(), isNull);
      expect(await service.runMonthlyBackupIfDue(), isNull);

      expect((await service.listBackups(BackupKind.monthly)).length, 1);
    });

    test('a backup is restorable and carries the data across', () async {
      final id = await products.insert(
        const Product(name: 'Survivor', priceCentavos: 999),
      );
      await sales.recordSale(
        lines: [CartLine(product: (await products.byId(id))!, qty: 1)],
        paymentType: PaymentType.cash,
      );

      final service = BackupService(
        db,
        rootOverride: Directory(p.join(tempDir.path, 'backups')),
      );
      final backup = (await service.createManualBackup()).file!;
      await db.close();

      // Open the backup directly: it must be a complete, valid database.
      final restored = await AppDatabase.openAt(
        backup.database.path,
        seedIfEmpty: false,
      );
      final restoredSales = await SalesRepository(restored).list();
      expect(restoredSales.single.totalCentavos, 999);
      expect((await ProductRepository(restored).byId(id))!.name, 'Survivor');
      await restored.close();

      // Reopen the original so tearDown's close() has something valid.
      db = await AppDatabase.openAt(p.join(tempDir.path, 'test.db'));
    });

    test('a file that is not a BentaGo database is refused', () async {
      final junk = File(p.join(tempDir.path, 'holiday-photo.db'));
      await junk.writeAsString('not a database at all');

      final service = BackupService(
        db,
        rootOverride: Directory(p.join(tempDir.path, 'backups')),
      );
      final result = await service.restoreFrom(junk);
      expect(result.ok, isFalse);
      expect(result.message, contains('not a BentaGo backup'));
    });
  });

  group('migration', () {
    test('a v1 database drops inventory and keeps everything else', () async {
      final path = p.join(tempDir.path, 'legacy.db');

      // Build a database shaped the way schema v1 left it, complete with the
      // stock columns and the stock_movements table.
      final legacy = await openDatabase(
        path,
        version: 1,
        onCreate: (d, _) async {
          await d.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              price_centavos INTEGER NOT NULL,
              cost_centavos INTEGER NOT NULL DEFAULT 0,
              description TEXT, category TEXT, emoji TEXT, barcode TEXT,
              unit_label TEXT NOT NULL DEFAULT 'pc',
              stock INTEGER NOT NULL DEFAULT 0,
              reorder_level INTEGER NOT NULL DEFAULT 0,
              track_stock INTEGER NOT NULL DEFAULT 1,
              archived INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await d.execute('''
            CREATE TABLE stock_movements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              delta INTEGER NOT NULL,
              reason TEXT NOT NULL,
              cost_centavos INTEGER NOT NULL DEFAULT 0,
              moved_at INTEGER NOT NULL,
              day_key TEXT NOT NULL,
              note TEXT
            )
          ''');
          final now = DateTime.now().millisecondsSinceEpoch;
          await d.insert('products', {
            'name': 'Carried over',
            'price_centavos': 1500,
            'cost_centavos': 1000,
            'category': 'Food',
            'stock': 7,
            'created_at': now,
            'updated_at': now,
          });
          await d.insert('stock_movements', {
            'product_id': 1,
            'delta': 12,
            'reason': 'restock',
            'moved_at': now,
            'day_key': '2026-08-01',
          });
        },
      );
      await legacy.close();

      final upgraded = await AppDatabase.openAt(path, seedIfEmpty: false);

      // The product and its money survive the upgrade untouched.
      final saved = (await ProductRepository(upgraded).all()).single;
      expect(saved.name, 'Carried over');
      expect(saved.priceCentavos, 1500);
      expect(saved.costCentavos, 1000);
      expect(saved.category, 'Food');
      expect(saved.marginCentavos, 500);

      final tables = await upgraded.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((t) => t['name'] as String).contains('stock_movements'),
        isFalse,
        reason: 'the movements table should be gone',
      );

      expect(await upgraded.db.getVersion(), AppDatabase.schemaVersion);
      await upgraded.close();
    });
  });
}
