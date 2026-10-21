import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/habits/services/habit_actions.dart';

import '../../helpers/test_app.dart';

void main() {
  test('toggling gives and takes back XP exactly once', () async {
    final db = createTestDatabase();
    final habits = HabitRepository(db: db);
    final users = UserRepository(db: db);
    final user = await createTestUser(db);
    await habits.createHabit(Habit(name: 'Lesen', userid: user.uid));
    final habit = (await habits.getAllHabits(user.uid)).single;
    final today = DateTime(2026, 3, 31);

    Future<void> toggle(bool current) => HabitActions.toggle(
          habits: habits,
          users: users,
          userId: user.uid,
          habitId: habit.id!,
          date: today,
          currentlyCompleted: current,
        );

    await toggle(false);
    await toggle(false); // Doppeltipp: keine zusätzlichen XP
    expect((await users.getUser(user.uid)).experiencePoints, HabitActions.xpPerCompletion);
    expect(await habits.isHabitCompletedOnDate(habit.id!, today), isTrue);

    await toggle(true);
    expect((await users.getUser(user.uid)).experiencePoints, 0);
    expect(await habits.isHabitCompletedOnDate(habit.id!, today), isFalse);
    await db.close();
  });

  test('deleting a habit hides it and its records', () async {
    final db = createTestDatabase();
    final habits = HabitRepository(db: db);
    final user = await createTestUser(db);
    await habits.createHabit(Habit(name: 'Laufen', userid: user.uid, selectedDays: [1, 3, 5]));
    final habit = (await habits.getAllHabits(user.uid)).single;
    expect(habit.selectedDays, [1, 3, 5]);

    await habits.toggleHabitCompletion(habit.id!, DateTime(2026, 3, 30), true);
    await habits.deleteHabit(habit.id!);

    expect(await habits.getAllHabits(user.uid), isEmpty);
    expect(await habits.isHabitCompletedOnDate(habit.id!, DateTime(2026, 3, 30)), isFalse);
    await db.close();
  });
}
