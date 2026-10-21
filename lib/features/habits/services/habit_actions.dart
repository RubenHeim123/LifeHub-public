import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/auth/models/user.dart';

/// Gemeinsame Habit-Logik für Heute- und Habits-Screen.
class HabitActions {
  HabitActions._();

  static const int xpPerCompletion = 15;

  /// Schaltet die Erledigung um.
  ///
  /// XP gibt es nur, wenn sich der gespeicherte Zustand wirklich ändert:
  /// Abhaken gibt [xpPerCompletion] XP, Zurücknehmen zieht sie wieder ab.
  /// So lassen sich durch wiederholtes Ab- und Anhaken keine XP farmen.
  /// Gibt den aktualisierten Nutzer zurück, oder null wenn sich nichts geändert hat.
  static Future<UserModel?> toggle({
    required HabitRepository habits,
    required UserRepository users,
    required int userId,
    required int habitId,
    required DateTime date,
    required bool currentlyCompleted,
  }) async {
    final target = !currentlyCompleted;
    final wasCompleted = await habits.isHabitCompletedOnDate(habitId, date);

    await habits.toggleHabitCompletion(habitId, date, target);
    if (wasCompleted == target) return null; // Zustand war schon so (z. B. Doppeltipp) → keine XP-Änderung

    return users.addExperience(userId, target ? xpPerCompletion : -xpPerCompletion);
  }

  /// Ist das Habit an diesem Wochentag geplant?
  static bool isScheduled(List<int> selectedDays, DateTime day) => selectedDays.contains(day.weekday);

  /// Der [n]-te geplante Tag vor [from] (Mitternacht).
  static DateTime pastScheduledDate(DateTime from, List<int> days, int n) => _nthScheduled(from, days, n, -1);

  /// Der [n]-te geplante Tag nach [from] (Mitternacht).
  static DateTime futureScheduledDate(DateTime from, List<int> days, int n) => _nthScheduled(from, days, n, 1);

  static DateTime _nthScheduled(DateTime from, List<int> days, int n, int step) {
    var d = DateTime(from.year, from.month, from.day);
    if (days.isEmpty) return d; // sonst Endlosschleife
    var count = 0;
    while (count < n) {
      d = DateTime(d.year, d.month, d.day + step);
      if (days.contains(d.weekday)) count++;
    }
    return d;
  }

  static String scheduleSummary(List<int> days) {
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final sorted = [...days]..sort();
    if (sorted.length == 7) return 'Jeden Tag';
    if (sorted.length == 5 && !sorted.contains(6) && !sorted.contains(7)) return 'Wochentags';
    if (sorted.length == 2 && sorted.contains(6) && sorted.contains(7)) return 'Am Wochenende';
    return sorted.map((d) => labels[d - 1]).join(', ');
  }
}
