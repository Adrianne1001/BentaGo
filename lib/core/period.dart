import 'format.dart';

enum PeriodKind { day, week, month, quarter, year, custom }

extension PeriodKindLabel on PeriodKind {
  String get label => switch (this) {
        PeriodKind.day => 'Day',
        PeriodKind.week => 'Week',
        PeriodKind.month => 'Month',
        PeriodKind.quarter => 'Quarter',
        PeriodKind.year => 'Year',
        PeriodKind.custom => 'Custom',
      };
}

/// The kinds the browsing UI steps through with its chips and arrows.
///
/// [PeriodKind.quarter] and [PeriodKind.year] are deliberately absent: they
/// exist for report export, where the range is chosen once, and adding two more
/// chips to a strip that has to stay thumb-sized on a budget phone costs more
/// than it gives. [PeriodKind.custom] has no meaningful "next" or "previous" to
/// step to at all.
const List<PeriodKind> browsablePeriodKinds = [
  PeriodKind.day,
  PeriodKind.week,
  PeriodKind.month,
];

/// An inclusive local-time date range plus the label the UI shows for it.
/// Every report screen works off one of these, so day / week / month reporting
/// shares a single code path.
class Period {
  const Period({
    required this.kind,
    required this.start,
    required this.end,
  });

  final PeriodKind kind;
  final DateTime start;
  final DateTime end;

  factory Period.of(PeriodKind kind, DateTime anchor) => switch (kind) {
        PeriodKind.day => Period(
            kind: kind,
            start: Dates.startOfDay(anchor),
            end: Dates.endOfDay(anchor),
          ),
        PeriodKind.week => Period(
            kind: kind,
            start: Dates.startOfWeek(anchor),
            end: Dates.endOfWeek(anchor),
          ),
        PeriodKind.month => Period(
            kind: kind,
            start: Dates.startOfMonth(anchor),
            end: Dates.endOfMonth(anchor),
          ),
        PeriodKind.quarter => Period(
            kind: kind,
            start: Dates.startOfQuarter(anchor),
            end: Dates.endOfQuarter(anchor),
          ),
        PeriodKind.year => Period(
            kind: kind,
            start: Dates.startOfYear(anchor),
            end: Dates.endOfYear(anchor),
          ),
        // A custom range is defined by two dates, not by an anchor. Falling back
        // to the anchor's day keeps this total without inventing a span the
        // caller did not ask for; use [Period.range] to build one properly.
        PeriodKind.custom => Period(
            kind: kind,
            start: Dates.startOfDay(anchor),
            end: Dates.endOfDay(anchor),
          ),
      };

  factory Period.today() => Period.of(PeriodKind.day, DateTime.now());

  /// An arbitrary start-to-end span, inclusive of both days. The two dates are
  /// swapped when handed over backwards, so a date picker cannot produce a
  /// range that queries to nothing.
  factory Period.range(DateTime start, DateTime end) {
    final from = Dates.startOfDay(start.isAfter(end) ? end : start);
    final to = Dates.endOfDay(start.isAfter(end) ? start : end);
    return Period(kind: PeriodKind.custom, start: from, end: to);
  }

  Period shift(int steps) => switch (kind) {
        PeriodKind.day => Period.of(kind, start.add(Duration(days: steps))),
        PeriodKind.week => Period.of(kind, start.add(Duration(days: 7 * steps))),
        PeriodKind.month =>
          Period.of(kind, DateTime(start.year, start.month + steps)),
        PeriodKind.quarter =>
          Period.of(kind, DateTime(start.year, start.month + 3 * steps)),
        PeriodKind.year => Period.of(kind, DateTime(start.year + steps)),
        // Slide the whole window by its own length.
        PeriodKind.custom => Period.range(
            Dates.startOfDay(start).add(Duration(days: dayCount * steps)),
            Dates.startOfDay(end).add(Duration(days: dayCount * steps)),
          ),
      };

  /// Narrowing from a wider period anchors on **today** when today is inside
  /// the current range, not on the range's first day. Switching Month to Day
  /// while looking at this month should land on today's sales -- landing on the
  /// 1st shows an empty screen and reads as data loss.
  ///
  /// For a period that does not contain today (browsing last month), the start
  /// is the only sensible anchor.
  Period withKind(PeriodKind next) =>
      Period.of(next, containsToday ? DateTime.now() : start);

  /// The equivalent stretch immediately before this one, for "vs last period".
  Period get previous => shift(-1);

  bool get containsToday {
    final now = DateTime.now();
    return !now.isBefore(start) && !now.isAfter(end);
  }

  String get startKey => Dates.dayKey(start);
  String get endKey => Dates.dayKey(end);

  int get dayCount => end.difference(start).inDays + 1;

  /// Every day in the range, oldest first. Drives the bar charts.
  List<DateTime> get days => List.generate(
        dayCount,
        (i) => Dates.startOfDay(start).add(Duration(days: i)),
      );

  String get label => switch (kind) {
        PeriodKind.day => Dates.relativeDay(start),
        PeriodKind.week => '${Dates.shortDay(start)} – ${Dates.shortDay(end)}',
        PeriodKind.month => Dates.monthName(start),
        PeriodKind.quarter => 'Q${Dates.quarterOf(start)} ${start.year}',
        PeriodKind.year => '${start.year}',
        PeriodKind.custom => Dates.rangeLabel(start, end),
      };

  String get subLabel => switch (kind) {
        PeriodKind.day => Dates.readableDay(start),
        PeriodKind.week => 'Week of ${Dates.readableDay(start)}',
        PeriodKind.month => '$dayCount days',
        PeriodKind.quarter =>
          '${Dates.monthShort(start)} – ${Dates.monthShort(end)} ${end.year}',
        PeriodKind.year =>
          '${Dates.monthShort(start)} – ${Dates.monthShort(end)} ${end.year}',
        PeriodKind.custom => '$dayCount days',
      };

  /// Used in exported file names: `2026-08-13` for a day, `2026-08` for a month,
  /// `2026-Q3`, `2026`, and `2026-08-01_2026-09-13` for a custom span.
  String get fileLabel => switch (kind) {
        PeriodKind.day => startKey,
        PeriodKind.week => '${startKey}_$endKey',
        PeriodKind.month => Dates.monthKey(start),
        PeriodKind.quarter => '${start.year}-Q${Dates.quarterOf(start)}',
        PeriodKind.year => '${start.year}',
        PeriodKind.custom => '${startKey}_$endKey',
      };

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}
