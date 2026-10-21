import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';
import 'package:frontend/features/todos/screens/todo_list_screen.dart';
import 'package:frontend/features/vision/models/vision.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/features/vision/screens/goal_plan_screen.dart';
import 'package:frontend/features/vision/screens/vision_board_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  /// Nutzer mit einem Bereich und einem Ziel; gibt (Nutzer, Ziel-ID) zurück.
  Future<(UserModel, int)> seedGoal(WidgetTester tester, {List<String> steps = const []}) {
    return seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = VisionRepository(db: db);
      final areaId = await repo.createArea(VisionArea(userid: user.uid, title: 'Beruf'));
      final goalId = await repo.createGoal(
          VisionGoal(areaId: areaId, userid: user.uid, title: 'Eigenes Unternehmen', note: 'bis Jahresende'));
      for (final s in steps) {
        await repo.createStep(GoalStep(goalId: goalId, userid: user.uid, title: s));
      }
      return (user, goalId);
    });
  }

  Future<GoalPlan> planOf(WidgetTester tester, int goalId) async =>
      (await readDb(tester, () => VisionRepository(db: db).getPlan(goalId)));

  Future<void> fillDialog(WidgetTester tester, List<String> values) async {
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
  }

  group('VisionBoardScreen', () {
    testWidgets('empty board offers the template with all its areas and goals', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, VisionBoardScreen(user: user)));
      await pumpUntil(tester, find.text('Noch kein Vision Board'));

      final (firstArea, _, _, firstGoals) = visionBoardTemplate.first;
      final goalCount = visionBoardTemplate.expand((t) => t.$4).length;
      await tester.tap(find.text('Vorlage laden'));
      await pumpUntil(tester, find.textContaining(firstArea.toUpperCase()));

      expect(find.text('STATUS 00 / ${goalCount.toString().padLeft(2, '0')}'), findsOneWidget);
      expect(find.textContaining(firstGoals.first.$1), findsOneWidget);

      // Jeder Bereich mit Vorlagenbild hat es (in den App-Ordner kopiert), die anderen keins
      final board = (await readDb(tester, () => VisionRepository(db: db).getBoard(user.uid)));
      expect(board.map((a) => a.area.imagePath != null), [for (final t in visionBoardTemplate) t.$3 != null]);
      await disposeApp(tester, db);
    });

    testWidgets('checking a goal updates area counter and overall status', (tester) async {
      useTallScreen(tester);
      final (user, _) = await seedGoal(tester);
      await tester.pumpWidget(testApp(db, VisionBoardScreen(user: user)));
      await pumpUntil(tester, find.textContaining('Eigenes Unternehmen'));
      expect(find.text('00/01'), findsOneWidget);

      await tester.tap(find.byType(AppCheck).first);
      await pumpUntil(tester, find.text('STATUS 01 / 01'));
      expect(find.text('01/01'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('adding an area and a goal through the dialogs', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, VisionBoardScreen(user: user)));
      await pumpUntil(tester, find.text('Noch kein Vision Board'));

      await tester.tap(find.text('Bereich anlegen'));
      await tester.pumpAndSettle();
      await fillDialog(tester, ['Gesundheit']);
      await pumpUntil(tester, find.textContaining('GESUNDHEIT'));

      // Neuer Bereich ohne Bild bietet direkt "Bild hinzufügen" an
      expect(find.text('Bild hinzufügen'), findsOneWidget);

      await tester.tap(find.text('Ziel hinzufügen'));
      await tester.pumpAndSettle();
      await fillDialog(tester, ['Halbmarathon laufen', '21,1 km']);
      await pumpUntil(tester, find.textContaining('Halbmarathon laufen'));
      expect(find.textContaining('21,1 km'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('tapping a goal opens its step-by-step plan', (tester) async {
      useTallScreen(tester);
      final (user, _) = await seedGoal(tester, steps: ['Businessplan schreiben']);
      await tester.pumpWidget(testApp(db, VisionBoardScreen(user: user)));
      await pumpUntil(tester, find.textContaining('Eigenes Unternehmen'));

      await tester.tap(find.textContaining('Eigenes Unternehmen'));
      await pumpUntil(tester, find.text('Businessplan schreiben'));

      expect(find.byType(GoalPlanScreen), findsOneWidget);
      expect(find.text('0 von 1 Schritten'), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  group('GoalPlanScreen', () {
    testWidgets('steps unlock in order and need their todos done', (tester) async {
      useTallScreen(tester);
      final (user, goalId) = await seedGoal(tester);
      await tester.pumpWidget(testApp(db, GoalPlanScreen(user: user, goalId: goalId)));
      await pumpUntil(tester, find.textContaining('Noch keine Schritte'));

      // Zwei Schritte anlegen
      for (final title in ['Markt analysieren', 'Firma gründen']) {
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await fillDialog(tester, [title]);
        await pumpUntil(tester, find.text(title));
      }
      expect(find.text('Erst den vorherigen Schritt abschließen'), findsOneWidget);

      // To-Do zum ersten Schritt über den Editor anlegen
      await tester.tap(find.text('To-Do').first);
      await pumpUntil(tester, find.text('Neue Aufgabe'));
      await enterInCard(tester, 'Titel', 'Wettbewerber recherchieren');
      await tester.ensureVisible(find.text('Hinzufügen'));
      await tester.tap(find.text('Hinzufügen'));
      await pumpUntilGone(tester, find.byType(AddUpdateTodoScreen));
      await pumpUntil(tester, find.text('Wettbewerber recherchieren'));
      expect(find.text('1 To-Do offen'), findsOneWidget);

      var plan = await planOf(tester, goalId);
      expect(plan.steps.first.canComplete, isFalse);

      // To-Do abhaken → Schritt abschließbar → abschließen → nächster Schritt aktiv
      // AppCheck 0 = "Ziel erreicht" im Kopf, 1 = das To-Do im ersten Schritt
      await tester.tap(find.byType(AppCheck).at(1));
      await pumpUntilGone(tester, find.text('1 To-Do offen'));
      await tester.tap(find.text('Schritt abschließen').first);
      await pumpUntil(tester, find.text('1 von 2 Schritten'));

      plan = await planOf(tester, goalId);
      expect(plan.steps.first.step.isDone, isTrue);
      expect(plan.steps.last.state, PlanStepState.active);
      await disposeApp(tester, db);
    });

    testWidgets('an existing todo can be linked to a step', (tester) async {
      useTallScreen(tester);
      final (user, goalId) = await seedGoal(tester, steps: ['Netzwerk aufbauen']);
      await seedDb(tester, db, () => TodoRepository(db: db).createTodo(Todo(title: 'Gründer-Meetup besuchen', userid: user.uid)));

      await tester.pumpWidget(testApp(db, GoalPlanScreen(user: user, goalId: goalId)));
      await pumpUntil(tester, find.text('Netzwerk aufbauen'));

      await tester.tap(find.text('Verknüpfen'));
      await pumpUntil(tester, find.text('Gründer-Meetup besuchen'));
      await tester.tap(find.text('Gründer-Meetup besuchen'));
      await pumpUntil(tester, find.text('1 To-Do offen'));

      final plan = await planOf(tester, goalId);
      expect(plan.steps.single.todos.single.title, 'Gründer-Meetup besuchen');
      await disposeApp(tester, db);
    });
  });

  group('links in other features', () {
    testWidgets('todo list shows the goal a todo belongs to', (tester) async {
      useTallScreen(tester);
      final (user, goalId) = await seedGoal(tester, steps: ['Businessplan']);
      await seedDb(tester, db, () async {
        final stepId = (await VisionRepository(db: db).getPlan(goalId)).steps.single.step.id;
        await TodoRepository(db: db).createTodo(Todo(title: 'Pitch Deck', userid: user.uid, goalStepId: stepId, dueDate: DateTime.now()));
      });

      await tester.pumpWidget(testApp(db, TodoListScreen(user: user)));
      await pumpUntil(tester, find.text('Pitch Deck'));

      expect(find.text('Eigenes Unternehmen'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('Home shows the vision board status', (tester) async {
      useTallScreen(tester);
      final (user, _) = await seedGoal(tester);
      await tester.pumpWidget(testApp(db, Home(user: user)));
      await pumpUntil(tester, find.text('Vision Board'));

      expect(find.text('0 von 1 Zielen erreicht'), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  group('phone layout (360 × 780)', () {
    void usePhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('board with the full template renders without overflow', (tester) async {
      usePhone(tester);
      final user = await seedDb(tester, db, () async {
        final user = await createTestUser(db);
        await VisionRepository(db: db).createTemplateBoard(user.uid);
        return user;
      });
      await tester.pumpWidget(testApp(db, VisionBoardScreen(user: user)));
      await pumpUntil(tester, find.textContaining(visionBoardTemplate.first.$1.toUpperCase()));

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await disposeApp(tester, db);
    });

    testWidgets('plan with todos and appointments renders without overflow', (tester) async {
      usePhone(tester);
      final (user, goalId) = await seedGoal(tester, steps: ['Ein Schritt mit einem sehr langen Titel, der umbrechen muss', 'Zweiter Schritt']);
      await seedDb(tester, db, () async {
        final stepId = (await VisionRepository(db: db).getPlan(goalId)).steps.first.step.id;
        await TodoRepository(db: db).createTodo(
            Todo(title: 'Eine Aufgabe mit langem Titel für den Zeilenumbruch', userid: user.uid, goalStepId: stepId, dueDate: DateTime(2027, 1, 5)));
        await AppointmentRepository(db: db).createAppointment(
            Appointment(title: 'Termin beim Notar für die Gründung', date: DateTime(2027, 2, 1, 10), userid: user.uid, goalStepId: stepId));
      });

      await tester.pumpWidget(testApp(db, GoalPlanScreen(user: user, goalId: goalId)));
      await pumpUntil(tester, find.text('Termin beim Notar für die Gründung'));
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Zweiter Schritt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeApp(tester, db);
    });
  });
}
