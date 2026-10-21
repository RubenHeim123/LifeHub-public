import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/finance/services/export_service.dart';

import '../../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late ExportService export;
  late TransactionRepository transactions;

  setUp(() {
    db = createTestDatabase();
    transactions = TransactionRepository(db: db);
    export = ExportService(
      db: db,
      users: UserRepository(db: db),
      accounts: AccountRepository(db: db),
      categories: CategoryRepository(db: db),
      transactions: transactions,
    );
  });

  tearDown(() => db.close());

  tr.Transaction tx(int uid, String description) => tr.Transaction(
        date: DateTime(2026, 3, 1),
        amount: 12.5,
        category: 'Lebensmittel',
        description: description,
        account: 'Girokonto',
        transactionType: TransactionType.expense,
        userid: uid,
      );

  test('full export contains the user data but never the password hash', () async {
    final user = await createTestUser(db);
    await createTestAccount(db, user.uid, 'Girokonto');
    await transactions.createTransaction(tx(user.uid, 'Einkauf'));

    final data = jsonDecode(await export.generateJson(user.uid)) as Map<String, dynamic>;

    expect(data['sync_type'], 'full');
    expect((data['user'] as Map).containsKey('password'), isFalse);
    expect(data['accounts'], hasLength(1));
    expect(data['transactions'], hasLength(1));
  });

  test('changeset only contains rows changed since the timestamp, including deletions', () async {
    final user = await createTestUser(db);
    await createTestAccount(db, user.uid, 'Girokonto');
    await transactions.createTransaction(tx(user.uid, 'alt'));
    final old = (await transactions.getAllTransactions(user.uid)).single;
    final database = await db.database;
    await database.update('transactions', {'last_changed': '2000-01-01T00:00:00'}, where: 'id = ?', whereArgs: [old.id]);
    await database.update('accounts', {'last_changed': '2000-01-01T00:00:00'});

    final since = DateTime(2020);
    await transactions.createTransaction(tx(user.uid, 'neu'));
    await transactions.deleteTransaction(old.id!);

    final data = jsonDecode(await export.generateChangeset(user.uid, since)) as Map<String, dynamic>;
    final changed = (data['transactions'] as List).cast<Map<String, dynamic>>();

    expect(data['sync_type'], 'delta');
    expect(changed.map((t) => t['description']), containsAll(['alt', 'neu']));
    expect(changed.firstWhere((t) => t['description'] == 'alt')['is_deleted'], 1);
  });

  test('transactions CSV uses readable type labels', () async {
    final user = await createTestUser(db);
    await createTestAccount(db, user.uid, 'Girokonto');
    await transactions.createTransaction(tx(user.uid, 'Einkauf; mit Semikolon'));

    final csv = await export.generateTransactionsCsv(user.uid);

    expect(csv.split('\n')[1], '2026-03-01;12.5;Lebensmittel;"Einkauf; mit Semikolon";Girokonto;Ausgabe');
  });
}
