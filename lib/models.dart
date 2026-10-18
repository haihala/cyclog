/// Core data model.
///
/// Design rule for this whole app: the stored data is exactly what the user
/// entered. Nothing here infers, corrects, backfills or flags user input.
library;

/// A date without time or timezone. Stored as 'YYYY-MM-DD'.
///
/// Using a plain calendar date avoids every DST / timezone off-by-one-day bug
/// that would otherwise silently alter what the user recorded.
class Day implements Comparable<Day> {
  final int year;
  final int month;
  final int day;

  const Day(this.year, this.month, this.day);

  factory Day.fromDateTime(DateTime d) => Day(d.year, d.month, d.day);

  factory Day.today() => Day.fromDateTime(DateTime.now());

  factory Day.parse(String s) {
    final parts = s.split('-');
    if (parts.length != 3) {
      throw FormatException('Not a YYYY-MM-DD date', s);
    }
    return Day(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static Day? tryParse(String? s) {
    if (s == null) return null;
    try {
      return Day.parse(s);
    } on Object {
      return null;
    }
  }

  /// Midday is used deliberately: it keeps arithmetic safe across DST shifts.
  DateTime toDateTime() => DateTime(year, month, day, 12);

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Whole days from this day to [other]. Negative if [other] is earlier.
  int daysTo(Day other) =>
      (other.toDateTime().difference(toDateTime()).inHours / 24).round();

  Day addDays(int n) => Day.fromDateTime(toDateTime().add(Duration(days: n)));

  /// ISO weekday, Monday = 1 through Sunday = 7.
  int get weekday => toDateTime().weekday;

  @override
  int compareTo(Day other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool operator <(Day other) => compareTo(other) < 0;
  bool operator <=(Day other) => compareTo(other) <= 0;
  bool operator >(Day other) => compareTo(other) > 0;
  bool operator >=(Day other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Day &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// A user-defined thing to track. The app ships with none; the user names
/// and defines every tracker themselves.
class Tracker {
  final int? id;

  /// Free text, entirely the user's choice.
  final String name;

  /// Whether occurrences of this tracker span multiple days (have an end
  /// date) or are single moments in time.
  final bool hasDuration;

  /// ARGB colour used purely for visual distinction in the list.
  final int color;

  /// Sort position in the home list.
  final int position;

  final String? notes;

  const Tracker({
    this.id,
    required this.name,
    required this.hasDuration,
    required this.color,
    this.position = 0,
    this.notes,
  });

  Tracker copyWith({
    int? id,
    String? name,
    bool? hasDuration,
    int? color,
    int? position,
    String? notes,
    bool clearNotes = false,
  }) {
    return Tracker(
      id: id ?? this.id,
      name: name ?? this.name,
      hasDuration: hasDuration ?? this.hasDuration,
      color: color ?? this.color,
      position: position ?? this.position,
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  Map<String, Object?> toDb() => {
        if (id != null) 'id': id,
        'name': name,
        'has_duration': hasDuration ? 1 : 0,
        'color': color,
        'position': position,
        'notes': notes,
      };

  factory Tracker.fromDb(Map<String, Object?> row) => Tracker(
        id: row['id'] as int?,
        name: row['name'] as String? ?? '',
        hasDuration: (row['has_duration'] as int? ?? 0) == 1,
        color: row['color'] as int? ?? 0xFF607D8B,
        position: row['position'] as int? ?? 0,
        notes: row['notes'] as String?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'hasDuration': hasDuration,
        'color': color,
        'position': position,
        'notes': notes,
      };

  factory Tracker.fromJson(Map<String, Object?> j) => Tracker(
        id: (j['id'] as num?)?.toInt(),
        name: j['name'] as String? ?? 'Unnamed',
        hasDuration: j['hasDuration'] as bool? ?? false,
        color: (j['color'] as num?)?.toInt() ?? 0xFF607D8B,
        position: (j['position'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String?,
      );
}

/// A single recorded occurrence. [end] is null either because the tracker has
/// no duration, or because the user has not (or will not) record an end.
///
/// A null [end] is never treated as an error or as missing data.
class Occurrence {
  final int? id;
  final int trackerId;
  final Day start;
  final Day? end;
  final String? note;

  const Occurrence({
    this.id,
    required this.trackerId,
    required this.start,
    this.end,
    this.note,
  });

  /// Inclusive length in days, or null if there is no recorded end.
  int? get lengthDays => end == null ? null : start.daysTo(end!) + 1;

  Occurrence copyWith({
    int? id,
    int? trackerId,
    Day? start,
    Day? end,
    String? note,
    bool clearEnd = false,
    bool clearNote = false,
  }) {
    return Occurrence(
      id: id ?? this.id,
      trackerId: trackerId ?? this.trackerId,
      start: start ?? this.start,
      end: clearEnd ? null : (end ?? this.end),
      note: clearNote ? null : (note ?? this.note),
    );
  }

  Map<String, Object?> toDb() => {
        if (id != null) 'id': id,
        'tracker_id': trackerId,
        'start_day': start.toIso(),
        'end_day': end?.toIso(),
        'note': note,
      };

  factory Occurrence.fromDb(Map<String, Object?> row) => Occurrence(
        id: row['id'] as int?,
        trackerId: row['tracker_id'] as int,
        start: Day.parse(row['start_day'] as String),
        end: Day.tryParse(row['end_day'] as String?),
        note: row['note'] as String?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'trackerId': trackerId,
        'start': start.toIso(),
        'end': end?.toIso(),
        'note': note,
      };

  factory Occurrence.fromJson(Map<String, Object?> j) => Occurrence(
        id: (j['id'] as num?)?.toInt(),
        trackerId: (j['trackerId'] as num).toInt(),
        start: Day.parse(j['start'] as String),
        end: Day.tryParse(j['end'] as String?),
        note: j['note'] as String?,
      );
}

/// Builds the record to persist from the entry form's current values.
///
/// A tracker whose entries are single days does not offer an end date. Any
/// end that was already recorded is carried through untouched rather than
/// erased, so changing a tracker's kind can never destroy data.
Occurrence buildOccurrenceForSave({
  required Tracker tracker,
  required Day start,
  required Day? end,
  required String? note,
  Occurrence? existing,
}) {
  final trimmed = note?.trim();
  return Occurrence(
    id: existing?.id,
    trackerId: tracker.id!,
    start: start,
    end: tracker.hasDuration ? end : existing?.end,
    note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
  );
}
