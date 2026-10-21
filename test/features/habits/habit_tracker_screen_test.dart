import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/habits/screens/habit_tracker_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('HabitTrackerScreen shows habits with their streak', (tester) async {
    final db = createTestDatabase();
    final user = (await tester.runAsync(() async {
      final user = await createTestUser(db);
      final repo = HabitRepository(db: db);
      await repo.createHabit(Habit(name: 'Wasser trinken', userid: user.uid));
      final habit = (await repo.getAllHabits(user.uid)).single;
      final today = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await repo.toggleHabitCompletion(habit.id!, DateTime(today.year, today.month, today.day - i), true);
      }
      return user;
    }))!;

    await tester.pumpWidget(testApp(db, HabitTrackerScreen(user: user)));
    await pumpUntil(tester, find.text('Wasser trinken'));

    expect(find.textContaining('heute erledigt'), findsOneWidget);
    expect(find.text('Wasser trinken'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);
    expect(find.text('Mo'), findsWidgets);

    await disposeApp(tester, db);
  });

  testWidgets('deleting a habit with undo keeps its streak', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = HabitRepository(db: db);
      await repo.createHabit(Habit(name: 'Wasser trinken', userid: user.uid));
      final habit = (await repo.getAllHabits(user.uid)).single;
      final today = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await repo.toggleHabitCompletion(habit.id!, DateTime(today.year, today.month, today.day - i), true);
      }
      return user;
    });
    await tester.pumpWidget(testApp(db, HabitTrackerScreen(user: user)));
    await pumpUntil(tester, find.text('Wasser trinken'));

    await swipeDelete(tester, find.text('Wasser trinken'));
    await pumpUntilGone(tester, find.text('Wasser trinken'));
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Wasser trinken'));
    final habit = (await readDb(tester, () => HabitRepository(db: db).getAllHabits(user.uid))).single;
    final today = DateTime.now();
    expect(await readDb(tester, () => HabitRepository(db: db).isHabitCompletedOnDate(habit.id!, today)), isTrue);
    await disposeApp(tester, db);
  });
}
