import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/models/repeat.dart';

import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  test('TodoRepository creates, completes and soft-deletes todos', () async {
    final db = createTestDatabase();
    final repo = TodoRepository(db: db);
    final user = await createTestUser(db);

    await repo.createTodo(Todo(title: 'Einkaufen', userid: user.uid));
    final created = (await repo.getAllTodos(user.uid)).single;
    expect(created.isCompleted, isFalse);

    await repo.updateTodo(Todo(id: created.id, title: created.title, isCompleted: true, userid: user.uid));
    expect((await repo.getAllTodos(user.uid)).single.isCompleted, isTrue);

    await repo.deleteTodo(created.id!);
    expect(await repo.getAllTodos(user.uid), isEmpty);
    await db.close();
  });

  test('recurring todo: checking it off creates the next occurrence once', () async {
    final db = createTestDatabase();
    final repo = TodoRepository(db: db);
    final user = await createTestUser(db);
    final friday = DateTime(2026, 10, 2); // Freitag

    await repo.createTodo(Todo(
      title: 'Bad putzen',
      userid: user.uid,
      dueDate: friday,
      repeat: const Repeat(RepeatFreq.weekly, interval: 2),
    ));
    final first = (await repo.getAllTodos(user.uid)).single;
    expect(first.seriesId, first.id);
    expect(first.repeatStart, friday);

    final next = await repo.setCompleted(first, true);
    expect(next!.dueDate, DateTime(2026, 10, 16)); // alle 2 Wochen
    expect(next.isCompleted, isFalse);
    expect(next.seriesId, first.id);

    // Wieder öffnen und erneut abhaken: kein zweites Folge-To-Do
    await repo.setCompleted(first, false);
    expect(await repo.setCompleted(first, true), isNull);
    final all = await repo.getAllTodos(user.uid);
    expect(all.map((t) => (t.dueDate, t.isCompleted)), [(friday, true), (DateTime(2026, 10, 16), false)]);

    // Das nächste Vorkommen erzeugt wieder das übernächste – Uhrzeit bleibt erhalten
    await repo.updateTodo(Todo(
      id: next.id,
      title: next.title,
      userid: user.uid,
      dueDate: DateTime(2026, 10, 16, 18, 30),
      repeat: next.repeat,
      repeatStart: next.repeatStart,
      seriesId: next.seriesId,
    ));
    final third = await repo.setCompleted((await repo.getTodo(next.id!)), true);
    expect(third!.dueDate, DateTime(2026, 10, 30, 18, 30));
    await db.close();
  });

  test('restore brings a deleted todo back', () async {
    final db = createTestDatabase();
    final repo = TodoRepository(db: db);
    final user = await createTestUser(db);
    await repo.createTodo(Todo(title: 'Steuer', userid: user.uid, dueDate: DateTime(2026, 11, 1)));
    final todo = (await repo.getAllTodos(user.uid)).single;
    await repo.deleteTodo(todo.id!);
    await repo.restoreTodo(todo);
    expect((await repo.getAllTodos(user.uid)).single.title, 'Steuer');
    await db.close();
  });
}
