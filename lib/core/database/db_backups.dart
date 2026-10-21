import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:frontend/core/models/app_exceptions.dart';

/// Warum eine Sicherung angelegt wurde.
enum BackupReason {
  update('update', 'Vor dem Update'),
  beforeRestore('restore', 'Vor dem Wiederherstellen'),
  manual('manual', 'Von Hand gesichert');

  const BackupReason(this.slug, this.label);
  final String slug;
  final String label;
}

/// Eine Kopie der Datenbank-Datei.
class DbBackup {
  final File file;
  final int version;
  final BackupReason reason;
  final DateTime createdAt;
  const DbBackup({required this.file, required this.version, required this.reason, required this.createdAt});

  int get sizeBytes => file.existsSync() ? file.lengthSync() : 0;
}

/// Sicherung lässt sich nicht verwenden (keine LifeHub-Datenbank, von einer neueren App …).
class BackupException extends UserFacingException {
  const BackupException(super.message);
}

/// Das Update der Datenbank ist fehlgeschlagen. Die Daten sind unverändert, [backup] ist die
/// Kopie von vorher.
class DatabaseUpgradeException extends UserFacingException {
  final int fromVersion;
  final int toVersion;
  final DbBackup? backup;
  final Object cause;
  DatabaseUpgradeException({required this.fromVersion, required this.toVersion, required this.backup, required this.cause})
      : super('Das Update der Datenbank von Version $fromVersion auf $toVersion ist fehlgeschlagen: $cause');
}

/// Kopien der Datenbank-Datei in einem eigenen Ordner neben der Datenbank. Name:
/// `finance_v29_20261020-163000_update.db`; behalten werden die [keep] neuesten.
class DbBackupStore {
  DbBackupStore(String dirPath) : _dir = (() async => dirPath);

  /// Für die App: Der Ordner steht erst fest, wenn der Pfad der Datenbank aufgelöst ist.
  DbBackupStore.lazy(Future<String> Function() dirPath) : _dir = dirPath;
  final Future<String> Function() _dir;

  static const keep = 5;
  static final _name = RegExp(r'^finance_v(\d+)_(\d{8})-(\d{6})(?:-\d+)?_([a-z]+)\.db$');

  /// Kopiert [dbPath] (die Datenbank muss geschlossen sein) und räumt alte Kopien auf.
  Future<DbBackup> create(String dbPath, {required int version, required BackupReason reason, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final dirPath = await _dir();
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}${two(at.second)}';
    var file = File(p.join(dirPath, 'finance_v${version}_${stamp}_${reason.slug}.db'));
    for (var i = 2; file.existsSync(); i++) {
      file = File(p.join(dirPath, 'finance_v${version}_$stamp-${i}_${reason.slug}.db'));
    }
    await File(dbPath).copy(file.path);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('$dbPath$suffix');
      if (side.existsSync()) await side.copy('${file.path}$suffix');
    }
    final backup = DbBackup(file: file, version: version, reason: reason, createdAt: at);
    await _prune();
    return backup;
  }

  /// Alle Sicherungen, neueste zuerst.
  Future<List<DbBackup>> list() async {
    final dir = Directory(await _dir());
    if (!dir.existsSync()) return [];
    final out = <DbBackup>[];
    for (final f in dir.listSync().whereType<File>()) {
      final m = _name.firstMatch(p.basename(f.path));
      if (m == null) continue;
      final d = m.group(2)!, t = m.group(3)!;
      out.add(DbBackup(
        file: f,
        version: int.parse(m.group(1)!),
        reason: BackupReason.values.firstWhere((r) => r.slug == m.group(4), orElse: () => BackupReason.manual),
        createdAt: DateTime(int.parse(d.substring(0, 4)), int.parse(d.substring(4, 6)), int.parse(d.substring(6, 8)),
            int.parse(t.substring(0, 2)), int.parse(t.substring(2, 4)), int.parse(t.substring(4, 6))),
      ));
    }
    out.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : b.file.path.compareTo(a.file.path);
    });
    return out;
  }

  Future<void> _prune() async {
    final all = await list();
    for (final old in all.skip(keep)) {
      for (final f in [old.file, File('${old.file.path}-wal'), File('${old.file.path}-shm')]) {
        if (f.existsSync()) await f.delete();
      }
    }
  }
}
