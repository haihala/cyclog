/// Layout maths for the ribbon calendar.
///
/// Kept free of widgets so the geometry can be tested directly.
///
/// An entry with no recorded end covers only its start day. Stretching it to
/// today would be the app inventing days the user never entered.
library;

import 'models.dart';

/// Days per calendar row.
const int kDaysPerWeek = 7;

/// Rows drawn for every month. Fixed at six so each month block has the same
/// height, which keeps scrolling predictable and lets the calendar jump
/// straight to a given month.
const int kWeeksPerMonthGrid = 6;

/// The last day an occurrence visibly covers.
///
/// With no recorded end this is the start day itself.
Day coveredEnd(Occurrence o) => o.end ?? o.start;

/// Monday-based start of the week containing [d].
Day startOfWeek(Day d) => d.addDays(-(d.weekday - 1));

/// First day of the grid for [year]/[month]: the Monday on or before the
/// first of that month.
Day monthGridStart(int year, int month) =>
    startOfWeek(Day(year, month, 1));

/// The six Monday week-starts that make up the grid for [year]/[month].
List<Day> monthGridWeeks(int year, int month) {
  final first = monthGridStart(year, month);
  return List.generate(
    kWeeksPerMonthGrid,
    (i) => first.addDays(i * kDaysPerWeek),
  );
}

/// Number of whole months from [from] to [to]. Negative if [to] is earlier.
int monthsBetween(Day from, Day to) =>
    (to.year - from.year) * 12 + (to.month - from.month);

/// Adds [count] months to the year/month pair, normalising overflow.
({int year, int month}) addMonths(int year, int month, int count) {
  final zeroBased = (year * 12 + (month - 1)) + count;
  return (year: zeroBased ~/ 12, month: zeroBased % 12 + 1);
}

/// One horizontal bar within a single week row.
class RibbonSegment {
  final Occurrence occurrence;

  /// Column indices within the week, 0 = Monday, both inclusive.
  final int startCol;
  final int endCol;

  /// The entry began before this week, so the bar should not be capped on
  /// the left.
  final bool continuesBefore;

  /// The entry runs past this week, so the bar should not be capped on the
  /// right.
  final bool continuesAfter;

  const RibbonSegment({
    required this.occurrence,
    required this.startCol,
    required this.endCol,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  int get columnSpan => endCol - startCol + 1;
}

/// The bars to draw for [occurrences] in the week beginning [weekStart].
///
/// Occurrences that do not touch the week are omitted. The result is ordered
/// by start column so overlapping entries draw left to right.
List<RibbonSegment> segmentsForWeek(
  List<Occurrence> occurrences,
  Day weekStart,
) {
  final weekEnd = weekStart.addDays(kDaysPerWeek - 1);
  final segments = <RibbonSegment>[];

  for (final o in occurrences) {
    final last = coveredEnd(o);
    if (last < weekStart || o.start > weekEnd) continue;

    final rawStart = weekStart.daysTo(o.start);
    final rawEnd = weekStart.daysTo(last);

    segments.add(
      RibbonSegment(
        occurrence: o,
        startCol: rawStart < 0 ? 0 : rawStart,
        endCol: rawEnd > kDaysPerWeek - 1 ? kDaysPerWeek - 1 : rawEnd,
        continuesBefore: o.start < weekStart,
        continuesAfter: last > weekEnd,
      ),
    );
  }

  segments.sort((a, b) => a.startCol.compareTo(b.startCol));
  return segments;
}

/// Occurrences covering [day], in the order given.
List<Occurrence> entriesOnDay(List<Occurrence> occurrences, Day day) {
  return occurrences
      .where((o) => o.start <= day && day <= coveredEnd(o))
      .toList();
}

/// Whether [day] falls inside [year]/[month]. Used to dim the leading and
/// trailing days borrowed from neighbouring months.
bool isInMonth(Day day, int year, int month) =>
    day.year == year && day.month == month;
