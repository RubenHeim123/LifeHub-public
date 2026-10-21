import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  final now = DateTime(2026, 9, 27, 12);

  InventoryItem item(String name,
          {InventoryKind kind = InventoryKind.food,
          DateTime? expiry,
          DateTime? bought,
          DateTime? used,
          String? category,
          String? location,
          ItemCondition? condition,
          String? color}) =>
      InventoryItem(
        userid: 1,
        kind: kind,
        name: name,
        expiryDate: expiry,
        purchaseDate: bought,
        lastUsedAt: used,
        category: category,
        location: location,
        condition: condition,
        color: color,
      );

  group('InventoryItem', () {
    test('expiry helpers count calendar days', () {
      expect(item('Milch', expiry: DateTime(2026, 9, 27)).daysUntilExpiry(now), 0);
      expect(item('Milch', expiry: DateTime(2026, 9, 29)).expiresSoon(now: now), isTrue);
      expect(item('Milch', expiry: DateTime(2026, 10, 1)).expiresSoon(now: now), isFalse);
      expect(item('Milch', expiry: DateTime(2026, 9, 26)).isExpired(now), isTrue);
      expect(item('Nudeln').daysUntilExpiry(now), isNull);
    });

    test('map round trip keeps all fields', () {
      final original = InventoryItem(
        id: 3,
        userid: 1,
        kind: InventoryKind.clothing,
        name: 'Jeans',
        category: 'Hosen',
        condition: ItemCondition.used,
        purchaseDate: DateTime(2024, 3, 1),
        size: '32/32',
        color: 'Blau',
        wearCount: 7,
        price: 89.9,
      );
      final copy = InventoryItem.fromMap(original.toMap());
      expect(copy.toMap(), original.toMap());
    });
  });

  group('InventoryQuery', () {
    final items = [
      item('Milch', expiry: DateTime(2026, 9, 28), category: 'Milchprodukte', location: 'Kühlschrank'),
      item('Joghurt', expiry: DateTime(2026, 9, 20), category: 'Milchprodukte', location: 'Kühlschrank'),
      item('Reis', category: 'Vorräte', location: 'Vorratsschrank', bought: DateTime(2025, 1, 1)),
      item('Hemd', kind: InventoryKind.clothing, color: 'Weiß', used: DateTime(2026, 9, 1), condition: ItemCondition.good),
      item('Anzug', kind: InventoryKind.clothing, used: DateTime(2025, 12, 24), condition: ItemCondition.good),
    ];

    List<String> names(InventoryQuery q) => q.apply(items, now: now).map((i) => i.name).toList();

    test('search looks at name, color, location', () {
      expect(names(const InventoryQuery(search: 'weiß')), ['Hemd']);
      expect(names(const InventoryQuery(search: 'kühl')), ['Joghurt', 'Milch']);
    });

    test('filters by category, location, condition and status', () {
      expect(names(const InventoryQuery(category: 'Vorräte')), ['Reis']);
      expect(names(const InventoryQuery(location: 'Kühlschrank')), ['Joghurt', 'Milch']);
      expect(names(const InventoryQuery(condition: ItemCondition.good, sort: InventorySort.name)), ['Anzug', 'Hemd']);
      expect(names(const InventoryQuery(status: InventoryStatus.expiringSoon)), ['Milch']);
      expect(names(const InventoryQuery(status: InventoryStatus.expired)), ['Joghurt']);
      expect(names(const InventoryQuery(status: InventoryStatus.notWornLately)).contains('Anzug'), isTrue);
      expect(names(const InventoryQuery(status: InventoryStatus.notWornLately)).contains('Hemd'), isFalse);
    });

    test('sorting: expiry first, without expiry at the end; longest unused first', () {
      expect(names(const InventoryQuery()).take(2), ['Joghurt', 'Milch']);
      final clothing = const InventoryQuery(sort: InventorySort.lastUsed)
          .apply(items.where((i) => i.kind == InventoryKind.clothing).toList(), now: now)
          .map((i) => i.name);
      expect(clothing, ['Anzug', 'Hemd']);
    });
  });

  group('InventoryRepository', () {
    late DatabaseService db;
    late InventoryRepository repo;
    late UserModel user;

    setUp(() async {
      db = createTestDatabase();
      repo = InventoryRepository(db: db);
      user = await createTestUser(db);
    });
    tearDown(() => db.close());

    InventoryItem mine(String name, {InventoryKind kind = InventoryKind.food, double quantity = 1, DateTime? expiry}) =>
        InventoryItem(userid: user.uid, kind: kind, name: name, quantity: quantity, expiryDate: expiry);

    test('filters by kind and only returns the own items', () async {
      final other = await createTestUser(db, email: 'x@test.de');
      await repo.createItem(mine('Milch'));
      await repo.createItem(mine('Wasser', kind: InventoryKind.drink));
      await repo.createItem(mine('Hemd', kind: InventoryKind.clothing));
      await repo.createItem(InventoryItem(userid: other.uid, kind: InventoryKind.food, name: 'Fremd'));

      final pantry = await repo.getItems(user.uid, kinds: {InventoryKind.food, InventoryKind.drink});
      expect(pantry.map((i) => i.name), ['Milch', 'Wasser']);
      expect((await repo.getItems(user.uid)).length, 3);
    });

    test('consume counts down and removes the item when used up', () async {
      final id = await repo.createItem(mine('Eier', quantity: 2));
      var eggs = (await repo.getItem(id))!;

      expect(await repo.consume(eggs), 1);
      eggs = (await repo.getItem(id))!;
      expect(eggs.quantity, 1);
      expect(eggs.lastUsedAt, isNotNull);

      expect(await repo.consume(eggs), 0);
      expect(await repo.getItem(id), isNull);
    });

    test('markWorn counts and remembers the date', () async {
      final id = await repo.createItem(mine('Hemd', kind: InventoryKind.clothing));
      await repo.markWorn(id, at: DateTime(2026, 9, 27));
      await repo.markWorn(id, at: DateTime(2026, 9, 28));

      final shirt = (await repo.getItem(id))!;
      expect(shirt.wearCount, 2);
      expect(shirt.lastUsedAt, DateTime(2026, 9, 28));
    });

    test('getExpiring returns expired and soon-expiring items, most urgent first', () async {
      await repo.createItem(mine('Käse', expiry: DateTime(2026, 9, 29)));
      await repo.createItem(mine('Joghurt', expiry: DateTime(2026, 9, 25)));
      await repo.createItem(mine('Konserve', expiry: DateTime(2027, 5, 1)));
      await repo.createItem(mine('Reis'));

      final expiring = await repo.getExpiring(user.uid, now: now);
      expect(expiring.map((i) => i.name), ['Joghurt', 'Käse']);
    });
  });
}
