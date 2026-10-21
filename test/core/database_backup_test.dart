import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/database/db_backups.dart';

import '../helpers/test_app.dart';

/// Datenbank-Updates dürfen nie Daten kosten: Sicherung vor jedem Update, fehlgeschlagene Updates
/// lassen die Daten unverändert, eine ältere App öffnet eine neuere Datenbank, Sicherungen lassen
/// sich wiederherstellen.
void main() {
  late String dir;
  late String path;

  setUp(() {
    createTestDatabase(); // initialisiert sqflite ffi
    dir = Directory.systemTemp.createTempSync('lifehub_backup_').path;
    path = p.join(dir, 'finance.db');
  });

  /// Aktuelles Schema mit Daten in allen Tabellen, dann auf [version] „zurückgedreht“ –
  /// so sieht die Datenbank aus, wenn das nächste Update kommt.
  Future<Map<String, int>> seedFull({int version = DatabaseService.schemaVersion - 1}) async {
    final service = DatabaseService(path: path);
    final db = await service.database;
    final counts = <String, int>{};
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
        .map((r) => r['name'] as String);
    for (final table in tables) {
      final columns = (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name'] as String).toSet();
      final row = {if (columns.contains('userid')) 'userid': 1, if (columns.contains('name')) 'name': 'Eigenes Rezept'};
      row.isEmpty ? await db.rawInsert('INSERT INTO $table DEFAULT VALUES') : await db.insert(table, row);
      counts[table] = (await db.query(table)).length;
    }
    await db.execute('PRAGMA user_version = $version');
    await service.close();
    return counts;
  }

  Future<int> versionOf(String file) async {
    final db = await openDatabase(file, readOnly: true, singleInstance: false);
    final v = await db.getVersion();
    await db.close();
    return v;
  }

  test('an update backs the old database up first and keeps every row of every table', () async {
    final before = await seedFull();
    final service = DatabaseService(path: path);
    final db = await service.database;
    expect(await db.getVersion(), DatabaseService.schemaVersion);
    for (final MapEntry(key: table, value: n) in before.entries) {
      expect((await db.query(table)).length, n, reason: table);
    }
    expect((await db.query('recipes')).single['name'], 'Eigenes Rezept');

    final backups = await service.backups.list();
    expect(backups, hasLength(1));
    expect((backups.single.version, backups.single.reason), (DatabaseService.schemaVersion - 1, BackupReason.update));
    expect(await versionOf(backups.single.file.path), DatabaseService.schemaVersion - 1);
    await service.close();

    // Ohne Update keine weitere Sicherung
    final again = DatabaseService(path: path);
    await again.database;
    expect(await again.backups.list(), hasLength(1));
    await again.close();
  });

  test('a fresh install creates no backup', () async {
    final service = DatabaseService(path: path);
    await service.database;
    expect(await service.backups.list(), isEmpty);
    await service.close();
  });

  test('a failing update leaves the data untouched and says so instead of crashing', () async {
    final old = await openDatabase(path, version: 29, onCreate: (db, _) async {
      await db.execute('CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, userid INTEGER, '
          'last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('todos', {'title': 'Wichtig', 'userid': 1});
      // Kaputter Zustand: Ein Index auf einen View schlägt im Update fehl
      await db.execute('CREATE VIEW flash_cards AS SELECT 1 AS deckId');
    });
    await old.close();

    final service = DatabaseService(path: path);
    await expectLater(service.database, throwsA(isA<DatabaseUpgradeException>()
        .having((e) => e.fromVersion, 'fromVersion', 29)
        .having((e) => e.backup, 'backup', isNotNull)));
    await service.close();

    expect(await versionOf(path), 29);
    final check = await openDatabase(path, readOnly: true, singleInstance: false);
    expect((await check.query('todos')).single['title'], 'Wichtig');
    await check.close();
  });

  test('an older app opens a newer database without changing or deleting it', () async {
    await seedFull(version: DatabaseService.schemaVersion + 1);
    final service = DatabaseService(path: path);
    final db = await service.database;
    expect(await db.getVersion(), DatabaseService.schemaVersion + 1);
    expect((await db.query('recipes')).single['name'], 'Eigenes Rezept');
    await service.close();
  });

  test('only the newest backups are kept', () async {
    final store = DbBackupStore(p.join(dir, 'db_backups'));
    File(path).writeAsStringSync('x');
    for (var i = 0; i < 8; i++) {
      await store.create(path, version: 20 + i, reason: BackupReason.update, now: DateTime(2026, 10, 1 + i, 12));
    }
    final kept = await store.list();
    expect(kept, hasLength(DbBackupStore.keep));
    expect(kept.first.version, 27); // neueste zuerst
    expect(kept.first.createdAt, DateTime(2026, 10, 8, 12));
  });

  test('restore: the current state is backed up first, then the old data comes back and is upgraded', () async {
    await seedFull();
    final service = DatabaseService(path: path);
    var db = await service.database;
    await db.insert('recipes', {'userid': 1, 'name': 'Nach dem Update'});
    final backup = (await service.backups.list()).single;

    await service.restoreBackup(backup.file);
    db = await service.database;
    expect([for (final r in await db.query('recipes')) r['name']], ['Eigenes Rezept']);
    expect(await db.getVersion(), DatabaseService.schemaVersion);

    final all = await service.backups.list();
    final safety = all.firstWhere((b) => b.reason == BackupReason.beforeRestore);
    expect(safety.version, DatabaseService.schemaVersion); // „Nach dem Update“ ist nicht verloren
    await service.restoreBackup(safety.file);
    db = await service.database;
    expect([for (final r in await db.query('recipes', orderBy: 'id')) r['name']], ['Eigenes Rezept', 'Nach dem Update']);
    await service.close();
  });

  test('restore refuses files that are no LifeHub database or come from a newer app', () async {
    final service = DatabaseService(path: path);
    final db = await service.database;
    await db.insert('recipes', {'userid': 1, 'name': 'Bleibt'});

    final junk = File(p.join(dir, 'foto.jpg'))..writeAsStringSync('kein sqlite');
    await expectLater(service.restoreBackup(junk), throwsA(isA<BackupException>()));

    final otherPath = p.join(dir, 'fremd.db');
    final other = await openDatabase(otherPath, version: 1, onCreate: (d, _) => d.execute('CREATE TABLE notes(id INTEGER)'));
    await other.close();
    await expectLater(service.restoreBackup(File(otherPath)), throwsA(isA<BackupException>()));

    final newerPath = p.join(dir, 'neuer.db');
    File(path).copySync(newerPath);
    final newer = await openDatabase(newerPath, singleInstance: false);
    await newer.execute('PRAGMA user_version = ${DatabaseService.schemaVersion + 1}');
    await newer.close();
    await expectLater(service.restoreBackup(File(newerPath)), throwsA(isA<BackupException>()));

    expect((await (await service.database).query('recipes')).single['name'], 'Bleibt');
    await service.close();
  });
}
