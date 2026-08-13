import 'dart:io';

import 'package:bentago/core/format.dart';
import 'package:bentago/core/period.dart';
import 'package:bentago/data/app_database.dart';
import 'package:bentago/data/backup_service.dart';
import 'package:bentago/data/customer_repository.dart';
import 'package:bentago/data/export_service.dart';
import 'package:bentago/data/models.dart';
import 'package:bentago/data/product_repository.dart';
import 'package:bentago/data/report_repository.dart';
import 'package:bentago/data/sales_repository.dart';
import 'package:bentago/demo/demo_seed.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Reads a numeric cell back as a plain number. The excel package narrows a
/// whole double to an int when decoding, so a test that cares about the value
/// must not also care about which of the two wrappers carried it.
num? numberAt(Sheet sheet, int column, int row) {
  final value = sheet.rows[row][column]?.value;
  return switch (value) {
    IntCellValue() => value.value,
    DoubleCellValue() => value.value,
    _ => null,
  };
}

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

  /// Corrections replace the undo that used to live on the sell screen. They
  /// run against a recorded sale, so the invariant that matters is that the
  /// price the item sold at is never revisited -- only how many of them.
  group('correcting a sale', () {
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

    test('lowering a quantity re-totals the sale', () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 2,
      );

      final after = await sales.byId(saleId);
      expect(after!.items.single.qty, 2);
      expect(after.totalCentavos, 2000);
      expect(after.costCentavos, 1400);
      expect(after.profitCentavos, 600);
      expect(after.voided, isFalse);
    });

    test('raising a quantity re-totals the sale', () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 4,
      );

      final after = await sales.byId(saleId);
      expect(after!.totalCentavos, 4000);
      expect(after.costCentavos, 2800);
    });

    test('the correction uses the recorded price, not the current one',
        () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      // The shelf price triples after the sale was recorded.
      await products.update(
        product.copyWith(priceCentavos: 3000, costCentavos: 2100),
      );

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 2,
      );

      final after = await sales.byId(saleId);
      expect(after!.items.single.unitPriceCentavos, 1000);
      expect(after.items.single.unitCostCentavos, 700);
      // 2 at the price it actually sold for, not 2 at today's price.
      expect(after.totalCentavos, 2000);
      expect(after.costCentavos, 1400);
    });

    test('taking one line off a multi-line sale leaves the rest', () async {
      final a = await item(name: 'Piattos', price: 2000, cost: 1700);
      final b = await item(name: 'Coke', price: 2500, cost: 2150);
      final saleId = await sales.recordSale(
        lines: [
          CartLine(product: a, qty: 2),
          CartLine(product: b, qty: 1),
        ],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);
      final piattos =
          before!.items.firstWhere((i) => i.productName == 'Piattos');

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: piattos.id!,
        qty: 0,
      );

      final after = await sales.byId(saleId);
      expect(after!.items, hasLength(1));
      expect(after.items.single.productName, 'Coke');
      expect(after.totalCentavos, 2500);
      expect(after.costCentavos, 2150);
      expect(after.voided, isFalse);
    });

    test('taking off the last line cancels the sale and keeps the record',
        () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 0,
      );

      final after = await sales.byId(saleId);
      expect(after!.voided, isTrue);
      // The line stays: a cancelled sale still says what was rung up.
      expect(after.items, hasLength(1));

      final summary = await reports.summary(Period.today());
      expect(summary.revenueCentavos, 0);
      expect(summary.saleCount, 0);
    });

    test('correcting a credit sale moves the customer balance to match',
        () async {
      final product = await item(price: 1000, cost: 700);
      final customerId =
          await customers.insert(const Customer(name: 'Aling Nena'));
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );
      expect((await customers.byId(customerId))!.balanceCentavos, 3000);

      final before = await sales.byId(saleId);
      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 1,
      );

      expect((await customers.byId(customerId))!.balanceCentavos, 1000);

      // Appended, not rewritten -- the original charge is still on the ledger.
      final ledger = await customers.ledger(customerId);
      expect(ledger, hasLength(2));
      expect(
        ledger.map((e) => e.amountCentavos).toList()..sort(),
        [-2000, 3000],
      );
    });

    test('raising a credit quantity increases the balance', () async {
      final product = await item(price: 1000, cost: 700);
      final customerId =
          await customers.insert(const Customer(name: 'Mang Tony'));
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );

      final before = await sales.byId(saleId);
      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 3,
      );

      expect((await customers.byId(customerId))!.balanceCentavos, 3000);
    });

    test('cancelling the last line of a credit sale clears the whole tab',
        () async {
      final product = await item(price: 1000, cost: 700);
      final customerId =
          await customers.insert(const Customer(name: 'Aling Rosa'));
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );

      final before = await sales.byId(saleId);
      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 0,
      );

      expect((await customers.byId(customerId))!.balanceCentavos, 0);
      expect((await sales.byId(saleId))!.voided, isTrue);
    });

    test('the edit is stamped on the sale so a total can be explained',
        () async {
      final product = await item(name: 'Piattos', price: 2000, cost: 1700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 2,
      );

      final after = await sales.byId(saleId);
      expect(after!.note, contains('Piattos 3→2'));
      expect(after.note, contains('edited'));
    });

    test('setting the same quantity changes nothing at all', () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 2,
      );

      final after = await sales.byId(saleId);
      expect(after!.totalCentavos, 2000);
      // No stamp for a no-op.
      expect(after.note, isNull);
    });

    test('a negative quantity is refused', () async {
      final product = await item();
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      expect(
        () => sales.setSaleItemQty(
          saleId: saleId,
          itemId: before!.items.single.id!,
          qty: -1,
        ),
        throwsArgumentError,
      );
    });

    test('an unknown line is ignored rather than corrupting the total',
        () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );

      await sales.setSaleItemQty(saleId: saleId, itemId: 999999, qty: 1);

      final after = await sales.byId(saleId);
      expect(after!.totalCentavos, 2000);
      expect(after.items, hasLength(1));
    });

    test('corrected totals flow through to the reports', () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 5)],
        paymentType: PaymentType.cash,
      );
      final before = await sales.byId(saleId);

      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: before!.items.single.id!,
        qty: 2,
      );

      final summary = await reports.summary(Period.today());
      expect(summary.revenueCentavos, 2000);
      expect(summary.grossProfitCentavos, 600);
      expect(summary.itemCount, 2);
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

  /// The exported report is a flat list of sold lines with the two totals above
  /// it. Both writers are checked by reading the file back, not by trusting that
  /// the call returned without throwing.
  group('exporting reports', () {
    late ExportService export;
    late Directory reportsDir;

    setUp(() async {
      reportsDir = Directory(p.join(tempDir.path, 'reports'));
      export = ExportService(db, rootOverride: reportsDir);
    });

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

    test('one row per sold line, not one per transaction', () async {
      final a = await item(name: 'Piattos', price: 2000, cost: 1700);
      final b = await item(name: 'Coke', price: 2500, cost: 2150);
      await sales.recordSale(
        lines: [
          CartLine(product: a, qty: 2),
          CartLine(product: b, qty: 1),
        ],
        paymentType: PaymentType.cash,
      );

      final data = await export.gather(Period.today());
      expect(data.lines, hasLength(2));
      expect(data.saleCount, 1);
      expect(
        data.lines.map((l) => l.product).toList(),
        containsAll(['Piattos', 'Coke']),
      );
    });

    test('gross sales and profit are totalled per line and overall', () async {
      final product = await item(price: 2000, cost: 1700);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );

      final data = await export.gather(Period.today());
      final line = data.lines.single;
      expect(line.qty, 3);
      expect(line.grossCentavos, 6000);
      expect(line.costCentavos, 5100);
      expect(line.profitCentavos, 900);

      expect(data.grossCentavos, 6000);
      expect(data.profitCentavos, 900);
      expect(data.qty, 3);
    });

    test('cancelled sales are left out of the report', () async {
      final product = await item(price: 1000, cost: 700);
      final keep = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );
      final drop = await sales.recordSale(
        lines: [CartLine(product: product, qty: 4)],
        paymentType: PaymentType.cash,
      );
      await sales.voidSale(drop);

      final data = await export.gather(Period.today());
      expect(data.lines, hasLength(1));
      expect(data.lines.single.saleId, keep);
      expect(data.grossCentavos, 1000);
    });

    test('a line taken off a sale is gone from the report', () async {
      final a = await item(name: 'Piattos', price: 2000, cost: 1700);
      final b = await item(name: 'Coke', price: 2500, cost: 2150);
      final saleId = await sales.recordSale(
        lines: [
          CartLine(product: a, qty: 2),
          CartLine(product: b, qty: 1),
        ],
        paymentType: PaymentType.cash,
      );
      final sale = await sales.byId(saleId);
      final piattos =
          sale!.items.firstWhere((i) => i.productName == 'Piattos');
      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: piattos.id!,
        qty: 0,
      );

      final data = await export.gather(Period.today());
      expect(data.lines, hasLength(1));
      expect(data.lines.single.product, 'Coke');
      expect(data.grossCentavos, 2500);
    });

    test('a corrected quantity is reported at its new value', () async {
      final product = await item(price: 1000, cost: 700);
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 5)],
        paymentType: PaymentType.cash,
      );
      final sale = await sales.byId(saleId);
      await sales.setSaleItemQty(
        saleId: saleId,
        itemId: sale!.items.single.id!,
        qty: 2,
      );

      final data = await export.gather(Period.today());
      expect(data.lines.single.qty, 2);
      expect(data.grossCentavos, 2000);
      expect(data.profitCentavos, 600);
    });

    test('a range outside the sales reports nothing rather than throwing',
        () async {
      final product = await item();
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );

      final lastYear = Period.of(
        PeriodKind.year,
        DateTime(DateTime.now().year - 1, 6),
      );
      final data = await export.gather(lastYear);
      expect(data.isEmpty, isTrue);
      expect(data.grossCentavos, 0);
      expect(data.profitCentavos, 0);
      expect(data.saleCount, 0);
    });

    test('profit is flagged as an estimate when a line has no cost', () async {
      final costed = await item(name: 'Costed', price: 1000, cost: 700);
      await sales.recordSale(
        lines: [CartLine(product: costed, qty: 1)],
        paymentType: PaymentType.cash,
      );
      expect((await export.gather(Period.today())).profitIsEstimate, isFalse);

      final uncosted = await item(name: 'No cost', price: 1000, cost: 0);
      await sales.recordSale(
        lines: [CartLine(product: uncosted, qty: 1)],
        paymentType: PaymentType.cash,
      );
      expect((await export.gather(Period.today())).profitIsEstimate, isTrue);
    });

    test('legacy utang rows are labelled Credit in the report', () async {
      final product = await item(price: 1000, cost: 700);
      final customerId =
          await customers.insert(const Customer(name: 'Aling Beth'));
      final saleId = await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.credit,
        customerId: customerId,
      );
      await db.db.update(
        'sales',
        {'payment_type': 'utang'},
        where: 'id = ?',
        whereArgs: [saleId],
      );

      final data = await export.gather(Period.today());
      expect(data.lines.single.payment, 'Credit');
      expect(data.lines.single.customer, 'Aling Beth');
    });

    test('the excel sheet carries the totals above the line table', () async {
      final product = await item(name: 'Piattos', price: 2000, cost: 1700);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );

      final data = await export.gather(Period.today());
      final book = Excel.decodeBytes(export.buildExcel(data));
      final sheet = book.tables['Sales'];
      expect(sheet, isNotNull);

      String? textAt(int column, int row) =>
          sheet!.rows[row][column]?.value?.toString();

      // Totals first, then the header row, then the data.
      final flat = sheet!.rows
          .map((r) => r.map((c) => c?.value?.toString() ?? '').join('|'))
          .toList();
      final totalsRow =
          flat.indexWhere((r) => r.startsWith('Total gross sales'));
      final headerRow = flat.indexWhere((r) => r.startsWith('Date|Time'));
      expect(totalsRow, greaterThanOrEqualTo(0));
      expect(headerRow, greaterThan(totalsRow));

      expect(numberAt(sheet, 1, totalsRow), 60);
      expect(numberAt(sheet, 1, totalsRow + 1), 9);

      // The single data line, immediately after the header.
      final dataRow = headerRow + 1;
      expect(textAt(3, dataRow), 'Piattos');
      expect(numberAt(sheet, 4, dataRow), 3);
      expect(numberAt(sheet, 7, dataRow), 60);
      expect(numberAt(sheet, 8, dataRow), 9);
      expect(textAt(9, dataRow), 'Cash');
    });

    test('excel money lands as numbers, not text, so it can be re-totalled',
        () async {
      final product = await item(price: 2000, cost: 1725);
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 3)],
        paymentType: PaymentType.cash,
      );

      final data = await export.gather(Period.today());
      final sheet = Excel.decodeBytes(export.buildExcel(data)).tables['Sales']!;
      final headerRow = sheet.rows.indexWhere(
        (r) => r.isNotEmpty && r.first?.value?.toString() == 'Date',
      );
      final dataRow = headerRow + 1;

      // Numeric, not a string -- that is the whole reason to write xlsx rather
      // than reuse the CSV the backup already produces. Whether a whole amount
      // comes back as an int or a double is the library's business.
      for (final column in [5, 6, 7, 8]) {
        final cell = sheet.rows[dataRow][column]?.value;
        expect(
          cell,
          anyOf(isA<IntCellValue>(), isA<DoubleCellValue>()),
          reason: 'column $column should be numeric',
        );
      }
      // Centavos survive the conversion to pesos.
      expect(numberAt(sheet, 6, dataRow), 17.25);
      expect(numberAt(sheet, 7, dataRow), 60);
      expect(numberAt(sheet, 8, dataRow), closeTo(8.25, 0.001));
    });

    test('the pdf writes a real document', () async {
      final product = await item();
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 2)],
        paymentType: PaymentType.cash,
      );

      final bytes = await export.buildPdf(await export.gather(Period.today()));
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('an empty period still produces both files', () async {
      final data = await export.gather(Period.today());
      expect(data.isEmpty, isTrue);

      expect(export.buildExcel(data), isNotEmpty);
      final pdf = await export.buildPdf(data);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('the file lands in the reports folder named after the period',
        () async {
      final product = await item();
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );

      final period = Period.of(PeriodKind.month, DateTime.now());
      final xlsx = await export.export(period, ExportFormat.excel);
      final pdf = await export.export(period, ExportFormat.pdf);

      expect(await xlsx.exists(), isTrue);
      expect(await pdf.exists(), isTrue);
      expect(
        p.basename(xlsx.path),
        'bentago-report-${Dates.monthKey(DateTime.now())}.xlsx',
      );
      expect(p.basename(pdf.path), endsWith('.pdf'));
      expect(p.dirname(xlsx.path), reportsDir.path);
    });

    test('each period kind exports to its own file name', () async {
      final product = await item();
      await sales.recordSale(
        lines: [CartLine(product: product, qty: 1)],
        paymentType: PaymentType.cash,
      );

      final now = DateTime.now();
      final names = <String>{};
      for (final kind in [
        PeriodKind.day,
        PeriodKind.month,
        PeriodKind.quarter,
        PeriodKind.year,
      ]) {
        final file = await export.export(Period.of(kind, now), ExportFormat.pdf);
        names.add(p.basename(file.path));
      }
      // Four kinds, four files -- exporting a year must not overwrite the month.
      expect(names, hasLength(4));
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

  // The seeder behind the recorded demo (tool/demo/). It writes rows directly
  // rather than through the repositories, because it has to date them into the
  // past, so nothing else enforces the invariants for it.
  //
  // Worth testing despite never shipping: without these, a regression only
  // surfaces as something wrong in a twelve-minute video.
  group('demo seeder', () {
    setUp(() => DemoSeeder.reset(db));

    test('writes six weeks of sales, all of them live', () async {
      final count = await sales.count();
      expect(count, greaterThan(400));

      final first = await reports.firstSaleDate();
      expect(first, isNotNull);
      final span = DateTime.now().difference(first!).inDays;
      expect(span, greaterThanOrEqualTo(40));
    });

    test('every dated row agrees with its own day_key', () async {
      for (final table in ['sales', 'ledger_entries', 'expenses']) {
        final stamp = switch (table) {
          'ledger_entries' => 'entered_at',
          'expenses' => 'spent_at',
          _ => 'sold_at',
        };
        final rows = await db.db.query(table, columns: [stamp, 'day_key']);
        expect(rows, isNotEmpty, reason: '$table should have been seeded');

        for (final row in rows) {
          final at = DateTime.fromMillisecondsSinceEpoch(row[stamp] as int);
          expect(
            row['day_key'],
            Dates.dayKey(at),
            reason: '$table row stamped $at carries the wrong day_key',
          );
        }
      }
    });

    test('nothing is dated into the future', () async {
      final now = DateTime.now();
      final rows = await db.db.rawQuery(
        'SELECT MAX(sold_at) AS latest FROM sales',
      );
      final latest =
          DateTime.fromMillisecondsSinceEpoch(rows.first['latest'] as int);
      expect(latest.isAfter(now), isFalse,
          reason: 'a sale stamped ahead of the clock reads as a bug on screen');
    });

    test('money is only ever whole centavos', () async {
      // A REAL would come back as a double here. Catches a stray `/ 2` or a
      // percentage that skipped integer division.
      final rows = await db.db.rawQuery('''
        SELECT total_centavos, cost_centavos FROM sales
        UNION ALL
        SELECT unit_price_centavos, unit_cost_centavos FROM sale_items
      ''');
      for (final row in rows) {
        expect(row['total_centavos'], isA<int>());
        expect(row['cost_centavos'], isA<int>());
      }
    });

    test('no tab ever reads as negative at any point in its history', () async {
      // The bug this exists for: settlements were once stamped 9am on the same
      // day as the charges they paid off, so reading the ledger in order showed
      // a customer in credit before they had paid.
      final all = await customers.all();
      expect(all, isNotEmpty);

      for (final customer in all) {
        final entries = await customers.ledger(customer.id!);
        if (entries.isEmpty) continue;

        // `ledger()` returns newest-first; walk it forwards.
        final chronological = entries.reversed.toList();
        var running = 0;
        for (final entry in chronological) {
          running += entry.amountCentavos;
          expect(
            running,
            greaterThanOrEqualTo(0),
            reason: '${customer.name} owes ${Money.format(running)} after the '
                'entry of ${Money.format(entry.amountCentavos)} on '
                '${entry.enteredAt} -- a tab cannot go negative',
          );
        }
        // And the sum of the entries is the balance the screens show.
        expect(running, customer.balanceCentavos);
      }
    });

    test('somebody still owes money, or the credit screen is empty', () async {
      expect(await customers.countWithBalance(), greaterThanOrEqualTo(1));
      expect(await customers.totalOutstandingCentavos(), greaterThan(0));
    });

    test('one sale is voided, and it reversed a tab rather than a cash sale',
        () async {
      final voided = await db.db.query('sales', where: 'voided = 1');
      expect(voided, hasLength(1), reason: 'exactly one cancelled sale');

      final sale = voided.single;
      expect(
        PaymentTypeX.fromCode(sale['payment_type'] as String?),
        PaymentType.credit,
        reason: 'cancelling a cash sale leaves the ledger untouched, so it '
            'would not demonstrate the adjusting entry',
      );

      // Reversed by appending, not by editing or deleting the charge.
      final entries = await db.db.query(
        'ledger_entries',
        where: 'sale_id = ?',
        whereArgs: [sale['id']],
        orderBy: 'entered_at, id',
      );
      expect(entries, hasLength(2), reason: 'the charge and its reversal');
      expect(entries.first['amount_centavos'], sale['total_centavos']);
      expect(entries.last['amount_centavos'], -(sale['total_centavos'] as int));
    });

    test('the demo trades at a profit in every window it shows', () async {
      // Seeded expenses must not double-count what sale_items already carries as
      // unit_cost_centavos: gross profit has taken the cost of goods off once,
      // and net profit subtracts expenses from that. Booking the restocking
      // spend as an expense too showed the store losing money every week.
      for (final kind in [PeriodKind.week, PeriodKind.month]) {
        final summary =
            await reports.summary(Period.of(kind, DateTime.now()));
        expect(
          summary.netProfitCentavos,
          greaterThan(0),
          reason: 'net profit over the ${kind.label.toLowerCase()} is '
              '${Money.format(summary.netProfitCentavos)} -- a demo should not '
              'open on a loss',
        );
        expect(summary.expensesCentavos, lessThan(summary.grossProfitCentavos));
      }
    });

    test('running it twice leaves the same data, not twice the data', () async {
      final before = await sales.count();
      final owedBefore = await customers.totalOutstandingCentavos();

      await DemoSeeder.reset(db);

      expect(await sales.count(), before);
      expect(await customers.totalOutstandingCentavos(), owedBefore);
      expect((await customers.all()).length, DemoSeeder.customerCount);
    });
  });
}
