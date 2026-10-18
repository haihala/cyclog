import 'dart:convert';

import 'package:cyclog/backup.dart';
import 'package:cyclog/models.dart';
import 'package:flutter_test/flutter_test.dart';

String doc({
  List<Map<String, Object?>>? trackers,
  List<Map<String, Object?>>? occurrences,
  String format = kBackupFormatId,
  int version = kBackupFormatVersion,
}) {
  return jsonEncode({
    'format': format,
    'version': version,
    'trackers': trackers ?? const [],
    'occurrences': occurrences ?? const [],
  });
}

Map<String, Object?> trackerJson({
  int? id = 1,
  String name = 'Thing',
  bool hasDuration = true,
}) {
  return {
    'id': id,
    'name': name,
    'hasDuration': hasDuration,
    'color': 0xFF1E88E5,
    'position': 0,
    'notes': null,
  };
}

Map<String, Object?> occurrenceJson({
  int? id = 10,
  int trackerId = 1,
  String start = '2025-01-01',
  String? end,
}) {
  return {
    'id': id,
    'trackerId': trackerId,
    'start': start,
    'end': end,
    'note': null,
  };
}

void main() {
  group('round trip', () {
    test('an export decodes back to the same data', () {
      final data = BackupData(
        const [
          Tracker(id: 1, name: 'A', hasDuration: true, color: 0xFF112233),
          Tracker(id: 2, name: 'B', hasDuration: false, color: 0xFF445566),
        ],
        [
          Occurrence(
            id: 1,
            trackerId: 1,
            start: Day.parse('2025-01-01'),
            end: Day.parse('2025-01-05'),
            note: 'note',
          ),
          Occurrence(id: 2, trackerId: 2, start: Day.parse('2025-02-01')),
        ],
      );

      final decoded = decodeBackup(encodeBackup(data));

      expect(decoded.trackers.map((t) => t.name), ['A', 'B']);
      expect(decoded.trackers[1].hasDuration, isFalse);
      expect(decoded.occurrences[0].end, Day.parse('2025-01-05'));
      expect(decoded.occurrences[0].note, 'note');
      expect(decoded.occurrences[1].end, isNull);
    });
  });

  group('rejects malformed files', () {
    test('not JSON', () {
      expect(() => decodeBackup('nonsense'), throwsA(isA<BackupException>()));
    });

    test('not an object at the top level', () {
      expect(() => decodeBackup('[]'), throwsA(isA<BackupException>()));
    });

    test('a different format id', () {
      expect(
        () => decodeBackup(doc(format: 'something-else')),
        throwsA(isA<BackupException>()),
      );
    });

    test('a newer format version', () {
      expect(
        () => decodeBackup(doc(version: kBackupFormatVersion + 1)),
        throwsA(isA<BackupException>()),
      );
    });

    test('missing lists', () {
      expect(
        () => decodeBackup(jsonEncode({
          'format': kBackupFormatId,
          'version': kBackupFormatVersion,
        })),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('entries are never silently dropped', () {
    test('a tracker without an id is refused rather than orphaning entries',
        () {
      final source = doc(
        trackers: [trackerJson(id: null)],
        occurrences: [occurrenceJson(trackerId: 1)],
      );
      expect(
        () => decodeBackup(source),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('no id'),
          ),
        ),
      );
    });

    test('duplicate tracker ids are refused', () {
      final source = doc(
        trackers: [trackerJson(id: 1), trackerJson(id: 1, name: 'Other')],
        occurrences: const [],
      );
      expect(
        () => decodeBackup(source),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('share the id'),
          ),
        ),
      );
    });

    test('an entry pointing at an absent tracker is refused', () {
      final source = doc(
        trackers: [trackerJson(id: 1)],
        occurrences: [occurrenceJson(trackerId: 99)],
      );
      expect(
        () => decodeBackup(source),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('not in this file'),
          ),
        ),
      );
    });

    test('a valid file keeps every entry', () {
      final source = doc(
        trackers: [trackerJson(id: 1), trackerJson(id: 2, name: 'Two')],
        occurrences: [
          occurrenceJson(id: 1, trackerId: 1),
          occurrenceJson(id: 2, trackerId: 2, start: '2025-03-03'),
          occurrenceJson(id: 3, trackerId: 1, start: '2025-04-04'),
        ],
      );
      final decoded = decodeBackup(source);
      expect(decoded.trackers.length, 2);
      expect(decoded.occurrences.length, 3);
    });
  });

  group('contradictory dates', () {
    test('an entry ending before it starts is refused', () {
      final source = doc(
        trackers: [trackerJson()],
        occurrences: [
          occurrenceJson(start: '2025-01-10', end: '2025-01-02'),
        ],
      );
      expect(
        () => decodeBackup(source),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('before it starts'),
          ),
        ),
      );
    });

    test('an entry starting and ending on the same day is accepted', () {
      final source = doc(
        trackers: [trackerJson()],
        occurrences: [
          occurrenceJson(start: '2025-01-10', end: '2025-01-10'),
        ],
      );
      expect(decodeBackup(source).occurrences.single.lengthDays, 1);
    });

    test('an entry with no end is accepted', () {
      final source = doc(
        trackers: [trackerJson()],
        occurrences: [occurrenceJson(end: null)],
      );
      expect(decodeBackup(source).occurrences.single.end, isNull);
    });
  });
}
