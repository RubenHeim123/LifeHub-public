import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/screens/calendar_screen.dart';
import 'package:frontend/features/calendar/services/calendar_sync.dart';
import 'package:frontend/features/calendar/widgets/external_event_card.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/profile/widgets/calendar_sync_card.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const google = DeviceCalendar(id: 'g1', name: 'privat', account: 'max@example.com', color: 0xFF3366CC, writable: true);
  const birthdays = DeviceCalendar(id: 'g2', name: 'Geburtstage', account: 'max@example.com', color: 0xFFCC3366);

  group('rules', () {
    test('repeat rules become iCalendar rules', () {
      final fri = DateTime(2026, 10, 23, 18);
      expect(CalendarSync.rruleFor(Repeat.none, fri), isNull);
      expect(CalendarSync.rruleFor(const Repeat(RepeatFreq.daily, interval: 2), fri), 'FREQ=DAILY;INTERVAL=2');
      expect(CalendarSync.rruleFor(const Repeat(RepeatFreq.weekly), fri), 'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR');
      expect(CalendarSync.rruleFor(const Repeat(RepeatFreq.weekly, interval: 2, weekdays: {5, 1}), fri), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR');
      expect(CalendarSync.rruleFor(const Repeat(RepeatFreq.monthly), fri), 'FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=23');
      expect(CalendarSync.rruleFor(Repeat.yearly, fri), 'FREQ=YEARLY;INTERVAL=1');
    });

    test('an appointment becomes a phone event: duration, all-day = whole day', () {
      final timed = CalendarSync.draftFor(Appointment(title: 'Arzt', date: DateTime(2026, 10, 23, 9, 30), durationMinutes: 45, userid: 1));
      expect((timed.start, timed.end, timed.allDay, timed.rrule), (DateTime(2026, 10, 23, 9, 30), DateTime(2026, 10, 23, 10, 15), false, null));
      final birthday = CalendarSync.draftFor(Appointment(title: 'Lena', date: DateTime(1990, 10, 25), allDay: true, repeatYearly: true, userid: 1));
      expect((birthday.start, birthday.end, birthday.allDay, birthday.rrule), (DateTime(1990, 10, 25), DateTime(1990, 10, 26), true, 'FREQ=YEARLY;INTERVAL=1'));
    });

    test('multi-day phone events show on every day; all-day events end the day before', () {
      final grouped = groupExternalByDay([
        ExternalEvent(eventId: '1', title: 'Urlaub', start: DateTime(2026, 10, 23), end: DateTime(2026, 10, 26), allDay: true, calendarId: 'g1'),
        ExternalEvent(eventId: '2', title: 'Kino', start: DateTime(2026, 10, 23, 20), end: DateTime(2026, 10, 23, 22), calendarId: 'g1'),
      ]);
      expect(grouped.keys, [DateTime(2026, 10, 23), DateTime(2026, 10, 24), DateTime(2026, 10, 25)]);
      expect(grouped[DateTime(2026, 10, 23)]!.map((e) => e.title), ['Urlaub', 'Kino']);
    });
  });

  group('LifeHub → phone', () {
    test('create, change, delete and restore are mirrored into the own calendar', () async {
      final db = createTestDatabase();
      final user = await createTestUser(db);
      final device = FakeDeviceCalendar(calendars: [google]);
      final sync = CalendarSync(device: device);
      final repo = AppointmentRepository(db: db, calendarSync: sync, notifications: RecordingNotifications());

      // Ausgeschaltet: nichts landet im Handy
      final early = await repo.createAppointment(Appointment(title: 'Vorher', date: DateTime(2026, 10, 22, 8), userid: user.uid));
      expect(device.written, isEmpty);

      final calId = (await sync.enableWrite(user.uid))!;
      expect(device.calendarList.map((c) => c.name), ['privat', 'LifeHub']);
      expect(await repo.mirrorAll(user.uid), 1);
      expect(device.written.values.single.$2.title, 'Vorher');

      final id = await repo.createAppointment(Appointment(
          title: 'Training', date: DateTime(2026, 10, 23, 18), repeat: const Repeat(RepeatFreq.weekly), userid: user.uid));
      final eventId = device.written.entries.firstWhere((e) => e.value.$2.title == 'Training').key;
      expect(device.written[eventId]!.$1, calId);
      expect(device.written[eventId]!.$2.rrule, 'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR');

      final a = await repo.getAppointment(id);
      await repo.updateAppointment(Appointment(id: id, title: 'Training (Park)', date: a.date, repeat: a.repeat, userid: user.uid));
      expect(device.written[eventId]!.$2.title, 'Training (Park)'); // gleicher Termin, nicht doppelt
      expect(device.written, hasLength(2));

      await repo.deleteAppointment(id);
      expect(device.deleted, [eventId]);
      await repo.restoreAppointment(await repo.getAppointment(id));
      expect(device.written.values.map((v) => v.$2.title), containsAll(['Vorher', 'Training (Park)']));

      // Ausschalten: Kalender „LifeHub“ weg, Verknüpfungen vergessen
      await sync.disableWrite(user.uid);
      await repo.forgetDeviceLinks(user.uid);
      expect(device.deletedCalendars, [calId]);
      expect(device.written, isEmpty);
      expect(await (await db.database).query('device_calendar_links'), isEmpty);
      await repo.updateAppointment(await repo.getAppointment(early));
      expect(device.written, isEmpty);
      await db.close();
    });

    test('a broken phone calendar never blocks saving in LifeHub', () async {
      final db = createTestDatabase();
      final user = await createTestUser(db);
      final device = FakeDeviceCalendar(failWrites: true);
      final sync = CalendarSync(device: device);
      await sync.enableWrite(user.uid);
      final repo = AppointmentRepository(db: db, calendarSync: sync, notifications: RecordingNotifications());
      await repo.createAppointment(Appointment(title: 'Zahnarzt', date: DateTime(2026, 10, 30, 9), userid: user.uid));
      expect((await repo.getAllAppointments(user.uid)).single.title, 'Zahnarzt');
      await db.close();
    });

    test('without calendar access writing cannot be switched on', () async {
      final sync = CalendarSync(device: FakeDeviceCalendar(access: false));
      expect(await sync.enableWrite(1), isNull);
      expect((await sync.settings(1)).write, isFalse);
    });
  });

  group('phone → LifeHub', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    List<ExternalEvent> events() => [
          ExternalEvent(
              eventId: 'e1',
              title: 'Kino mit Lena',
              start: today.add(const Duration(hours: 23)),
              end: today.add(const Duration(hours: 23, minutes: 50)),
              location: 'Cinemaxx',
              calendarId: 'g1',
              calendarName: 'privat',
              color: 0xFF3366CC),
          ExternalEvent(
              eventId: 'e2', title: 'Omas Geburtstag', start: today, end: today.add(const Duration(days: 1)), allDay: true, calendarId: 'g2', calendarName: 'Geburtstage'),
        ];

    test('only chosen calendars are read, never the own LifeHub calendar', () async {
      final device = FakeDeviceCalendar(calendars: [google, birthdays], events: events());
      final sync = CalendarSync(device: device);
      expect(await sync.events(1, today, today.add(const Duration(days: 2))), isEmpty); // aus
      await sync.saveRead(1, read: true, calendarIds: {'g1'});
      expect((await sync.events(1, today, today.add(const Duration(days: 2)))).map((e) => e.title), ['Kino mit Lena']);
      final own = (await sync.enableWrite(1))!;
      await sync.saveRead(1, read: true, calendarIds: {'g1', own});
      device.events.add(ExternalEvent(eventId: 'x', title: 'Gespiegelt', start: today, end: today.add(const Duration(hours: 1)), calendarId: own));
      expect((await sync.events(1, today, today.add(const Duration(days: 2)))).map((e) => e.title), ['Kino mit Lena']);
      expect((await sync.selectableCalendars(1)).map((c) => c.name), ['privat', 'Geburtstage']);
    });

    testWidgets('the calendar shows phone events in their colour, read-only', (tester) async {
      useTallScreen(tester);
      final db = createTestDatabase();
      final user = await seedDb(tester, db, () async {
        final u = await createTestUser(db);
        await AppointmentRepository(db: db, notifications: RecordingNotifications())
            .createAppointment(Appointment(title: 'Zahnarzt', date: today.add(const Duration(hours: 22)), userid: u.uid));
        await CalendarSync().saveRead(u.uid, read: true, calendarIds: {'g1', 'g2'});
        return u;
      });
      final device = FakeDeviceCalendar(calendars: [google, birthdays], events: events());
      await tester.pumpWidget(testApp(db, CalendarScreen(user: user), deviceCalendar: device));
      await pumpUntil(tester, find.text('Kino mit Lena'));
      expect(find.text('3 Termine'), findsOneWidget);
      // Reihenfolge: ganztägig, 22 Uhr (LifeHub), 23 Uhr (Handy)
      final y = [for (final t in ['Omas Geburtstag', 'Zahnarzt', 'Kino mit Lena']) tester.getTopLeft(find.text(t)).dy];
      expect(y, orderedEquals([...y]..sort()));
      expect(find.text('privat · Cinemaxx'), findsOneWidget);

      await tester.tap(find.text('Kino mit Lena'));
      await pumpUntil(tester, find.textContaining('ändern kannst du ihn dort'));
      await disposeApp(tester, db);
    });

    testWidgets('"Als Nächstes" on Today mixes LifeHub and phone events', (tester) async {
      useTallScreen(tester);
      final db = createTestDatabase();
      final user = await seedDb(tester, db, () async {
        final u = await createTestUser(db);
        await CalendarSync().saveRead(u.uid, read: true, calendarIds: {'g1'});
        return u;
      });
      // Morgen statt heute 23 Uhr – sonst schlägt der Test kurz vor Mitternacht fehl
      final tomorrow = today.add(const Duration(days: 1, hours: 19));
      final device = FakeDeviceCalendar(calendars: [google], events: [
        ExternalEvent(eventId: 'e1', title: 'Kino mit Lena', start: tomorrow, end: tomorrow.add(const Duration(hours: 2)), calendarId: 'g1', calendarName: 'privat'),
      ]);
      await tester.pumpWidget(testApp(db, Home(user: user), deviceCalendar: device));
      await pumpUntil(tester, find.text('Kino mit Lena'));
      expect(find.text('Als Nächstes'), findsOneWidget);
      expect(find.text('privat'), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  testWidgets('profile card: switch on reading, choose calendars, write into "LifeHub"', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await AppointmentRepository(db: db, notifications: RecordingNotifications())
          .createAppointment(Appointment(title: 'Zahnarzt', date: DateTime(2026, 11, 2, 9), userid: u.uid));
      return u;
    });
    final device = FakeDeviceCalendar(calendars: [google, birthdays]);
    await tester.pumpWidget(testApp(db, Scaffold(body: SingleChildScrollView(child: CalendarSyncCard(userid: user.uid))), deviceCalendar: device));
    await pumpUntil(tester, find.text('Handy-Termine anzeigen'));

    await tester.tap(find.text('Handy-Termine anzeigen'));
    await pumpUntil(tester, find.text('privat · max@example.com'));
    expect(find.text('Geburtstage · max@example.com'), findsOneWidget);
    expect((await CalendarSync().settings(user.uid)).calendarIds, {'g1', 'g2'}); // anfangs alle

    await tester.tap(find.text('Geburtstage · max@example.com'));
    await pumpUntil(tester, find.byWidgetPredicate((w) => w is CheckboxListTile && w.value == false));
    expect((await CalendarSync().settings(user.uid)).calendarIds, {'g1'});

    await tester.tap(find.text('LifeHub-Termine ins Handy schreiben'));
    await pumpUntil(tester, find.textContaining('1 Termin im Handy-Kalender „LifeHub“'));
    expect(device.written.values.single.$2.title, 'Zahnarzt');
    expect(find.text('LifeHub'), findsNothing); // der eigene Kalender steht nicht zur Auswahl
    await disposeApp(tester, db);
  });

  testWidgets('profile card: without permission a hint explains where to allow it', (tester) async {
    useTallScreen(tester);
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, Scaffold(body: SingleChildScrollView(child: CalendarSyncCard(userid: user.uid))),
        deviceCalendar: FakeDeviceCalendar(access: false)));
    await pumpUntil(tester, find.text('Handy-Termine anzeigen'));
    await tester.tap(find.text('Handy-Termine anzeigen'));
    await pumpUntil(tester, find.textContaining('Ohne Zugriff auf den Kalender'));
    expect((await CalendarSync().settings(user.uid)).read, isFalse);
    await disposeApp(tester, db);
  });
}
