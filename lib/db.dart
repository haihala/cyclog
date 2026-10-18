/// SQLite persistence. Plain CRUD — the database never rewrites, merges or
/// "corrects" anything the user entered.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDb {
  AppDb._();

  static final AppDb instance = AppDb._();

  /// The in-flight or completed open. Caching the future rather than the
  /// database means concurrent first callers share one open instead of each
  /// starting their own.
  Future<Database>? _db;

  Future<Database> get database => _db ??= _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'cyclog.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tracker (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            has_duration INTEGER NOT NULL DEFAULT 0,
            color INTEGER NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE occurrence (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tracker_id INTEGER NOT NULL
              REFERENCES tracker(id) ON DELETE CASCADE,
            start_day TEXT NOT NULL,
            end_day TEXT,
            note TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_occurrence_tracker '
          'ON occurrence(tracker_id, start_day)',
        );
        await db.execute('''
          CREATE TABLE setting (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ---------------------------------------------------------------- backup

  /// Folds the write-ahead log into the main database file.
  ///
  /// Android's Auto Backup copies the `.db` file but not its `-wal` sidecar.
  /// SQLite keeps recent commits in that sidecar, so without this the backup
  /// could silently omit the newest entries. Called when the app goes to the
  /// background, which is also when a backup is likely to run.
  Future<void> checkpoint() async {
    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  // ---------------------------------------------------------------- trackers

  Future<List<Tracker>> getTrackers() async {
    final db = await database;
    final rows = await db.query('tracker', orderBy: 'position ASC, id ASC');
    return rows.map(Tracker.fromDb).toList();
  }

  Future<Tracker?> getTracker(int id) async {
    final db = await database;
    final rows = await db.query(
      'tracker',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Tracker.fromDb(rows.first);
  }

  Future<int> insertTracker(Tracker t) async {
    final db = await database;
    final maxPos = Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(position) FROM tracker'),
        ) ??
        -1;
    return db.insert('tracker', t.copyWith(position: maxPos + 1).toDb());
  }

  Future<void> updateTracker(Tracker t) async {
    final db = await database;
    await db.update(
      'tracker',
      t.toDb(),
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  Future<void> deleteTracker(int id) async {
    final db = await database;
    await db.delete('tracker', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorderTrackers(List<Tracker> ordered) async {
    final db = await database;
    final batch = db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(
        'tracker',
        {'position': i},
        where: 'id = ?',
        whereArgs: [ordered[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------- occurrences

  Future<List<Occurrence>> getOccurrences(int trackerId) async {
    final db = await database;
    final rows = await db.query(
      'occurrence',
      where: 'tracker_id = ?',
      whereArgs: [trackerId],
      orderBy: 'start_day DESC',
    );
    return rows.map(Occurrence.fromDb).toList();
  }

  Future<List<Occurrence>> getAllOccurrences() async {
    final db = await database;
    final rows = await db.query('occurrence', orderBy: 'start_day DESC');
    return rows.map(Occurrence.fromDb).toList();
  }

  Future<int> insertOccurrence(Occurrence o) async {
    final db = await database;
    return db.insert('occurrence', o.toDb());
  }

  Future<void> updateOccurrence(Occurrence o) async {
    final db = await database;
    await db.update(
      'occurrence',
      o.toDb(),
      where: 'id = ?',
      whereArgs: [o.id],
    );
  }

  Future<void> deleteOccurrence(int id) async {
    final db = await database;
    await db.delete('occurrence', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- settings

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'setting',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'setting',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------------------ backup

  /// Replaces all content with the supplied data. Used only by an explicit,
  /// confirmed import.
  Future<void> replaceAll(
    List<Tracker> trackers,
    List<Occurrence> occurrences,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('occurrence');
      await txn.delete('tracker');

      final idMap = <int, int>{};
      for (var i = 0; i < trackers.length; i++) {
        final t = trackers[i];
        final data = t.copyWith(position: i).toDb()..remove('id');
        final newId = await txn.insert('tracker', data);
        if (t.id != null) idMap[t.id!] = newId;
      }
      for (final o in occurrences) {
        final mapped = idMap[o.trackerId];
        if (mapped == null) continue;
        final data = o.copyWith(trackerId: mapped).toDb()..remove('id');
        await txn.insert('occurrence', data);
      }
    });
  }

  /// Adds the supplied data alongside existing content, leaving current
  /// records untouched.
  Future<void> mergeIn(
    List<Tracker> trackers,
    List<Occurrence> occurrences,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final maxPos = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT MAX(position) FROM tracker'),
          ) ??
          -1;

      final idMap = <int, int>{};
      for (var i = 0; i < trackers.length; i++) {
        final t = trackers[i];
        final data = t.copyWith(position: maxPos + 1 + i).toDb()..remove('id');
        final newId = await txn.insert('tracker', data);
        if (t.id != null) idMap[t.id!] = newId;
      }
      for (final o in occurrences) {
        final mapped = idMap[o.trackerId];
        if (mapped == null) continue;
        final data = o.copyWith(trackerId: mapped).toDb()..remove('id');
        await txn.insert('occurrence', data);
      }
    });
  }
}
