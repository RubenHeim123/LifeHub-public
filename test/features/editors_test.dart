import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/features/finance/repositories/financial_goal_repository.dart';
import 'package:frontend/features/finance/screens/add_update_financial_goal.dart';
import 'package:frontend/features/finance/screens/financial_goals_view.dart';
import 'package:frontend/features/finance/screens/sync_hub_screen.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/habits/screens/add_habit_screen.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';

import '../helpers/test_app.dart';

/// Anlege-Formulare und kleinere Screens aller Features: speichern landet in der DB.
void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  Future<void> open(WidgetTester tester, Widget page, Finder ready) async {
    useTallScreen(tester);
    await tester.pumpWidget(testApp(db, launcher(page)));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, ready);
  }

  testWidgets('AddUpdateTodoScreen saves a todo', (tester) async {
    final user = await seedDb(tester, db, () => createTestUser(db));
    await open(tester, AddUpdateTodoScreen(userid: user.uid), find.text('Neue Aufgabe'));

    await enterInCard(tester, 'Titel', 'Arzt anrufen');
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('result:true'));

    final todos = (await readDb(tester, () => TodoRepository(db: db).getAllTodos(user.uid)));
    expect(todos.single.title, 'Arzt anrufen');
    await disposeApp(tester, db);
  });

  testWidgets('AddHabitScreen saves a habit', (tester) async {
    final user = await seedDb(tester, db, () => createTestUser(db));
    await open(tester, AddHabitScreen(userid: user.uid), find.text('Wochentags'));

    await enterInCard(tester, 'Name', 'Joggen');
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.textContaining('result:'));

    final habits = (await readDb(tester, () => HabitRepository(db: db).getAllHabits(user.uid)));
    expect(habits.single.name, 'Joggen');
    await disposeApp(tester, db);
  });

  testWidgets('AddUpdateAppointmentScreen saves an appointment', (tester) async {
    final user = await seedDb(tester, db, () => createTestUser(db));
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await open(
      tester,
      AddUpdateAppointmentScreen(userid: user.uid, initialDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day)),
      find.text('Als Geburtstag'),
    );

    await enterInCard(tester, 'Titel', 'Elternabend');
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.textContaining('result:'));

    final appointments = (await readDb(tester, () => AppointmentRepository(db: db).getAllAppointments(user.uid)));
    expect(appointments.single.title, 'Elternabend');
    expect(appointments.single.reminderMinutes, 15);
    await disposeApp(tester, db);
  });

  testWidgets('FinancialGoalsView shows goal progress from linked accounts', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await createTestAccount(db, user.uid, 'Sparkonto', amount: 250);
      await FinancialGoalRepository(db: db).createGoal(FinancialGoal(
        name: 'Neues Fahrrad',
        targetAmount: 1000,
        selectedAccountNames: 'Sparkonto',
        colorHex: '#3498db',
        userid: user.uid,
      ));
      return user;
    });

    await tester.pumpWidget(testApp(db, FinancialGoalsView(user: user)));
    await pumpUntil(tester, find.text('Neues Fahrrad'));

    expect(find.text('250,00 €'), findsOneWidget);
    expect(find.text('25 %'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('AddUpdateFinancialGoal rejects 0 €, accepts a comma amount and links an account', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await createTestAccount(db, user.uid, 'Sparkonto', amount: 100);
      return user;
    });
    await open(tester, AddUpdateFinancialGoal(user: user), find.text('Sparkonto'));

    await enterInCard(tester, 'Name', 'Urlaub');
    await enterInCard(tester, 'Zielbetrag (€)', '0');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pump();
    expect(find.text('Das Ziel muss größer als 0 € sein'), findsOneWidget);

    await enterInCard(tester, 'Zielbetrag (€)', '1500,50');
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Bitte wähle mindestens ein Konto aus.'));
    await tester.tap(find.text('Sparkonto'));
    await tester.pump();
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.textContaining('result:'));

    final goal = (await readDb(tester, () => FinancialGoalRepository(db: db).getAllGoals(user.uid))).single;
    expect((goal.name, goal.targetAmount), ('Urlaub', 1500.5));
    expect(goal.accountNames, ['Sparkonto']);
    await disposeApp(tester, db);
  });

  testWidgets('FinancialGoalsView: deleting in the editor removes the goal with undo', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await FinancialGoalRepository(db: db).createGoal(FinancialGoal(
        name: 'Auto',
        targetAmount: 5000,
        selectedAccountNames: '',
        colorHex: 'kaputt', // alte/fehlerhafte Farbe darf nicht abstürzen
        deadline: '31.12.2027',
        userid: user.uid,
      ));
      return user;
    });
    await tester.pumpWidget(testApp(db, FinancialGoalsView(user: user)));
    await pumpUntil(tester, find.text('Auto'));
    await tester.tap(find.text('Auto'));
    await pumpUntil(tester, find.text('Löschen')); // Konten werden noch geladen
    await tester.ensureVisible(find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Noch keine Sparziele'));
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Auto'));
    expect(await readDb(tester, () => FinancialGoalRepository(db: db).getAllGoals(user.uid)), hasLength(1));
    await disposeApp(tester, db);
  });

  testWidgets('SyncHubScreen opens the backups and asks for the PC address before syncing', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, SyncHubScreen(user: user)));
    await pumpUntil(tester, find.text('Sicherungen & Wiederherstellen'));

    await tester.tap(find.text('Sicherungen & Wiederherstellen'));
    await pumpUntil(tester, find.text('Noch keine Sicherungen'));
    await pageBack(tester);
    await pumpUntil(tester, find.byTooltip('Jetzt synchronisieren').hitTestable());
    await tester.tap(find.byTooltip('Jetzt synchronisieren'));
    await pumpUntil(tester, find.text('Bitte die IP-Adresse deines PCs eingeben.'));
    await disposeApp(tester, db);
  });

  testWidgets('AddUpdateAppointmentScreen lets you choose the reminder', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await open(
      tester,
      AddUpdateAppointmentScreen(userid: user.uid, initialDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day)),
      find.text('Als Geburtstag'),
    );
    expect(find.text('ERINNERUNG'), findsOneWidget);
    await enterInCard(tester, 'Titel', 'Friseur');
    await tester.ensureVisible(find.text('30 min vorher'));
    await tester.tap(find.text('30 min vorher'));
    await tester.pump();
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.textContaining('result:'));

    final saved = (await readDb(tester, () => AppointmentRepository(db: db).getAllAppointments(user.uid))).single;
    expect(saved.reminderMinutes, 30);
    await disposeApp(tester, db);
  });
}
