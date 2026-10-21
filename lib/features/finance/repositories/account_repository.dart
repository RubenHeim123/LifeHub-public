import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/finance/models/account.dart';

class AccountRepository {
  AccountRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  /// Konten werden über den Namen referenziert – zwei gleichnamige würden Buchungen doppelt zählen.
  Future<void> _checkName(DatabaseExecutor db, int uid, String name, {int? exceptId}) async {
    final rows = await db.query('accounts',
        columns: ['id'],
        where: 'accountUserid = ? AND is_deleted = 0 AND LOWER(TRIM(accountName)) = ? AND id != ?',
        whereArgs: [uid, name.trim().toLowerCase(), exceptId ?? -1]);
    if (rows.isNotEmpty) throw UserFacingException('Ein Konto „${name.trim()}“ gibt es schon.');
  }

  Future<void> createAccount(Account account) async {
    final db = await _db.database;
    await _checkName(db, account.accountUserid, account.accountName);
    await db.insert('accounts', account.toMap());
  }

  /// Legt mehrere Konten in einem Batch an (z. B. Standardkonten bei der Registrierung).
  Future<void> createAccounts(List<Account> accounts) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final a in accounts) {
      batch.insert('accounts', a.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<Account> getAccount(int id) async {
    final db = await _db.database;
    final maps = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) throw Exception('Account not found');
    return Account.fromMap(maps.first);
  }

  Future<List<Account>> getAllAccounts(int uid) async {
    final db = await _db.database;
    final maps = await db.query(
      'accounts',
      where: 'accountUserid = ? AND is_deleted = 0',
      whereArgs: [uid],
    );
    return maps.map(Account.fromMap).toList();
  }

  /// Speichert das Konto. Bei einer Umbenennung werden Transaktionen, wiederkehrende
  /// Transaktionen und Sparziele mitgezogen, weil sie das Konto über den Namen referenzieren.
  Future<void> updateAccount(Account account) async {
    final db = await _db.database;
    final now = syncStamp();
    await db.transaction((txn) async {
      await _checkName(txn, account.accountUserid, account.accountName, exceptId: account.id);
      final old = await txn.query('accounts', columns: ['accountName'], where: 'id = ?', whereArgs: [account.id]);
      final oldName = old.isEmpty ? null : old.first['accountName'] as String?;

      await txn.update('accounts', {...account.toMap(), 'last_changed': now},
          where: 'id = ?', whereArgs: [account.id]);

      if (oldName != null && oldName != account.accountName) {
        await _renameReferences(txn, account.accountUserid, oldName, account.accountName, now);
      }
    });
  }

  Future<void> _renameReferences(Transaction txn, int uid, String oldName, String newName, String now) async {
    for (final table in ['transactions', 'fixed_transactions']) {
      await txn.update(table, {'account': newName, 'last_changed': now},
          where: 'userid = ? AND account = ?', whereArgs: [uid, oldName]);
    }
    final goals = await txn.query('financial_goals',
        columns: ['id', 'selectedAccountNames'], where: 'userid = ?', whereArgs: [uid]);
    for (final g in goals) {
      final names = (g['selectedAccountNames'] as String? ?? '').split(',').map((e) => e.trim()).toList();
      if (!names.contains(oldName)) continue;
      final updated = names.map((n) => n == oldName ? newName : n).join(',');
      await txn.update('financial_goals', {'selectedAccountNames': updated, 'last_changed': now},
          where: 'id = ?', whereArgs: [g['id']]);
    }
  }

  Future<void> restoreAccount(int id) async {
    final db = await _db.database;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final a = Account.fromMap(rows.first);
    await _checkName(db, a.accountUserid, a.accountName, exceptId: id);
    await _db.restoreRow('accounts', id);
  }

  /// Löscht ein Konto – aber nur, wenn keine Buchungen mehr darauf laufen (sonst stimmten Kontostand
  /// und Buchungen nach einem Wiederherstellen nicht mehr überein).
  Future<void> deleteAccount(int id) async {
    final db = await _db.database;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final a = Account.fromMap(rows.first);
      final used = await db.rawQuery(
          'SELECT (SELECT COUNT(*) FROM transactions WHERE userid = ? AND account = ? AND is_deleted = 0) + '
          '(SELECT COUNT(*) FROM fixed_transactions WHERE userid = ? AND account = ? AND is_deleted = 0) AS n',
          [a.accountUserid, a.accountName, a.accountUserid, a.accountName]);
      final n = (used.first['n'] as int?) ?? 0;
      if (n > 0) {
        throw UserFacingException('„${a.accountName}“ hat noch $n ${n == 1 ? 'Buchung' : 'Buchungen'} – '
            'bitte diese erst löschen oder einem anderen Konto zuordnen.');
      }
    }
    await db.update(
      'accounts',
      {'is_deleted': 1, 'last_changed': syncStamp()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
