import 'package:sqflite/sqflite.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/core/services/notification_service.dart';

class TodoRepository {
  TodoRepository({DatabaseService? db, NotificationService? notifications})
      : _db = db ?? DatabaseService.instance,
        _notifications = notifications ?? NotificationService();

  final DatabaseService _db;
  final NotificationService _notifications;

  /// Legt eine Aufgabe an. Wiederkehrende Aufgaben bekommen ihre Serien-ID (= eigene ID)
  /// und das Startdatum der Serie. Liefert die ID.
  Future<int> createTodo(Todo todo) async {
    final db = await _db.database;
    final map = todo.toMap()..remove('id');
    if (todo.repeats) map['repeatStart'] ??= todo.dueDate!.toIso8601String();
    final id = await db.insert('todos', map, conflictAlgorithm: ConflictAlgorithm.replace);
    if (todo.repeats && todo.seriesId == null) {
      await db.update('todos', {'seriesId': id}, where: 'id = ?', whereArgs: [id]);
    }
    await _scheduleReminder(todo, id);
    return id;
  }

  /// Plant die Erinnerungen aller offenen To-Dos neu (beim Anmelden).
  Future<void> refreshReminders(int uid) async {
    for (final t in await getAllTodos(uid)) {
      if (t.id != null && !t.isCompleted && t.dueDate != null) await _scheduleReminder(t, t.id!);
    }
  }

  /// Erinnerung zur Fälligkeit: zur eingestellten Uhrzeit, ohne Uhrzeit um 9 Uhr.
  Future<void> _scheduleReminder(Todo todo, int id) async {
    await _notifications.cancelNotification(id + NotificationService.todoIdOffset);
    final due = todo.dueDate;
    if (due == null || todo.isCompleted) return;
    final at = due.hour == 0 && due.minute == 0 ? DateTime(due.year, due.month, due.day, 9) : due;
    await _notifications.scheduleNotification(
      id: id + NotificationService.todoIdOffset,
      title: 'To-Do: ${todo.title}',
      body: todo.description ?? 'Aufgabe erledigen',
      scheduledDate: at,
    );
  }

  Future<Todo> getTodo(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'todos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Todo.fromMap(maps.first);
    } else {
      throw Exception('Todo ID $id not found');
    }
  }

  Future<List<Todo>> getAllTodos(int uid) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'todos',
      where: 'userid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'dueDate ASC',
    );
    return List.generate(maps.length, (i) {
      return Todo.fromMap(maps[i]);
    });
  }

  Future<void> updateTodo(Todo todo) async {
    final db = await _db.database;
    final Map<String, dynamic> data = todo.toMap();
    if (todo.repeats) {
      data['repeatStart'] ??= todo.dueDate!.toIso8601String();
      data['seriesId'] ??= todo.id;
    }
    data['last_changed'] = syncStamp();
    await db.update(
      'todos',
      data,
      where: 'id = ?',
      whereArgs: [todo.id],
    );
    if (todo.id != null) await _scheduleReminder(todo, todo.id!);
  }

  /// Abhaken bzw. wieder öffnen. Bei wiederkehrenden Aufgaben entsteht beim Abhaken das
  /// nächste Vorkommen (nur einmal – auch wenn man mehrfach an- und abhakt). Liefert es zurück.
  Future<Todo?> setCompleted(Todo todo, bool completed) async {
    await updateTodo(todo.copyWith(isCompleted: completed));
    if (!completed || !todo.repeats) return null;
    final next = todo.nextDue;
    if (next == null) return null;
    final seriesId = todo.seriesId ?? todo.id;
    final db = await _db.database;
    final existing = await db.query('todos',
        where: 'seriesId = ? AND is_deleted = 0 AND isCompleted = 0 AND dueDate >= ?',
        whereArgs: [seriesId, DateTime(next.year, next.month, next.day).toIso8601String()]);
    if (existing.isNotEmpty) return null;
    final nextTodo = todo.copyWith(clearId: true, isCompleted: false, dueDate: next, seriesId: seriesId);
    final id = await createTodo(nextTodo);
    return Todo.fromMap({...nextTodo.toMap(), 'id': id});
  }

  /// Macht ein gelöschtes To-Do wieder sichtbar und plant die Erinnerung neu.
  Future<void> restoreTodo(Todo todo) async {
    await _db.restoreRow('todos', todo.id!);
    await updateTodo(todo);
  }

  Future<void> deleteTodo(int id) async {
    final db = await _db.database;
    await db.update(
      'todos',
      {
        'is_deleted': 1,
        'last_changed': syncStamp(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _notifications.cancelNotification(id + NotificationService.todoIdOffset);
  }
}
