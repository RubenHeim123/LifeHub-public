import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/screens/calendar_screen.dart';
import 'package:frontend/features/dashboard/widgets/global_search_delegate.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('CalendarScreen shows today\'s appointments from the database', (tester) async {
    final db = createTestDatabase();
    final now = DateTime.now();
    final user = (await tester.runAsync(() async {
      final user = await createTestUser(db);
      final repo = AppointmentRepository(db: db);
      await repo.createAppointment(Appointment(
        title: 'Zahnarzttermin',
        description: 'Jährliche Kontrolle',
        date: DateTime(now.year, now.month, now.day, 23, 0),
        userid: user.uid,
      ));
      return user;
    }))!;

    await tester.pumpWidget(testApp(db, CalendarScreen(user: user)));
    await pumpUntil(tester, find.text('Zahnarzttermin'));

    expect(find.text('Zahnarzttermin'), findsOneWidget);
    expect(find.text('Jährliche Kontrolle'), findsOneWidget);

    await disposeApp(tester, db);
  });

  Future<(DatabaseService, UserModel)> seedOne(WidgetTester tester) async {
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final now = DateTime.now();
      await AppointmentRepository(db: db).createAppointment(Appointment(
        title: 'Zahnarzttermin',
        date: DateTime(now.year, now.month, now.day),
        allDay: true,
        userid: user.uid,
      ));
      return user;
    });
    return (db, user);
  }

  Future<List<Appointment>> stored(WidgetTester tester, DatabaseService db, UserModel user) =>
      readDb(tester, () => AppointmentRepository(db: db).getAllAppointments(user.uid));

  testWidgets('an appointment found by the search can be deleted in its editor and restored', (tester) async {
    useTallScreen(tester);
    final (db, user) = await seedOne(tester);
    await tester.pumpWidget(testApp(
      db,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSearch(context: context, delegate: GlobalSearchDelegate(userId: user.uid, db: db)),
            child: const Text('suchen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zahnarzt');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(tester, find.text('Zahnarzttermin'));
    await tester.tap(find.text('Zahnarzttermin'));
    await pumpUntil(tester, find.text('Termin bearbeiten'));
    await tester.ensureVisible(find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('Rückgängig'));
    expect(await stored(tester, db, user), isEmpty);

    await tester.tap(find.text('Rückgängig'));
    await pumpUntilGone(tester, find.text('Rückgängig'));
    await tester.pump(const Duration(milliseconds: 300));
    expect((await stored(tester, db, user)).single.title, 'Zahnarzttermin');
    await disposeApp(tester, db);
  });

  testWidgets('deleting from the editor in the calendar removes the entry with undo', (tester) async {
    useTallScreen(tester);
    final (db, user) = await seedOne(tester);
    await tester.pumpWidget(testApp(db, CalendarScreen(user: user)));
    await pumpUntil(tester, find.text('Zahnarzttermin'));
    await tester.tap(find.text('Zahnarzttermin'));
    await pumpUntil(tester, find.text('Termin bearbeiten'));
    await tester.ensureVisible(find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('Rückgängig'));
    await pumpUntilGone(tester, find.text('Zahnarzttermin'));
    expect(await stored(tester, db, user), isEmpty);
    await disposeApp(tester, db);
  });
}
