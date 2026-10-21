import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/receipts/models/receipt.dart';
import 'package:frontend/features/receipts/services/receipt_import_service.dart';
import 'package:frontend/features/receipts/services/receipt_matcher.dart';

import '../../helpers/test_app.dart';

void main() {
  InventoryItem pantry(int id, String name, double quantity, String? unit, {int? foodId}) => InventoryItem(
        id: id,
        userid: 1,
        kind: InventoryKind.food,
        name: name,
        quantity: quantity,
        unit: unit,
        foodId: foodId,
        fromShopping: true,
      );

  group('ReceiptMatcher', () {
    const matcher = ReceiptMatcher();

    test('pairs abbreviated receipt text with what was checked off, flags other amounts', () {
      final items = [
        const ReceiptItem(name: 'HAFERFL. ZART 500G', price: 0.59),
        const ReceiptItem(name: 'BIO TOFU NATUR 200G', price: 3.58, count: 2),
        const ReceiptItem(name: 'ZWIEBELN', price: 1.20, weightKg: 1),
        const ReceiptItem(name: 'SCHOKOLADE', price: 1.29),
        const ReceiptItem(name: 'PFAND', price: 0.25),
      ];
      final trip = [
        pantry(1, 'Haferflocken', 500, 'g'),
        pantry(2, 'Tofu', 200, 'g'),
        pantry(3, 'Zwiebel', 1, 'kg'), // 1 kg = 1000 g
        pantry(4, 'Hackfleisch', 400, 'g'),
      ];
      final cmp = matcher.compare(items, List.filled(items.length, null), trip);
      expect(cmp.pairs.map((i, p) => MapEntry(i, p.name)), {0: 'Haferflocken', 1: 'Tofu', 2: 'Zwiebel'});
      expect(cmp.status, [
        ReceiptMatchStatus.matched,
        ReceiptMatchStatus.amountDiffers, // 2 × 200 g gekauft, 200 g eingetragen
        ReceiptMatchStatus.matched,
        ReceiptMatchStatus.onlyOnReceipt,
        ReceiptMatchStatus.onlyOnReceipt,
      ]);
      expect(cmp.onlyInPantry.map((p) => p.name), ['Hackfleisch']);
      expect(cmp.matchedCount, 3);
    });

    test('the same food wins over a similar name; each pantry item is used once', () {
      final items = [
        const ReceiptItem(name: 'MILCH 1,5L', price: 1.1),
        const ReceiptItem(name: 'MILCH 1,5L', price: 1.1),
      ];
      final food = Food(id: 7, userid: 1, name: 'Hafermilch');
      final trip = [pantry(1, 'Milch', 1500, 'ml'), pantry(2, 'Hafermilch', 1000, 'ml', foodId: 7)];
      final cmp = matcher.compare(items, [food, null], trip);
      expect(cmp.pairs[0]!.name, 'Hafermilch');
      expect(cmp.pairs[1]!.name, 'Milch');
      expect(cmp.status, [ReceiptMatchStatus.amountDiffers, ReceiptMatchStatus.matched]);
    });

    test('pieces vs. grams are not compared; no trip → everything only on the receipt', () {
      const item = ReceiptItem(name: 'GURKE', price: 0.69);
      expect(ReceiptMatcher.amountsDiffer(item, pantry(1, 'Gurke', 300, 'g')), isFalse);
      final cmp = matcher.compare([item], [null], const []);
      expect(cmp.hasTrip, isFalse);
      expect(cmp.status, [ReceiptMatchStatus.onlyOnReceipt]);
    });
  });

  group('shopping trip ↔ receipt in the database', () {
    late DatabaseService db;
    late UserModel user;
    late InventoryRepository inventory;
    late ListsRepository lists;

    setUp(() async {
      db = createTestDatabase();
      user = await createTestUser(db);
      await createTestAccount(db, user.uid, 'Girokonto', amount: 100);
      inventory = InventoryRepository(db: db);
      lists = ListsRepository(db: db, inventory: inventory);
    });
    tearDown(() => db.close());

    /// Kauft [name] über die Einkaufsliste am Tag [at].
    Future<int> buy(String name, double amount, DateTime at, {String? barcode}) async {
      await lists.addToList(user.uid, name: name, amount: amount, unit: 'g');
      final item = (await lists.getShopping(user.uid)).firstWhere((i) => i.name == name);
      final done = await lists.toggleShopping(item, at: at, bought: amount, barcode: barcode);
      return (await lists.moveToInventory(done))!;
    }

    test('checking off carries amount, barcode and origin into the pantry; undo restores the list', () async {
      final id = await buy('Haferflocken', 1000, DateTime(2026, 10, 20, 17), barcode: '4000000000001');
      final item = (await inventory.getItem(id))!;
      expect((item.quantity, item.unit, item.barcode, item.fromShopping, item.receiptTxId), (1000.0, 'g', '4000000000001', true, null));

      await lists.addToList(user.uid, name: 'Tofu', amount: 200, unit: 'g');
      final tofu = (await lists.getShopping(user.uid)).single;
      final done = await lists.toggleShopping(tofu, bought: 2, boughtUnit: (null,));
      expect((done.boughtAmount, done.unit), (2.0, null)); // gekauft in Stück statt g
      final tofuId = (await lists.moveToInventory(done))!;
      await lists.undoMoveToInventory(tofu, tofuId);
      final back = (await lists.getShopping(user.uid)).single;
      expect((back.name, back.done, back.amount, back.unit), ('Tofu', false, 200.0, 'g'));
      expect(await inventory.getItem(tofuId), isNull);
      expect((await inventory.tripsWithoutReceipt(user.uid, now: DateTime(2026, 10, 21))).single, (DateTime(2026, 10, 20), 1));
      // Der Hinweis gilt nur am Einkaufstag und am Tag danach
      expect(await inventory.tripsWithoutReceipt(user.uid, now: DateTime(2026, 10, 22)), isEmpty);
    });

    test('bought cooking ingredients still count as bought after moving into the pantry', () async {
      await lists.addToList(user.uid, name: 'Linsen', amount: 250, unit: 'g', label: 'Dal', batchId: 3);
      final item = (await lists.getShopping(user.uid)).single;
      await lists.moveToInventory(await lists.toggleShopping(item));
      expect(await lists.boughtFor(user.uid, 3), {('linsen', 'g'): 250.0});
    });

    test('only the trip of the receipt day is loaded; a saved receipt links it instead of adding duplicates', () async {
      final oats = await buy('Haferflocken', 500, DateTime(2026, 10, 20, 9));
      final tofu = await buy('Tofu', 200, DateTime(2026, 10, 20, 18));
      final other = await buy('Hackfleisch', 400, DateTime(2026, 10, 19, 18)); // Vortag: eigener Bon

      final trip = await inventory.shoppingTrip(user.uid, DateTime(2026, 10, 20));
      expect(trip.map((i) => i.name), ['Haferflocken', 'Tofu']);

      final txId = await ReceiptImportService(transactions: TransactionRepository(db: db), inventory: inventory).save(ReceiptDraft(
        userid: user.uid,
        description: 'ALDI',
        amount: 5.0,
        date: DateTime(2026, 10, 20, 18, 30),
        category: 'Lebensmittel',
        account: 'Girokonto',
        pantry: const [PantryLine(name: 'Schokolade', quantity: 1, price: 1.29)],
        links: [ReceiptLink(inventoryId: oats, price: 0.59), ReceiptLink(inventoryId: tofu, price: 3.58, quantity: 400, unit: 'g')],
        closesTrip: true,
      ));

      final items = {for (final i in await inventory.getItems(user.uid)) i.name: i};
      expect(items.keys.toSet(), {'Haferflocken', 'Tofu', 'Hackfleisch', 'Schokolade'}); // nichts doppelt
      expect((items['Haferflocken']!.price, items['Haferflocken']!.receiptTxId), (0.59, txId));
      expect((items['Tofu']!.quantity, items['Tofu']!.price), (400.0, 3.58));
      expect(items['Schokolade']!.receiptTxId, txId);
      expect((await inventory.getItem(other))!.receiptTxId, isNull);
      expect(await inventory.shoppingTrip(user.uid, DateTime(2026, 10, 20)), isEmpty);
      expect((await inventory.tripsWithoutReceipt(user.uid, now: DateTime(2026, 10, 20))).map((t) => t.$1), [DateTime(2026, 10, 19)]);
    });

    test('a receipt for an existing booking updates it instead of booking twice', () async {
      await buy('Tofu', 200, DateTime(2026, 10, 20, 18));
      final transactions = TransactionRepository(db: db);
      final id = await transactions.createTransaction(Transaction(
        date: DateTime(2026, 10, 20),
        amount: 4,
        category: 'Lebensmittel',
        description: 'Einkauf',
        account: 'Girokonto',
        transactionType: TransactionType.expense,
        userid: user.uid,
      ));
      expect(await balanceOf(db, user.uid, 'Girokonto'), 96);

      await ReceiptImportService(transactions: transactions, inventory: inventory).save(ReceiptDraft(
        userid: user.uid,
        description: 'REWE',
        amount: 3.58,
        date: DateTime(2026, 10, 20, 18, 30),
        category: 'Lebensmittel',
        account: 'Girokonto',
        imagePath: 'receipt_images/bon.jpg',
        closesTrip: true,
        transactionId: id,
      ));
      final all = await transactions.getAllTransactions(user.uid);
      expect(all.map((t) => (t.id, t.description, t.amount, t.imagePath)), [(id, 'REWE', 3.58, 'receipt_images/bon.jpg')]);
      expect(await balanceOf(db, user.uid, 'Girokonto'), closeTo(96.42, 0.001));
      expect((await inventory.getItems(user.uid)).single.receiptTxId, id);
    });

    test('a day can be closed without a receipt and reopened', () async {
      await buy('Äpfel', 1000, DateTime(2026, 10, 20, 10));
      final at = await inventory.dismissTrip(user.uid, DateTime(2026, 10, 20));
      expect(await inventory.tripsWithoutReceipt(user.uid, now: DateTime(2026, 10, 21)), isEmpty);
      await inventory.undoDismissTrip(user.uid, at);
      expect(await inventory.tripsWithoutReceipt(user.uid, now: DateTime(2026, 10, 21)), hasLength(1));
    });
  });
}
