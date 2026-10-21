import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late RecordingNotifications notifications;
  late AppointmentRepository appointments;
  late ContactRepository repo;
  late int uid;
  var now = DateTime(2026, 10, 20, 8); // Dienstag, vor 9 Uhr

  setUp(() async {
    now = DateTime(2026, 10, 20, 8);
    db = createTestDatabase();
    notifications = RecordingNotifications();
    appointments = AppointmentRepository(db: db, notifications: notifications, clock: () => now);
    repo = ContactRepository(db: db, appointments: appointments, notifications: notifications, clock: () => now);
    uid = (await createTestUser(db)).uid;
  });
  tearDown(() => db.close());

  int noteId(ContactNote n) => NotificationService.contactIdOffset + 2 * n.id!;

  test('contact model: initials, next birthday, age, 29 February', () {
    final lena = Contact(userid: 1, name: 'Lena Marie Müller', birthday: DateTime(1990, 10, 25));
    expect(lena.initials, 'LM');
    expect(const Contact(userid: 1, name: 'ömer').initials, 'Ö');
    expect(lena.nextBirthday(now), DateTime(2026, 10, 25));
    expect((lena.daysUntilBirthday(now), lena.ageAtNextBirthday(now)), (5, 36));
    expect(Contact(userid: 1, name: 'A', birthday: DateTime(1990, 10, 20)).daysUntilBirthday(now), 0);
    expect(Contact(userid: 1, name: 'A', birthday: DateTime(1990, 1, 2)).nextBirthday(now), DateTime(2027, 1, 2));
    expect(Contact(userid: 1, name: 'A', birthday: DateTime(2000, 2, 29)).nextBirthday(now), DateTime(2027, 2, 28));
  });

  test('a birthday creates a yearly all-day appointment, moves it, removes it; delete and undo take it along', () async {
    await expectLater(repo.saveContact(const Contact(userid: 0, name: ' ')), throwsA(isA<UserFacingException>()));
    final id = await repo.saveContact(Contact(userid: uid, name: 'Lena', relation: 'Freundin', birthday: DateTime(1990, 10, 25)));
    var lena = (await repo.getContact(id))!;
    expect(lena.appointmentId, isNotNull);
    var appt = await appointments.getAppointment(lena.appointmentId!);
    expect((appt.title, appt.allDay, appt.repeat.freq, appt.reminderMinutes), ('Geburtstag: Lena', true, RepeatFreq.yearly, 0));
    expect(notifications.scheduled[appt.id]!.$3, DateTime(2026, 10, 25, 9));

    await repo.saveContact(Contact(id: id, userid: uid, name: 'Lena M.', birthday: DateTime(1990, 11, 2), appointmentId: lena.appointmentId));
    appt = await appointments.getAppointment(lena.appointmentId!);
    expect((appt.title, appt.date), ('Geburtstag: Lena M.', DateTime(1990, 11, 2)));
    expect(await appointments.getAllAppointments(uid), hasLength(1));

    final at = await repo.deleteContact(id);
    expect(await repo.getContacts(uid), isEmpty);
    expect(await appointments.getAllAppointments(uid), isEmpty);
    await repo.restoreContact(id, at);
    expect((await repo.getContacts(uid)).single.name, 'Lena M.');
    expect(await appointments.getAllAppointments(uid), hasLength(1));

    lena = (await repo.getContact(id))!;
    await repo.saveContact(Contact(id: id, userid: uid, name: 'Lena M.', appointmentId: lena.appointmentId));
    expect(await appointments.getAllAppointments(uid), isEmpty);
    expect((await repo.getContact(id))!.appointmentId, isNull);
  });

  test('dated notes remind at 9 on the day and the day after; done cancels, undone plans again', () async {
    final id = await repo.saveContact(Contact(userid: uid, name: 'Lena'));
    final note = await repo.saveNote(ContactNote(userid: uid, contactId: id, text: 'Arzttermin', date: DateTime(2026, 10, 28), followUp: true, created: now));
    expect(notifications.scheduled[noteId(note)], ('Lena: Arzttermin', 'Heute', DateTime(2026, 10, 28, 9)));
    expect(notifications.scheduled[noteId(note) + 1]!.$1, 'Bei Lena nachfragen');
    expect(notifications.scheduled[noteId(note) + 1]!.$3, DateTime(2026, 10, 29, 9));

    final done = await repo.setNoteDone(note, true);
    expect(notifications.scheduled.containsKey(noteId(note)), isFalse);
    expect(notifications.scheduled.containsKey(noteId(note) + 1), isFalse);
    await repo.setNoteDone(done, false);
    expect(notifications.scheduled.containsKey(noteId(note)), isTrue);

    // Notizen ohne Datum oder in der Vergangenheit planen nichts
    await repo.saveNote(ContactNote(userid: uid, contactId: id, text: 'mag keine Oliven', created: now));
    final past = await repo.saveNote(ContactNote(userid: uid, contactId: id, text: 'Umzug', date: DateTime(2026, 10, 1), created: now));
    expect(notifications.scheduled.containsKey(noteId(past)), isFalse);
    expect(notifications.scheduled.keys.where((k) => k >= NotificationService.contactIdOffset), hasLength(2));

    // Nach dem Abmelden (alles weg) plant die Anmeldung neu
    await notifications.cancelAllNotifications();
    await repo.refreshReminders(uid);
    expect(notifications.scheduled.keys.where((k) => k >= NotificationService.contactIdOffset), hasLength(2));

    // Löschen der Notiz entfernt die Erinnerungen, Rückgängig plant sie wieder
    await repo.deleteNote(note);
    expect(notifications.scheduled.containsKey(noteId(note)), isFalse);
    await repo.restoreNote(note);
    expect(notifications.scheduled.containsKey(noteId(note)), isTrue);

    // Kontakt löschen nimmt die Erinnerungen mit
    final at = await repo.deleteContact(id);
    expect(notifications.scheduled.keys.where((k) => k >= NotificationService.contactIdOffset), isEmpty);
    await repo.restoreContact(id, at);
    expect(await repo.getNotes(id), hasLength(3));
    expect(notifications.scheduled.containsKey(noteId(note)), isTrue);
  });

  test('notes order: open dated first by date, then the rest newest first, done at the end', () async {
    final id = await repo.saveContact(Contact(userid: uid, name: 'Tom'));
    Future<void> add(String text, {DateTime? date, bool done = false, int minutes = 0}) async {
      final n = await repo.saveNote(ContactNote(userid: uid, contactId: id, text: text, date: date, created: now.add(Duration(minutes: minutes))));
      if (done) await repo.setNoteDone(n, true);
    }

    await add('alt', minutes: 1);
    await add('Freitag Party', date: DateTime(2026, 10, 23));
    await add('neu', minutes: 2);
    await add('Mittwoch Zahnarzt', date: DateTime(2026, 10, 21));
    await add('erledigt', date: DateTime(2026, 10, 22), done: true);
    expect([for (final n in await repo.getNotes(id)) n.text], ['Mittwoch Zahnarzt', 'Freitag Party', 'neu', 'alt', 'erledigt']);
  });

  test('today: dated notes of today, follow-ups from yesterday and birthdays of the next 7 days', () async {
    final lena = await repo.saveContact(Contact(userid: uid, name: 'Lena', birthday: DateTime(1990, 10, 25)));
    final tom = await repo.saveContact(Contact(userid: uid, name: 'Tom', birthday: DateTime(1985, 12, 1)));
    await repo.saveNote(ContactNote(userid: uid, contactId: lena, text: 'Arzttermin', date: DateTime(2026, 10, 20), created: now));
    await repo.saveNote(ContactNote(userid: uid, contactId: tom, text: 'Vorstellungsgespräch', date: DateTime(2026, 10, 19), followUp: true, created: now));
    await repo.saveNote(ContactNote(userid: uid, contactId: tom, text: 'ohne Nachfragen', date: DateTime(2026, 10, 19), created: now));
    await repo.saveNote(ContactNote(userid: uid, contactId: tom, text: 'morgen', date: DateTime(2026, 10, 21), created: now));

    final today = await repo.notesForDay(uid, now);
    expect([for (final n in today.due) '${n.contactName}: ${n.text}'], ['Lena: Arzttermin']);
    expect([for (final n in today.followUps) '${n.contactName}: ${n.text}'], ['Tom: Vorstellungsgespräch']);

    final birthdays = await repo.upcomingBirthdays(uid, now: now);
    expect([for (final c in birthdays) c.name], ['Lena']); // Tom erst im Dezember

    await repo.deleteContact(lena);
    expect((await repo.notesForDay(uid, now)).due, isEmpty);
  });

  test('search: name, relation, nickname, the general notes and the dated notes', () async {
    final lena = await repo.saveContact(Contact(userid: uid, name: 'Lena', relation: 'Arbeitskollegin', notes: 'Vegetarierin'));
    await repo.saveContact(Contact(userid: uid, name: 'Tom', nickname: 'Tommy'));
    await repo.saveContact(Contact(userid: uid, name: 'anna'));
    await repo.saveNote(ContactNote(userid: uid, contactId: lena, text: 'Hat einen Hund namens Bello', created: now));
    expect([for (final c in await repo.getContacts(uid)) c.name], ['anna', 'Lena', 'Tom']); // A–Z ohne Groß/klein
    for (final q in ['kolleg', 'vegetar', 'bello', 'LENA']) {
      expect([for (final c in await repo.getContacts(uid, search: q)) c.name], ['Lena'], reason: q);
    }
    expect([for (final c in await repo.getContacts(uid, search: 'tommy')) c.name], ['Tom']);
  });
}
