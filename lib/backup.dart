/// JSON backup: export and import.
///
/// The export is a plain, readable JSON document so the data is never locked
/// inside this app.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'db.dart';
import 'models.dart';

const int kBackupFormatVersion = 1;

/// Identifier written into every backup file.
const String kBackupFormatId = 'cyclog-backup';

class BackupData {
  final List<Tracker> trackers;
  final List<Occurrence> occurrences;

  const BackupData(this.trackers, this.occurrences);
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

String encodeBackup(BackupData data) {
  final doc = <String, Object?>{
    'format': kBackupFormatId,
    'version': kBackupFormatVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'trackers': data.trackers.map((t) => t.toJson()).toList(),
    'occurrences': data.occurrences.map((o) => o.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(doc);
}

/// Parses a backup document. Throws [BackupException] with a readable message
/// rather than silently dropping or guessing at malformed records.
BackupData decodeBackup(String source) {
  late final Object? raw;
  try {
    raw = jsonDecode(source);
  } on FormatException catch (e) {
    throw BackupException('That file is not valid JSON (${e.message}).');
  }

  if (raw is! Map<String, Object?>) {
    throw BackupException('Expected a JSON object at the top level.');
  }
  if (raw['format'] != kBackupFormatId) {
    throw BackupException('That file is not a cyclog backup.');
  }
  final version = (raw['version'] as num?)?.toInt() ?? 0;
  if (version > kBackupFormatVersion) {
    throw BackupException(
      'That backup was made by a newer version of cyclog '
      '(format $version, this app understands $kBackupFormatVersion).',
    );
  }

  final trackersRaw = raw['trackers'];
  final occurrencesRaw = raw['occurrences'];
  if (trackersRaw is! List || occurrencesRaw is! List) {
    throw BackupException('The backup is missing its trackers or entries.');
  }

  final trackers = <Tracker>[];
  final trackerIds = <int>{};
  for (var i = 0; i < trackersRaw.length; i++) {
    final item = trackersRaw[i];
    if (item is! Map<String, Object?>) {
      throw BackupException('Tracker #${i + 1} is not a JSON object.');
    }
    late final Tracker tracker;
    try {
      tracker = Tracker.fromJson(item);
    } on Object catch (e) {
      throw BackupException('Tracker #${i + 1} could not be read: $e');
    }

    // Entries are matched to their tracker by id. Without a usable id the
    // entries would be imported against nothing and silently vanish, so
    // refuse the file instead.
    if (tracker.id == null) {
      throw BackupException(
        'Tracker #${i + 1} ("${tracker.name}") has no id, so its entries '
        'could not be matched to it.',
      );
    }
    if (!trackerIds.add(tracker.id!)) {
      throw BackupException(
        'Two trackers share the id ${tracker.id}, so their entries could '
        'not be told apart.',
      );
    }
    trackers.add(tracker);
  }

  final occurrences = <Occurrence>[];
  for (var i = 0; i < occurrencesRaw.length; i++) {
    final item = occurrencesRaw[i];
    if (item is! Map<String, Object?>) {
      throw BackupException('Entry #${i + 1} is not a JSON object.');
    }
    late final Occurrence occurrence;
    try {
      occurrence = Occurrence.fromJson(item);
    } on Object catch (e) {
      throw BackupException('Entry #${i + 1} could not be read: $e');
    }

    if (!trackerIds.contains(occurrence.trackerId)) {
      throw BackupException(
        'Entry #${i + 1} belongs to tracker ${occurrence.trackerId}, which '
        'is not in this file.',
      );
    }
    // The same contradiction the entry form refuses to store.
    if (occurrence.end != null && occurrence.end! < occurrence.start) {
      throw BackupException(
        'Entry #${i + 1} ends (${occurrence.end}) before it starts '
        '(${occurrence.start}).',
      );
    }
    occurrences.add(occurrence);
  }

  return BackupData(trackers, occurrences);
}

Future<BackupData> loadFromDb() async {
  final db = AppDb.instance;
  final trackers = await db.getTrackers();
  final occurrences = await db.getAllOccurrences();
  return BackupData(trackers, occurrences);
}

String defaultFileName() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'cyclog-backup-${now.year}-${two(now.month)}-${two(now.day)}.json';
}

/// Shows a save dialog and writes the backup. Returns the path chosen, or
/// null if the user cancelled.
Future<String?> exportToFile() async {
  final data = await loadFromDb();
  final json = encodeBackup(data);
  final bytes = Uint8List.fromList(utf8.encode(json));

  return FilePicker.saveFile(
    dialogTitle: 'Save cyclog backup',
    fileName: defaultFileName(),
    bytes: bytes,
  );
}

/// Shows an open dialog and parses the chosen file. Returns null if the user
/// cancelled. Nothing is written to the database here — the caller confirms
/// first.
Future<BackupData?> pickBackupFile() async {
  final result = await FilePicker.pickFiles(
    dialogTitle: 'Choose a cyclog backup',
    type: FileType.any,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null) {
    throw const BackupException('Could not read that file.');
  }

  late final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const BackupException('That file is not readable text.');
  }

  return decodeBackup(text);
}
