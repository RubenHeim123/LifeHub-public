import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';
import 'package:frontend/features/fitness/screens/session_screen.dart';
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

  /// Nutzer mit Workout „Push“ (Liegestütze 2 × 10, Plank 1 × 30 s), das heute wiederholt wird.
  Future<UserModel> seedPushDay(WidgetTester tester) => seedDb(tester, db, () async {
        final user = await createTestUser(db);
        final repo = WorkoutRepository(db: db);
        final pushups = await repo.saveExercise(Exercise(userid: user.uid, name: 'Liegestütze'));
        final plank = await repo.saveExercise(Exercise(userid: user.uid, name: 'Plank', metric: ExerciseMetric.time));
        final exercises = await repo.getExercises(user.uid);
        await repo.saveWorkout(Workout(
          userid: user.uid,
          name: 'Push',
          repeatWeekdays: [today().weekday],
          exercises: [
            WorkoutExercise(exercise: exercises.firstWhere((e) => e.id == pushups), sets: 2, reps: 10),
            WorkoutExercise(exercise: exercises.firstWhere((e) => e.id == plank), sets: 1, durationSec: 30),
          ],
        ));
        return user;
      });

  testWidgets('compose a workout from starter exercises and plan it for today', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, TrainingScreen(user: user)));
    await pumpUntil(tester, find.text('Stell dir zuerst ein Workout zusammen.'));

    await tester.tap(find.text('Workouts'));
    await pumpUntil(tester, find.text('Noch keine Workouts'));
    await tester.tap(find.text('Workout'));
    await pumpUntil(tester, find.byType(WorkoutEditorScreen));

    await enterInCard(tester, 'Name', 'Oberkörper');
    await tester.tap(find.text(weekdayShort[today().weekday - 1]));
    await tester.tap(find.text('Übung hinzufügen'));
    await pumpUntil(tester, find.text('Übung wählen')); // ein Katalog für alles
    await pumpUntil(tester, find.text('Klimmzüge')); // Startübungen werden angelegt
    await tester.tap(find.text('Klimmzüge').first);
    await pumpUntil(tester, find.text('3 × 10'));

    // Vorgabe anpassen
    await tester.tap(find.text('3 × 10'));
    await pumpUntil(tester, find.byType(AlertDialog));
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await tester.enterText(fields.at(0), '4');
    await tester.enterText(fields.at(1), '8');
    await tester.tap(find.text('Speichern'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    expect(find.text('4 × 8'), findsOneWidget);

    await tester.tap(find.text('Hinzufügen'));
    await pumpUntilGone(tester, find.byType(WorkoutEditorScreen));
    await pumpUntil(tester, find.text('Oberkörper'));
    await pageBack(tester);
    await pumpUntil(tester, find.text('Starten'));
    expect(find.text('Klimmzüge 4 × 8'), findsOneWidget);

    final plan = await readDb(tester, () => WorkoutRepository(db: db).getPlanForDay(user.uid, today()));
    expect(plan.single.workout.name, 'Oberkörper');
    expect(plan.single.isFromRepeat, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('run a session: log sets and finish marks today as done', (tester) async {
    useTallScreen(tester);
    final user = await seedPushDay(tester);
    await tester.pumpWidget(testApp(db, TrainingScreen(user: user)));
    await pumpUntil(tester, find.text('Starten'));

    await tester.tap(find.text('Starten'));
    await pumpUntil(tester, find.byType(SessionScreen));
    expect(find.text('0 von 3 Sätzen erledigt'), findsOneWidget);

    // Satz 1: Wert ändern (hakt automatisch ab)
    await tester.tap(find.text('10 Wdh.').first);
    await pumpUntil(tester, find.byType(AlertDialog));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '12');
    await tester.tap(find.text('Übernehmen'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntil(tester, find.text('1 von 3 Sätzen erledigt'));

    await tester.tap(find.text('Training beenden'));
    await pumpUntilGone(tester, find.byType(SessionScreen));
    await pumpUntil(tester, find.text('Protokoll ansehen'));
    expect(find.textContaining('Erledigt'), findsOneWidget);

    final repo = WorkoutRepository(db: db);
    final entry = (await readDb(tester, () => repo.getPlanForDay(user.uid, today()))).single;
    expect(entry.status, PlanStatus.done);
    final session = await readDb(tester, () => repo.getSession(entry.sessionId!));
    expect(session!.sets.first.value, 12);
    expect(session.sets.first.done, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('skip a repeated workout', (tester) async {
    useTallScreen(tester);
    final user = await seedPushDay(tester);
    await tester.pumpWidget(testApp(db, TrainingScreen(user: user)));
    await pumpUntil(tester, find.text('Starten'));

    await tester.drag(find.text('Starten'), const Offset(400, 0)); // nach rechts wischen
    await pumpUntil(tester, find.text('Überspringen'));
    await tester.tap(find.text('Überspringen'));
    await pumpUntilGone(tester, find.text('Starten'));
    expect(find.textContaining('Übersprungen'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('one catalog: own exercises next to the catalog, + adds one, swipe deletes with undo', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, CatalogScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Human-Flag-Progression')); // Startübungen als eigene Übungen
    expect(find.text('EIGENE ÜBUNGEN'), findsOneWidget);

    await tester.tap(find.text('Eigene Übung'));
    await pumpUntil(tester, find.text('Neue Übung'));
    expect(find.text('Messen in'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern')); // ohne Namen
    await tester.pump();
    expect(find.text('Name erforderlich'), findsOneWidget);
    expect(find.text('Neue Übung'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'L-Sit');
    await tester.tap(find.text('Zeit'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntilGone(tester, find.text('Neue Übung'));
    await pumpUntil(tester, find.text('L-Sit'));

    await tester.tap(find.text('Eigene'));
    await tester.pump();
    expect(find.text('Liegestütz (Hände erhöht)'), findsNothing); // nur eigene
    await tester.drag(find.text('L-Sit'), const Offset(-400, 0));
    await pumpUntil(tester, find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('„L-Sit“ gelöscht'));
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('L-Sit'));

    final names = (await readDb(tester, () => WorkoutRepository(db: db).getExercises(user.uid))).map((e) => e.name);
    expect(names, contains('L-Sit'));
    await disposeApp(tester, db);
  });

  testWidgets('training renders on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seedPushDay(tester);
    await tester.pumpWidget(testApp(db, TrainingScreen(user: user)));
    await pumpUntil(tester, find.text('Starten'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });
}
