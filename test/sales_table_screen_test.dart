import 'package:bentago/core/theme.dart';
import 'package:bentago/data/models.dart';
import 'package:bentago/screens/sales_table_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the sale line editor as a widget.
///
/// This file exists because the editor shipped unusable and nothing noticed:
/// the dialog put a `Spacer` among `AlertDialog.actions`, and `actions` are laid
/// out in an `OverflowBar`, which is not a `Flex` -- so applying the flex parent
/// data threw while the dialog was building and tapping a line item did nothing
/// but log an error. `flutter analyze` cannot see that, and every other test
/// calls `SalesRepository.setSaleItemQty` directly, so the suite stayed green
/// while the feature was unreachable from the app.
///
/// The repository half of correcting a sale is covered in database_test.dart.
/// What is worth testing here is that the dialog builds at all, that its
/// arithmetic matches what the repository will do, and that the destructive
/// action is the one the button says it is.
void main() {
  const piattos = SaleItem(
    id: 11,
    saleId: 1,
    productName: 'Piattos',
    qty: 2,
    unitPriceCentavos: 2000,
    unitCostCentavos: 1700,
  );
  const coke = SaleItem(
    id: 12,
    saleId: 1,
    productName: 'Coke',
    qty: 1,
    unitPriceCentavos: 2500,
    unitCostCentavos: 2150,
  );

  Sale saleOf(
    List<SaleItem> items, {
    PaymentType paymentType = PaymentType.cash,
  }) {
    return Sale(
      id: 1,
      soldAt: DateTime(2026, 8, 13, 10, 30),
      totalCentavos:
          items.fold<int>(0, (sum, i) => sum + i.lineTotalCentavos),
      costCentavos: items.fold<int>(0, (sum, i) => sum + i.lineCostCentavos),
      paymentType: paymentType,
      items: items,
    );
  }

  /// Pumps the dialog and hands back a getter for whatever it pops.
  Future<int? Function()> pumpEditor(
    WidgetTester tester, {
    required Sale sale,
    required SaleItem item,
    Brightness brightness = Brightness.light,
  }) async {
    int? result;
    var popped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<int>(
                    context: context,
                    builder: (_) =>
                        SaleLineEditorDialog(sale: sale, item: item),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    return () {
      expect(popped, isTrue, reason: 'the dialog has not closed yet');
      return result;
    };
  }

  testWidgets('the editor builds and offers quantity and removal',
      (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    // The regression this file exists for: this used to throw during build.
    expect(tester.takeException(), isNull);

    expect(find.text('Piattos'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Remove this item'), findsOneWidget);
  });

  testWidgets('it builds in the dark theme too', (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Remove this item'), findsOneWidget);
  });

  testWidgets('the price it sold at cannot be edited', (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    // Quantity is a stepper, and there is no field to retype a price into.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('₱20.00 each · sold at this price'), findsOneWidget);
  });

  testWidgets('nothing can be saved until the quantity moves', (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    FilledButton save() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save'),
        );
    expect(save().onPressed, isNull);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull);
  });

  testWidgets('it previews the new sale total, not just the line',
      (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]), // 2 x P20 + 1 x P25 = P65
      item: piattos,
    );

    expect(find.text('₱40.00'), findsOneWidget); // the line as it stands
    expect(find.text('₱65.00'), findsOneWidget); // the sale as it stands

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // 3 x P20 = P60 on the line, so the sale becomes P85, and the figure it
    // replaces is shown struck through rather than silently swapped.
    expect(find.text('₱60.00'), findsOneWidget);
    expect(find.text('₱85.00'), findsOneWidget);
    expect(find.text('₱65.00'), findsOneWidget);
  });

  testWidgets('saving pops the chosen quantity', (tester) async {
    final result = await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(result(), 3);
  });

  testWidgets('the stepper will not walk a line down to nothing',
      (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    // Removal is an explicit, confirmed action -- not somewhere you arrive by
    // holding the minus button.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('removing a line pops zero', (tester) async {
    final result = await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    await tester.tap(find.text('Remove this item'));
    await tester.pumpAndSettle();

    expect(result(), 0);
  });

  testWidgets('the only line on a sale offers to cancel the sale instead',
      (tester) async {
    final result = await pumpEditor(
      tester,
      sale: saleOf([piattos]),
      item: piattos,
    );

    expect(find.text('Cancel this sale'), findsOneWidget);
    expect(find.text('Remove this item'), findsNothing);

    await tester.tap(find.text('Cancel this sale'));
    await tester.pumpAndSettle();
    expect(result(), 0);
  });

  testWidgets('backing out pops nothing at all', (tester) async {
    final result = await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });

  testWidgets('a credit sale says the tab moves with the total',
      (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke], paymentType: PaymentType.credit),
      item: piattos,
    );
    expect(
      find.text('The customer\'s credit moves with the total.'),
      findsOneWidget,
    );
  });

  testWidgets('a cash sale does not mention credit', (tester) async {
    await pumpEditor(
      tester,
      sale: saleOf([piattos, coke]),
      item: piattos,
    );
    expect(
      find.text('The customer\'s credit moves with the total.'),
      findsNothing,
    );
  });
}
