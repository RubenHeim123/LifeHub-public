import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/finance/models/category.dart';

class CategoryRepository {
  CategoryRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  /// Gleich heißen dürfen nur Kategorien verschiedenen Typs (z. B. „Geschenke“ als Einnahme und Ausgabe).
  Future<void> _checkName(DatabaseExecutor db, Category c, {int? exceptId}) async {
    final rows = await db.query('categories',
        columns: ['id'],
        where: 'categoryUserid = ? AND is_deleted = 0 AND transactionType = ? AND LOWER(TRIM(categoryName)) = ? AND id != ?',
        whereArgs: [c.categoryUserid, c.transactionType.dbValue, c.categoryName.trim().toLowerCase(), exceptId ?? -1]);
    if (rows.isNotEmpty) {
      throw UserFacingException('Eine ${c.transactionType.label}-Kategorie „${c.categoryName.trim()}“ gibt es schon.');
    }
  }

  Future<void> createCategory(Category category) async {
    final db = await _db.database;
    await _checkName(db, category);
    await db.insert('categories', category.toMap());
  }

  /// Legt mehrere Kategorien in einem Batch an (z. B. Standardkategorien bei der Registrierung).
  Future<void> createCategories(List<Category> categories) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final c in categories) {
      batch.insert('categories', c.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<Category> getCategory(int id) async {
    final db = await _db.database;
    final maps = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) throw Exception('Category not found');
    return Category.fromMap(maps.first);
  }

  Future<List<Category>> getAllCategories(int uid) async {
    final db = await _db.database;
    final maps = await db.query(
      'categories',
      where: 'categoryUserid = ? AND is_deleted = 0',
      whereArgs: [uid],
    );
    return maps.map(Category.fromMap).toList();
  }

  /// Speichert die Kategorie. Bei einer Umbenennung werden Transaktionen desselben
  /// Typs mitgezogen, weil sie die Kategorie über den Namen referenzieren.
  Future<void> updateCategory(Category category) async {
    final db = await _db.database;
    final now = syncStamp();
    await db.transaction((txn) async {
      await _checkName(txn, category, exceptId: category.id);
      final old = await txn.query('categories',
          columns: ['categoryName', 'transactionType'], where: 'id = ?', whereArgs: [category.id]);

      await txn.update('categories', {...category.toMap(), 'last_changed': now},
          where: 'id = ?', whereArgs: [category.id]);

      if (old.isEmpty) return;
      final oldName = old.first['categoryName'] as String?;
      if (oldName == null || oldName == category.categoryName) return;
      for (final table in ['transactions', 'fixed_transactions']) {
        await txn.update(table, {'category': category.categoryName, 'last_changed': now},
            where: 'userid = ? AND category = ? AND transactionType = ?',
            whereArgs: [category.categoryUserid, oldName, old.first['transactionType']]);
      }
    });
  }

  Future<void> restoreCategory(int id) async {
    final db = await _db.database;
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    await _checkName(db, Category.fromMap(rows.first), exceptId: id);
    await _db.restoreRow('categories', id);
  }

  Future<void> deleteCategory(int id) async {
    final db = await _db.database;
    await db.update(
      'categories',
      {'is_deleted': 1, 'last_changed': syncStamp()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
