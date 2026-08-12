import 'format.dart';

enum PeriodKind { day, week, month }

extension PeriodKindLabel on PeriodKind {
  String get label => switch (this) {
        PeriodKind.day => 'Day',
        PeriodKind.week => 'Week',
        PeriodKind.month => 'Month',
      };
}

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
      };

  factory Period.today() => Period.of(PeriodKind.day, DateTime.now());

  Period shift(int steps) => switch (kind) {
        PeriodKind.day =>
          Period.of(kind, start.add(Duration(days: steps))),
        PeriodKind.week =>
          Period.of(kind, start.add(Duration(days: 7 * steps))),
        PeriodKind.month =>
          Period.of(kind, DateTime(start.year, start.month + steps)),
      };

  /// Narrowing from a wider period anchors on **today** when today is inside
  /// the current range, not on the range's first day. Switching Buwan to Araw
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
        PeriodKind.week =>
          '${Dates.shortDay(start)} – ${Dates.shortDay(end)}',
        PeriodKind.month => Dates.monthName(start),
      };

  String get subLabel => switch (kind) {
        PeriodKind.day => Dates.readableDay(start),
        PeriodKind.week => 'Week of ${Dates.readableDay(start)}',
        PeriodKind.month => '$dayCount days',
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
