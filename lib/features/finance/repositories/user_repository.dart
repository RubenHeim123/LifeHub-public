import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';

class UserRepository {
  UserRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  /// Legt den Nutzer an und gibt die von SQLite vergebene `uid` zurück.
  Future<int> createUser(UserModel user) async {
    final db = await _db.database;
    return db.insert('users', user.toMap()..remove('uid'));
  }

  Future<UserModel> getUser(int uid) async {
    final db = await _db.database;
    final maps = await db.query('users', where: 'uid = ?', whereArgs: [uid]);
    if (maps.isEmpty) throw Exception('User not found');
    return UserModel.fromMap(maps.first);
  }

  Future<UserModel?> getUserFromEmail(String email) async {
    final db = await _db.database;
    final maps = await db.query('users', where: 'email = ?', whereArgs: [email]);
    return maps.isEmpty ? null : UserModel.fromMap(maps.first);
  }

  /// Speichert die Profildaten. Das Passwort wird bewusst nicht angefasst
  /// (dafür gibt es [updatePasswordHash]), sonst würde ein Profil-Update ohne
  /// Passwort den Hash löschen.
  Future<void> updateUser(UserModel user) async {
    final db = await _db.database;
    await db.update('users', user.toMap()..remove('password'), where: 'uid = ?', whereArgs: [user.uid]);
  }

  Future<void> updatePasswordHash(int uid, String hash) async {
    final db = await _db.database;
    await db.update('users', {'password': hash}, where: 'uid = ?', whereArgs: [uid]);
  }

  /// Addiert [delta] XP (nie unter 0) und gibt den aktualisierten Nutzer zurück.
  Future<UserModel> addExperience(int uid, int delta) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE users SET experiencePoints = MAX(0, COALESCE(experiencePoints, 0) + ?) WHERE uid = ?',
      [delta, uid],
    );
    return getUser(uid);
  }

  Future<List<UserModel>> getAllUsers() async {
    final db = await _db.database;
    final maps = await db.query('users');
    return maps.map(UserModel.fromMap).toList();
  }

  Future<void> deleteUser(int uid) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('transactions', where: 'userid = ?', whereArgs: [uid]);
      await txn.delete('fixed_transactions', where: 'userid = ?', whereArgs: [uid]);
      await txn.delete('categories', where: 'categoryUserid = ?', whereArgs: [uid]);
      await txn.delete('accounts', where: 'accountUserid = ?', whereArgs: [uid]);
      await txn.delete('todos', where: 'userid = ?', whereArgs: [uid]);
      await txn.delete('appointments', where: 'userid = ?', whereArgs: [uid]);
      await txn.delete('financial_goals', where: 'userid = ?', whereArgs: [uid]);
      await txn.rawDelete('DELETE FROM habit_records WHERE habitId IN (SELECT id FROM habits WHERE userid = ?)', [uid]);
      await txn.delete('habits', where: 'userid = ?', whereArgs: [uid]);
      for (final table in ['goal_steps', 'vision_goals', 'vision_areas', ...DatabaseService.lifestyleTables]) {
        await txn.delete(table, where: 'userid = ?', whereArgs: [uid]);
      }
      await txn.delete('users', where: 'uid = ?', whereArgs: [uid]);
    });
  }
}
