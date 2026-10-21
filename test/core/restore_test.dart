import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';

import '../helpers/test_app.dart';

/// „Rückgängig“ stellt genau das wieder her, was mit dem Löschen verschwunden ist – nicht mehr.
void main() {
  late DatabaseService db;
  late UserModel user;

  setUp(() async {
    db = createTestDatabase();
    user = await createTestUser(db);
  });
  tearDown(() => db.close());

  test('restoring a habit brings back its check-ins, but not the ones unticked before', () async {
    final habits = HabitRepository(db: db);
    await habits.createHabit(Habit(name: 'Lesen', userid: user.uid));
    final id = (await habits.getAllHabits(user.uid)).single.id!;
    final monday = DateTime(2026, 10, 5), tuesday = DateTime(2026, 10, 6);
    await habits.toggleHabitCompletion(id, monday, true);
    await habits.toggleHabitCompletion(id, tuesday, true);
    await habits.toggleHabitCompletion(id, tuesday, false); // vertippt, wieder abgewählt
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await habits.deleteHabit(id);
    expect(await habits.getAllHabits(user.uid), isEmpty);
    await habits.restoreHabit(id);

    expect(await habits.isHabitCompletedOnDate(id, monday), isTrue);
    expect(await habits.isHabitCompletedOnDate(id, tuesday), isFalse);
  });

  test('restoring a gift list brings back its ideas, but not one deleted on its own before', () async {
    final lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
    final listId = await lists.saveGiftList(GiftList(userid: user.uid, person: 'Schwester', occasion: 'Geburtstag'));
    await lists.saveGift(GiftItem(listId: listId, userid: user.uid, name: 'Buch'));
    final scarf = await lists.saveGift(GiftItem(listId: listId, userid: user.uid, name: 'Schal'));
    await lists.deleteGift(scarf);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await lists.deleteGiftList(listId);
    expect(await lists.getGiftLists(user.uid), isEmpty);
    await lists.restoreGiftList(listId);

    expect((await lists.getGiftLists(user.uid)).single.items.map((i) => i.name), ['Buch']);
  });

  test('restoring an appointment plans its reminder again', () async {
    final notifications = RecordingNotifications();
    final appointments = AppointmentRepository(db: db, notifications: notifications);
    final soon = DateTime.now().add(const Duration(days: 3));
    await appointments.createAppointment(Appointment(title: 'Zahnarzt', date: soon, userid: user.uid));
    final saved = (await appointments.getAllAppointments(user.uid)).single;
    expect(notifications.scheduled, hasLength(1));

    await appointments.deleteAppointment(saved.id!);
    expect(notifications.scheduled, isEmpty);
    await appointments.restoreAppointment(saved);
    expect(notifications.scheduled, hasLength(1));
  });
}
