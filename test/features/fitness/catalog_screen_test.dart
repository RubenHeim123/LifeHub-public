import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/features/fitness/catalog/exercise_howto.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/fitness/catalog/sample_plans.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';
import 'package:frontend/features/fitness/screens/sample_plans_screen.dart';
import 'package:frontend/features/fitness/screens/workout_editor_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  testWidgets('search the catalog, open a detail and add the exercise', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, CatalogScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Übungskatalog'));
    await pumpUntil(tester, find.text('EIGENE ÜBUNGEN')); // Startübungen fertig angelegt

    await tester.tap(find.text('Waden'));
    await tester.pump();
    expect(find.text('Cliffhanger'), findsOneWidget);
    expect(find.text('Liegestütz'), findsNothing);

    await tester.enterText(find.byType(TextField), 'cliff');
    await tester.pump();
    expect(find.text('Wadenheben'), findsNothing);
    await tester.tap(find.text('Cliffhanger'));
    await pumpUntil(tester, find.text('Muskeln')); // Detailseite offen
    expect(find.text('Ausführung'), exerciseHowTo.isEmpty ? findsNothing : findsOneWidget); // öffentliche Version ohne Texte
    expect(find.text('Stufe 4'), findsOneWidget);

    await tester.tap(find.text('Zu meinen Übungen'));
    await pumpUntil(tester, find.text('In deinen Übungen'));

    final exercises = await readDb(tester, () => WorkoutRepository(db: db).getExercises(user.uid));
    expect(exercises.where((e) => e.catalogKey == 'cliffhanger'), hasLength(1));
    await disposeApp(tester, db);
  });

  testWidgets('pick an exercise from the catalog in the workout editor', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, WorkoutEditorScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Übung hinzufügen'));

    await tester.tap(find.text('Übung hinzufügen'));
    await pumpUntil(tester, find.text('EIGENE ÜBUNGEN')); // ein Katalog für alle Übungen, Startübungen angelegt
    await tester.enterText(find.byType(TextField), 'pistol');
    await tester.pump();
    await tester.tap(find.text('Pistole'));
    await pumpUntil(tester, find.text('Auswählen'));
    await tester.tap(find.text('Auswählen'));
    await pumpUntil(tester, find.text('3 × 10'));
    expect(find.text('Pistole'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('take over a block of a sample plan as workouts', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, SamplePlansScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Basisprogramm'));

    await tester.tap(find.text('Basisprogramm'));
    await pumpUntil(tester, find.text('Woche 1–2 übernehmen'));
    expect(find.textContaining('Liegestütz (Hände erhöht)'), findsWidgets);

    await tester.tap(find.text('Woche 1–2 übernehmen'));
    await pumpUntil(tester, find.text('Übernehmen'));
    await tester.tap(find.text('Übernehmen'));
    await pumpUntil(tester, find.textContaining('4 Workouts angelegt'));

    final workouts = await readDb(tester, () => WorkoutRepository(db: db).getWorkouts(user.uid));
    expect(workouts, hasLength(4));
    expect(workouts.expand((w) => w.repeatWeekdays).toList()..sort(), [1, 2, 4, 5]);
    await disposeApp(tester, db);
  });

  testWidgets('catalog, detail and plan render on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seedDb(tester, db, () => createTestUser(db));

    await tester.pumpWidget(testApp(db, CatalogScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Übungskatalog'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Liegestütz').first);
    await pumpUntil(tester, find.text('Muskeln')); // Detailseite offen
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox()); // Navigator mit geöffneter Detailseite verwerfen
    await tester.pumpWidget(testApp(db, SamplePlanScreen(userid: user.uid, plan: samplePlanByKey('chief_class')!)));
    await pumpUntil(tester, find.text('Einstiegstest'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });
}
