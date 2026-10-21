import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/core/database/database.dart';

class FinancialGoalRepository {
  FinancialGoalRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  Future<void> createGoal(FinancialGoal goal) async {
    final db = await _db.database;
    await db.insert('financial_goals', goal.toMap());
  }

  Future<FinancialGoal> getGoal(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps =
        await db.query('financial_goals', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return FinancialGoal.fromMap(maps.first);
    } else {
      throw Exception('Financial Goal not found');
    }
  }

  Future<List<FinancialGoal>> getAllGoals(int uid) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'financial_goals',
      where: 'userid = ? AND is_deleted = 0',
      whereArgs: [uid],
    );
    return List.generate(maps.length, (i) {
      return FinancialGoal.fromMap(maps[i]);
    });
  }

  Future<void> updateGoal(FinancialGoal goal) async {
    final db = await _db.database;
    final Map<String, dynamic> data = goal.toMap();
    data['last_changed'] = syncStamp();
    await db.update('financial_goals', data,
        where: 'id = ?', whereArgs: [goal.id]);
  }

  Future<void> restoreGoal(int id) => _db.restoreRow('financial_goals', id);

  Future<void> deleteGoal(int id) async {
    final db = await _db.database;
    await db.update(
      'financial_goals',
      {
        'is_deleted': 1,
        'last_changed': syncStamp(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
