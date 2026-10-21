import 'package:sqflite/sqflite.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:intl/intl.dart';

class HabitRepository {
  HabitRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;
  Future<void> createHabit(Habit habit) async {
    final db = await _db.database;
    await db.insert('habits', habit.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Habit>> getAllHabits(int uid) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'habits', 
      where: 'userid = ? AND is_deleted = 0', 
      whereArgs: [uid]
    );
    return List.generate(maps.length, (i) => Habit.fromMap(maps[i]));
  }

  Future<void> updateHabit(Habit habit) async {
    final db = await _db.database;
    final Map<String, dynamic> data = habit.toMap();
    data['last_changed'] = syncStamp();
    await db.update('habits', data, where: 'id = ?', whereArgs: [habit.id]);
  }

  /// Macht einen gelöschten Habit samt der mit ihm gelöschten Einträge wieder sichtbar.
  Future<void> restoreHabit(int id) async {
    final db = await _db.database;
    final rows = await db.query('habits', columns: ['last_changed'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final deletedAt = rows.first['last_changed'];
    final now = syncStamp();
    await db.update('habits', {'is_deleted': 0, 'last_changed': now}, where: 'id = ?', whereArgs: [id]);
    await db.update('habit_records', {'is_deleted': 0, 'last_changed': now},
        where: 'habitId = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [id, deletedAt]);
  }

  Future<void> deleteHabit(int id) async {
    final db = await _db.database;
    final String now = syncStamp();
    // Soft delete habit
    await db.update(
      'habits', 
      {'is_deleted': 1, 'last_changed': now}, 
      where: 'id = ?', 
      whereArgs: [id]
    );
    // Nur die sichtbaren Einträge mitlöschen – schon abgewählte behalten ihren Zeitstempel,
    // sonst würde „Rückgängig“ (restoreHabit) sie wieder als erledigt herstellen
    await db.update(
      'habit_records',
      {'is_deleted': 1, 'last_changed': now},
      where: 'habitId = ? AND is_deleted = 0',
      whereArgs: [id],
    );
  }

  Future<void> toggleHabitCompletion(int habitId, DateTime date, bool isCompleted) async {
    final db = await _db.database;
    String dateStr = DateFormat('yyyy-MM-dd').format(date);
    final String now = syncStamp();
    
    if (isCompleted) {
      // Check if record already exists (could be a soft-deleted one)
      final List<Map<String, dynamic>> existing = await db.query(
        'habit_records',
        where: 'habitId = ? AND date = ?',
        whereArgs: [habitId, dateStr],
      );

      if (existing.isNotEmpty) {
        await db.update(
          'habit_records', 
          {'is_deleted': 0, 'last_changed': now},
          where: 'habitId = ? AND date = ?',
          whereArgs: [habitId, dateStr],
        );
      } else {
        await db.insert('habit_records', {
          'habitId': habitId,
          'date': dateStr,
          'last_changed': now,
          'is_deleted': 0,
        });
      }
    } else {
      // Instead of DELETE, we use UPDATE for delta sync
      await db.update(
        'habit_records', 
        {'is_deleted': 1, 'last_changed': now},
        where: 'habitId = ? AND date = ?',
        whereArgs: [habitId, dateStr],
      );
    }
  }

  Future<bool> isHabitCompletedOnDate(int habitId, DateTime date) async {
    final db = await _db.database;
    String dateStr = DateFormat('yyyy-MM-dd').format(date);
    final count = Sqflite.firstIntValue(await db.query(
      'habit_records',
      columns: ['COUNT(*)'],
      where: 'habitId = ? AND date = ? AND is_deleted = 0',
      whereArgs: [habitId, dateStr],
    ));
    return (count ?? 0) > 0;
  }

  Future<int> calculateStreak(int habitId) async {
    final db = await _db.database;
    final habitMaps = await db.query('habits', where: 'id = ?', whereArgs: [habitId]);
    if (habitMaps.isEmpty) return 0;
    Habit habit = Habit.fromMap(habitMaps.first);

    final maps = await db.rawQuery(
      'SELECT DISTINCT date FROM habit_records WHERE habitId = ? AND is_deleted = 0 ORDER BY date DESC', 
      [habitId]
    );
    if (maps.isEmpty) return 0;

    List<DateTime> completedDates = maps.map((m) => DateTime.parse(m['date'] as String)).toList();
    
    return computeStreak(habit.selectedDays, completedDates);
  }

  /// Anzahl der zuletzt lückenlos erledigten geplanten Tage. [completedDates] darf
  /// unsortiert sein. Ein heute noch offener Termin bricht die Serie nicht.
  static int computeStreak(List<int> scheduledWeekdays, List<DateTime> completedDates, {DateTime? now}) {
    if (scheduledWeekdays.isEmpty || completedDates.isEmpty) return 0;
    completedDates = [...completedDates]..sort((a, b) => b.compareTo(a));

    int streak = 0;
    now ??= DateTime.now();
    DateTime checkDate = DateTime(now.year, now.month, now.day);
    
    // First, handle today separately
    bool isTodayScheduled = scheduledWeekdays.contains(checkDate.weekday);
    bool isTodayCompleted = completedDates.any((d) => d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
    
    if (isTodayScheduled && isTodayCompleted) {
       streak++;
    }
    
    checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
    
    DateTime oldestCompleted = completedDates.last;
    DateTime oldestNormalized = DateTime(oldestCompleted.year, oldestCompleted.month, oldestCompleted.day);

    // Loop backwards until we reach before the oldest completed date
    while (!checkDate.isBefore(oldestNormalized)) {
      if (scheduledWeekdays.contains(checkDate.weekday)) {
        bool isCompleted = completedDates.any((d) => d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
        if (isCompleted) {
          streak++;
        } else {
          // Missed a scheduled day, streak broken
          break;
        }
      }
      checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
    }
    
    return streak;
  }
}
