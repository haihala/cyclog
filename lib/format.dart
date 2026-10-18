/// Display formatting.
///
/// Wording rule: describe, never judge. A date that has passed is "3 days
/// ago", not "overdue" or "late". The app has no opinion about whether the
/// user's body or their record-keeping is on schedule.
library;

import 'package:intl/intl.dart';

import 'models.dart';

final _long = DateFormat('EEE d MMM yyyy');
final _short = DateFormat('d MMM yyyy');
final _noYear = DateFormat('d MMM');

String formatDay(Day d) => _short.format(d.toDateTime());

String formatDayLong(Day d) => _long.format(d.toDateTime());

/// Omits the year when it's the current year, to reduce visual noise.
String formatDayCompact(Day d) {
  final today = Day.today();
  if (d.year == today.year) return _noYear.format(d.toDateTime());
  return _short.format(d.toDateTime());
}

/// Neutral relative description of [d] with respect to today.
String relativeDay(Day d) {
  final diff = Day.today().daysTo(d);
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  if (diff == -1) return 'yesterday';
  if (diff > 0) return 'in $diff days';
  return '${-diff} days ago';
}

String plural(int n, String singular, [String? pluralForm]) {
  if (n == 1) return '1 $singular';
  return '$n ${pluralForm ?? '${singular}s'}';
}

/// Formats a day count that may be fractional, e.g. "28.4 days".
String formatDays(double value) {
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text ${rounded == 1 ? 'day' : 'days'}';
}

/// Describes a date range in a compact way, e.g. "3–11 Mar 2025".
String formatRange(Day a, Day b) {
  if (a == b) return formatDay(a);
  if (a.year == b.year && a.month == b.month) {
    return '${a.day}\u2013${formatDay(b)}';
  }
  if (a.year == b.year) {
    return '${_noYear.format(a.toDateTime())} \u2013 ${formatDay(b)}';
  }
  return '${formatDay(a)} \u2013 ${formatDay(b)}';
}
