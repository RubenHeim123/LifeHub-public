import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/finance/services/export_service.dart';
import 'package:frontend/features/finance/services/local_sync_service.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';

import '../../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late List<Map<String, dynamic>> sent;
  late LocalSyncService sync;

  setUp(() {
    db = createTestDatabase();
    sent = [];
    final client = MockClient((request) async {
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('ok', 200);
    });
    final export = ExportService(
      db: db,
      users: UserRepository(db: db),
      accounts: AccountRepository(db: db),
      categories: CategoryRepository(db: db),
      transactions: TransactionRepository(db: db),
    );
    sync = LocalSyncService(db: db, exportService: export, client: client);
  });
  tearDown(() => db.close());

  List<String> todoTitles(Map<String, dynamic> payload) => [
        for (final t in (payload['todos'] as List? ?? const [])) (t as Map)['title'] as String,
      ];

  test('a to-do added right after a sync is in the next delta (same day, insert)', () async {
    final user = await createTestUser(db);
    final todos = TodoRepository(db: db);
    await todos.createTodo(Todo(title: 'Alt', userid: user.uid));

    expect(await sync.syncToIP(user.uid, '192.168.0.2'), isTrue);
    expect(sent.last['sync_type'], 'full');

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await todos.createTodo(Todo(title: 'Neu', userid: user.uid));
    expect(await sync.syncToIP(user.uid, '192.168.0.2'), isTrue);
    expect(sent.last['sync_type'], 'delta');
    expect(todoTitles(sent.last), ['Neu']); // vorher fehlte die Einfügung (CURRENT_TIMESTAMP-Format)
  });

  test('sync sessions are per user: a second account on the device starts with a full sync', () async {
    final alice = await createTestUser(db);
    final bob = await createTestUser(db, email: 'bob@example.com');
    await sync.syncToIP(alice.uid, '192.168.0.2');
    await sync.syncToIP(bob.uid, '192.168.0.2');
    expect(sent.map((p) => p['sync_type']), ['full', 'full']);
  });

  test('all timestamps are UTC with Z – inserted, updated and restored rows alike', () async {
    final UserModel user = await createTestUser(db);
    final todos = TodoRepository(db: db);
    final id = await todos.createTodo(Todo(title: 'A', userid: user.uid));
    final raw = await db.database;
    await raw.insert('todos', {'title': 'roh', 'userid': user.uid, 'isCompleted': 0, 'last_changed': '2026-10-10T10:00:00.000'});
    await todos.deleteTodo(id);
    final stamps = (await raw.query('todos', columns: ['last_changed'])).map((r) => r['last_changed'] as String);
    expect(stamps, everyElement(matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$'))));
    expect(syncStamp(DateTime.utc(2026, 10, 10, 8, 15)), '2026-10-10T08:15:00.000Z');
  });
}
