import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/todo_list_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  testWidgets('+ opens the full form; the new todo is due today and the box completes it', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () => createTestUser(db));

    await tester.pumpWidget(testApp(db, TodoListScreen(user: user)));
    await pumpUntil(tester, find.text('0 offen'));
    expect(find.byType(TextField), findsNothing); // keine Schnellleiste mehr

    await tester.tap(find.text('Aufgabe'));
    await pumpUntil(tester, find.text('Neue Aufgabe'));
    for (final label in ['Titel', 'Beschreibung', 'Fällig am', 'Uhrzeit (Erinnerung)', 'Wiederholung']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await enterInCard(tester, 'Titel', 'Müll rausbringen');
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntilGone(tester, find.text('Neue Aufgabe'));
    await pumpUntil(tester, find.text('Müll rausbringen'));
    expect(find.text('Heute'), findsWidgets);

    await tester.tap(find.byType(AppCheck).first);
    await pumpUntilTrue(tester, () async => (await TodoRepository(db: db).getAllTodos(user.uid)).single.isCompleted);
    final todos = await readDb(tester, () => TodoRepository(db: db).getAllTodos(user.uid));
    expect(todos.single.dueDate, today());
    await disposeApp(tester, db);
  });

  testWidgets('a weekly todo on another day: next one appears after checking it off', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, TodoListScreen(user: user)));
    await pumpUntil(tester, find.text('0 offen'));

    await tester.tap(find.text('Aufgabe'));
    await pumpUntil(tester, find.text('Neue Aufgabe'));
    await enterInCard(tester, 'Titel', 'Putzen');
    await tester.tap(find.text('Wöchentlich'));
    await tester.pump();
    expect(find.textContaining('Wöchentlich ('), findsOneWidget);
    await tester.tap(find.byTooltip('Längerer Abstand')); // alle 2 Wochen
    await tester.pump();
    expect(find.textContaining('Alle 2 Wochen'), findsOneWidget);
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntilGone(tester, find.text('Neue Aufgabe'));
    await pumpUntil(tester, find.text('Putzen'));
    expect(find.textContaining('Alle 2 Wochen'), findsOneWidget);

    await tester.tap(find.byType(AppCheck).first);
    await pumpUntil(tester, find.textContaining('Nächstes Mal'));
    final todos = await readDb(tester, () => TodoRepository(db: db).getAllTodos(user.uid));
    expect(todos.map((t) => (t.dueDate, t.isCompleted)), [(today(), true), (addDays(today(), 14), false)]); // Kalendertage: über die Zeitumstellung hinweg
    await disposeApp(tester, db);
  });

  testWidgets('swipe: edit opens the form, delete offers undo', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await TodoRepository(db: db).createTodo(Todo(
        title: 'Steuererklärung',
        userid: u.uid,
        dueDate: DateTime(2030, 5, 31),
        repeat: Repeat.yearly,
      ));
      return u;
    });
    await tester.pumpWidget(testApp(db, TodoListScreen(user: user)));
    await pumpUntil(tester, find.text('Steuererklärung'));
    expect(find.text('Jährlich'), findsOneWidget);

    await tester.drag(find.text('Steuererklärung'), const Offset(-400, 0));
    await pumpUntil(tester, find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('„Steuererklärung“ gelöscht'));
    expect(await readDb(tester, () => TodoRepository(db: db).getAllTodos(user.uid)), isEmpty);
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Steuererklärung'));

    await tester.tap(find.text('Steuererklärung'));
    await pumpUntil(tester, find.text('Aufgabe bearbeiten'));
    expect(find.text('31.05.2030'), findsOneWidget);
    expect(find.text('Erledigt'), findsOneWidget);
    await disposeApp(tester, db);
  });
}
