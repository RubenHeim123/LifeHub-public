import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/catalog/sample_plans.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/sample_plans_screen.dart';
import 'package:frontend/features/fitness/screens/training_screen.dart';
import 'package:frontend/features/fitness/screens/workout_editor_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<(UserModel, Workout)> seedWorkout(WidgetTester tester) => seedDb(tester, db, () async {
        final user = await createTestUser(db);
        final repo = WorkoutRepository(db: db);
        final e = await repo.addFromCatalog(user.uid, 'liegestuetz');
        final id = await repo.saveWorkout(Workout(
          userid: user.uid,
          name: 'Push',
          method: TrainingMethod.intervall,
          exercises: [WorkoutExercise(exercise: e, sets: 1)],
        ));
        return (user, (await repo.getWorkout(id))!);
      });

  group('repository', () {
    late WorkoutRepository repo;
    late UserModel user;

    setUp(() async {
      repo = WorkoutRepository(db: db);
      user = await createTestUser(db);
    });
    tearDown(() => db.close());

    test('a block can be planned once on the next matching weekdays instead of weekly', () async {
      final plan = samplePlanByKey('basis')!;
      final monday = DateTime(2026, 10, 5);
      final ids = await repo.importSampleBlock(user.uid, plan, plan.blocks.first,
          weekdays: [1, 2, 4, 5], once: true, start: DateTime(2026, 10, 3)); // Samstag

      final workouts = await repo.getWorkouts(user.uid);
      expect(workouts.every((w) => w.repeatWeekdays.isEmpty), isTrue);

      final week1 = await repo.getPlan(user.uid, monday, DateTime(2026, 10, 11));
      expect(week1.keys.map((d) => d.day).toList()..sort(), [5, 6, 8, 9]);
      expect(week1.values.expand((l) => l).every((e) => !e.isFromRepeat), isTrue);
      final week2 = await repo.getPlan(user.uid, DateTime(2026, 10, 12), DateTime(2026, 10, 18));
      expect(week2, isEmpty);

      final upcoming = await repo.getUpcomingOnce(user.uid, ids.first, from: DateTime(2026, 10, 3));
      expect(upcoming.single.date, monday);
    });
  });

  testWidgets('plan a workout once from the workout editor', (tester) async {
    useTallScreen(tester);
    final (user, workout) = await seedWorkout(tester);
    await tester.pumpWidget(testApp(db, WorkoutEditorScreen(userid: user.uid, workout: workout)));
    await pumpUntil(tester, find.text('Einmalig an bestimmten Tagen'));
    expect(find.text('Jede Woche wiederholen'), findsOneWidget);

    await tester.tap(find.text('Datum hinzufügen'));
    await pumpUntil(tester, find.text('OK'));
    await tester.tap(find.text('OK'));
    await pumpUntilGone(tester, find.text('OK'));
    expect(find.byType(InputChip), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await pumpUntilGone(tester, find.byType(WorkoutEditorScreen));

    final repo = WorkoutRepository(db: db);
    final entry = (await readDb(tester, () => repo.getPlanForDay(user.uid, today()))).single;
    expect(entry.isFromRepeat, isFalse);
    expect(entry.workout.name, 'Push');
    final saved = (await readDb(tester, () => repo.getWorkout(workout.id!)))!;
    expect(saved.repeatWeekdays, isEmpty);
    await disposeApp(tester, db);
  });

  testWidgets('plan a workout once from the workout list', (tester) async {
    useTallScreen(tester);
    final (user, _) = await seedWorkout(tester);
    await tester.pumpWidget(testApp(db, TrainingScreen(user: user)));
    await pumpUntil(tester, find.text('Workouts'));
    await tester.tap(find.text('Workouts'));
    await pumpUntil(tester, find.byTooltip('Einmalig einplanen'));
    await tester.tap(find.byTooltip('Einmalig einplanen'));
    await pumpUntil(tester, find.text('OK'));
    await tester.tap(find.text('OK'));
    await pumpUntil(tester, find.textContaining('Eingeplant für'));

    final plan = await readDb(tester, () => WorkoutRepository(db: db).getPlanForDay(user.uid, today()));
    expect(plan.single.isFromRepeat, isFalse);
    await disposeApp(tester, db);
  });

  testWidgets('take over a sample block once instead of weekly', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, SamplePlanScreen(userid: user.uid, plan: samplePlanByKey('basis')!)));
    await pumpUntil(tester, find.text('Woche 1–2 übernehmen'));
    await tester.tap(find.text('Woche 1–2 übernehmen'));
    await pumpUntil(tester, find.text('Einmalig'));
    await tester.tap(find.text('Einmalig'));
    await tester.pump();
    expect(find.textContaining('nächsten passenden Wochentag'), findsOneWidget);
    expect(find.text('Ab heute'), findsOneWidget);
    await pumpUntil(tester, find.text('Übernehmen').hitTestable());
    await tester.tap(find.text('Übernehmen'));
    final repo = WorkoutRepository(db: db);
    // Auf das Ergebnis warten statt nur auf die Meldung – unter Last dauert das Anlegen länger.
    // readDb statt pumpUntilTrue: sqflite-Abfragen in runAsync hängen bei der zweiten Abfrage.
    for (var i = 0; i < 200 && (await readDb(tester, () => repo.getWorkouts(user.uid))).length < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpUntil(tester, find.textContaining('4 Workouts angelegt'));

    final workouts = await readDb(tester, () => repo.getWorkouts(user.uid));
    expect(workouts.every((w) => w.repeatWeekdays.isEmpty), isTrue);
    final t = today();
    final plan = await readDb(tester, () => repo.getPlan(user.uid, t, DateTime(t.year, t.month, t.day + 6)));
    expect(plan.values.expand((l) => l), hasLength(4));
    await disposeApp(tester, db);
  });

  testWidgets('take over a sample block once starting at a chosen date', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, SamplePlanScreen(userid: user.uid, plan: samplePlanByKey('basis')!)));
    await pumpUntil(tester, find.text('Woche 1–2 übernehmen'));
    await tester.tap(find.text('Woche 1–2 übernehmen'));
    await pumpUntil(tester, find.text('Einmalig'));
    await tester.tap(find.text('Einmalig'));
    await tester.pump();

    // Startdatum: in 14 Tagen (per Texteingabe im Datumsdialog)
    final t = today();
    final start = DateTime(t.year, t.month, t.day + 14);
    await tester.tap(find.text('Ab heute'));
    await pumpUntil(tester, find.byIcon(Icons.edit_outlined));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    final field = find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextField));
    await tester.enterText(field, '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'); // deutsches Format
    await tester.tap(find.text('OK'));
    await pumpUntilGone(tester, find.byType(DatePickerDialog));
    expect(find.textContaining('Ab '), findsOneWidget);
    expect(find.text('Ab heute'), findsNothing);

    // Unter Last läuft die Dialog-Animation noch – erst tippen, wenn der Knopf wirklich erreichbar ist
    await pumpUntil(tester, find.text('Übernehmen').hitTestable());
    await tester.tap(find.text('Übernehmen'));
    await pumpUntil(tester, find.textContaining('4 Workouts angelegt'));

    final repo = WorkoutRepository(db: db);
    final before = await readDb(tester, () => repo.getPlan(user.uid, t, DateTime(start.year, start.month, start.day - 1)));
    expect(before, isEmpty);
    final plan = await readDb(tester, () => repo.getPlan(user.uid, start, DateTime(start.year, start.month, start.day + 6)));
    expect(plan.values.expand((l) => l), hasLength(4));
    await disposeApp(tester, db);
  });
}
