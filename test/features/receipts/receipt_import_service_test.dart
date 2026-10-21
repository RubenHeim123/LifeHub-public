import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/receipts/services/receipt_import_service.dart';

import '../../helpers/test_app.dart';

/// Scheitert beim zweiten Vorratsartikel – wie ein voller Speicher oder ein Absturz mitten im Speichern.
class _FailingInventory extends InventoryRepository {
  _FailingInventory(DatabaseService db) : super(db: db);
  int calls = 0;

  @override
  Future<int> insertItem(DatabaseExecutor ex, InventoryItem item) async {
    if (++calls == 2) throw Exception('Speicher voll');
    return super.insertItem(ex, item);
  }
}

void main() {
  late DatabaseService db;
  late UserModel user;

  setUp(() async {
    db = createTestDatabase();
    user = await createTestUser(db);
    await createTestAccount(db, user.uid, 'Girokonto', amount: 100);
  });
  tearDown(() => db.close());

  ReceiptDraft draft() => ReceiptDraft(
        userid: user.uid,
        description: 'ALDI',
        amount: 4.5,
        date: DateTime(2026, 10, 9),
        category: 'Lebensmittel',
        account: 'Girokonto',
        pantry: const [
          PantryLine(name: 'Haferflocken', quantity: 500, unit: 'g'),
          PantryLine(name: 'Tofu', quantity: 200, unit: 'g'),
        ],
      );

  test('a receipt books the expense and fills the pantry', () async {
    final inventory = InventoryRepository(db: db);
    await ReceiptImportService(transactions: TransactionRepository(db: db), inventory: inventory).save(draft());
    expect(await balanceOf(db, user.uid, 'Girokonto'), 95.5);
    expect((await inventory.getItems(user.uid)).map((i) => i.name), containsAll(['Haferflocken', 'Tofu']));
  });

  test('if saving fails halfway, nothing is booked and nothing lands in the pantry', () async {
    final failing = _FailingInventory(db);
    final service = ReceiptImportService(transactions: TransactionRepository(db: db), inventory: failing);
    await expectLater(service.save(draft()), throwsException);
    expect(await balanceOf(db, user.uid, 'Girokonto'), 100);
    expect(await TransactionRepository(db: db).getAllTransactions(user.uid), isEmpty);
    expect(await InventoryRepository(db: db).getItems(user.uid), isEmpty);
  });
}
