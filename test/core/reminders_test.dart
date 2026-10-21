import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';

import '../helpers/test_app.dart';

void main() {
  test('after sign-out (all cancelled) the login plans to-do and pantry reminders again', () async {
    final db = createTestDatabase();
    final notifications = RecordingNotifications();
    final todos = TodoRepository(db: db, notifications: notifications);
    final inventory = InventoryRepository(db: db, notifications: notifications);
    final user = await createTestUser(db);
    final soon = DateTime.now().add(const Duration(days: 5));

    final open = await todos.createTodo(Todo(title: 'Steuer', userid: user.uid, dueDate: soon));
    await todos.createTodo(Todo(title: 'Erledigt', userid: user.uid, dueDate: soon, isCompleted: true));
    final milk = await inventory.createItem(
        InventoryItem(userid: user.uid, kind: InventoryKind.food, name: 'Milch', expiryDate: DateTime(soon.year, soon.month, soon.day)));
    await inventory.createItem(InventoryItem(userid: user.uid, kind: InventoryKind.clothing, name: 'Jacke'));

    await notifications.cancelAllNotifications(); // Abmelden
    await todos.refreshReminders(user.uid);
    await inventory.refreshReminders(user.uid);

    expect(notifications.scheduled.keys.toSet(),
        {open + NotificationService.todoIdOffset, milk + NotificationService.inventoryIdOffset});
    await db.close();
  });
}
