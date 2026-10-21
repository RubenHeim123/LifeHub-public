import 'package:flutter_test/flutter_test.dart';


import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  test('AppointmentRepository CRUD with duration and soft delete', () async {
    final db = createTestDatabase();
    final repo = AppointmentRepository(db: db);
    final user = await createTestUser(db);
    final start = DateTime(2026, 5, 4, 9, 30);

    await repo.createAppointment(Appointment(title: 'Arzt', date: start, durationMinutes: 45, userid: user.uid));
    final saved = (await repo.getAllAppointments(user.uid)).single;
    expect(saved.endDate, DateTime(2026, 5, 4, 10, 15));

    await repo.updateAppointment(Appointment(id: saved.id, title: 'Zahnarzt', date: start, userid: user.uid));
    expect((await repo.getAppointment(saved.id!)).title, 'Zahnarzt');

    await repo.deleteAppointment(saved.id!);
    expect(await repo.getAllAppointments(user.uid), isEmpty);
    await db.close();
  });

  test('appointments are returned in chronological order and per user', () async {
    final db = createTestDatabase();
    final repo = AppointmentRepository(db: db);
    final a = await createTestUser(db, email: 'a@test.de');
    final b = await createTestUser(db, email: 'b@test.de');

    await repo.createAppointment(Appointment(title: 'Später', date: DateTime(2026, 6, 2), userid: a.uid));
    await repo.createAppointment(Appointment(title: 'Früher', date: DateTime(2026, 6, 1), userid: a.uid));
    await repo.createAppointment(Appointment(title: 'Fremd', date: DateTime(2026, 6, 1), userid: b.uid));

    expect((await repo.getAllAppointments(a.uid)).map((x) => x.title), ['Früher', 'Später']);
    await db.close();
  });

  test('reminders: 15 minutes before by default, configurable, none cancels', () async {
    final db = createTestDatabase();
    final notifications = RecordingNotifications();
    final repo = AppointmentRepository(db: db, notifications: notifications);
    final user = await createTestUser(db);
    final start = DateTime(2030, 5, 4, 14, 0);

    await repo.createAppointment(Appointment(title: 'Zahnarzt', description: 'Praxis Mitte', date: start, userid: user.uid));
    final saved = (await repo.getAllAppointments(user.uid)).single;
    expect(saved.reminderMinutes, 15);
    final (title, body, at) = notifications.scheduled[saved.id]!;
    expect(title, 'Termin: Zahnarzt');
    expect(body, 'In 15 Minuten · 14:00 Uhr\nPraxis Mitte');
    expect(at, DateTime(2030, 5, 4, 13, 45));

    await repo.updateAppointment(Appointment(id: saved.id, title: 'Zahnarzt', date: start, userid: user.uid, reminderMinutes: 60));
    expect(notifications.scheduled[saved.id]!.$3, DateTime(2030, 5, 4, 13, 0));
    expect(notifications.scheduled[saved.id]!.$2, startsWith('In 1 Stunde'));

    await repo.updateAppointment(Appointment(id: saved.id, title: 'Zahnarzt', date: start, userid: user.uid, reminderMinutes: null));
    expect(notifications.scheduled, isEmpty);
    expect((await repo.getAppointment(saved.id!)).reminderMinutes, isNull);

    expect(Appointment.reminderLabel(15), '15 min vorher');
    expect(Appointment.reminderLabel(120), '2 h vorher');
    expect(Appointment.reminderLabel(1440), '1 Tag vorher');
    await db.close();
  });
}
