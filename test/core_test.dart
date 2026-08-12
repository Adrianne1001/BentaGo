import 'package:bentago/core/format.dart';
import 'package:bentago/core/period.dart';
import 'package:bentago/data/export_service.dart';
import 'package:bentago/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the two pieces of pure logic every screen and report depends on:
/// centavo arithmetic and period boundaries. Both are easy to get subtly wrong
/// and expensive to notice later -- a bad rounding rule or an off-by-one week
/// boundary shows up as a total that quietly disagrees with the notebook.
void main() {
  group('Money.parse', () {
    test('reads whole pesos as centavos', () {
      expect(Money.parse('12'), 1200);
    });

    test('reads decimals', () {
      expect(Money.parse('12.50'), 1250);
      expect(Money.parse('0.25'), 25);
    });

    test('ignores thousands separators and the peso sign', () {
      expect(Money.parse('1,250'), 125000);
      expect(Money.parse('₱12.50'), 1250);
      expect(Money.parse('₱ 1,250.75'), 125075);
    });

    test('rounds rather than truncating the third decimal', () {
      expect(Money.parse('12.005'), 1201);
      expect(Money.parse('12.004'), 1200);
    });

    test('returns null for anything unusable', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('   '), isNull);
    });
  });

  group('Money.format', () {
    test('formats centavos as pesos', () {
      expect(Money.format(1250), '₱12.50');
      expect(Money.format(125000), '₱1,250.00');
      expect(Money.format(0), '₱0.00');
    });

    test('formatShort drops centavos only when they are zero', () {
      expect(Money.formatShort(1200), '₱12');
      expect(Money.formatShort(1250), '₱12.50');
    });

    test('plain omits the symbol for CSV columns', () {
      expect(Money.plain(125075), '1,250.75');
    });

    test('survives a parse/format round trip', () {
      for (final centavos in [0, 25, 1200, 1250, 125075, 9999999]) {
        expect(Money.parse(Money.plain(centavos)), centavos);
      }
    });
  });

  group('Period', () {
    test('a day runs midnight to end of the same day', () {
      final period = Period.of(PeriodKind.day, DateTime(2026, 8, 11, 14, 30));
      expect(period.start, DateTime(2026, 8, 11));
      expect(period.end.day, 11);
      expect(period.end.hour, 23);
      expect(period.dayCount, 1);
    });

    test('weeks start on Monday', () {
      // 2026-08-11 is a Tuesday.
      final period = Period.of(PeriodKind.week, DateTime(2026, 8, 11));
      expect(period.start.weekday, DateTime.monday);
      expect(period.start, DateTime(2026, 8, 10));
      expect(period.end.day, 16);
      expect(period.dayCount, 7);
    });

    test('a week anchored on Sunday stays in that same week', () {
      // 2026-08-16 is a Sunday -- it must not roll into the next week.
      final period = Period.of(PeriodKind.week, DateTime(2026, 8, 16));
      expect(period.start, DateTime(2026, 8, 10));
      expect(period.dayCount, 7);
    });

    test('months cover the whole calendar month', () {
      final period = Period.of(PeriodKind.month, DateTime(2026, 2, 15));
      expect(period.start, DateTime(2026, 2));
      expect(period.end.day, 28);
      expect(period.dayCount, 28);
    });

    test('handles a leap February', () {
      final period = Period.of(PeriodKind.month, DateTime(2028, 2, 15));
      expect(period.end.day, 29);
      expect(period.dayCount, 29);
    });

    test('shifting a month crosses the year boundary', () {
      final january = Period.of(PeriodKind.month, DateTime(2026));
      final december = january.shift(-1);
      expect(december.start, DateTime(2025, 12));
      expect(december.dayCount, 31);
    });

    test('days() zero-fills the whole range for the chart', () {
      final period = Period.of(PeriodKind.week, DateTime(2026, 8, 11));
      expect(period.days.length, 7);
      expect(Dates.dayKey(period.days.first), '2026-08-10');
      expect(Dates.dayKey(period.days.last), '2026-08-16');
    });

    test('equality holds so provider families do not thrash', () {
      final a = Period.of(PeriodKind.month, DateTime(2026, 8, 1, 9));
      final b = Period.of(PeriodKind.month, DateTime(2026, 8, 20, 17));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('withKind re-anchors on the same start date', () {
      final day = Period.of(PeriodKind.day, DateTime(2026, 8, 11));
      expect(day.withKind(PeriodKind.month).start, DateTime(2026, 8));
    });

    test('a quarter spans three whole months', () {
      final q3 = Period.of(PeriodKind.quarter, DateTime(2026, 8, 13));
      expect(q3.start, DateTime(2026, 7));
      expect(q3.end.month, 9);
      expect(q3.end.day, 30);
      expect(q3.dayCount, 92);
      expect(q3.label, 'Q3 2026');
    });

    test('every month lands in the quarter that contains it', () {
      const expected = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4];
      for (var month = 1; month <= 12; month++) {
        final period = Period.of(PeriodKind.quarter, DateTime(2026, month, 15));
        expect(
          period.label,
          'Q${expected[month - 1]} 2026',
          reason: 'month $month',
        );
        expect(period.start.month, ((month - 1) ~/ 3) * 3 + 1);
      }
    });

    test('shifting a quarter crosses the year boundary', () {
      final q1 = Period.of(PeriodKind.quarter, DateTime(2026, 2, 3));
      final q4 = q1.shift(-1);
      expect(q4.start, DateTime(2025, 10));
      expect(q4.label, 'Q4 2025');
    });

    test('a year covers January to December, leap years included', () {
      final leap = Period.of(PeriodKind.year, DateTime(2028, 6, 1));
      expect(leap.start, DateTime(2028));
      expect(leap.dayCount, 366);
      expect(leap.label, '2028');
      expect(Period.of(PeriodKind.year, DateTime(2026)).dayCount, 365);
    });

    test('shifting a year steps one year', () {
      final year = Period.of(PeriodKind.year, DateTime(2026, 5, 5));
      expect(year.shift(-1).label, '2025');
      expect(year.shift(1).label, '2027');
    });

    test('a custom range covers both end days in full', () {
      final range = Period.range(DateTime(2026, 8, 3), DateTime(2026, 8, 5));
      expect(range.kind, PeriodKind.custom);
      expect(range.startKey, '2026-08-03');
      expect(range.endKey, '2026-08-05');
      expect(range.dayCount, 3);
      // End of day, so a sale at 23:30 on the last day is inside the range.
      expect(range.end.hour, 23);
    });

    test('a backwards custom range is straightened out, not left empty', () {
      final range = Period.range(DateTime(2026, 8, 5), DateTime(2026, 8, 3));
      expect(range.startKey, '2026-08-03');
      expect(range.endKey, '2026-08-05');
      expect(range.dayCount, 3);
    });

    test('shifting a custom range slides it by its own length', () {
      final range = Period.range(DateTime(2026, 8, 10), DateTime(2026, 8, 12));
      final before = range.shift(-1);
      expect(before.startKey, '2026-08-07');
      expect(before.endKey, '2026-08-09');
      expect(before.dayCount, range.dayCount);
    });

    test('fileLabel is distinct per kind so exports do not overwrite', () {
      final anchor = DateTime(2026, 8, 13);
      final labels = {
        Period.of(PeriodKind.day, anchor).fileLabel,
        Period.of(PeriodKind.month, anchor).fileLabel,
        Period.of(PeriodKind.quarter, anchor).fileLabel,
        Period.of(PeriodKind.year, anchor).fileLabel,
      };
      expect(labels, hasLength(4));
      expect(labels, contains('2026-08-13'));
      expect(labels, contains('2026-08'));
      expect(labels, contains('2026-Q3'));
      expect(labels, contains('2026'));
    });

    test('the browsing strip stays day, week and month', () {
      // Quarter and year exist for export only; adding them to this list would
      // put two more chips on the reports strip.
      expect(browsablePeriodKinds, [
        PeriodKind.day,
        PeriodKind.week,
        PeriodKind.month,
      ]);
    });
  });

  /// The product form asks for a markup (profit over cost) while every report
  /// talks in margin (profit over price). These are different numbers on the
  /// same product and the two must never be quietly swapped.
  group('markup and margin', () {
    test('markup adds a percentage on top of the cost', () {
      expect(Product.priceFromMarkup(1000, 25), 1250);
      expect(Product.priceFromMarkup(1400, 20), 1680);
      expect(Product.priceFromMarkup(1000, 0), 1000);
    });

    test('a price implies the markup that produced it', () {
      expect(Product.markupFor(1000, 1250), 25);
      expect(Product.markupFor(1400, 1680), closeTo(20, 0.001));
    });

    test('markup and price round-trip through each other', () {
      for (final cost in [150, 700, 1400, 3500]) {
        for (final markup in [0.0, 10.0, 20.0, 25.0, 50.0, 100.0]) {
          final price = Product.priceFromMarkup(cost, markup);
          expect(
            Product.markupFor(cost, price),
            closeTo(markup, 0.5),
            reason: 'cost $cost at $markup%',
          );
        }
      }
    });

    test('markup and margin are different figures on the same product', () {
      const product =
          Product(name: 'Pancit Canton', priceCentavos: 1700, costCentavos: 1400);
      // 300 over a 1400 cost is 21.4%; 300 of a 1700 price is 17.6%.
      expect(product.markupPercent, closeTo(21.43, 0.01));
      expect(product.marginPercent, closeTo(17.65, 0.01));
    });

    test('markup is undefined rather than zero without a cost', () {
      const product = Product(name: 'No cost', priceCentavos: 1000);
      expect(product.markupPercent, isNull);
      expect(product.marginPercent, isNull);
      expect(Product.markupFor(0, 1000), isNull);
    });

    test('a price below cost reads as a negative markup', () {
      expect(Product.markupFor(1000, 800), -20);
      expect(Product.priceFromMarkup(1000, -20), 800);
    });

    test('rounding lands on whole centavos, never a fraction', () {
      // 333 at 15% is 382.95 centavos.
      expect(Product.priceFromMarkup(333, 15), 383);
    });
  });

  /// The PDF writer only carries the 14 standard fonts, which are WinAnsi. Any
  /// character beyond that is dropped silently by the writer, so it gets folded
  /// down to an ASCII stand-in first.
  group('pdfSafe', () {
    test('typographic dashes become hyphens', () {
      expect(pdfSafe('Aug 1 – Aug 7'), 'Aug 1 - Aug 7');
      expect(pdfSafe('BentaGo — Sales report'), 'BentaGo - Sales report');
    });

    test('the peso sign is spelled out', () {
      expect(pdfSafe('₱1,250.00'), 'PHP1,250.00');
    });

    test('curly quotes and ellipses flatten', () {
      expect(pdfSafe('Nena’s tab'), "Nena's tab");
      expect(pdfSafe('“paid”'), '"paid"');
      expect(pdfSafe('more…'), 'more...');
    });

    test('plain text and Latin-1 accents pass through untouched', () {
      expect(pdfSafe('Lucky Me Pancit Canton'), 'Lucky Me Pancit Canton');
      expect(pdfSafe('Café 3-in-1'), 'Café 3-in-1');
      expect(pdfSafe('1,250.75'), '1,250.75');
    });

    test('a product name with an emoji stays readable', () {
      // Names are typed by the user, so anything can arrive.
      expect(pdfSafe('Coke 🥤'), 'Coke ?');
    });

    test('every period label survives the fold to ASCII', () {
      final anchor = DateTime(2026, 8, 13);
      for (final kind in PeriodKind.values) {
        final label = Period.of(kind, anchor).label;
        expect(
          pdfSafe(label).codeUnits.every((c) => c >= 0x20 && c <= 0xFF),
          isTrue,
          reason: '$kind label "$label"',
        );
      }
      final range = Period.range(anchor, DateTime(2026, 9, 2)).label;
      expect(pdfSafe(range), isNot(contains('–')));
    });
  });

  group('Dates', () {
    test('dayKey is local and sortable', () {
      expect(Dates.dayKey(DateTime(2026, 8, 11, 23, 59)), '2026-08-11');
      expect(Dates.monthKey(DateTime(2026, 8, 11)), '2026-08');
    });

    test('monthKey is derivable from dayKey by substring', () {
      // report_repository groups months with SUBSTR(day_key, 1, 7).
      final day = Dates.dayKey(DateTime(2026, 8, 11));
      expect(day.substring(0, 7), Dates.monthKey(DateTime(2026, 8, 11)));
    });
  });

  group('csvField', () {
    test('quotes fields containing commas, quotes or newlines', () {
      expect(csvField('plain'), 'plain');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('say "hi"'), '"say ""hi"""');
      expect(csvField(null), '');
    });

    test('builds a full row', () {
      expect(csvRow(['a', 'b,c', 1]), 'a,"b,c",1');
    });
  });
}
