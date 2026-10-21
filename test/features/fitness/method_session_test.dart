import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/method_session_screen.dart';
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

  Future<(UserModel, Workout)> seedWorkout(WidgetTester tester, TrainingMethod method, List<String> keys) =>
      seedDb(tester, db, () async {
        final user = await createTestUser(db);
        final repo = WorkoutRepository(db: db);
        final exercises = [for (final k in keys) await repo.addFromCatalog(user.uid, k)];
        final id = await repo.saveWorkout(Workout(
          userid: user.uid,
          name: 'Test-Workout',
          method: method,
          exercises: [for (final e in exercises) WorkoutExercise(exercise: e, sets: 1, reps: 6)],
        ));
        return (user, (await repo.getWorkout(id))!);
      });

  MethodSessionScreenState stateOf(WidgetTester tester) => tester.state(find.byType(MethodSessionScreen));

  testWidgets('start an entered workout from the list and run interval sets with the timer', (tester) async {
    useTallScreen(tester);
    final (user, _) = await seedWorkout(tester, TrainingMethod.intervall, ['liegestuetz']);
    await tester.pumpWidget(testApp(db, TrainingScreen(user: user)));
    await pumpUntil(tester, find.text('Workouts'));
    await tester.tap(find.text('Workouts'));
    await pumpUntil(tester, find.byTooltip('Jetzt starten'));
    await tester.tap(find.byTooltip('Jetzt starten'));
    await pumpUntil(tester, find.text("Los geht's"));
    expect(find.text('Intervallsätze'), findsWidgets);
    expect(find.text('3:00'), findsOneWidget);

    await tester.tap(find.text("Los geht's"));
    await tester.pump();
    expect(find.text('Satz 1 von 3'), findsOneWidget);

    // Satz 1: 10 Wiederholungen eintragen (Standard 8, zweimal +)
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pump();
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pump();
    await tester.tap(find.text('Satz geschafft'));
    await tester.pump();
    expect(find.textContaining('Pause bis zum nächsten Satz'), findsOneWidget);

    for (var set = 2; set <= 3; set++) {
      stateOf(tester).advance(const Duration(minutes: 3));
      await tester.pump();
      expect(find.text('Satz $set von 3'), findsOneWidget);
      await tester.tap(find.text('Satz geschafft'));
      await tester.pump();
    }
    expect(find.text('Stark! Training geschafft.'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await pumpUntilGone(tester, find.byType(MethodSessionScreen));

    final repo = WorkoutRepository(db: db);
    final entry = (await readDb(tester, () => repo.getPlanForDay(user.uid, today()))).single;
    expect(entry.status, PlanStatus.done);
    final session = await readDb(tester, () => repo.getSession(entry.sessionId!));
    expect(session!.sets.map((s) => s.value), [10, 8, 8]);
    await disposeApp(tester, db);
  });

  testWidgets('step intervals: ladder with rest and early finish saves the total', (tester) async {
    useTallScreen(tester);
    final (user, workout, session) = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = WorkoutRepository(db: db);
      final e = await repo.addFromCatalog(user.uid, 'kniebeuge');
      final id = await repo.saveWorkout(Workout(
        userid: user.uid,
        name: 'Beine',
        method: TrainingMethod.stufen,
        exercises: [WorkoutExercise(exercise: e, sets: 1)],
      ));
      final w = (await repo.getWorkout(id))!;
      final (_, s) = await repo.startNow(user.uid, w);
      return (user, w, s);
    });
    await tester.pumpWidget(testApp(db, launcher(MethodSessionScreen(workout: workout, session: session, autoTick: false))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text("Los geht's"));
    expect(find.text('7:30'), findsOneWidget);

    await tester.tap(find.text("Los geht's"));
    await tester.pump();
    stateOf(tester).advance(const Duration(seconds: 6));
    await tester.pump();
    await tester.tap(find.text('Stufe 1 geschafft'));
    await tester.pump();
    expect(find.text('Pause – danach Stufe 2'), findsOneWidget);
    expect(find.text('0:06'), findsOneWidget); // Pause so lang wie die Arbeitsphase

    stateOf(tester).advance(const Duration(seconds: 6));
    await tester.pump();
    await tester.tap(find.text('Muskelversagen bei Stufe 2 – ab jetzt abwärts'));
    await tester.pump();
    expect(find.textContaining('Bisher 3 Wdh.'), findsOneWidget);
    expect(find.text('Pause – danach Stufe 1'), findsOneWidget);

    await tester.tap(find.text('Training beenden'));
    await pumpUntil(tester, find.text('Beenden'));
    await tester.tap(find.text('Beenden'));
    await pumpUntil(tester, find.text('result:true'));

    final saved = await readDb(tester, () => WorkoutRepository(db: db).getSession(session.id));
    expect(saved!.sets.single.value, 3);
    expect(user.uid, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('high intensity: no rep counting, the next exercise is shown during the change', (tester) async {
    useTallScreen(tester);
    final (user, workout, session) = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = WorkoutRepository(db: db);
      final a = await repo.addFromCatalog(user.uid, 'kniebeuge');
      final b = await repo.addFromCatalog(user.uid, 'liegestuetz');
      final id = await repo.saveWorkout(Workout(
        userid: user.uid,
        name: 'HIT',
        method: TrainingMethod.hochintensiv,
        exercises: [WorkoutExercise(exercise: a, sets: 1), WorkoutExercise(exercise: b, sets: 1)],
      ));
      final w = (await repo.getWorkout(id))!;
      final (_, s) = await repo.startNow(user.uid, w);
      return (user, w, s);
    });
    await tester.pumpWidget(testApp(db, launcher(MethodSessionScreen(workout: workout, session: session, autoTick: false))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text("Los geht's"));
    await tester.tap(find.text("Los geht's"));
    await tester.pump();
    expect(find.text('+1 Wiederholung'), findsNothing);
    expect(find.text('So schnell wie möglich – sauber bleiben!'), findsOneWidget);

    // 8 Runden à 20 s + 7 × 10 s Pause → Wechsel; die nächste Übung steht schon da
    for (var i = 0; i < 8 * 20 + 7 * 10; i++) {
      stateOf(tester).advance(const Duration(seconds: 1));
    }
    await tester.pump();
    expect(find.textContaining('Gleich: Übung 2 von 2'), findsOneWidget);
    expect(find.textContaining('Wechsel – gleich:'), findsOneWidget);
    expect(user.uid, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('workout editor: training method replaces sets and reps', (tester) async {
    useTallScreen(tester);
    final (user, _) = await seedWorkout(tester, TrainingMethod.zirkel, ['liegestuetz', 'kniebeuge']);
    final workout = (await readDb(tester, () => WorkoutRepository(db: db).getWorkouts(user.uid))).single;
    await tester.pumpWidget(testApp(db, WorkoutEditorScreen(userid: user.uid, workout: workout)));
    await pumpUntil(tester, find.text('Zirkelintervalle'));
    expect(find.text('6 Wdh. pro Runde'), findsNWidgets(2));

    await tester.tap(find.text('Supersätze'));
    await tester.pump();
    expect(find.textContaining('Paar 1'), findsNWidgets(2));
    expect(find.textContaining('Der Timer führt dich'), findsOneWidget);

    await tester.tap(find.text('Frei (Sätze × Wdh.)'));
    await tester.pump();
    expect(find.text('1 × 6'), findsNWidgets(2));

    await tester.tap(find.text('Hochintensitätssätze'));
    await tester.tap(find.text('Speichern'));
    await pumpUntilGone(tester, find.byType(WorkoutEditorScreen));
    final saved = (await readDb(tester, () => WorkoutRepository(db: db).getWorkouts(user.uid))).single;
    expect(saved.method, TrainingMethod.hochintensiv);
    await disposeApp(tester, db);
  });

  testWidgets('timer screens render on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final (_, workout, session) = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = WorkoutRepository(db: db);
      final a = await repo.addFromCatalog(user.uid, 'sturzflug');
      final b = await repo.addFromCatalog(user.uid, 'liegestuetz_abstossen');
      final id = await repo.saveWorkout(Workout(
        userid: user.uid,
        name: 'Master Class Woche 5–6 · Tag 1 Drücken',
        method: TrainingMethod.supersatz,
        exercises: [WorkoutExercise(exercise: a, sets: 1), WorkoutExercise(exercise: b, sets: 1)],
      ));
      final w = (await repo.getWorkout(id))!;
      final (_, s) = await repo.startNow(user.uid, w);
      return (user, w, s);
    });
    await tester.pumpWidget(testApp(db, MethodSessionScreen(workout: workout, session: session, autoTick: false)));
    await tester.pump();
    await tester.tap(find.text("Los geht's"));
    await tester.pump();
    expect(find.text('Supersatz geschafft'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });
}
