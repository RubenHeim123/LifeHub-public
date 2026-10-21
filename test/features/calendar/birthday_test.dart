import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/repeat.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/calendar/screens/calendar_screen.dart';
import 'package:frontend/features/dashboard/screens/home.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  Appointment birthday(DateTime date, {int? reminder = 0}) => Appointment(
        title: 'Geburtstag Lena',
        date: date,
        userid: 1,
        allDay: true,
        repeatYearly: true,
        reminderMinutes: reminder,
      );

  group('model', () {
    test('yearly entries occur every year from the first one on', () {
      final b = birthday(DateTime(1990, 3, 12));
      expect(b.occurrenceOn(DateTime(2026, 3, 12)), DateTime(2026, 3, 12));
      expect(b.occurrenceOn(DateTime(2026, 3, 13)), isNull);
      expect(b.occurrenceOn(DateTime(1989, 3, 12)), isNull);
      expect(b.yearsAt(DateTime(2026, 3, 12)), 36);
      expect(b.occurrencesBetween(DateTime(2025, 1, 1), DateTime(2027, 12, 31)),
          [DateTime(2025, 3, 12), DateTime(2026, 3, 12), DateTime(2027, 3, 12)]);

      // Nächstes Vorkommen: am Tag selbst noch „heute“, danach das Folgejahr
      expect(b.nextOccurrence(DateTime(2026, 3, 12, 20)), DateTime(2026, 3, 12));
      expect(b.nextOccurrence(DateTime(2026, 3, 13)), DateTime(2027, 3, 12));
    });

    test('29 February falls on 28 February in other years', () {
      final b = birthday(DateTime(2000, 2, 29));
      expect(b.occurrenceOn(DateTime(2026, 2, 28)), DateTime(2026, 2, 28));
      expect(b.occurrenceOn(DateTime(2028, 2, 29)), DateTime(2028, 2, 29));
    });

    test('all-day reminders fire at 9 o\'clock, rolling over to next year', () {
      final b = birthday(DateTime(1990, 3, 12));
      expect(b.reminderFor(DateTime(2026, 3, 1)), DateTime(2026, 3, 12, 9));
      expect(b.reminderFor(DateTime(2026, 3, 12, 10)), DateTime(2027, 3, 12, 9)); // heute schon erinnert
      expect(birthday(DateTime(1990, 3, 12), reminder: 1440).reminderFor(DateTime(2026, 3, 1)), DateTime(2026, 3, 11, 9));
      expect(Appointment.reminderLabel(0, allDay: true), 'Am Tag (9 Uhr)');

      // Einmalige ganztägige Notiz: gilt den ganzen Tag, danach nicht mehr
      final note = Appointment(title: 'Paket abholen', date: DateTime(2026, 5, 4), userid: 1, allDay: true);
      expect(note.endDate, DateTime(2026, 5, 4, 23, 59, 59));
      expect(note.occurrenceOn(DateTime(2027, 5, 4)), isNull);
    });
  });

  test('weekly appointments every 2 weeks: occurrences and next reminder', () {
    final sport = Appointment(
      title: 'Lauftreff',
      date: DateTime(2026, 10, 6, 18), // Dienstag
      userid: 1,
      reminderMinutes: 30,
      repeat: const Repeat(RepeatFreq.weekly, interval: 2),
    );
    expect(sport.occurrencesBetween(DateTime(2026, 10, 1), DateTime(2026, 11, 10)),
        [DateTime(2026, 10, 6, 18), DateTime(2026, 10, 20, 18), DateTime(2026, 11, 3, 18)]);
    expect(sport.occurrenceOn(DateTime(2026, 10, 13)), isNull);
    expect(sport.nextOccurrence(DateTime(2026, 10, 6, 20)), DateTime(2026, 10, 20, 18)); // vorbei → nächstes
    expect(sport.reminderFor(DateTime(2026, 10, 6, 17, 45)), DateTime(2026, 10, 20, 17, 30));
    expect(sport.yearsAt(DateTime(2027, 10, 5)), isNull);
    expect(Appointment.fromMap(sport.toMap()).repeat, sport.repeat);
  });

  test('repository plans the birthday reminder with the age and refreshes it', () async {
    final db = createTestDatabase();
    final notifications = RecordingNotifications();
    var now = DateTime(2026, 3, 1, 12);
    final repo = AppointmentRepository(db: db, notifications: notifications, clock: () => now);
    final user = await createTestUser(db);

    await repo.createAppointment(Appointment(
      title: 'Geburtstag Lena',
      date: DateTime(1990, 3, 12),
      userid: user.uid,
      allDay: true,
      repeatYearly: true,
      reminderMinutes: 0,
    ));
    final saved = (await repo.getAllAppointments(user.uid)).single;
    expect(saved.allDay, isTrue);
    expect(saved.repeatYearly, isTrue);
    final (title, body, at) = notifications.scheduled[saved.id]!;
    expect(title, 'Geburtstag Lena');
    expect(body, 'Heute · 36 Jahre');
    expect(at, DateTime(2026, 3, 12, 9));

    // Ein Jahr später: beim App-Start wird das nächste Jahr geplant
    now = DateTime(2026, 3, 20);
    await repo.refreshReminders(user.uid);
    expect(notifications.scheduled[saved.id]!.$3, DateTime(2027, 3, 12, 9));
    expect(notifications.scheduled[saved.id]!.$2, 'Heute · 37 Jahre');
    await db.close();
  });

  testWidgets('editor: birthday preset makes an all-day yearly entry, even with a past date', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, launcher(AddUpdateAppointmentScreen(userid: user.uid))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Als Geburtstag'));

    await enterInCard(tester, 'Titel', 'Geburtstag Lena');
    await tester.tap(find.text('Als Geburtstag'));
    await tester.pump();
    expect(find.byIcon(Icons.access_time), findsNothing); // keine Uhrzeit
    expect(find.text('DAUER'), findsNothing);
    expect(find.text('Am Tag (9 Uhr)'), findsWidgets);

    // Geburtsdatum in der Vergangenheit per Texteingabe im Datumsdialog
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await pumpUntil(tester, find.byIcon(Icons.edit_outlined));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.enterText(find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextField)), '12.03.1990'); // deutsches Format
    await tester.tap(find.text('OK'));
    await pumpUntilGone(tester, find.byType(DatePickerDialog));
    expect(find.text('12.03.1990'), findsOneWidget);

    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.textContaining('result:'));

    final saved = (await readDb(tester, () => AppointmentRepository(db: db).getAllAppointments(user.uid))).single;
    expect(saved.allDay, isTrue);
    expect(saved.repeatYearly, isTrue);
    expect(saved.date, DateTime(1990, 3, 12));
    expect(saved.reminderMinutes, 0);
    await disposeApp(tester, db);
  });

  testWidgets('calendar and home show the birthday every year with the age', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final now = DateTime.now();
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await AppointmentRepository(db: db).createAppointment(Appointment(
        title: 'Geburtstag Lena',
        date: DateTime(now.year - 30, now.month, now.day),
        userid: u.uid,
        allDay: true,
        repeatYearly: true,
        reminderMinutes: 0,
      ));
      return u;
    });

    await tester.pumpWidget(testApp(db, CalendarScreen(user: user)));
    await pumpUntil(tester, find.text('Geburtstag Lena'));
    expect(find.text('Jährlich · 30 Jahre'), findsOneWidget);
    expect(find.text('Ganztägig'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Geburtstag Lena'));
    expect(find.text('30 Jahre'), findsOneWidget);
    expect(find.text('HEUTE'), findsOneWidget);
    await disposeApp(tester, db);
  });
}
