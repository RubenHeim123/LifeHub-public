import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/catalog/recipe_catalog.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Home aggregates today\'s habits, todos, appointments and finances', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final now = DateTime.now();
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await HabitRepository(db: db).createHabit(Habit(name: 'Meditieren', userid: user.uid));
      await TodoRepository(db: db).createTodo(Todo(title: 'Steuer machen', dueDate: now, userid: user.uid));
      await AppointmentRepository(db: db).createAppointment(Appointment(
        title: 'Friseur',
        date: DateTime(now.year, now.month, now.day, 23, 30),
        userid: user.uid,
      ));
      return user;
    });

    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Habits heute'));

    expect(find.text('Meditieren'), findsOneWidget);
    expect(find.text('Steuer machen'), findsOneWidget);
    expect(find.text('Friseur'), findsOneWidget);
    expect(find.text('Bilanz Monat'), findsOneWidget);

    await tester.tap(find.text('Meditieren'));
    await pumpUntil(tester, find.text('1/1'));

    // To-Do: Antippen öffnet die Aufgabe, das Kästchen hakt ab
    await tester.tap(find.text('Steuer machen'));
    await pumpUntil(tester, find.text('Aufgabe bearbeiten'));
    await pageBack(tester);
    await pumpUntil(tester, find.text('1 offen'));
    await tester.tap(find.bySemanticsLabel('Erledigt'));
    await pumpUntil(tester, find.text('0 offen'));
    // Gespeichert wird im Hintergrund – erst danach abbauen (sonst hängt unter Last noch ein DB-Timer)
    var done = false;
    for (var i = 0; i < 200 && !done; i++) {
      done = (await readDb(tester, () => TodoRepository(db: db).getAllTodos(user.uid))).single.isCompleted;
      if (!done) await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('Home shows unfinished past to-dos on top, marked as overdue; finished past ones stay hidden', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repo = TodoRepository(db: db);
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await repo.createTodo(Todo(title: 'Heute erledigen', dueDate: today, userid: user.uid));
      await repo.createTodo(Todo(title: 'Rechnung bezahlen', dueDate: addDays(today, -3), userid: user.uid));
      await repo.createTodo(Todo(title: 'Paket abholen', dueDate: addDays(today, -1), userid: user.uid));
      await repo.createTodo(Todo(title: 'Schon erledigt', dueDate: addDays(today, -2), isCompleted: true, userid: user.uid));
      await repo.createTodo(Todo(title: 'Ohne Datum', userid: user.uid));
      return user;
    });

    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Rechnung bezahlen'));
    expect(find.text('Paket abholen'), findsOneWidget);
    expect(find.text('Heute erledigen'), findsOneWidget);
    expect(find.text('Schon erledigt'), findsNothing); // erledigt bleibt in der Vergangenheit
    expect(find.text('Ohne Datum'), findsNothing);

    // Älteste überfällige zuerst, dann heute; deutlich markiert
    final ys = [for (final title in ['Rechnung bezahlen', 'Paket abholen', 'Heute erledigen']) tester.getTopLeft(find.text(title)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.text('Überfällig · seit gestern'), findsOneWidget);
    expect(find.textContaining('Überfällig · seit 3 Tagen'), findsOneWidget);
    expect(find.text('3 offen · 2 überfällig'), findsOneWidget);
    expect(find.text('0/1'), findsWidgets); // Tages-Score zählt nur die heutigen Aufgaben

    // Abhaken klappt auch bei überfälligen
    final check = find.descendant(
        of: find.ancestor(of: find.text('Rechnung bezahlen'), matching: find.byType(Row)).first, matching: find.bySemanticsLabel('Erledigt'));
    await tester.tap(check);
    await pumpUntil(tester, find.text('2 offen · 1 überfällig'));
    var done = false;
    for (var i = 0; i < 200 && !done; i++) {
      done = (await readDb(tester, () => repo.getAllTodos(user.uid))).firstWhere((t) => t.title == 'Rechnung bezahlen').isCompleted;
      if (!done) await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('Home for a brand-new user: friendly empty texts, optional sections hidden', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Habits heute'));

    expect(find.text('Heute sind keine Habits geplant.'), findsOneWidget);
    expect(find.text('Als Nächstes'), findsNothing); // ohne Termine ausgeblendet
    expect(find.text('Keine Aufgaben für heute.'), findsOneWidget);
    for (final hidden in ['Training heute', 'Essen heute', 'Läuft bald ab']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });

  testWidgets('Home fully filled on a small phone with large text; section links jump to the right tab', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final db = createTestDatabase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const long = 'Ein ziemlich langer Name, der auf schmalen Handys umbrechen muss';
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await HabitRepository(db: db).createHabit(Habit(name: long, userid: u.uid));
      await TodoRepository(db: db).createTodo(Todo(title: long, dueDate: now, userid: u.uid));
      await AppointmentRepository(db: db).createAppointment(
          Appointment(title: long, date: DateTime(now.year, now.month, now.day, 23, 30), userid: u.uid));
      await WorkoutRepository(db: db).saveWorkout(Workout(userid: u.uid, name: long, repeatWeekdays: [now.weekday]));
      final inventory = InventoryRepository(db: db);
      await inventory.createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: long, expiryDate: today));
      final meals = MealPlanRepository(db: db, lists: ListsRepository(db: db, inventory: inventory), inventory: inventory);
      final recipe = catalogRecipe('rote-linsen-dal')!;
      await meals.planBatch(uid: u.uid, recipe: recipe, cookDate: today, slots: [
        PortionSlot(today, Meal.lunch, 1),
        PortionSlot(today, Meal.dinner, 2),
      ]);
      await createTestAccount(db, u.uid, 'Girokonto', amount: 1234.56);
      return u;
    });

    final jumps = <(AppTab, Enum?)>[];
    await tester.pumpWidget(testApp(db, Home(user: user, onTabNav: (tab, [section]) => jumps.add((tab, section)))));
    await pumpUntil(tester, find.text('Habits heute'));

    final list = find.byType(Scrollable).first;
    for (final section in ['Training heute', 'Essen heute', 'Läuft bald ab', 'Vision Board']) {
      await tester.scrollUntilVisible(find.text(section), 200, scrollable: list);
      expect(tester.takeException(), isNull, reason: section);
    }
    await tester.scrollUntilVisible(find.text('Vorrat'), -100, scrollable: list);
    await tester.ensureVisible(find.text('Vorrat'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Vorrat'));
    expect(jumps.last, (AppTab.food, FoodSection.pantry));
    await tester.scrollUntilVisible(find.text('Plan'), -100, scrollable: list);
    await tester.ensureVisible(find.text('Plan'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Plan'));
    expect(jumps.last, (AppTab.training, null));
    await tester.scrollUntilVisible(find.textContaining('offen'), -100, scrollable: list);
    await tester.ensureVisible(find.textContaining('offen'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('offen'));
    expect(jumps.last, (AppTab.plan, PlanSection.todos));
    await disposeApp(tester, db);
  });

  testWidgets('Home orders its sections by daily use: habits, food, training, to-dos, then the rest', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await HabitRepository(db: db).createHabit(Habit(name: 'Meditieren', userid: u.uid));
      await TodoRepository(db: db).createTodo(Todo(title: 'Steuer', dueDate: now, userid: u.uid));
      await AppointmentRepository(db: db).createAppointment(
          Appointment(title: 'Friseur', date: DateTime(now.year, now.month, now.day, 23, 30), userid: u.uid));
      await WorkoutRepository(db: db).saveWorkout(Workout(userid: u.uid, name: 'Beine', repeatWeekdays: [now.weekday]));
      final inventory = InventoryRepository(db: db);
      await inventory.createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Joghurt', expiryDate: today));
      final meals = MealPlanRepository(db: db, lists: ListsRepository(db: db, inventory: inventory), inventory: inventory);
      await meals.planBatch(uid: u.uid, recipe: catalogRecipe('rote-linsen-dal')!, cookDate: today, slots: [PortionSlot(today, Meal.lunch, 1)]);
      return u;
    });
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Training heute'));

    double y(String title) => tester.getTopLeft(find.text(title).last).dy; // „To-Dos“ steht auch im Tages-Score
    final order = ['Habits heute', 'Essen heute', 'Training heute', 'To-Dos', 'Als Nächstes', 'Läuft bald ab', 'Journal', 'Vision Board'];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i - 1]) < y(order[i]), isTrue, reason: '${order[i - 1]} vor ${order[i]}');
    }
    await disposeApp(tester, db);
  });
}
