import 'package:intl/intl.dart';

/// Money is stored everywhere as an integer number of centavos. Doubles are
/// never used for currency -- 0.1 + 0.2 problems turn into wrong daily totals.
abstract class Money {
  static final NumberFormat _peso = NumberFormat.currency(
    locale: 'en_US',
    symbol: '₱',
    decimalDigits: 2,
  );
  static final NumberFormat _pesoCompact = NumberFormat.currency(
    locale: 'en_US',
    symbol: '₱',
    decimalDigits: 0,
  );
  static final NumberFormat _plain = NumberFormat('#,##0.00', 'en_US');

  /// `12345` -> `P123.45`
  static String format(int centavos) => _peso.format(centavos / 100);

  /// Drops the centavos when they are zero -- easier to scan on stat tiles.
  static String formatShort(int centavos) {
    if (centavos % 100 == 0) return _pesoCompact.format(centavos ~/ 100);
    return _peso.format(centavos / 100);
  }

  /// No currency symbol, for CSV columns and text fields.
  static String plain(int centavos) => _plain.format(centavos / 100);

  /// Accepts `12`, `12.5`, `12.50`, `1,250` and `P12.50`.
  /// Returns null when the text is not a usable amount.
  static int? parse(String input) {
    final cleaned =
        input.replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }
}

abstract class Dates {
  static final DateFormat _dayKey = DateFormat('yyyy-MM-dd');
  static final DateFormat _monthKey = DateFormat('yyyy-MM');
  static final DateFormat _readableDay = DateFormat('EEE, d MMM yyyy');
  static final DateFormat _shortDay = DateFormat('d MMM');
  static final DateFormat _weekday = DateFormat('EEE');
  static final DateFormat _monthName = DateFormat('MMMM yyyy');
  static final DateFormat _monthShort = DateFormat('MMM');
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _stamp = DateFormat('yyyyMMdd-HHmmss');

  /// Local-time `yyyy-MM-dd`. Stored on every sale so grouping by day never
  /// has to reason about UTC offsets in SQL.
  static String dayKey(DateTime d) => _dayKey.format(d);
  static String monthKey(DateTime d) => _monthKey.format(d);

  static String readableDay(DateTime d) => _readableDay.format(d);
  static String shortDay(DateTime d) => _shortDay.format(d);
  static String weekday(DateTime d) => _weekday.format(d);
  static String monthName(DateTime d) => _monthName.format(d);
  static String monthShort(DateTime d) => _monthShort.format(d);
  static String time(DateTime d) => _time.format(d);
  static String fileStamp(DateTime d) => _stamp.format(d);

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// Weeks run Monday to Sunday.
  static DateTime startOfWeek(DateTime d) {
    final day = startOfDay(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime endOfWeek(DateTime d) =>
      endOfDay(startOfWeek(d).add(const Duration(days: 6)));

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);
  static DateTime endOfMonth(DateTime d) =>
      DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);

  static DateTime parseDayKey(String key) => DateTime.parse('${key}T00:00:00');

  /// "Today" / "Yesterday" / the date. Used in list headers.
  static String relativeDay(DateTime d) {
    final today = startOfDay(DateTime.now());
    final target = startOfDay(d);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return readableDay(d);
  }
}

/// Escapes a single CSV field: quotes wrap anything containing a comma,
/// quote or newline, and inner quotes are doubled.
String csvField(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(RegExp(r'[",\n\r]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvRow(List<Object?> values) => values.map(csvField).join(',');
