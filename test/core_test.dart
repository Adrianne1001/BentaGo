import 'package:bentago/core/format.dart';
import 'package:bentago/core/period.dart';
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
